import AppKit
import Combine
import Core
import Foundation
import Treemap

enum DashboardMode: String, CaseIterable {
    case map
    case overview

    var displayName: String {
        switch self {
        case .map: return "Map"
        case .overview: return "Overview"
        }
    }
}

enum AppDestination: String, CaseIterable {
    case workspace
    case settings
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case scanning
    case cleanup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appearance: return "Appearance"
        case .scanning: return "Scanning"
        case .cleanup: return "Cleanup"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: return "circle.lefthalf.filled"
        case .scanning: return "internaldrive"
        case .cleanup: return "lock.shield"
        }
    }
}

struct ScanActivity: Equatable {
    let startedAt: Date
    var phase: ScanProgress.Phase
    var inspectedItems: Int
    var currentPath: String
    var itemsPerSecond: Double

    var currentLocation: String {
        let url = URL(fileURLWithPath: currentPath)
        let name = url.lastPathComponent
        return name.isEmpty ? "Macintosh HD" : name
    }
}

/// High-frequency scan telemetry is isolated from the application model so a
/// counter tick does not invalidate the treemap, inspector, and every rail row.
@MainActor
final class ScanTelemetryState: ObservableObject {
    @Published var activity: ScanActivity?
}

/// Physical capacity for the volume that contains the selected scan root.
/// It stays separate from scan totals because a folder snapshot and a whole
/// APFS volume answer different questions.
struct VolumeSpaceSnapshot: Equatable, Sendable {
    let name: String
    let capacity: UInt64
    let available: UInt64

    var used: UInt64 { capacity > available ? capacity - available : 0 }

    static func read(from url: URL) -> VolumeSpaceSnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let rawCapacity = values.volumeTotalCapacity,
              let rawAvailable = values.volumeAvailableCapacity,
              rawCapacity > 0
        else { return nil }

        let capacity = UInt64(rawCapacity)
        let available = UInt64(max(0, min(rawAvailable, rawCapacity)))
        return VolumeSpaceSnapshot(
            name: values.volumeName ?? "Volume",
            capacity: capacity,
            available: available
        )
    }
}

