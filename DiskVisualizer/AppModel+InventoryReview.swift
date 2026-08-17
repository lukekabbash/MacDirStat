import AppKit
import Core
import Foundation

private struct AppMetadataResult: Sendable {
    let reference: AppPackageReference
    let displayName: String
    let version: String?
    let bundleIdentifier: String?
    let sourceName: String
}

extension AppModel {
    func prepareAppInventory() {
        appInventoryTask?.cancel()
        let snapshots: [LocationSnapshot]
        switch appInventoryScope {
        case .selectedLocation:
            snapshots = selectedLocationID.flatMap { locationSnapshots[$0] }.map { [$0] } ?? []
        case .allCompletedLocations:
            snapshots = Array(locationSnapshots.values)
        }
        guard !snapshots.isEmpty else {
            appInventory = []
            isPreparingAppInventory = false
            return
        }

        let locationsByID = Dictionary(uniqueKeysWithValues: savedLocations.map { ($0.id, $0) })
        isPreparingAppInventory = true
        appInventoryTask = Task { [weak self] in
            let results = await Task.detached(priority: .userInitiated) {
                var output: [AppMetadataResult] = []
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
                    defer { if accessed { rootURL?.stopAccessingSecurityScopedResource() } }

                    for reference in references {
                        guard !Task.isCancelled else { break }
                        let bundle = Bundle(path: reference.path)
                        let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                            ?? URL(fileURLWithPath: reference.fallbackName).deletingPathExtension().lastPathComponent
                        let version = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                        output.append(AppMetadataResult(
                            reference: reference,
                            displayName: displayName,
                            version: version,
                            bundleIdentifier: bundle?.bundleIdentifier,
                            sourceName: location.displayName
                        ))
                    }
                }
                return output
            }.value

            guard let self, !Task.isCancelled else { return }
            self.appInventory = results.map { result in
                AppInventoryItem(
                    reference: result.reference,
                    displayName: result.displayName,
                    version: result.version,
                    bundleIdentifier: result.bundleIdentifier,
                    sourceName: result.sourceName,
                    icon: NSWorkspace.shared.icon(forFile: result.reference.path)
                )
            }
            .sorted { lhs, rhs in
                let leftSize = lhs.reference.size(for: self.sizeMetric)
                let rightSize = rhs.reference.size(for: self.sizeMetric)
                if leftSize != rightSize { return leftSize > rightSize }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            self.isPreparingAppInventory = false
            if let selectedAppInventoryID,
               !self.appInventory.contains(where: { $0.id == selectedAppInventoryID }) {
                self.selectedAppInventoryID = nil
            }
        }
    }

    func addSelectedNodeToReview() {
        guard let locationID = selectedLocationID,
              let snapshot = locationSnapshots[locationID],
              let nodeID = selectedNodeID,
              nodeID != .root,
              let node = snapshot.session.node(id: nodeID)
        else { return }
        addToReview(node: node, nodeID: nodeID, snapshot: snapshot, reason: .addedFromScan)
    }

    func addAppToReview(_ inventoryID: String) {
        guard let app = appInventory.first(where: { $0.id == inventoryID }),
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
