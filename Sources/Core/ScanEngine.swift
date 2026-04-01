import Foundation

#if canImport(Darwin)

public struct ScanProgress: Sendable {
    public var scannedNodes: Int
    public var currentPath: String
    public var partialSession: ScanSession

    public init(scannedNodes: Int, currentPath: String, partialSession: ScanSession) {
        self.scannedNodes = scannedNodes
        self.currentPath = currentPath
        self.partialSession = partialSession
    }
}

/// Background filesystem scanner: no symlinks followed, packages optional leaf.
public final class ScanEngine: @unchecked Sendable {
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
        let rootName = rootURL.lastPathComponent
        arena.reset(rootName: rootName, rootPath: rootPath)

        var warnings: [String] = []
        var scanned = 0

        func emitPartial(complete: Bool) {
            arena.aggregateTotals()
            let snap = arena.makeSnapshot(
                rootBookmarkID: rootBookmarkID,
                rootDisplayName: rootName,
                options: options,
                warnings: warnings,
                isComplete: complete
            )
            progress?(ScanProgress(scannedNodes: scanned, currentPath: rootPath, partialSession: snap))
        }

        try enumerate(
            url: rootURL,
            parentID: .root,
            isUserSelectedRoot: true,
            options: options,
            writeAccess: writeAccess,
            arena: &arena,
            warnings: &warnings,
            scanned: &scanned,
            shouldCancel: shouldCancel,
            emitPartial: { emitPartial(complete: false) }
        )

        arena.aggregateTotals()
        let final = arena.makeSnapshot(
            rootBookmarkID: rootBookmarkID,
            rootDisplayName: rootName,
            options: options,
            warnings: warnings,
            isComplete: true
        )
        progress?(ScanProgress(scannedNodes: scanned, currentPath: rootPath, partialSession: final))
        return final
    }

    private func enumerate(
        url: URL,
        parentID: NodeID,
        isUserSelectedRoot: Bool,
        options: ScanOptions,
        writeAccess: Bool,
        arena: inout ScanNodeArena,
        warnings: inout [String],
        scanned: inout Int,
        shouldCancel: (@Sendable () -> Bool)?,
        emitPartial: () -> Void
    ) throws {
        if shouldCancel?() == true { return }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isPackageKey,
            .mayShareFileContentKey,
            .isSparseKey,
            .isUbiquitousItemKey,
        ]

        let values = try? url.resourceValues(forKeys: Set(keys))
        let isDir = values?.isDirectory == true
        let isPackage = values?.isPackage == true
        let mayShare = values?.mayShareFileContent == true
        let isSparse = values?.isSparse == true
        let logical = UInt64(values?.fileSize ?? Int64(clamping: 0))
        let allocated = UInt64(
            values?.totalFileAllocatedSize
                ?? values?.fileAllocatedSize
                ?? Int64(clamping: max(logical, 1))
        )

        if isDir {
            if options.treatPackagesAsLeaves && isPackage {
                let _ = arena.addChild(
                    parent: parentID,
                    kind: .packageLeaf,
                    name: url.lastPathComponent,
                    path: url.path,
                    logicalSize: logical,
                    allocatedSize: max(allocated, logical),
                    isPackage: true,
                    mayShareContent: mayShare,
                    isSparse: isSparse,
                    isPurgeable: false,
                    writeAccess: writeAccess
                )
                scanned += 1
                if scanned % 400 == 0 { emitPartial() }
                return
            }

            let childURLs: [URL]
            do {
                childURLs = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsPackageDescendants]
                )
            } catch {
                warnings.append("Could not read contents of \(url.path): \(error.localizedDescription)")
                return
            }

            let visible = childURLs.filter { u in
                if options.showHiddenFiles { return true }
                return !u.lastPathComponent.hasPrefix(".")
            }

            if isUserSelectedRoot {
                for child in visible.sorted(by: { $0.path < $1.path }) {
                    if shouldCancel?() == true { break }
                    var isSym = false
                    if let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey]) {
                        isSym = rv.isSymbolicLink == true
                    }
                    if isSym { continue }

                    try enumerate(
                        url: child,
                        parentID: .root,
                        isUserSelectedRoot: false,
                        options: options,
                        writeAccess: writeAccess,
                        arena: &arena,
                        warnings: &warnings,
                        scanned: &scanned,
                        shouldCancel: shouldCancel,
                        emitPartial: emitPartial
                    )
                }
                return
            }

            let dirID = arena.addChild(
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
            scanned += 1
            if scanned % 400 == 0 { emitPartial() }

            for child in visible.sorted(by: { $0.path < $1.path }) {
                if shouldCancel?() == true { break }
                var isSym = false
                if let rv = try? child.resourceValues(forKeys: [.isSymbolicLinkKey]) {
                    isSym = rv.isSymbolicLink == true
                }
                if isSym { continue }

                try enumerate(
                    url: child,
                    parentID: dirID,
                    isUserSelectedRoot: false,
                    options: options,
                    writeAccess: writeAccess,
                    arena: &arena,
                    warnings: &warnings,
                    scanned: &scanned,
                    shouldCancel: shouldCancel,
                    emitPartial: emitPartial
                )
            }
        } else {
            let _ = arena.addChild(
                parent: parentID,
                kind: .file,
                name: url.lastPathComponent,
                path: url.path,
                logicalSize: logical,
                allocatedSize: max(allocated, logical),
                isPackage: isPackage,
                mayShareContent: mayShare,
                isSparse: isSparse,
                isPurgeable: false,
                writeAccess: writeAccess
            )
            scanned += 1
            if scanned % 400 == 0 { emitPartial() }
        }
    }
}

#endif
