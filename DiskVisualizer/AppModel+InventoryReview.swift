import AppKit
import Core
import Foundation

struct AppInventoryCacheKey: Hashable, Sendable {
    let snapshotCatalogRevision: Int
    let scope: String
    let selectedLocationID: UUID?
}

struct AppBundleSignature: Hashable, Sendable {
    let path: String
    let bundleModifiedAt: Int64?
    let infoModifiedAt: Int64?
    let infoSize: Int?
    let fallbackGeneration: UUID?
}

struct CachedAppMetadata: Sendable {
    let signature: AppBundleSignature
    let displayName: String
    let version: String?
    let bundleIdentifier: String?
}

struct CachedAppIcon {
    let signature: AppBundleSignature
    let image: NSImage
}

struct AppInventoryDiagnostics: Equatable {
    var buildStarts = 0
    var cacheHits = 0
    var inFlightDeduplications = 0
    var cancelledGenerations = 0
    var staleResultsRejected = 0
    var metadataReads = 0
    var metricResorts = 0
    var iconLoads = 0
}

@MainActor
final class AppInventoryPipelineState {
    var buildTask: Task<Void, Never>?
    var iconTask: Task<Void, Never>?
    var inFlightKey: AppInventoryCacheKey?
    var presentedKey: AppInventoryCacheKey?
    var iconKey: AppInventoryCacheKey?
    var buildGeneration = UUID()
    var iconGeneration = UUID()
    var inventoryCache: [AppInventoryCacheKey: [AppInventoryItem]] = [:]
    var metadataByPath: [String: CachedAppMetadata] = [:]
    var iconByPath: [String: CachedAppIcon] = [:]
    var placeholderIcon: NSImage?
    var diagnostics = AppInventoryDiagnostics()
}

private struct AppMetadataResult: Sendable {
    let reference: AppPackageReference
    let signature: AppBundleSignature
    let displayName: String
    let version: String?
    let bundleIdentifier: String?
    let sourceName: String
}

private struct AppInventoryBuildOutput: Sendable {
    let results: [AppMetadataResult]
    let metadataUpdates: [String: CachedAppMetadata]
    let metadataReads: Int
}

