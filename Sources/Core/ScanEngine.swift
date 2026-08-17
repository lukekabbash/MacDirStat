import Foundation

public struct ScanProgress: Sendable {
    public enum Phase: String, Sendable {
        case indexing
        case discovering
        case measuringPackage
        case preparingMap
    }

    public var scannedNodes: Int
    public var currentPath: String
    public var phase: Phase
    public var totalNodes: Int?
    /// Lightweight inventory work completed beside measurement. It lets the
    /// UI show honest forward motion before the final denominator is known.
    public var inventoryNodes: Int
    /// Present only at deliberate visual checkpoints. Most progress updates
    /// stay lightweight so a large arena is not copied just to update a count.
    public var partialSession: ScanSession?

    public init(
        scannedNodes: Int,
        currentPath: String,
        phase: Phase = .discovering,
        totalNodes: Int? = nil,
        inventoryNodes: Int = 0,
        partialSession: ScanSession? = nil
    ) {
        self.scannedNodes = scannedNodes
        self.currentPath = currentPath
        self.phase = phase
        self.totalNodes = totalNodes
        self.inventoryNodes = inventoryNodes
        self.partialSession = partialSession
    }
}

/// A deliberate scan outcome rather than an opaque filesystem failure.
public enum ScanError: LocalizedError, Sendable {
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Scan cancelled."
        }
    }
}

/// Background filesystem scanner: no symlinks followed, packages optional leaf.
public final class ScanEngine: @unchecked Sendable {
    private final class ExactProgressState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedTotal: Int?
        private var storedInventory = 0

        var total: Int? {
            lock.lock()
            defer { lock.unlock() }
            return storedTotal
        }

