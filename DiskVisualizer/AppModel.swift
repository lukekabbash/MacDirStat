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
    case scan
    case apps
    case review
    case settings
}

struct ScanActivity: Equatable {
    let startedAt: Date
    var phase: ScanProgress.Phase
    var inspectedItems: Int
    var inventoryItems: Int
    var currentPath: String
    var itemsPerSecond: Double
    var totalItems: Int?

    var currentLocation: String {
        let url = URL(fileURLWithPath: currentPath)
        let name = url.lastPathComponent
        return name.isEmpty ? "Macintosh HD" : name
    }

    var fractionCompleted: Double? {
        if phase == .preparingMap { return 1.0 }
        if let totalItems, totalItems > 0 {
            // Inventory is half of the deliberate work; measurement and map
            // construction make up the second half.
            let measuredFraction = min(1, max(0, Double(inspectedItems) / Double(totalItems)))
            return min(0.995, 0.5 + measuredFraction * 0.5)
        }

        let observedWork = max(0, inspectedItems) + max(0, inventoryItems)
        guard observedWork > 0 else { return 0 }
        // Until inventory finishes there is no truthful denominator. Use a
        // monotonic, capped estimate based only on work actually observed;
        // the exact phase always begins beyond this ceiling.
        let estimate = 0.48 * (1 - exp(-Double(observedWork) / 250_000))
        return min(0.48, max(0.01, estimate))
    }