private enum AppInventoryOrdering {
    static func sorted(_ items: [AppInventoryItem], metric: SizeMetric) -> [AppInventoryItem] {
        items.sorted { lhs, rhs in
            let leftSize = lhs.reference.size(for: metric)
            let rightSize = rhs.reference.size(for: metric)
            if leftSize != rightSize { return leftSize > rightSize }
            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

private enum AppInventoryLoader {
    private static let signatureKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]

    static func load(
        snapshots: [LocationSnapshot],
        locationsByID: [UUID: SavedLocation],
        cachedMetadata: [String: CachedAppMetadata]
    ) -> AppInventoryBuildOutput {
        var output: [AppMetadataResult] = []
        var updates: [String: CachedAppMetadata] = [:]
        var metadataReads = 0

        for snapshot in snapshots {
            guard !Task.isCancelled,
                  let location = locationsByID[snapshot.locationID]
            else { continue }

            let references = AppsProjectionBuilder.make(
                locationID: snapshot.locationID,
                generation: snapshot.generation,
                scannedAt: snapshot.scannedAt,
                session: snapshot.session
            )
            var stale = false
            let rootURL = try? URL(
                resolvingBookmarkData: location.scanRoot.bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            let accessed = rootURL?.startAccessingSecurityScopedResource() ?? false

            for reference in references {
                guard !Task.isCancelled else { break }
                let signature = signature(for: reference)
                let metadata: CachedAppMetadata
                if let cached = updates[reference.path] ?? cachedMetadata[reference.path],
                   cached.signature == signature {
                    metadata = cached
                } else {
                    metadataReads += 1
                    metadata = readMetadata(reference: reference, signature: signature)
                    updates[reference.path] = metadata
                }
                output.append(AppMetadataResult(
                    reference: reference,
                    signature: signature,
                    displayName: metadata.displayName,
                    version: metadata.version,
                    bundleIdentifier: metadata.bundleIdentifier,
                    sourceName: location.displayName
                ))
            }

            if accessed { rootURL?.stopAccessingSecurityScopedResource() }
        }
        return AppInventoryBuildOutput(
            results: output,
            metadataUpdates: updates,
            metadataReads: metadataReads
        )
    }

    private static func signature(for reference: AppPackageReference) -> AppBundleSignature {
        let bundleURL = URL(fileURLWithPath: reference.path, isDirectory: true)
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        let bundleValues = try? bundleURL.resourceValues(forKeys: signatureKeys)
        let infoValues = try? infoURL.resourceValues(forKeys: signatureKeys)
        let bundleModifiedAt = timestamp(bundleValues?.contentModificationDate)
        let infoModifiedAt = timestamp(infoValues?.contentModificationDate)
        let infoSize = infoValues?.fileSize
        return AppBundleSignature(
            path: reference.path,
            bundleModifiedAt: bundleModifiedAt,
            infoModifiedAt: infoModifiedAt,
            infoSize: infoSize,
            fallbackGeneration: bundleModifiedAt == nil && infoModifiedAt == nil && infoSize == nil
                ? reference.snapshotGeneration
                : nil
        )
    }

    private static func readMetadata(
        reference: AppPackageReference,
        signature: AppBundleSignature
    ) -> CachedAppMetadata {
        let bundle = Bundle(path: reference.path)
        let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? URL(fileURLWithPath: reference.fallbackName).deletingPathExtension().lastPathComponent
        let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        return CachedAppMetadata(
            signature: signature,
            displayName: displayName,
            version: version,
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }

    private static func timestamp(_ date: Date?) -> Int64? {
        date.map { Int64(($0.timeIntervalSinceReferenceDate * 1_000).rounded()) }
    }
}

extension AppModel {
    var appInventoryDiagnostics: AppInventoryDiagnostics {
        appInventoryPipeline.diagnostics
    }

    func prepareAppInventory() {
        guard appDestination == .apps else { return }

        let key = appInventoryCacheKey()
        if let cached = appInventoryPipeline.inventoryCache[key] {
            appInventoryPipeline.diagnostics.cacheHits += 1
            appInventoryPipeline.buildTask?.cancel()
            appInventoryPipeline.buildTask = nil
            appInventoryPipeline.inFlightKey = nil
            if appInventoryPipeline.presentedKey != key {
                installAppInventory(cached, for: key)
            } else {
                isPreparingAppInventory = false
            }
            scheduleMissingAppIcons(for: key)
            return
        }

        if appInventoryPipeline.inFlightKey == key,
           appInventoryPipeline.buildTask != nil {
            appInventoryPipeline.diagnostics.inFlightDeduplications += 1
            return
        }

        let snapshots = appInventorySnapshots()
        guard !snapshots.isEmpty else {
            cancelAppInventoryPipeline()
            appInventory = []
            appInventoryPipeline.inventoryCache[key] = []
            appInventoryPipeline.presentedKey = key
            isPreparingAppInventory = false
            return
        }

        if appInventoryPipeline.buildTask != nil {
            appInventoryPipeline.diagnostics.cancelledGenerations += 1
        }
        appInventoryPipeline.buildTask?.cancel()
        appInventoryPipeline.iconTask?.cancel()
        appInventoryPipeline.iconTask = nil
        appInventoryPipeline.iconKey = nil

        // A different scope/revision must never present actionable rows from
        // the previous cache while its replacement is being prepared.
        if appInventoryPipeline.presentedKey != key {
            appInventory = []
            selectedAppInventoryID = nil
            appInventoryPipeline.presentedKey = nil
        }

        let locationsByID = Dictionary(uniqueKeysWithValues: savedLocations.map { ($0.id, $0) })
        let cachedMetadata = appInventoryPipeline.metadataByPath
        let generation = UUID()
        appInventoryPipeline.buildGeneration = generation
        appInventoryPipeline.inFlightKey = key
        appInventoryPipeline.diagnostics.buildStarts += 1
        isPreparingAppInventory = true
        let worker = Task.detached(priority: .userInitiated) {
            AppInventoryLoader.load(
                snapshots: snapshots,
                locationsByID: locationsByID,
                cachedMetadata: cachedMetadata
            )
        }
        appInventoryPipeline.buildTask = Task { @MainActor [weak self] in
            let output = await withTaskCancellationHandler(
                operation: { await worker.value },
                onCancel: { worker.cancel() }
            )
            guard !Task.isCancelled, let self else { return }
            self.finishAppInventoryBuild(output, key: key, generation: generation)
        }
    }

    func resortAppInventoryForMetric() {
        guard !appInventory.isEmpty else { return }
        appInventory = AppInventoryOrdering.sorted(appInventory, metric: sizeMetric)
        appInventoryPipeline.diagnostics.metricResorts += 1
    }

    private func appInventoryCacheKey() -> AppInventoryCacheKey {
        AppInventoryCacheKey(
            snapshotCatalogRevision: snapshotCatalogRevision,
            scope: appInventoryScope.rawValue,
            selectedLocationID: appInventoryScope == .selectedLocation ? selectedLocationID : nil
        )
    }

    private func appInventorySnapshots() -> [LocationSnapshot] {
        let snapshots: [LocationSnapshot]
        switch appInventoryScope {
        case .selectedLocation:
            snapshots = selectedLocationID.flatMap { locationSnapshots[$0] }.map { [$0] } ?? []
        case .allCompletedLocations:
            snapshots = Array(locationSnapshots.values)
        }
        return snapshots
            .filter(\.session.isComplete)
            .sorted { $0.locationID.uuidString < $1.locationID.uuidString }
    }

    private func finishAppInventoryBuild(
        _ output: AppInventoryBuildOutput,
        key: AppInventoryCacheKey,
        generation: UUID
    ) {
        guard appInventoryPipeline.buildGeneration == generation,
              appInventoryPipeline.inFlightKey == key,
              appInventoryCacheKey() == key
        else {
            appInventoryPipeline.diagnostics.staleResultsRejected += 1
            if appInventoryPipeline.buildGeneration == generation {
                appInventoryPipeline.buildTask = nil
                appInventoryPipeline.inFlightKey = nil
                isPreparingAppInventory = false
            }
            return
        }

        appInventoryPipeline.buildTask = nil
        appInventoryPipeline.inFlightKey = nil
        appInventoryPipeline.diagnostics.metadataReads += output.metadataReads
        for (path, metadata) in output.metadataUpdates {
            appInventoryPipeline.metadataByPath[path] = metadata
        }

        let items = materializeAppInventory(output.results)
        appInventoryPipeline.inventoryCache = appInventoryPipeline.inventoryCache.filter {
            $0.key.snapshotCatalogRevision == key.snapshotCatalogRevision
        }
        appInventoryPipeline.inventoryCache[key] = items
        installAppInventory(items, for: key)
        scheduleMissingAppIcons(for: key)
    }

    private func materializeAppInventory(_ results: [AppMetadataResult]) -> [AppInventoryItem] {
        let placeholder = appInventoryPlaceholderIcon()
        return results.map { result in
            let icon = appInventoryPipeline.iconByPath[result.reference.path].flatMap { cached in
                cached.signature == result.signature ? cached.image : nil
            } ?? placeholder
            return AppInventoryItem(
                reference: result.reference,
                displayName: result.displayName,
                version: result.version,
                bundleIdentifier: result.bundleIdentifier,
                sourceName: result.sourceName,
                icon: icon
            )
        }
    }

    private func installAppInventory(_ items: [AppInventoryItem], for key: AppInventoryCacheKey) {
        let hydrated = hydrateCachedIcons(in: items)
        appInventoryPipeline.inventoryCache[key] = hydrated
        if appInventoryPipeline.presentedKey != key || appInventory.map(\.id) != hydrated.map(\.id) {
            appInventory = AppInventoryOrdering.sorted(hydrated, metric: sizeMetric)
        }
        appInventoryPipeline.presentedKey = key
        isPreparingAppInventory = false
        if let selectedAppInventoryID,
           !appInventory.contains(where: { $0.id == selectedAppInventoryID }) {
            self.selectedAppInventoryID = nil
        }
    }

    private func hydrateCachedIcons(in items: [AppInventoryItem]) -> [AppInventoryItem] {
        items.map { item in
            guard let metadata = appInventoryPipeline.metadataByPath[item.reference.path],
                  let icon = appInventoryPipeline.iconByPath[item.reference.path],
                  icon.signature == metadata.signature,
                  icon.image !== item.icon
            else { return item }
            return AppInventoryItem(
                reference: item.reference,
                displayName: item.displayName,
                version: item.version,
                bundleIdentifier: item.bundleIdentifier,
                sourceName: item.sourceName,
                icon: icon.image
            )
        }
    }

    private func scheduleMissingAppIcons(for key: AppInventoryCacheKey) {
        guard appDestination == .apps,
              let cachedItems = appInventoryPipeline.inventoryCache[key]
        else { return }
        if appInventoryPipeline.iconKey == key, appInventoryPipeline.iconTask != nil { return }

        let requests = cachedItems.compactMap { item -> (id: String, path: String, signature: AppBundleSignature)? in
            guard let metadata = appInventoryPipeline.metadataByPath[item.reference.path] else { return nil }
            if let icon = appInventoryPipeline.iconByPath[item.reference.path],
               icon.signature == metadata.signature {
                return nil
            }
            return (item.id, item.reference.path, metadata.signature)
        }
        guard !requests.isEmpty else { return }

        appInventoryPipeline.iconTask?.cancel()
        let generation = UUID()
        appInventoryPipeline.iconGeneration = generation
        appInventoryPipeline.iconKey = key
        appInventoryPipeline.iconTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let batchSize = 4
            var start = 0
            while start < requests.count {
                guard !Task.isCancelled,
                      self.appInventoryPipeline.iconGeneration == generation,
                      self.appInventoryPipeline.iconKey == key,
                      self.appDestination == .apps
                else {
                    self.finishAppIconLoading(generation: generation)
                    return
                }

                let end = min(start + batchSize, requests.count)
                for request in requests[start ..< end] {
                    let icon = NSWorkspace.shared.icon(forFile: request.path)
                    self.appInventoryPipeline.iconByPath[request.path] = CachedAppIcon(
                        signature: request.signature,
                        image: icon
                    )
                    self.appInventoryPipeline.diagnostics.iconLoads += 1
                }
                if let items = self.appInventoryPipeline.inventoryCache[key] {
                    let hydrated = self.hydrateCachedIcons(in: items)
                    self.appInventoryPipeline.inventoryCache[key] = hydrated
                    if self.appInventoryPipeline.presentedKey == key {
                        self.appInventory = self.hydrateCachedIcons(in: self.appInventory)
                    }
                }
                start = end
                await Task.yield()
            }
            self.finishAppIconLoading(generation: generation)
        }
    }

    private func finishAppIconLoading(generation: UUID) {
        guard appInventoryPipeline.iconGeneration == generation else { return }
        appInventoryPipeline.iconTask = nil
        appInventoryPipeline.iconKey = nil
    }

    private func appInventoryPlaceholderIcon() -> NSImage {
        if let icon = appInventoryPipeline.placeholderIcon { return icon }
        let icon = NSWorkspace.shared.icon(for: .application)
        appInventoryPipeline.placeholderIcon = icon
        return icon
    }

    private func cancelAppInventoryPipeline() {
        appInventoryPipeline.buildTask?.cancel()
        appInventoryPipeline.iconTask?.cancel()
        appInventoryPipeline.buildTask = nil
        appInventoryPipeline.iconTask = nil
        appInventoryPipeline.inFlightKey = nil
        appInventoryPipeline.iconKey = nil
        appInventoryPipeline.buildGeneration = UUID()
        appInventoryPipeline.iconGeneration = UUID()
    }

    func addSelectedNodeToReview() {
        guard !isPresentingHistoricalSnapshot,
              let locationID = selectedLocationID,
              let snapshot = locationSnapshots[locationID],
              let nodeID = selectedNodeID,
              nodeID != .root,
              let node = snapshot.session.node(id: nodeID)
        else { return }
        addToReview(node: node, nodeID: nodeID, snapshot: snapshot, reason: .addedFromScan)
    }

    func addAppToReview(_ inventoryID: String) {
        guard !isPresentingHistoricalSnapshot,
              let app = appInventory.first(where: { $0.id == inventoryID }),
              let snapshot = locationSnapshots[app.reference.sourceLocationID],
              let node = snapshot.session.node(id: app.reference.nodeID)
        else { return }
        addToReview(
            node: node,
            nodeID: app.reference.nodeID,
            snapshot: snapshot,
            reason: .addedFromApps
        )
    }

    private func addToReview(
        node: FileNode,
        nodeID: NodeID,
        snapshot: LocationSnapshot,
        reason: ReviewReason
    ) {
        guard !reviewItems.contains(where: {
            $0.sourceLocationID == snapshot.locationID && $0.path == node.path && $0.state != .actionComplete
        }) else {
            statusLine = "Already in Review"
            return
        }
        let deletionAllowed = savedLocations.first { $0.id == snapshot.locationID }?.scanRoot.accessMode == .readWrite
        reviewItems.append(ReviewItem(
            sourceLocationID: snapshot.locationID,
            snapshotGeneration: snapshot.generation,
            snapshotDate: snapshot.scannedAt,
            originalNodeID: nodeID,
            node: node,
            reason: reason,
            state: deletionAllowed ? .ready : .deletionLocked
        ))
        persistReviewItems()
        statusLine = "Added to Review"
    }

    func removeFromReview(_ id: UUID) {
        reviewItems.removeAll { $0.id == id }
        if selectedReviewItemID == id { selectedReviewItemID = nil }
        persistReviewItems()
    }

    func reviewState(for item: ReviewItem) -> ReviewItemState {
        if item.state == .actionComplete || item.state == .actionFailed { return item.state }
        let location = savedLocations.first { $0.id == item.sourceLocationID }
        let snapshot = locationSnapshots[item.sourceLocationID]
        return ReviewSnapshotValidator.state(
            for: item,
            currentSession: snapshot?.session,
            currentGeneration: snapshot?.generation,
            sourceAvailable: location?.availability == .ready,
            deletionAllowed: location?.scanRoot.accessMode == .readWrite
        )
    }

    func quickLookSelected() {
        let path: String?
        switch appDestination {
        case .scan:
            path = selectedNodeID.flatMap { session?.node(id: $0)?.path }
        case .apps:
            path = selectedAppInventoryID.flatMap { id in
                appInventory.first(where: { $0.id == id })?.reference.path
            }
        case .review:
            path = selectedReviewItemID.flatMap { id in
                reviewItems.first(where: { $0.id == id })?.path
            }
        case .settings:
            path = nil
        }
        guard let path, quickLookService.preview(path: path) else {
            workspaceNotice = .information(
                title: "Preview Unavailable",
                message: "This item cannot be previewed from its current source."
            )
            return
        }
    }

    func requestSearchFocus() {
        guard appDestination == .scan else { return }
        searchFocusRequest &+= 1
    }

    func markActionComplete(locationID: UUID, path: String, note: String) {
        for index in reviewItems.indices where reviewItems[index].sourceLocationID == locationID
            && reviewItems[index].path == path {
            reviewItems[index].state = .actionComplete
            reviewItems[index].actionNote = note
        }
        locationSnapshots[locationID] = nil
        snapshotCatalogRevision &+= 1
        if selectedLocationID == locationID {
            presentLocationSnapshot(nil)
            statusLine = "Snapshot may be stale · refresh this location"
        }
        persistReviewItems()
        prepareAppInventory()
    }

    func sourceName(for locationID: UUID) -> String {
        savedLocations.first(where: { $0.id == locationID })?.displayName ?? "Unavailable source"
    }

    func isDeletionAllowed(for locationID: UUID) -> Bool {
        savedLocations.first(where: { $0.id == locationID })?.scanRoot.accessMode == .readWrite
    }

    func actionEligibility(
        for request: StorageActionRequest,
        action: StorageAction,
        sameVolumeDestination: Bool? = nil
    ) -> StorageActionEligibility {
        guard let location = savedLocations.first(where: { $0.id == request.locationID }),
              let snapshot = locationSnapshots[request.locationID],
              let node = snapshot.session.nodes.first(where: { $0.path == request.path })
        else {
            return StorageActionEligibility(isEnabled: false, reason: "Refresh this source before changing the item")
        }
        return ActionEligibility.evaluate(
            action,
            node: node,
            sourceAvailable: location.availability == .ready,
            snapshotCurrent: true,
            deletionAllowed: location.scanRoot.accessMode == .readWrite,
            sameVolumeDestination: sameVolumeDestination
        )
    }

    func sourceRoot(for locationID: UUID) -> ScanRoot? {
        savedLocations.first(where: { $0.id == locationID })?.scanRoot
    }

    func currentNode(for request: StorageActionRequest) -> FileNode? {
        locationSnapshots[request.locationID]?.session.nodes.first { $0.path == request.path }
    }
}