        var inventory: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedInventory
        }

        func recordInventory(_ count: Int) {
            lock.lock()
            storedInventory = max(storedInventory, count)
            lock.unlock()
        }

        func finish(with total: Int?) {
            lock.lock()
            storedTotal = total
            if let total { storedInventory = max(storedInventory, total) }
            lock.unlock()
        }
    }

    private struct AddedEntry {
        let directoryID: NodeID?
        let inspectedDelta: Int
        let skipDescendants: Bool
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .isPackageKey,
        .mayShareFileContentKey,
        .isSparseKey,
    ]
    private static let resourceKeySet = Set(resourceKeys)

    public init() {}

    /// - Parameters:
    ///   - rootURL: Must be accessed with `startAccessingSecurityScopedResource()` by caller for sandbox.
    ///   - writeAccess: Whether the current scope includes write (user-selected read-write).
    public func scan(
        rootURL: URL,
        rootBookmarkID: UUID?,
        options: ScanOptions,
        writeAccess: Bool,
        progress: (@Sendable (ScanProgress) -> Void)? = nil,
        shouldCancel: (@Sendable () -> Bool)? = nil
    ) async throws -> ScanSession {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let session = try self.scanSync(
                        rootURL: rootURL,
                        rootBookmarkID: rootBookmarkID,
                        options: options,
                        writeAccess: writeAccess,
                        progress: progress,
                        shouldCancel: shouldCancel
                    )
                    continuation.resume(returning: session)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func scanSync(
        rootURL: URL,
        rootBookmarkID: UUID?,
        options: ScanOptions,
        writeAccess: Bool,
        progress: (@Sendable (ScanProgress) -> Void)?,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws -> ScanSession {
        var arena = ScanNodeArena()
        let rootPath = rootURL.path
        let volumeName = try? rootURL.resourceValues(forKeys: [.volumeNameKey]).volumeName
        let rootName = rootPath == "/"
            ? (volumeName ?? "Macintosh HD")
            : (rootURL.lastPathComponent.isEmpty ? (volumeName ?? "Volume") : rootURL.lastPathComponent)
        arena.reset(rootName: rootName, rootPath: rootPath)

        var warnings: [String] = []
        var scanned = 0
        let exactProgress = ExactProgressState()
        let countGroup = DispatchGroup()
        if options.calculatesExactProgress {
            countGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { countGroup.leave() }
                let total = try? self.countScanUnits(
                    rootURL: rootURL,
                    rootPath: rootPath,
                    options: options,
                    onProgress: { count in exactProgress.recordInventory(count) },
                    shouldCancel: shouldCancel
                )
                exactProgress.finish(with: total)
            }
        }
        defer {
            if options.calculatesExactProgress { countGroup.wait() }
        }
        var lastProgressNodeCount = 0
        var lastProgressTime = Date.timeIntervalSinceReferenceDate
        var lastPartialSnapshotNodeCount = 0

        try enumerateFlat(
            rootURL: rootURL,
            options: options,
            writeAccess: writeAccess,
            arena: &arena,
            warnings: &warnings,
            scanned: &scanned,
            lastProgressNodeCount: &lastProgressNodeCount,
            lastProgressTime: &lastProgressTime,
            lastPartialSnapshotNodeCount: &lastPartialSnapshotNodeCount,
            rootBookmarkID: rootBookmarkID,
            rootName: rootName,
            rootPath: rootPath,
            totalNodes: { exactProgress.total },
            inventoryNodes: { exactProgress.inventory },
            progress: progress,
            shouldCancel: shouldCancel
        )

        if shouldCancel?() == true {
            throw ScanError.cancelled
        }

        if options.calculatesExactProgress { countGroup.wait() }
        let totalNodes = exactProgress.total

        return makeSnapshot(
            arena: &arena,
            rootBookmarkID: rootBookmarkID,
            rootName: rootName,
            rootPath: rootPath,
            options: options,
            warnings: warnings,
            scanned: scanned,
            totalNodes: totalNodes,
            isComplete: true,
            progress: progress
        )
    }

    /// Filesystem APIs do not expose a recursive item total. This lightweight
    /// inventory runs beside measurement so the map can grow immediately while
    /// the visible percentage acquires a real denominator.
    private func countScanUnits(
        rootURL: URL,
        rootPath: String,
        options: ScanOptions,
        onProgress: @Sendable (Int) -> Void,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws -> Int {
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.showHiddenFiles { enumerationOptions.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: enumerationOptions,
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            if shouldCancel?() == true { throw ScanError.cancelled }
            if Self.shouldSkipNonContentPath(path: url.path, rootPath: rootPath) {
                enumerator.skipDescendants()
                continue
            }
            count += 1
            if count.isMultiple(of: 2_048) { onProgress(count) }
        }
        onProgress(count)
        return count
    }

    /// Full-volume traversal lists only privacy-sensitive boundaries manually;
    /// every safe branch retains the fast recursive enumerator.
    private func enumerateFlat(
        rootURL: URL,
        options: ScanOptions,
        writeAccess: Bool,
        arena: inout ScanNodeArena,
        warnings: inout [String],
        scanned: inout Int,
        lastProgressNodeCount: inout Int,
        lastProgressTime: inout TimeInterval,
        lastPartialSnapshotNodeCount: inout Int,
        rootBookmarkID: UUID?,
        rootName: String,
        rootPath: String,
        totalNodes: @escaping @Sendable () -> Int?,
        inventoryNodes: @escaping @Sendable () -> Int,
        progress: (@Sendable (ScanProgress) -> Void)?,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws {
        var listingOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.showHiddenFiles { listingOptions.insert(.skipsHiddenFiles) }

        func publishProgress(at url: URL) {
            emitProgressIfNeeded(
                arena: &arena,
                warnings: warnings,
                scanned: scanned,
                lastProgressNodeCount: &lastProgressNodeCount,
                lastProgressTime: &lastProgressTime,
                lastPartialSnapshotNodeCount: &lastPartialSnapshotNodeCount,
                rootBookmarkID: rootBookmarkID,
                rootName: rootName,
                currentPath: url.path,
                options: options,
                totalNodes: totalNodes,
                inventoryNodes: inventoryNodes,
                progress: progress
            )
        }

        func addEntry(_ url: URL, to parentID: NodeID) throws -> AddedEntry {
            guard let values = try? url.resourceValues(forKeys: Self.resourceKeySet) else {
                Self.recordWarning("Could not inspect \(url.path).", in: &warnings)
                return AddedEntry(directoryID: nil, inspectedDelta: 1, skipDescendants: true)
            }
            if values.isSymbolicLink == true {
                return AddedEntry(directoryID: nil, inspectedDelta: 1, skipDescendants: true)
            }

            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true
            let mayShare = values.mayShareFileContent == true
            let isSparse = values.isSparse == true
            let logical = UInt64(max(0, values.fileSize ?? 0))
            let allocatedValue = values.totalFileAllocatedSize ?? values.fileAllocatedSize
            let allocated = allocatedValue.map { UInt64(max(0, $0)) } ?? logical

            if isDirectory, options.treatPackagesAsLeaves, isPackage {
                let usage = try measuredPackageUsage(
                    at: url,
                    options: options,
                    scannedBase: scanned,
                    totalNodes: totalNodes,
                    inventoryNodes: inventoryNodes,
                    progress: progress,
                    shouldCancel: shouldCancel
                )
                _ = arena.addChild(
                    parent: parentID,
                    kind: .packageLeaf,
                    name: url.lastPathComponent,
                    path: url.path,
                    logicalSize: usage.logical,
                    allocatedSize: usage.allocated,
                    isPackage: true,
                    mayShareContent: mayShare,
                    isSparse: isSparse,
                    isPurgeable: false,
                    writeAccess: writeAccess
                )
                return AddedEntry(
                    directoryID: nil,
                    inspectedDelta: 1 + usage.inspectedItems,
                    skipDescendants: true
                )
            }

            if isDirectory {
                let directoryID = arena.addChild(
                    parent: parentID,
                    kind: .directory,
                    name: url.lastPathComponent,
                    path: url.path,
                    logicalSize: 0,
                    allocatedSize: 0,
                    isPackage: isPackage,
                    mayShareContent: mayShare,
                    isSparse: false,
                    isPurgeable: false,
                    writeAccess: writeAccess
                )
                return AddedEntry(directoryID: directoryID, inspectedDelta: 1, skipDescendants: false)
            }

            _ = arena.addChild(
                parent: parentID,
                kind: .file,
                name: url.lastPathComponent,
                path: url.path,
                logicalSize: logical,
                allocatedSize: allocated,
                isPackage: isPackage,
                mayShareContent: mayShare,
                isSparse: isSparse,
                isPurgeable: false,
                writeAccess: writeAccess
            )
            return AddedEntry(directoryID: nil, inspectedDelta: 1, skipDescendants: false)
        }

        func scanFastBranch(_ branchURL: URL, parentID: NodeID) throws {
            var enumerationOptions = listingOptions
            if options.treatPackagesAsLeaves { enumerationOptions.insert(.skipsPackageDescendants) }
            var branchWarnings: [String] = []
            guard let enumerator = FileManager.default.enumerator(
                at: branchURL,
                includingPropertiesForKeys: Self.resourceKeys,
                options: enumerationOptions,
                errorHandler: { url, error in
                    branchWarnings.append("Could not read contents of \(url.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                Self.recordWarning("Could not enumerate \(branchURL.path).", in: &warnings)
                return
            }

            var directoryStack: [NodeID] = [parentID]
            for case let url as URL in enumerator {
                if shouldCancel?() == true { break }
                let level = max(1, enumerator.level)
                while directoryStack.count > level { directoryStack.removeLast() }
                let currentParentID = directoryStack.last ?? parentID

                if Self.shouldSkipNonContentPath(path: url.path, rootPath: rootPath) {
                    enumerator.skipDescendants()
                    continue
                }

                let entry = try addEntry(url, to: currentParentID)
                if entry.skipDescendants { enumerator.skipDescendants() }
                if let directoryID = entry.directoryID { directoryStack.append(directoryID) }
                guard entry.inspectedDelta > 0 else { continue }
                scanned += entry.inspectedDelta
                publishProgress(at: url)
            }
            for warning in branchWarnings { Self.recordWarning(warning, in: &warnings) }
        }

        func scanBoundary(_ directoryURL: URL, parentID: NodeID) throws {
            if shouldCancel?() == true { return }
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: listingOptions
                )
            } catch {
                Self.recordWarning(
                    "Could not read contents of \(directoryURL.path): \(error.localizedDescription)",
                    in: &warnings
                )
                return
            }

            for url in children {
                if shouldCancel?() == true { break }
                if Self.shouldSkipNonContentPath(path: url.path, rootPath: rootPath) { continue }
                let entry = try addEntry(url, to: parentID)
                guard entry.inspectedDelta > 0 else { continue }
                scanned += entry.inspectedDelta
                publishProgress(at: url)

                guard let directoryID = entry.directoryID else { continue }
                if Self.isSegmentationBoundary(url.path) {
                    try scanBoundary(url, parentID: directoryID)
                } else {
                    try scanFastBranch(url, parentID: directoryID)
                }
            }
        }

        if rootPath == "/" {
            try scanBoundary(rootURL, parentID: .root)
        } else {
            try scanFastBranch(rootURL, parentID: .root)
        }
    }

    private static func isSegmentationBoundary(_ path: String) -> Bool {
        if path == "/System" || path == "/Users" { return true }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.first == "Users" else { return false }
        return components.count == 2
            || (components.count == 3 && components[2] == "Library")
    }

    /// Full-volume scans omit virtual namespaces, volume indexes, credential
    /// roots, and protected personal stores. They are not cleanup candidates;
    /// their physical use remains represented by whole-volume capacity.
    private static func shouldSkipNonContentPath(path: String, rootPath: String) -> Bool {
        guard rootPath == "/" else { return false }
        switch path {
        case "/Volumes",
             "/System/Volumes",
             "/dev",
             "/Network",
             "/net",
             "/home",
             "/.vol",
             "/.file",
             "/.resolve",
             "/.Spotlight-V100",
             "/.fseventsd",
             "/.Trashes",
             "/.TemporaryItems",
             "/.DocumentRevisions-V100",
             "/.MobileBackups":
            return true
        default:
            break
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 3, components[0] == "Users" else { return false }
        let relativePath = "/" + components.dropFirst(2).joined(separator: "/")
        let protectedRoots: Set<String> = [
            "/.Trash",
            "/.config",
            "/.cups",
            "/.ssh",
            "/.secrets",
            "/Library/Accounts",
            "/Library/Calendars",
            "/Library/HomeKit",
            "/Library/IdentityServices",
            "/Library/Mail",
            "/Library/Messages",
            "/Library/PersonalizationPortrait",
            "/Library/Safari",
            "/Library/Suggestions",
        ]
        return protectedRoots.contains(relativePath)
    }

    private static func recordWarning(_ warning: String, in warnings: inout [String]) {
        let limit = 240
        if warnings.count < limit {
            warnings.append(warning)
        } else if warnings.count == limit {
            warnings.append("Additional unreadable locations were omitted from this list.")
        }
    }

    /// Measures a package without adding its interior to the presentation tree.
    /// This retains a compact map while keeping bundle totals honest.
    private func measuredPackageUsage(
        at packageURL: URL,
        options: ScanOptions,
        scannedBase: Int,
        totalNodes: @escaping @Sendable () -> Int?,
        inventoryNodes: @escaping @Sendable () -> Int,
        progress: (@Sendable (ScanProgress) -> Void)?,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws -> (logical: UInt64, allocated: UInt64, inspectedItems: Int) {
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.showHiddenFiles {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: Self.resourceKeys,
            options: enumerationOptions
        ) else {
            return (0, 0, 0)
        }

        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        var inspectedItems = 0
        var lastProgressTime = Date.timeIntervalSinceReferenceDate
        for case let childURL as URL in enumerator {
            if shouldCancel?() == true { throw ScanError.cancelled }
            inspectedItems += 1
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastProgressTime >= 1.0 {
                lastProgressTime = now
                progress?(ScanProgress(
                    scannedNodes: scannedBase + 1 + inspectedItems,
                    currentPath: packageURL.path,
                    phase: .measuringPackage,
                    totalNodes: totalNodes(),
                    inventoryNodes: inventoryNodes()
                ))
            }
            guard let values = try? childURL.resourceValues(forKeys: Self.resourceKeySet) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory != true else { continue }

            let childLogical = UInt64(max(0, values.fileSize ?? 0))
            let childAllocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize
            logical += childLogical
            allocated += childAllocated.map { UInt64(max(0, $0)) } ?? childLogical
        }
        return (logical, allocated, inspectedItems)
    }

    private func emitProgressIfNeeded(
        arena: inout ScanNodeArena,
        warnings: [String],
        scanned: Int,
        lastProgressNodeCount: inout Int,
        lastProgressTime: inout TimeInterval,
        lastPartialSnapshotNodeCount: inout Int,
        rootBookmarkID: UUID?,
        rootName: String,
        currentPath: String,
        options: ScanOptions,
        totalNodes: @Sendable () -> Int?,
        inventoryNodes: @Sendable () -> Int,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) {
        guard let progress else { return }
        let now = Date.timeIntervalSinceReferenceDate
        // Filesystem enumeration can advance thousands of nodes between display
        // frames. A hard presentation ceiling keeps scan telemetry from
        // contending with pointer tracking and animation on the main actor.
        let hasNewWork = scanned > lastProgressNodeCount
        let presentationInterval: TimeInterval = 0.75
        let isPresentationDue = now - lastProgressTime >= presentationInterval
        let minimumDelta = partialSnapshotInterval(for: scanned)
        let publishesSnapshot = scanned - lastPartialSnapshotNodeCount >= minimumDelta
        guard hasNewWork, isPresentationDue else { return }

        var partialSession: ScanSession?
        if publishesSnapshot {
            lastPartialSnapshotNodeCount = scanned
            arena.aggregateTotals()
            partialSession = arena.makeSnapshot(
                rootBookmarkID: rootBookmarkID,
                rootDisplayName: rootName,
                options: options,
                warnings: warnings,
                isComplete: false
            )
        }
        lastProgressNodeCount = scanned
        lastProgressTime = now
        progress(ScanProgress(
            scannedNodes: scanned,
            currentPath: currentPath,
            totalNodes: totalNodes(),
            inventoryNodes: inventoryNodes(),
            partialSession: partialSession
        ))
    }

    /// A snapshot copies the mapped node arena and rebuilds the visible map.
    /// Publish early enough to establish trust, then become deliberately sparse
    /// so multi-million-node scans keep the interface responsive.
    private func partialSnapshotInterval(for scanned: Int) -> Int {
        switch scanned {
        case ..<5_000:
            return 1_000
        case ..<25_000:
            return 5_000
        case ..<100_000:
            return 20_000
        case ..<500_000:
            return 100_000
        default:
            return 500_000
        }
    }

    @discardableResult
    private func makeSnapshot(
        arena: inout ScanNodeArena,
        rootBookmarkID: UUID?,
        rootName: String,
        rootPath: String,
        options: ScanOptions,
        warnings: [String],
        scanned: Int,
        totalNodes: Int?,
        isComplete: Bool,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) -> ScanSession {
        progress?(ScanProgress(
            scannedNodes: max(scanned, totalNodes ?? 0),
            currentPath: rootPath,
            phase: .preparingMap,
            totalNodes: max(scanned, totalNodes ?? 0)
        ))
        arena.aggregateTotals()
        let snapshot = arena.makeSnapshot(
            rootBookmarkID: rootBookmarkID,
            rootDisplayName: rootName,
            options: options,
            warnings: warnings,
            isComplete: isComplete
        )
        return snapshot
    }
}