    var percentageText: String? {
        guard let fractionCompleted else { return nil }
        let value = fractionCompleted.formatted(.percent.precision(.fractionLength(0)))
        return totalItems == nil && fractionCompleted > 0 ? "~\(value)" : value
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

final class CancellationState: @unchecked Sendable {
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
    @Published var appDestination: AppDestination = .scan {
        didSet {
            if appDestination == .apps { prepareAppInventory() }
        }
    }
    @Published var savedLocations: [SavedLocation] = []
    @Published var selectedLocationID: UUID?
    @Published var snapshotCatalogRevision = 0
    @Published var reviewItems: [ReviewItem] = []
    @Published var selectedReviewItemID: UUID?
    @Published var appInventoryScope: AppInventoryScope = .selectedLocation {
        didSet { prepareAppInventory() }
    }
    @Published var appInventory: [AppInventoryItem] = []
    @Published var selectedAppInventoryID: String?
    @Published var isPreparingAppInventory = false
    @Published var workspaceNotice: WorkspaceNotice?
    @Published var searchFocusRequest = 0
    @Published private(set) var sessionRevision = 0
    @Published var sizeMetric: SizeMetric = .allocated {
        didSet {
            resetVisibleOverviewIfNeeded()
            prepareOverviewIfNeeded()
            prepareSelectedOverviewGroupIfNeeded()
            prepareMapLegendIfNeeded()
            prepareAppInventory()
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
    @Published var showHiddenFiles = true {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Self.showHiddenFilesKey) }
    }
    @Published var treatPackagesAsLeaves = true {
        didSet { UserDefaults.standard.set(treatPackagesAsLeaves, forKey: Self.treatPackagesAsLeavesKey) }
    }
    @Published var calculatesExactProgress = true {
        didSet { UserDefaults.standard.set(calculatesExactProgress, forKey: Self.exactProgressKey) }
    }
    @Published var isScanning = false
    @Published var statusLine = "Choose a folder or volume to map."
    @Published private(set) var selectedNodeID: NodeID?
    @Published var focusedNodeID: NodeID = .root
    @Published var hoveredNodeID: NodeID?
    @Published var activeRoot: ScanRoot?
    @Published var showFreeSpaceInMap = false {
        didSet { UserDefaults.standard.set(showFreeSpaceInMap, forKey: Self.showFreeSpaceKey) }
    }
    @Published private(set) var volumeSpace: VolumeSpaceSnapshot?
    @Published var cleanupControlsEnabled = false
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    private let engine = ScanEngine()
    let quickLookService = QuickLookService()
    let savedLocationStore = SavedLocationStore.default
    let reviewStore = ReviewStore.default
    var locationSnapshots: [UUID: LocationSnapshot] = [:]
    var activeCancellationState: CancellationState?
    var activeScanID = UUID()
    var activeScanLocationID: UUID?
    var scanTask: Task<Void, Never>?
    var appInventoryTask: Task<Void, Never>?
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
    private static let themeDefaultsVersionKey = "themeDefaultsVersion"
    private static let showHiddenFilesKey = "showHiddenFiles"
    private static let treatPackagesAsLeavesKey = "treatPackagesAsLeaves"
    private static let exactProgressKey = "calculatesExactProgress"
    private static let showFreeSpaceKey = "showFreeSpaceInMap"

    init() {
        appearanceMode = DiskAppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? ""
        ) ?? .system
        let defaults = UserDefaults.standard
        let storedTheme = DiskThemeID(rawValue: defaults.string(forKey: Self.themeIDKey) ?? "")
        if defaults.integer(forKey: Self.themeDefaultsVersionKey) < 2 {
            themeID = .softGlass
            defaults.set(2, forKey: Self.themeDefaultsVersionKey)
            defaults.set(DiskThemeID.softGlass.rawValue, forKey: Self.themeIDKey)
        } else {
            themeID = storedTheme ?? .softGlass
        }
        showHiddenFiles = Self.storedBool(Self.showHiddenFilesKey, default: true)
        treatPackagesAsLeaves = Self.storedBool(Self.treatPackagesAsLeavesKey, default: true)
        calculatesExactProgress = Self.storedBool(Self.exactProgressKey, default: true)
        showFreeSpaceInMap = Self.storedBool(Self.showFreeSpaceKey, default: false)

        Task { await restorePersistentWorkspace() }
    }

    private static func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
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

    func pickAttachedVolume() {
        pickLocation(.attachedVolume)
    }

    private enum LocationIntent {
        case folder
        case startupVolume
        case attachedVolume
    }

    private func pickLocation(_ intent: LocationIntent) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        switch intent {
        case .folder:
            panel.message = "Choose a folder to map. Deletion remains disabled until you allow it in Settings."
            panel.prompt = "Map Folder"
        case .startupVolume:
            panel.directoryURL = URL(fileURLWithPath: "/", isDirectory: true)
            panel.message = "Choose Macintosh HD once to map the startup volume. This grants read access; deletion remains disabled."
            panel.prompt = "Map Full Mac"
        case .attachedVolume:
            panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
            panel.message = "Choose the root of an attached volume. Selecting it saves access but does not begin scanning."
            panel.prompt = "Add Volume"
        }
        guard panel.runModal() == .OK, let pickedURL = panel.url else { return }

        let url: URL
        switch intent {
        case .folder:
            url = pickedURL
        case .startupVolume, .attachedVolume:
            // A full-volume map must include hidden locations such as /private
            // and user Library data or it materially understates disk use.
            showHiddenFiles = true
            guard let volumeURL = try? pickedURL.resourceValues(forKeys: [.volumeURLKey]).volume else {
                statusLine = "Could not resolve the selected volume."
                return
            }
            guard pickedURL.standardizedFileURL.path == volumeURL.standardizedFileURL.path else {
                statusLine = "Choose the volume itself, not a folder inside it."
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
        addSavedLocation(root)
        appDestination = .scan
        statusLine = "\(root.displayName) is ready to scan"
    }

    /// File-change permission is a presentation and intent lock. The selected-folder bookmark
    /// already supplies the underlying read-write scope, so toggling it should
    /// never force an expensive filesystem rescan.
    func setCleanupControls(enabled: Bool) {
        guard let id = selectedLocationID,
              let index = savedLocations.firstIndex(where: { $0.id == id })
        else {
            cleanupControlsEnabled = false
            return
        }
        cleanupControlsEnabled = enabled
        savedLocations[index].scanRoot.accessMode = enabled ? .readWrite : .readOnly
        activeRoot = savedLocations[index].scanRoot
        persistLocations()
        refreshSelectedReviewStates()
        statusLine = enabled
            ? "Deletion allowed · every deletion still requires confirmation"
            : "Deletion disabled · snapshot unchanged"
    }

    func startScan() {
        guard let root = activeRoot else {
            statusLine = "Choose a location first."
            return
        }
        guard !isScanning else {
            statusLine = "One location is already scanning. Stop it before starting another."
            return
        }

        activeCancellationState?.cancel()
        scanTask?.cancel()
        let cancellationState = CancellationState()
        activeCancellationState = cancellationState
        let scanID = UUID()
        activeScanID = scanID
        let locationID = root.id
        activeScanLocationID = locationID
        let scanGeneration = UUID()

        let preservesCurrentSnapshot = locationSnapshots[locationID] != nil
        dashboardMode = .map
        isScanning = true
        scannedNodeCount = 0
        let scanStartedAt = Date()
        scanTelemetry.activity = ScanActivity(
            startedAt: scanStartedAt,
            phase: .discovering,
            inspectedItems: 0,
            inventoryItems: 0,
            currentPath: urlPathPlaceholder(for: root),
            itemsPerSecond: 0,
            totalItems: nil
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
            activeScanLocationID = nil
            scanTelemetry.activity = nil
            statusLine = "This location is no longer available. Choose it again."
            markLocationNeedsAccessIfRequired(locationID)
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            isScanning = false
            activeScanLocationID = nil
            scanTelemetry.activity = nil
            statusLine = "Access was denied. Choose the location again."
            markLocationNeedsAccessIfRequired(locationID)
            return
        }

        let scanVolumeSpace = VolumeSpaceSnapshot.read(from: url)
        if selectedLocationID == locationID { volumeSpace = scanVolumeSpace }

        let options = ScanOptions(
            metric: sizeMetric,
            showHiddenFiles: showHiddenFiles,
            treatPackagesAsLeaves: treatPackagesAsLeaves,
            calculatesExactProgress: calculatesExactProgress
        )

        let engine = self.engine
        scanTask = Task { [weak self] in
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let final = try await engine.scan(
                    rootURL: url,
                    rootBookmarkID: root.id,
                    options: options,
                    // The file-change lock, not the scanner, controls whether
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
                                inventoryItems: progress.inventoryNodes,
                                currentPath: progress.currentPath,
                                itemsPerSecond: smoothedRate,
                                totalItems: progress.totalNodes
                            )
                            self.lastProgressSampleTime = now
                            self.lastProgressSampleCount = progress.scannedNodes
                            if let partialSession = progress.partialSession {
                                let partialSnapshot = LocationSnapshot(
                                    locationID: locationID,
                                    session: partialSession,
                                    scannedAt: scanStartedAt,
                                    volumeSpace: scanVolumeSpace,
                                    generation: scanGeneration
                                )
                                self.locationSnapshots[locationID] = partialSnapshot
                                self.snapshotCatalogRevision &+= 1
                                if self.selectedLocationID == locationID {
                                    self.publishSession(partialSession)
                                }
                            }
                        }
                    },
                    shouldCancel: { [cancellationState] in
                        cancellationState.isCancelled() || Task.isCancelled
                    }
                )

                await MainActor.run {
                    guard let self, self.activeScanID == scanID else { return }
                    let scannedAt = Date()
                    let completedSnapshot = LocationSnapshot(
                        locationID: locationID,
                        session: final,
                        scannedAt: scannedAt,
                        volumeSpace: scanVolumeSpace,
                        generation: scanGeneration
                    )
                    self.locationSnapshots[locationID] = completedSnapshot
                    self.snapshotCatalogRevision &+= 1
                    if self.selectedLocationID == locationID {
                        self.publishSession(final)
                        self.volumeSpace = scanVolumeSpace
                    }
                    self.isScanning = false
                    self.activeScanLocationID = nil
                    let completedCount = max(0, final.nodes.count - 1)
                    if self.selectedLocationID == locationID {
                        self.scannedNodeCount = completedCount
                        self.holdCompletedScanActivity(
                            scanID: scanID,
                            startedAt: scanStartedAt,
                            finalCount: completedCount,
                            currentPath: url.path
                        )
                    } else {
                        self.scanTelemetry.activity = nil
                    }
                    self.scanTask = nil
                    self.activeCancellationState = nil
                    self.recordCompletedScan(
                        locationID: locationID,
                        session: final,
                        scannedAt: scannedAt,
                        volumeSpace: scanVolumeSpace
                    )
                    self.overviewCache.removeAll(keepingCapacity: true)
                    self.overviewGroupCache.removeAll(keepingCapacity: true)
                    self.mapLegendCache.removeAll(keepingCapacity: true)
                    if self.selectedLocationID == locationID {
                        self.statusLine = "Updated just now · \(completedCount.formatted()) items"
                        self.prepareMapLegendIfNeeded()
                        self.prepareOverviewIfNeeded()
                    }
                    self.refreshSelectedReviewStates()
                    self.prepareAppInventory()
                    if stale, self.selectedLocationID == locationID {
                        self.statusLine += " · choose the location again if paths fail"
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.activeScanID == scanID else { return }
                    self.isScanning = false
                    let failedLocationID = self.activeScanLocationID
                    self.activeScanLocationID = nil
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
                    if wasCancelled, self.selectedLocationID == failedLocationID {
                        self.statusLine = self.session == nil
                            ? "Scan stopped before a snapshot was ready"
                            : "Refresh stopped · showing the last available snapshot"
                        self.prepareOverviewIfNeeded()
                    } else if !wasCancelled {
                        if self.selectedLocationID == failedLocationID {
                            self.statusLine = "Scan failed · \(error.localizedDescription)"
                        }
                        if let failedLocationID {
                            self.markLocationNeedsAccessIfRequired(failedLocationID)
                        }
                    }
                }
            }
        }
    }

    private func holdCompletedScanActivity(
        scanID: UUID,
        startedAt: Date,
        finalCount: Int,
        currentPath: String
    ) {
        let previousActivity = scanTelemetry.activity
        let completedCount = max(finalCount, previousActivity?.totalItems ?? 0)
        scanTelemetry.activity = ScanActivity(
            startedAt: startedAt,
            phase: .preparingMap,
            inspectedItems: completedCount,
            inventoryItems: completedCount,
            currentPath: currentPath,
            itemsPerSecond: previousActivity?.itemsPerSecond ?? 0,
            totalItems: completedCount
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard let self,
                  self.activeScanID == scanID,
                  !self.isScanning,
                  self.scanTelemetry.activity?.phase == .preparingMap
            else { return }
            self.scanTelemetry.activity = nil
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
        let cancelledLocationID = activeScanLocationID
        activeScanLocationID = nil
        isScanning = false
        scanTelemetry.activity = nil
        scanTask = nil
        activeCancellationState = nil
        if let cancelledLocationID,
           let snapshot = locationSnapshots[cancelledLocationID],
           selectedLocationID == cancelledLocationID {
            publishSession(snapshot.session)
            scannedNodeCount = max(0, snapshot.session.nodes.count - 1)
            statusLine = "Scan stopped · showing the latest snapshot"
            prepareOverviewIfNeeded()
        } else if selectedLocationID == cancelledLocationID {
            scannedNodeCount = 0
            statusLine = "Scan stopped · ready when you are"
        }
    }

    func openSettings() {
        appDestination = .settings
    }

    func closeSettings() {
        appDestination = .scan
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

    func publishSession(_ value: ScanSession?) {
        session = value
        sessionRevision &+= 1
    }

    func presentLocationSnapshot(_ snapshot: LocationSnapshot?) {
        overviewTask?.cancel()
        overviewGroupTask?.cancel()
        mapLegendTask?.cancel()
        overviewCache.removeAll(keepingCapacity: true)
        overviewGroupCache.removeAll(keepingCapacity: true)
        mapLegendCache.removeAll(keepingCapacity: true)
        overviewGroups = []
        overviewLargestNodeIDs = []
        mapFileTypeGroups = []
        mapLocationGroups = []
        selectOverviewGroup(nil)
        selectNode(nil)
        focusedNodeID = .root
        hoveredNodeID = nil
        publishSession(snapshot?.session)
        volumeSpace = snapshot?.volumeSpace
        scannedNodeCount = max(0, (snapshot?.session.nodes.count ?? 1) - 1)
        if let snapshot, let location = selectedLocation {
            statusLine = "Scanned \(snapshot.scannedAt.formatted(.relative(presentation: .named))) · \(scannedNodeCount.formatted()) items"
            if location.availability != .ready { statusLine = "Snapshot only · source unavailable" }
            prepareMapLegendIfNeeded()
            prepareOverviewIfNeeded()
        } else if let location = selectedLocation {
            if let summary = location.lastScanSummary {
                statusLine = "Last scanned \(summary.scannedAt.formatted(.relative(presentation: .named))) · rescan to inspect details"
            } else {
                statusLine = "\(location.displayName) is ready to scan"
            }
        } else {
            statusLine = "Choose a saved location to begin"
        }
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
