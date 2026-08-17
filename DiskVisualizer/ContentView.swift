import AppKit
import Core
import SwiftUI
import Treemap

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @StateObject private var treemapBridge = TreemapBridge()
    @State private var breadcrumb: [NodeID] = [.root]
    @State private var confirmTrash = false
    @State private var pendingAction: StorageActionRequest?
    @State private var confirmMove = false
    @State private var pendingMove: MoveRequest?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 292)

            Rectangle()
                .fill(DiskVisualStyle.hairline)
                .frame(width: 1)

            destinationCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1_120, minHeight: 680)
        .tint(DiskVisualStyle.accent)
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: model.appDestination)
        .toolbar { toolbar }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(onContinue: model.dismissOnboarding)
        }
        .alert("Move to Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) { pendingAction = nil }
            Button("Move to Trash", role: .destructive) {
                if let pendingAction { performTrash(pendingAction) }
                pendingAction = nil
            }
        } message: {
            Text(pendingAction.map { request in
                request.isApplication
                    ? "Only the app bundle “\(request.displayName)” will move to Trash. Support files and documents may remain. The source snapshot will be invalidated."
                    : "“\(request.displayName)” will move to Trash. The source snapshot will be invalidated and will not refresh automatically."
            } ?? "This item will move to Trash.")
        }
        .alert("Move item?", isPresented: $confirmMove) {
            Button("Cancel", role: .cancel) { pendingMove = nil }
            Button("Move") {
                if let pendingMove { performMove(pendingMove) }
                pendingMove = nil
            }
        } message: {
            Text(pendingMove.map {
                "Move \($0.source.lastPathComponent) into \($0.destination.lastPathComponent)? Existing files will not be overwritten."
            } ?? "Choose a destination folder before moving an item.")
        }
        .alert(
            model.workspaceNotice?.title ?? "Notice",
            isPresented: Binding(
                get: { model.workspaceNotice != nil },
                set: { if !$0 { model.workspaceNotice = nil } }
            )
        ) {
            Button("OK") { model.workspaceNotice = nil }
        } message: {
            Text(model.workspaceNotice?.message ?? "")
        }
        .onKeyPress(.space) {
            model.quickLookSelected()
            return .handled
        }
        .onKeyPress(.return) {
            guard model.appDestination == .scan,
                  model.dashboardMode == .map,
                  let selected = model.selectedNodeID,
                  model.session?.node(id: selected)?.kind == .directory
            else { return .ignored }
            treemapBridge.zoomInto(selected)
            return .handled
        }
        .onKeyPress(.escape) {
            guard model.appDestination == .scan,
                  model.dashboardMode == .map,
                  breadcrumb.count > 1
            else { return .ignored }
            treemapBridge.zoomOut()
            return .handled
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        WorkspaceSidebar(selectedNodeID: selectedNodeBinding)
    }

    @ViewBuilder
    private var destinationCanvas: some View {
        switch model.appDestination {
        case .scan:
            dashboard.transition(.opacity)
        case .apps:
            AppsWorkspaceView(
                requestTrash: { requestTrash(locationID: $0, path: $1, name: $2, isApplication: $3) },
                requestMove: { requestMove(locationID: $0, path: $1, name: $2, isApplication: $3) }
            )
                .transition(.opacity)
        case .review:
            ReviewWorkspaceView(
                requestTrash: { requestTrash(locationID: $0, path: $1, name: $2, isApplication: $3) },
                requestMove: { requestMove(locationID: $0, path: $1, name: $2, isApplication: $3) }
            )
                .transition(.opacity)
        case .settings:
            SettingsCanvas()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var selectedNodeBinding: Binding<NodeID?> {
        Binding(
            get: { model.selectedNodeID },
            set: { model.selectNode($0) }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.appDestination == .scan, model.session != nil {
                Button("Zoom Out", systemImage: "arrow.up.left.and.arrow.down.right") {
                    treemapBridge.zoomOut()
                }
                .disabled(model.dashboardMode != .map || breadcrumb.count < 2)
            }
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        if let session = model.session {
            VStack(spacing: 0) {
                DiskDashboardHeader(
                    session: session,
                    metric: model.sizeMetric,
                    isScanning: model.selectedLocationIsScanning,
                    scannedNodeCount: model.scannedNodeCount,
                    statusLine: model.statusLine,
                    scanTelemetry: model.scanTelemetry,
                    breadcrumb: breadcrumb,
                    dashboardMode: $model.dashboardMode
                )
                workspace(session: session)
            }
            .background(DiskVisualStyle.canvas)
        } else if model.selectedLocationIsScanning {
            FirstScanView(
                rootName: model.activeRoot?.displayName ?? "Location",
                scanTelemetry: model.scanTelemetry,
                cancel: model.cancelActiveScan
            )
        } else {
            EmptyDiskDashboard(
                selectedRootName: model.activeRoot?.displayName,
                selectedRootAvailability: model.selectedLocation?.availability,
                metric: model.sizeMetric,
                includesHiddenItems: model.showHiddenFiles,
                groupsAppBundles: model.treatPackagesAsLeaves
            )
        }
    }

    private func workspace(session: ScanSession) -> some View {
        ZStack(alignment: .trailing) {
            Group {
                switch model.dashboardMode {
                case .map:
                    treemapPane(session: session)
                case .overview:
                    StorageInsightsView(
                        session: session,
                        metric: model.sizeMetric,
                        grouping: $model.overviewGrouping,
                        groups: model.overviewGroups,
                        largestNodeIDs: model.overviewLargestNodeIDs,
                        isPreparing: model.isPreparingOverview,
                        selectedNodeID: model.selectedNodeID,
                        selectedGroupID: model.selectedOverviewGroupID,
                        onSelectNode: selectNode,
                        onSelectGroup: selectOverviewGroup
                    )
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            if hasInspectorContent(in: session) {
                inspectorColumn(session: session)
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(DiskVisualStyle.strongHairline)
                            .frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 14, x: -3)
                    .transition(inspectorTransition)
                    .zIndex(1)
            }
        }
        .clipped()
        .animation(
            reduceMotion ? nil : DiskVisualStyle.contentMotion,
            value: hasInspectorContent(in: session)
        )
    }

    private var inspectorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    private func hasInspectorContent(in session: ScanSession) -> Bool {
        if model.dashboardMode == .overview,
           let selectedGroupID = model.selectedOverviewGroupID,
           model.overviewGroups.contains(where: { $0.id == selectedGroupID }) {
            return true
        }

        guard let selectedNodeID = model.selectedNodeID else { return false }
        return session.node(id: selectedNodeID) != nil
    }

    @ViewBuilder
    private func inspectorColumn(session: ScanSession) -> some View {
        if model.dashboardMode == .overview,
           let selectedGroupID = model.selectedOverviewGroupID,
           let selectedGroup = model.overviewGroups.first(where: { $0.id == selectedGroupID }) {
            StorageGroupInspectorView(
                session: session,
                item: selectedGroup,
                grouping: model.overviewGrouping,
                metric: model.sizeMetric,
                largestNodeIDs: model.overviewGroupLargestNodeIDs,
                isPreparing: model.isPreparingOverviewGroup,
                close: closeOverviewInspector,
                selectNode: { selectNode($0) }
            )
        } else if let selectedID = model.selectedNodeID,
                  session.node(id: selectedID) != nil {
            StorageInspectorView(
                session: session,
                selectedNodeID: selectedID,
                metric: model.sizeMetric,
                cleanupControlsEnabled: model.cleanupControlsEnabled,
                close: { selectNode(nil) },
                quickLook: { _ in model.quickLookSelected() },
                addToReview: model.addSelectedNodeToReview,
                reveal: { CleanupService().revealInFinder(path: $0) },
                open: { CleanupService().openFile(path: $0) },
                move: requestMove,
                trash: requestTrash
            )
        }
    }

    private func treemapPane(session: ScanSession) -> some View {
        VStack(spacing: 0) {
            TreemapView(
                session: $model.session,
                sessionRevision: model.sessionRevision,
                metric: model.sizeMetric,
                colorMode: model.treemapColorMode,
                capacityContext: treemapCapacityContext(session: session),
                showsCapacityContext: model.showFreeSpaceInMap,
                selectedNodeID: model.selectedNodeID,
                bridge: treemapBridge,
                onSelectionChange: selectNode,
                onZoomChange: model.focus,
                onBreadcrumbChange: { breadcrumb = $0 },
                onHoverChange: { model.hoveredNodeID = $0 }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            MapLegendStrip(
                session: session,
                items: model.treemapColorMode == .fileCategory
                    ? model.mapFileTypeGroups
                    : model.mapLocationGroups,
                mode: $model.treemapColorMode,
                metric: model.sizeMetric,
                isPreparing: model.isPreparingMapLegend,
                showsCapacity: $model.showFreeSpaceInMap,
                canShowCapacity: model.volumeSpace != nil && model.sizeMetric == .allocated
            )

            if let volumeSpace = model.volumeSpace {
                VolumeSpaceContextView(
                    snapshot: volumeSpace,
                    scopeName: session.rootDisplayName,
                    scopeAllocatedSize: session.rootTotalAllocated,
                    isIncludedInMap: model.showFreeSpaceInMap
                )
            }
        }
        .background(DiskVisualStyle.canvas)
    }

    private func treemapCapacityContext(session: ScanSession) -> TreemapCapacityContext? {
        guard model.sizeMetric == .allocated, let volume = model.volumeSpace else { return nil }
        return TreemapCapacityContext(
            capacity: volume.capacity,
            available: volume.available,
            scannedAllocated: session.rootTotalAllocated
        )
    }

    private func selectNode(_ id: NodeID?) {
        withAnimation(reduceMotion ? nil : DiskVisualStyle.motion) {
            model.selectNode(id)
        }
    }

    private func selectOverviewGroup(_ item: StorageBreakdownItem) {
        withAnimation(reduceMotion ? nil : DiskVisualStyle.selectionMotion) {
            model.selectOverviewGroup(item.id)
        }
    }

    private func closeOverviewInspector() {
        withAnimation(reduceMotion ? nil : DiskVisualStyle.contentMotion) {
            model.selectOverviewGroup(nil)
        }
    }

    private func zoom(toBreadcrumbIndex index: Int) {
        let steps = max(0, breadcrumb.count - index - 1)
        for _ in 0 ..< steps { treemapBridge.zoomOut() }
    }

    private func requestTrash(path: String) {
        guard let locationID = model.selectedLocationID else { return }
        requestTrash(
            locationID: locationID,
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            isApplication: path.lowercased().hasSuffix(".app")
        )
    }

    private func requestTrash(locationID: UUID, path: String, name: String, isApplication: Bool) {
        let request = StorageActionRequest(kind: .moveToTrash, locationID: locationID, path: path, displayName: name, isApplication: isApplication)
        let eligibility = model.actionEligibility(for: request, action: .moveToTrash)
        guard eligibility.isEnabled else {
            model.workspaceNotice = .information(title: "Move Unavailable", message: eligibility.reason ?? "This item cannot be moved.")
            return
        }
        pendingAction = request
        confirmTrash = true
    }

    private func performTrash(_ request: StorageActionRequest) {
        Task { @MainActor in
            guard let root = model.sourceRoot(for: request.locationID),
                  let sourceURL = model.resolvedURL(for: root)
            else {
                model.workspaceNotice = .error(title: "Source Unavailable", message: "Reconnect or grant access to this source before changing it.")
                return
            }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            let eligibility = model.actionEligibility(for: request, action: .moveToTrash)
            guard eligibility.isEnabled,
                  let node = model.currentNode(for: request),
                  CleanupService().matchesSnapshot(path: request.path, node: node)
            else {
                model.workspaceNotice = .error(title: "Item Changed", message: "The item no longer matches the current snapshot. Refresh the source before trying again.")
                return
            }
            do {
                try CleanupService().moveToTrash(path: request.path)
                model.markActionComplete(locationID: request.locationID, path: request.path, note: "Moved to Trash")
                model.workspaceNotice = .information(title: "Moved to Trash", message: "The source snapshot is now invalid and was not refreshed automatically.")
            } catch {
                model.workspaceNotice = .error(title: "Could Not Move Item", message: error.localizedDescription)
            }
        }
    }

    private func requestMove(path: String) {
        guard let locationID = model.selectedLocationID else { return }
        requestMove(
            locationID: locationID,
            path: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            isApplication: path.lowercased().hasSuffix(".app")
        )
    }

    private func requestMove(locationID: UUID, path: String, name: String, isApplication: Bool) {
        let request = StorageActionRequest(kind: .moveToFolder, locationID: locationID, path: path, displayName: name, isApplication: isApplication)
        let initialEligibility = model.actionEligibility(for: request, action: .moveToFolder)
        guard initialEligibility.isEnabled else {
            model.workspaceNotice = .information(title: "Move Unavailable", message: initialEligibility.reason ?? "This item cannot be moved.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination. You will confirm the move before anything changes."
        panel.prompt = "Choose Destination"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let relationship = CleanupService().volumeRelationship(sourcePath: path, destinationPath: destination.path)
        guard relationship == .same else {
            let message = relationship == .different
                ? "Transfers between volumes are not available yet. Choose a folder on the same volume."
                : "The destination volume could not be verified, so the move was not enabled."
            model.workspaceNotice = .information(title: "Same Volume Required", message: message)
            return
        }
        pendingMove = MoveRequest(request: request, source: URL(fileURLWithPath: path), destination: destination)
        confirmMove = true
    }

    private func performMove(_ request: MoveRequest) {
        Task { @MainActor in
            guard let root = model.sourceRoot(for: request.request.locationID),
                  let sourceRootURL = model.resolvedURL(for: root)
            else {
                model.workspaceNotice = .error(title: "Source Unavailable", message: "Reconnect or grant access before moving this item.")
                return
            }
            let accessed = sourceRootURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceRootURL.stopAccessingSecurityScopedResource() } }
            let relationship = CleanupService().volumeRelationship(sourcePath: request.source.path, destinationPath: request.destination.path)
            let eligibility = model.actionEligibility(for: request.request, action: .moveToFolder, sameVolumeDestination: relationship == .same)
            guard eligibility.isEnabled,
                  let node = model.currentNode(for: request.request),
                  CleanupService().matchesSnapshot(path: request.source.path, node: node)
            else {
                model.workspaceNotice = .error(title: "Move Blocked", message: eligibility.reason ?? "The item changed since the snapshot was created.")
                return
            }
            do {
                try CleanupService().moveItem(path: request.source.path, to: request.destination.path)
                model.markActionComplete(locationID: request.request.locationID, path: request.source.path, note: "Moved to \(request.destination.path)")
                model.workspaceNotice = .information(title: "Item Moved", message: "The source snapshot is now invalid and was not refreshed automatically.")
            } catch {
                model.workspaceNotice = .error(title: "Could Not Move Item", message: error.localizedDescription)
            }
        }
    }
}

private struct MapLegendStrip: View {
    let session: ScanSession
    let items: [StorageBreakdownItem]
    @Binding var mode: TreemapColorMode
    let metric: SizeMetric
    let isPreparing: Bool
    @Binding var showsCapacity: Bool
    let canShowCapacity: Bool

    private var total: UInt64 {
        metric == .allocated ? session.rootTotalAllocated : session.rootTotalLogical
    }

    var body: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(TreemapColorMode.allCases, id: \.self) { option in
                    Button {
                        mode = option
                    } label: {
                        if mode == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Color: \(mode.displayName)")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose how map color is assigned")

            Button {
                showsCapacity.toggle()
            } label: {
                Label("Capacity", systemImage: "square.dashed")
            }
            .buttonStyle(DiskGelButtonStyle(isSelected: showsCapacity))
            .disabled(!canShowCapacity)
            .help("Include free space and use outside this scan in the map")

            if isPreparing && items.isEmpty {
                ProgressView()
                    .controlSize(.mini)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(items) { item in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(color(for: item))
                                    .frame(width: 8, height: 8)
                                Text(item.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                Text(StoragePresentation.percentage(item.size, of: total))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .help("\(item.title): \(StoragePresentation.bytes(item.size)) across \(item.itemCount.formatted()) items")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private func color(for item: StorageBreakdownItem) -> Color {
        if item.id.hasPrefix("type:") {
            return Color(nsColor: TreemapColorPalette.color(forFileTypeKey: item.id))
        }
        if item.id.hasPrefix("location:"),
           let rawValue = UInt32(item.id.dropFirst("location:".count)),
           let node = session.node(id: NodeID(rawValue: rawValue)) {
            return Color(nsColor: TreemapColorPalette.color(forLocationSeed: node.path))
        }
        return .secondary
    }
}

private struct MoveRequest {
    let request: StorageActionRequest
    let source: URL
    let destination: URL
}

private struct FirstScanView: View {
    let rootName: String
    @ObservedObject var scanTelemetry: ScanTelemetryState
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Mapping \(rootName)")
                    .font(.system(size: 27, weight: .semibold))
                    .tracking(-0.4)
                Text("The first useful snapshot will appear while the scan continues.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let activity = scanTelemetry.activity {
                ScanActivityDetails(activity: activity)
                    .frame(maxWidth: 620)
            }
            Button("Stop", action: cancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiskVisualStyle.canvas)
    }
}

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 7) {
                Text("See your storage clearly")
                    .font(.largeTitle.weight(.semibold))
                Text("Map any folder or volume, compare what is actually on disk, and allow deletion only when you need it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPoint(icon: "eye", title: "Browse first", detail: "Deletion starts disabled.")
                OnboardingPoint(icon: "square.grid.3x3.square", title: "See hierarchy", detail: "Size, type, and location stay visible together.")
                OnboardingPoint(icon: "trash", title: "Confirm every change", detail: "Moves and Trash actions never happen silently.")
            }

            Spacer()
            HStack {
                Text("APFS shared blocks can make file totals differ from physically reclaimable space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560, height: 420)
    }
}

private struct OnboardingPoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