private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var appearanceMode: DiskAppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }
    @Published var themeID: DiskThemeID {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: Self.themeIDKey) }
    }
    @Published var session: ScanSession?
    @Published var appDestination: AppDestination = .workspace
    @Published var settingsSection: SettingsSection = .appearance
    @Published private(set) var sessionRevision = 0
    @Published var sizeMetric: SizeMetric = .allocated {
        didSet {
            resetVisibleOverviewIfNeeded()
            prepareOverviewIfNeeded()
            prepareSelectedOverviewGroupIfNeeded()
            prepareMapLegendIfNeeded()
        }
    }
    @Published var dashboardMode: DashboardMode = .map {
        didSet {
            if dashboardMode == .map { selectOverviewGroup(nil) }
            resetVisibleOverviewIfNeeded()
            prepareOverviewIfNeeded()
        }
    }
    @Published var treemapColorMode: TreemapColorMode = .fileCategory
    @Published var overviewGrouping: StorageBreakdownGrouping = .fileType {
        didSet {
            selectNode(nil)
            selectOverviewGroup(nil)
            resetVisibleOverviewIfNeeded()
            prepareOverviewIfNeeded()
        }
    }
    @Published private(set) var overviewGroups: [StorageBreakdownItem] = []
    @Published private(set) var overviewLargestNodeIDs: [NodeID] = []
    @Published private(set) var isPreparingOverview = false
    @Published private(set) var selectedOverviewGroupID: String?
    @Published private(set) var overviewGroupLargestNodeIDs: [NodeID] = []
    @Published private(set) var isPreparingOverviewGroup = false
    @Published private(set) var mapFileTypeGroups: [StorageBreakdownItem] = []
    @Published private(set) var mapLocationGroups: [StorageBreakdownItem] = []
    @Published private(set) var isPreparingMapLegend = false
    @Published private(set) var scannedNodeCount = 0
    let scanTelemetry = ScanTelemetryState()
    @Published var showHiddenFiles = true
    @Published var treatPackagesAsLeaves = true
    @Published var isScanning = false
    @Published var statusLine = "Choose a folder or volume to map."
    @Published private(set) var selectedNodeID: NodeID?
    @Published var focusedNodeID: NodeID = .root
    @Published var hoveredNodeID: NodeID?
    @Published var activeRoot: ScanRoot?
    @Published var showFreeSpaceInMap = false
    @Published private(set) var volumeSpace: VolumeSpaceSnapshot?
    @Published private(set) var cleanupControlsEnabled = false
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    private let engine = ScanEngine()
    private var activeCancellationState: CancellationState?
    private var activeScanID = UUID()
    private var scanTask: Task<Void, Never>?
    private var overviewTask: Task<Void, Never>?
    private var overviewGroupTask: Task<Void, Never>?
    private var mapLegendTask: Task<Void, Never>?
    private var overviewCache: [String: ([StorageBreakdownItem], [NodeID])] = [:]
    private var overviewGroupCache: [String: [NodeID]] = [:]
    private var mapLegendCache: [String: ([StorageBreakdownItem], [StorageBreakdownItem])] = [:]
    private var lastProgressSampleTime: TimeInterval?
    private var lastProgressSampleCount = 0

    private static let appearanceModeKey = "appearanceMode"
    private static let themeIDKey = "themeID"

    init() {
        appearanceMode = DiskAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? ""
        ) ?? .system
        themeID = DiskThemeID(
            rawValue: UserDefaults.standard.string(forKey: Self.themeIDKey) ?? ""
        ) ?? .integrator

        Task {
            try? await BookmarkStore.default.load()
            let roots = await BookmarkStore.default.allRoots()
            await MainActor.run {
                if var last = roots.last {
                    var stale = false
                    if let url = try? URL(
                        resolvingBookmarkData: last.bookmarkData,
                        options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    ), url.standardizedFileURL.path == "/" {
                        let name = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
                        last.displayName = name ?? "Macintosh HD"
                    }
                    // Restore intent, never work. Launching the app must be an
                    // idle operation; the user explicitly starts every scan.
                    last.accessMode = .readOnly
                    self.activeRoot = last
                    self.statusLine = "\(last.displayName) is ready to scan"
                    Task { try? await BookmarkStore.default.upsert(last) }
                }
            }
        }
    }

    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        showOnboarding = false
    }

    func pickFolder() {
        pickLocation(.folder)
    }

    func pickFullMac() {
        pickLocation(.startupVolume)
    }

    private enum LocationIntent {
        case folder
        case startupVolume
    }

    private func pickLocation(_ intent: LocationIntent) {
        cancelActiveScan()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        switch intent {
        case .folder:
            panel.message = "Choose a folder to map. Cleanup remains locked until you enable it."
            panel.prompt = "Map Folder"
        case .startupVolume:
            panel.directoryURL = URL(fileURLWithPath: "/", isDirectory: true)
            panel.message = "Choose Macintosh HD once to map the startup volume. This grants read access; cleanup remains locked."
            panel.prompt = "Map Full Mac"
        }
        guard panel.runModal() == .OK, let pickedURL = panel.url else { return }

        let url: URL
        switch intent {
        case .folder:
            url = pickedURL
        case .startupVolume:
            // A full-volume map must include hidden locations such as /private
            // and user Library data or it materially understates disk use.
            showHiddenFiles = true
            guard let volumeURL = try? pickedURL.resourceValues(forKeys: [.volumeURLKey]).volume else {
                statusLine = "Could not resolve the selected startup volume."
                return
            }
            guard pickedURL.standardizedFileURL.path == volumeURL.standardizedFileURL.path else {
                statusLine = "Choose Macintosh HD itself, not a folder inside it."
                return
            }
            url = volumeURL
        }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            statusLine = "Could not remember this location: \(error.localizedDescription)"
            return
        }

        var stale = false
        let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let volumeIdentifier: String? = resolved.flatMap { resolvedURL in
            guard let identifier = try? resolvedURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
                return nil
            }
            return String(describing: identifier)
        }

        let volumeName = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName
        let displayName = intent == .startupVolume
            ? (volumeName ?? "Macintosh HD")
            : (url.lastPathComponent.isEmpty ? (volumeName ?? "Volume") : url.lastPathComponent)
        let root = ScanRoot(
            displayName: displayName,
            volumeIdentifier: volumeIdentifier,
            accessMode: .readOnly,
            bookmarkData: bookmark
        )
        activeRoot = root
        cleanupControlsEnabled = false
        publishSession(nil)
        overviewGroups = []
        overviewLargestNodeIDs = []
        mapFileTypeGroups = []
        mapLocationGroups = []
        volumeSpace = nil
        selectOverviewGroup(nil)
        selectNode(nil)
        Task { try? await BookmarkStore.default.upsert(root) }
        appDestination = .workspace
        statusLine = "\(root.displayName) is ready to scan"
    }

    /// Cleanup is a presentation and intent lock. The selected-folder bookmark
    /// already supplies the underlying read-write scope, so toggling it should
    /// never force an expensive filesystem rescan.
    func setCleanupControls(enabled: Bool) {
        cleanupControlsEnabled = enabled
        guard var root = activeRoot else { return }
        root.accessMode = enabled ? .readWrite : .readOnly
        activeRoot = root
        Task { try? await BookmarkStore.default.upsert(root) }
        statusLine = enabled
            ? "Cleanup unlocked · every move still requires confirmation"
            : "Cleanup locked · snapshot unchanged"
    }

    func startScan() {
        guard let root = activeRoot else {
            statusLine = "Choose a location first."
            return
        }

        activeCancellationState?.cancel()
        scanTask?.cancel()
        let cancellationState = CancellationState()
        activeCancellationState = cancellationState
        let scanID = UUID()
        activeScanID = scanID

        let preservesCurrentSnapshot = session?.rootURLBookmarkID == root.id
        isScanning = true
        scannedNodeCount = 0
        let scanStartedAt = Date()
        scanTelemetry.activity = ScanActivity(
            startedAt: scanStartedAt,
            phase: .discovering,
            inspectedItems: 0,
            currentPath: urlPathPlaceholder(for: root),
            itemsPerSecond: 0
        )
        lastProgressSampleTime = Date.timeIntervalSinceReferenceDate
        lastProgressSampleCount = 0
        statusLine = preservesCurrentSnapshot ? "Refreshing in the background…" : "Building the first snapshot…"
        if !preservesCurrentSnapshot {
            publishSession(nil)
            overviewGroups = []
            overviewLargestNodeIDs = []
        }
        selectNode(nil)
        selectOverviewGroup(nil)
        focusedNodeID = .root
        hoveredNodeID = nil

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: root.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            isScanning = false
            scanTelemetry.activity = nil
            statusLine = "This location is no longer available. Choose it again."
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            isScanning = false
            scanTelemetry.activity = nil
            statusLine = "Access was denied. Choose the location again."
            return
        }

        volumeSpace = VolumeSpaceSnapshot.read(from: url)

        let options = ScanOptions(
            metric: sizeMetric,
            showHiddenFiles: showHiddenFiles,
            treatPackagesAsLeaves: treatPackagesAsLeaves
        )

        let engine = self.engine
        scanTask = Task { [weak self] in
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let final = try await engine.scan(
                    rootURL: url,
                    rootBookmarkID: root.id,
                    options: options,
                    // The cleanup lock, not the scanner, controls whether
                    // mutation is offered to the user.
                    writeAccess: true,
                    progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.activeScanID == scanID else { return }
                            let now = Date.timeIntervalSinceReferenceDate
                            let previousTime = self.lastProgressSampleTime ?? now
                            let elapsed = max(0.001, now - previousTime)
                            let delta = max(0, progress.scannedNodes - self.lastProgressSampleCount)
                            let instantRate = Double(delta) / elapsed
                            let previousRate = self.scanTelemetry.activity?.itemsPerSecond ?? 0
                            let smoothedRate = previousRate == 0
                                ? instantRate
                                : previousRate * 0.72 + instantRate * 0.28
                            self.scanTelemetry.activity = ScanActivity(
                                startedAt: scanStartedAt,
                                phase: progress.phase,
                                inspectedItems: progress.scannedNodes,
                                currentPath: progress.currentPath,
                                itemsPerSecond: smoothedRate
                            )
                            self.lastProgressSampleTime = now
                            self.lastProgressSampleCount = progress.scannedNodes
                            if !preservesCurrentSnapshot, let partialSession = progress.partialSession {
                                self.publishSession(partialSession)
                            }
                        }
                    },
                    shouldCancel: { [cancellationState] in
                        cancellationState.isCancelled() || Task.isCancelled
                    }
                )

                await MainActor.run {
                    guard let self, self.activeScanID == scanID else { return }
                    self.publishSession(final)
                    self.isScanning = false
                    self.scanTelemetry.activity = nil
                    self.scannedNodeCount = max(0, final.nodes.count - 1)
                    self.scanTask = nil
                    self.activeCancellationState = nil
                    self.overviewCache.removeAll(keepingCapacity: true)
                    self.overviewGroupCache.removeAll(keepingCapacity: true)
                    self.mapLegendCache.removeAll(keepingCapacity: true)
                    self.statusLine = "Updated just now · \(self.scannedNodeCount.formatted()) items"
                    self.prepareMapLegendIfNeeded()
                    self.prepareOverviewIfNeeded()
                    if stale {
                        self.statusLine += " · choose the location again if paths fail"
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.activeScanID == scanID else { return }
                    self.isScanning = false
                    self.scanTelemetry.activity = nil
                    self.scanTask = nil
                    self.activeCancellationState = nil
                    let wasCancelled: Bool
                    if error is CancellationError {
                        wasCancelled = true
                    } else if case ScanError.cancelled = error {
                        wasCancelled = true
                    } else {
                        wasCancelled = false
                    }
                    if wasCancelled {
                        self.statusLine = self.session == nil
                            ? "Scan stopped before a snapshot was ready"
                            : "Refresh stopped · showing the last available snapshot"
                        self.prepareOverviewIfNeeded()
                    } else {
                        self.statusLine = "Scan failed · \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func cancelActiveScan() {
        guard isScanning else { return }
        activeCancellationState?.cancel()
        scanTask?.cancel()
        // Cancellation of a blocked filesystem call is cooperative. Retire its
        // identity immediately so the interface never waits for that unwind and
        // no late progress or result can replace the snapshot on screen.
        activeScanID = UUID()
        isScanning = false
        scanTelemetry.activity = nil
        scanTask = nil
        activeCancellationState = nil
        if let session {
            scannedNodeCount = max(0, session.nodes.count - 1)
            statusLine = "Scan stopped · showing the latest snapshot"
            prepareOverviewIfNeeded()
        } else {
            scannedNodeCount = 0
            statusLine = "Scan stopped · ready when you are"
        }
    }

    func openSettings(_ section: SettingsSection = .appearance) {
        settingsSection = section
        appDestination = .settings
    }

    func closeSettings() {
        appDestination = .workspace
    }

    private func urlPathPlaceholder(for root: ScanRoot) -> String {
        root.displayName == "Macintosh HD" ? "/" : root.displayName
    }

    func focus(on nodeID: NodeID) {
        focusedNodeID = nodeID
    }

    func selectNode(_ nodeID: NodeID?) {
        selectedNodeID = nodeID
        if nodeID != nil { selectOverviewGroup(nil) }
    }

    func selectOverviewGroup(_ groupID: String?) {
        overviewGroupTask?.cancel()
        selectedOverviewGroupID = groupID
        if groupID != nil { selectedNodeID = nil }
        overviewGroupLargestNodeIDs = []
        isPreparingOverviewGroup = false
        prepareSelectedOverviewGroupIfNeeded()
    }

    private func publishSession(_ value: ScanSession?) {
        session = value
        sessionRevision &+= 1
    }

    private func resetVisibleOverviewIfNeeded() {
        guard dashboardMode == .overview else { return }
        overviewTask?.cancel()
        overviewGroups = []
        overviewLargestNodeIDs = []
        isPreparingOverview = false
    }

    private func prepareOverviewIfNeeded() {
        guard dashboardMode == .overview, let session else { return }

        let metric = sizeMetric
        let grouping = overviewGrouping
        let nodeCount = session.nodes.count
        let cacheKey = [
            session.rootURLBookmarkID?.uuidString ?? session.rootDisplayName,
            String(nodeCount),
            String(session.rootTotalAllocated),
            metric.rawValue,
            grouping.rawValue,
        ].joined(separator: ":")

        if let cached = overviewCache[cacheKey] {
            overviewTask?.cancel()
            overviewGroups = cached.0
            overviewLargestNodeIDs = cached.1
            isPreparingOverview = false
            prepareSelectedOverviewGroupIfNeeded()
            return
        }

        overviewTask?.cancel()
        isPreparingOverview = true
        overviewTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                (
                    StorageBreakdownBuilder.items(
                        in: session,
                        metric: metric,
                        grouping: grouping,
                        limit: grouping == .fileType ? 8 : 7
                    ),
                    StorageBreakdownBuilder.largestLeafNodeIDs(
                        in: session,
                        metric: metric,
                        limit: 14
                    )
                )
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.session?.nodes.count == nodeCount,
                  self.sizeMetric == metric,
                  self.overviewGrouping == grouping,
                  self.dashboardMode == .overview
            else { return }

            self.overviewCache[cacheKey] = result
            self.overviewGroups = result.0
            self.overviewLargestNodeIDs = result.1
            self.isPreparingOverview = false
            self.prepareSelectedOverviewGroupIfNeeded()
        }
    }

    private func prepareMapLegendIfNeeded() {
        guard let session, session.isComplete else { return }
        let metric = sizeMetric
        let nodeCount = session.nodes.count
        let cacheKey = [
            session.rootURLBookmarkID?.uuidString ?? session.rootDisplayName,
            String(nodeCount),
            String(session.rootTotalAllocated),
            metric.rawValue,
        ].joined(separator: ":")

        if let cached = mapLegendCache[cacheKey] {
            mapLegendTask?.cancel()
            mapFileTypeGroups = cached.0
            mapLocationGroups = cached.1
            isPreparingMapLegend = false
            return
        }

        mapLegendTask?.cancel()
        isPreparingMapLegend = true
        mapLegendTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                (
                    StorageBreakdownBuilder.items(
                        in: session,
                        metric: metric,
                        grouping: .fileType,
                        limit: 6
                    ),
                    StorageBreakdownBuilder.items(
                        in: session,
                        metric: metric,
                        grouping: .location,
                        limit: 6
                    )
                )
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.session?.nodes.count == nodeCount,
                  self.sizeMetric == metric
            else { return }

            self.mapLegendCache[cacheKey] = result
            self.mapFileTypeGroups = result.0
            self.mapLocationGroups = result.1
            self.isPreparingMapLegend = false
        }
    }

    private func prepareSelectedOverviewGroupIfNeeded() {
        guard dashboardMode == .overview,
              let session,
              let groupID = selectedOverviewGroupID,
              let group = overviewGroups.first(where: { $0.id == groupID })
        else { return }

        let metric = sizeMetric
        let grouping = overviewGrouping
        let nodeCount = session.nodes.count
        let cacheKey = [
            session.rootURLBookmarkID?.uuidString ?? session.rootDisplayName,
            String(nodeCount),
            String(session.rootTotalAllocated),
            metric.rawValue,
            grouping.rawValue,
            group.memberKeys.sorted().joined(separator: ","),
        ].joined(separator: ":")

        if let cached = overviewGroupCache[cacheKey] {
            overviewGroupTask?.cancel()
            overviewGroupLargestNodeIDs = cached
            isPreparingOverviewGroup = false
            return
        }

        overviewGroupTask?.cancel()
        isPreparingOverviewGroup = true
        overviewGroupTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                StorageBreakdownBuilder.largestLeafNodeIDs(
                    in: session,
                    metric: metric,
                    grouping: grouping,
                    memberKeys: group.memberKeys,
                    limit: 10
                )
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.session?.nodes.count == nodeCount,
                  self.sizeMetric == metric,
                  self.overviewGrouping == grouping,
                  self.selectedOverviewGroupID == groupID
            else { return }

            self.overviewGroupCache[cacheKey] = result
            self.overviewGroupLargestNodeIDs = result
            self.isPreparingOverviewGroup = false
        }
    }
}
