import AppKit
import Core
import Foundation

extension AppModel {
    var selectedLocation: SavedLocation? {
        guard let selectedLocationID else { return nil }
        return savedLocations.first { $0.id == selectedLocationID }
    }

    var orderedLocations: [SavedLocation] {
        savedLocations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var selectedLocationIsScanning: Bool {
        isScanning && activeScanLocationID == selectedLocationID
    }

    func restorePersistentWorkspace() async {
        let loadedLocations = (try? await savedLocationStore.load()) ?? []
        let loadedReview = (try? await reviewStore.load()) ?? []
        var restored: [SavedLocation] = []
        restored.reserveCapacity(loadedLocations.count)

        for var location in loadedLocations {
            // File changes never remain armed across an app launch.
            location.scanRoot.accessMode = .readOnly
            location.availability = availability(for: location.scanRoot)
            if let resolved = resolvedURL(for: location.scanRoot) {
                location.canonicalPath = canonicalPath(for: resolved)
            }
            restored.append(location)
        }
        restored = SavedLocationDeduplicator.collapse(restored)

        savedLocations = restored
        reviewItems = loadedReview
        let mostRecent = restored.max { ($0.lastSelectedAt ?? .distantPast) < ($1.lastSelectedAt ?? .distantPast) }
        if let location = mostRecent ?? restored.last {
            selectLocation(location.id)
        } else {
            statusLine = "Choose a saved location to begin"
        }
        persistLocations()
    }

    func selectDestination(_ destination: AppDestination) {
        appDestination = destination
        if destination == .apps { prepareAppInventory() }
    }

    func selectLocation(_ id: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else { return }
        selectedLocationID = id
        savedLocations[index].lastSelectedAt = Date()
        savedLocations[index].scanRoot.accessMode = .readOnly
        activeRoot = savedLocations[index].scanRoot
        cleanupControlsEnabled = false
        appDestination = .scan
        presentLocationSnapshot(locationSnapshots[id])
        persistLocations()
    }

    func addSavedLocation(_ proposedRoot: ScanRoot, canonicalPath proposedCanonicalPath: String? = nil) {
        let proposedPath = proposedCanonicalPath ?? resolvedPath(for: proposedRoot)
        if let proposedPath,
           let existingIndex = savedLocations.firstIndex(where: {
               ($0.canonicalPath ?? resolvedPath(for: $0.scanRoot)) == proposedPath
           }) {
            var refreshedRoot = proposedRoot
            refreshedRoot.id = savedLocations[existingIndex].id
            refreshedRoot.accessMode = .readOnly
            savedLocations[existingIndex].scanRoot = refreshedRoot
            savedLocations[existingIndex].canonicalPath = proposedPath
            savedLocations[existingIndex].availability = .ready
            selectLocation(savedLocations[existingIndex].id)
            persistLocations()
            return
        }

        var root = proposedRoot
        root.accessMode = .readOnly
        let nextOrder = (savedLocations.map(\.sortOrder).max() ?? -1) + 1
        let location = SavedLocation(
            scanRoot: root,
            canonicalPath: proposedPath,
            sortOrder: nextOrder,
            availability: .ready,
            lastSelectedAt: Date()
        )
        savedLocations.append(location)
        selectLocation(location.id)
        persistLocations()
    }

    func togglePin(_ id: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else { return }
        savedLocations[index].isPinned.toggle()
        persistLocations()
    }

    func renameLocation(_ id: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Saved Location"
        alert.informativeText = "This changes only the name shown in Mac Directory Statistics."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: savedLocations[index].displayName)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLocations[index].customName = name.isEmpty ? nil : name
        if selectedLocationID == id { activeRoot?.displayName = savedLocations[index].displayName }
        persistLocations()
    }

