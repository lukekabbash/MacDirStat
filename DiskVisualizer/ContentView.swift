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
    @State private var pendingTrashPath: String?
    @State private var confirmMove = false
    @State private var pendingMove: MoveRequest?

    var body: some View {
        NavigationSplitView {
            sidebar
            .navigationSplitViewColumnWidth(min: 276, ideal: 292, max: 324)
        } detail: {
            destinationCanvas
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1_180, minHeight: 720)
        .tint(DiskVisualStyle.accent)
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: model.appDestination)
        .toolbar { toolbar }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(onContinue: model.dismissOnboarding)
        }
        .alert("Move to Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) { pendingTrashPath = nil }
            Button("Move to Trash", role: .destructive) {
                if let pendingTrashPath { performTrash(path: pendingTrashPath) }
                pendingTrashPath = nil
            }
        } message: {
            Text("This item will move to Trash, then the snapshot will refresh. Nothing is permanently deleted by this action.")
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
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.appDestination == .settings {
            SettingsNavigationSidebar(
                selection: $model.settingsSection,
                close: model.closeSettings
            )
        } else {
            StorageExplorerSidebar(
                session: model.session,
                activeRoot: model.activeRoot,
                focusNodeID: model.focusedNodeID,
                isScanning: model.isScanning,
                scanTelemetry: model.scanTelemetry,
                selectedNodeID: selectedNodeBinding,
                metric: $model.sizeMetric,
                cleanupControlsEnabled: cleanupControlsBinding,
                chooseFullMac: model.pickFullMac,
                chooseFolder: model.pickFolder,
                startScan: model.startScan,
                cancelScan: model.cancelActiveScan,
                openSettings: { model.openSettings(.appearance) }
            )
        }
    }

    @ViewBuilder
    private var destinationCanvas: some View {
        if model.appDestination == .settings {
            SettingsCanvas()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        } else {
            dashboard
                .transition(.opacity)
        }
    }

    private var cleanupControlsBinding: Binding<Bool> {
        Binding(
            get: { model.cleanupControlsEnabled },
            set: { model.setCleanupControls(enabled: $0) }
        )
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
            if model.appDestination == .settings {
                Button("Storage", systemImage: "square.grid.3x3") {
                    model.closeSettings()
                }
                .help("Return to the storage workspace")
            } else {
                Menu("Scan", systemImage: "internaldrive") {
                    Button("Full Mac…", systemImage: "desktopcomputer", action: model.pickFullMac)
                    Button("Choose Folder…", systemImage: "folder.badge.plus", action: model.pickFolder)
                }

                if model.isScanning {
                    Button("Stop", systemImage: "stop.fill", action: model.cancelActiveScan)
                        .help("Stop refreshing and keep the last available snapshot")
                } else {
                    Button(
                        model.session == nil ? "Scan" : "Refresh",
                        systemImage: model.session == nil ? "play.fill" : "arrow.clockwise",
                        action: model.startScan
                    )
                    .disabled(model.activeRoot == nil)
                }

                Button("Zoom Out", systemImage: "arrow.up.left.and.arrow.down.right") {
                    treemapBridge.zoomOut()
                }
                .disabled(model.dashboardMode != .map || breadcrumb.count < 2)

                Button("Settings", systemImage: "gearshape") {
                    model.openSettings(.appearance)
                }
                .help("Open app settings")
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
                    isScanning: model.isScanning,
                    scannedNodeCount: model.scannedNodeCount,
                    statusLine: model.statusLine,
                    scanTelemetry: model.scanTelemetry,
                    breadcrumb: breadcrumb,
                    dashboardMode: $model.dashboardMode
                )
                workspace(session: session)
            }
            .background(DiskVisualStyle.canvas)
        } else if model.isScanning {
            FirstScanView(
                rootName: model.activeRoot?.displayName ?? "Location",
                scanTelemetry: model.scanTelemetry,
                cancel: model.cancelActiveScan
            )
        } else {
            EmptyDiskDashboard(
                selectedRootName: model.activeRoot?.displayName,
                startScan: model.startScan,
                chooseFullMac: model.pickFullMac,
                chooseFolder: model.pickFolder
            )
        }
    }

    private func workspace(session: ScanSession) -> some View {
        HStack(spacing: 0) {
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

            Divider()
            inspectorColumn(session: session)
                .frame(width: 320)
                .frame(maxHeight: .infinity)
        }
    }

    /// The inspector is permanently reserved so selecting a block changes
    /// information, never the geometry under the pointer.
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
                close: { model.selectOverviewGroup(nil) },
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
                reveal: { CleanupService().revealInFinder(path: $0) },
                open: { CleanupService().openFile(path: $0) },
                move: requestMove,
                trash: requestTrash
            )
        } else {
            InspectorPlaceholderView(mode: model.dashboardMode)
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
        withAnimation(reduceMotion ? nil : DiskVisualStyle.settleMotion) {
            model.selectOverviewGroup(item.id)
        }
    }

    private func zoom(toBreadcrumbIndex index: Int) {
        let steps = max(0, breadcrumb.count - index - 1)
        for _ in 0 ..< steps { treemapBridge.zoomOut() }
    }

    private func requestTrash(path: String) {
        guard model.cleanupControlsEnabled else { return }
        pendingTrashPath = path
        confirmTrash = true
    }

    private func performTrash(path: String) {
        Task { @MainActor in
            do {
                try CleanupService().moveToTrash(path: path)
                model.statusLine = "Moved to Trash · refreshing in the background"
                model.startScan()
            } catch {
                model.statusLine = "Could not move item to Trash · \(error.localizedDescription)"
            }
        }
    }

    private func requestMove(path: String) {
        guard model.cleanupControlsEnabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination. You will confirm the move before anything changes."
        panel.prompt = "Choose Destination"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        pendingMove = MoveRequest(source: URL(fileURLWithPath: path), destination: destination)
        confirmMove = true
    }

    private func performMove(_ request: MoveRequest) {
        Task { @MainActor in
            do {
                try CleanupService().moveItem(path: request.source.path, to: request.destination.path)
                model.statusLine = "Moved \(request.source.lastPathComponent) · refreshing in the background"
                model.startScan()
            } catch {
                model.statusLine = "Could not move item · \(error.localizedDescription)"
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
            Button {
                showsCapacity.toggle()
            } label: {
                Image(systemName: "square.dashed")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(DiskGelButtonStyle(isSelected: showsCapacity))
            .disabled(!canShowCapacity)
            .help("Include free space and use outside this scan in the map")

            Picker("Color by", selection: $mode) {
                ForEach(TreemapColorMode.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 154)
            .help("Color blocks by file type or top-level location")

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
    let source: URL
    let destination: URL
}

private struct FirstScanView: View {
    let rootName: String
    @ObservedObject var scanTelemetry: ScanTelemetryState
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScanningMark()
                .frame(width: 36, height: 36)
            VStack(spacing: 5) {
                Text("Mapping \(rootName)")
                    .font(.title2.weight(.semibold))
                Text("\((scanTelemetry.activity?.inspectedItems ?? 0).formatted()) items checked. The map will appear as soon as a useful snapshot is ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let activity = scanTelemetry.activity {
                ScanActivityDetails(activity: activity)
                    .frame(maxWidth: 520)
            }
            Button("Stop", action: cancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background(DiskVisualStyle.canvas)
    }
}

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 7) {
                Text("See your storage clearly")
                    .font(.largeTitle.weight(.semibold))
                Text("Map any folder or volume, compare what is actually on disk, and act only when you choose to unlock cleanup.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPoint(icon: "eye", title: "Browse first", detail: "Cleanup controls start locked.")
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