    func removeLocation(_ id: UUID) {
        guard let location = savedLocations.first(where: { $0.id == id }) else { return }
        if location.lastScanSummary != nil {
            let alert = NSAlert()
            alert.messageText = "Remove “\(location.displayName)” from the list?"
            alert.informativeText = "This forgets the app’s saved access and local scan summary. It does not change the folder or volume."
            alert.addButton(withTitle: "Remove from List")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        if activeScanLocationID == id { cancelActiveScan() }
        savedLocations.removeAll { $0.id == id }
        locationSnapshots[id] = nil
        snapshotCatalogRevision &+= 1
        if selectedLocationID == id {
            if let replacement = orderedLocations.first {
                selectLocation(replacement.id)
            } else {
                selectedLocationID = nil
                activeRoot = nil
                cleanupControlsEnabled = false
                presentLocationSnapshot(nil)
            }
        }
        persistLocations()
        prepareAppInventory()
    }

    func revealLocation(_ id: UUID) {
        guard let location = savedLocations.first(where: { $0.id == id }),
              let path = resolvedPath(for: location.scanRoot)
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func locationStatusText(_ location: SavedLocation) -> String {
        if activeScanLocationID == location.id, isScanning { return "Scanning…" }
        switch location.availability {
        case .needsAccess: return "Needs access"
        case .disconnected: return "Drive disconnected"
        case .ready:
            guard let summary = location.lastScanSummary else { return "Ready to scan" }
            return summary.isComplete
                ? "Scanned \(summary.scannedAt.formatted(.relative(presentation: .named)))"
                : "Incomplete snapshot"
        }
    }

    func scanSelectedLocation() {
        guard let location = selectedLocation else {
            statusLine = "Choose a location first."
            return
        }
        guard !isScanning else {
            statusLine = "One location is already scanning. Stop it before starting another."
            return
        }
        guard locationHasUsableAccess(location) else {
            reconnectAndScan(location.id)
            return
        }
        startScan()
    }

    func snapshot(for locationID: UUID) -> LocationSnapshot? {
        locationSnapshots[locationID]
    }

    func recordCompletedScan(
        locationID: UUID,
        session: ScanSession,
        scannedAt: Date,
        volumeSpace: VolumeSpaceSnapshot?
    ) {
        guard let index = savedLocations.firstIndex(where: { $0.id == locationID }) else { return }
        savedLocations[index].availability = .ready
        savedLocations[index].lastScanSummary = ScanSummary(
            scannedAt: scannedAt,
            allocatedSize: session.rootTotalAllocated,
            logicalSize: session.rootTotalLogical,
            nodeCount: max(0, session.nodes.count - 1),
            isComplete: session.isComplete,
            warningCount: session.warnings.count,
            volumeName: volumeSpace?.name,
            volumeCapacity: volumeSpace?.capacity,
            volumeAvailable: volumeSpace?.available
        )
        persistLocations()
    }

    func markLocationNeedsAccessIfRequired(_ locationID: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == locationID }) else { return }
        savedLocations[index].availability = availability(for: savedLocations[index].scanRoot)
        persistLocations()
    }

    func refreshSelectedReviewStates() {
        reviewItems = reviewItems.map { item in
            var updated = item
            guard updated.state != .actionComplete else { return updated }
            let location = savedLocations.first { $0.id == item.sourceLocationID }
            let snapshot = locationSnapshots[item.sourceLocationID]
            updated.state = ReviewSnapshotValidator.state(
                for: item,
                currentSession: snapshot?.session,
                currentGeneration: snapshot?.generation,
                sourceAvailable: location?.availability == .ready,
                deletionAllowed: location?.scanRoot.accessMode == .readWrite
            )
            return updated
        }
        persistReviewItems()
    }

    func persistLocations() {
        let current = savedLocations
        Task { try? await savedLocationStore.save(current) }
    }

    func persistReviewItems() {
        let current = reviewItems
        Task { try? await reviewStore.save(current) }
    }

    func resolvedURL(for root: ScanRoot) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: root.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    func resolvedPath(for root: ScanRoot) -> String? {
        resolvedURL(for: root).map(canonicalPath)
    }

    func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func locationHasUsableAccess(_ location: SavedLocation) -> Bool {
        guard location.availability == .ready,
              let url = resolvedURL(for: location.scanRoot)
        else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        if accessed { url.stopAccessingSecurityScopedResource() }
        return accessed && FileManager.default.fileExists(atPath: url.path)
    }

    private func reconnectAndScan(_ locationID: UUID) {
        guard let index = savedLocations.firstIndex(where: { $0.id == locationID }) else { return }
        let location = savedLocations[index]
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access & Scan"
        panel.message = "Choose “\(location.displayName)” again. Access will be renewed and the scan will start immediately."
        if let path = location.canonicalPath {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        } else if location.availability == .disconnected {
            panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let pickedPath = canonicalPath(for: url)
        if let expectedPath = location.canonicalPath,
           canonicalPath(for: URL(fileURLWithPath: expectedPath, isDirectory: true)) != pickedPath {
            workspaceNotice = .information(
                title: "Choose the Same Location",
                message: "Select “\(expectedPath)” to renew this saved source, or use New Scan to add a different one."
            )
            return
        }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            workspaceNotice = .error(
                title: "Access Could Not Be Saved",
                message: error.localizedDescription
            )
            return
        }

        let volumeIdentifier = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier)
            .map { String(describing: $0) }
        var refreshedRoot = location.scanRoot
        refreshedRoot.volumeIdentifier = volumeIdentifier
        refreshedRoot.accessMode = .readOnly
        refreshedRoot.bookmarkData = bookmark
        savedLocations[index].scanRoot = refreshedRoot
        savedLocations[index].canonicalPath = pickedPath
        savedLocations[index].availability = .ready
        selectedLocationID = locationID
        activeRoot = refreshedRoot
        cleanupControlsEnabled = false
        appDestination = .scan
        persistLocations()
        startScan()
    }

    private func availability(for root: ScanRoot) -> LocationAvailability {
        guard let url = resolvedURL(for: root) else { return .needsAccess }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard accessed else {
            return FileManager.default.fileExists(atPath: url.path)
                ? .needsAccess
                : (root.volumeIdentifier == nil ? .needsAccess : .disconnected)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return root.volumeIdentifier == nil ? .needsAccess : .disconnected
        }
        return .ready
    }
}
