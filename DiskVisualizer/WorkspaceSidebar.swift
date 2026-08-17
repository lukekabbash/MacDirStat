import Core
import SwiftUI
import Treemap

struct WorkspaceSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedNodeID: NodeID?
    @State private var showsNewLocation = false
    @State private var searchText = ""
    @State private var searchResultIDs: [NodeID] = []
    @State private var isSearching = false
    @State private var kindFilter: SidebarKindFilter = .all
    @State private var minimumSize: UInt64 = 0
    @FocusState private var searchFocused: Bool
    @Namespace private var destinationSelectionSurface
    @Namespace private var locationSelectionSurface
    @Namespace private var nodeSelectionSurface

    var body: some View {
        VStack(spacing: 0) {
            brand
            primaryAction
            destinationList
            locations
            if model.appDestination == .scan { scanBrowser }
            Spacer(minLength: 6)
            settingsDestination
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DiskVisualStyle.sidebar)
        .sheet(isPresented: $showsNewLocation) { NewLocationSheet() }
        .task(id: searchTaskID) { await updateSearchResults() }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ThemedAppIcon(theme: model.themeID, size: 30)
                .accessibilityHidden(true)
            Text("Mac Directory Statistics")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var primaryAction: some View {
        Button { showsNewLocation = true } label: {
            Label("New Scan", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isScanning)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .help("Choose a new Mac, folder, or attached volume and start scanning it")
    }

    private var destinationList: some View {
        VStack(spacing: 2) {
            SidebarDestinationRow(
                title: "Scan", symbol: "square.grid.3x3.fill",
                isSelected: model.appDestination == .scan,
                badge: nil,
                selectionNamespace: destinationSelectionSurface
            ) { selectDestination(.scan) }
            SidebarDestinationRow(
                title: "Apps", symbol: "app.dashed",
                isSelected: model.appDestination == .apps,
                badge: completedLocationCount > 0 ? completedLocationCount.formatted() : nil,
                selectionNamespace: destinationSelectionSurface
            ) { selectDestination(.apps) }
            SidebarDestinationRow(
                title: "Review", symbol: "tray.full",
                isSelected: model.appDestination == .review,
                badge: model.reviewItems.isEmpty ? nil : model.reviewItems.count.formatted(),
                selectionNamespace: destinationSelectionSurface
            ) { selectDestination(.review) }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private var completedLocationCount: Int {
        model.savedLocations.lazy.filter { $0.lastScanSummary != nil }.count
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("LOCATIONS")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showsNewLocation = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Add Location")
            }
            .padding(.horizontal, 14)

            if model.orderedLocations.isEmpty {
                Text("Use New Scan to choose a source, or select a saved source and press Scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.orderedLocations) { location in
                            VStack(spacing: 2) {
                                SavedLocationRow(
                                    location: location,
                                    selected: model.selectedLocationID == location.id,
                                    scanning: model.activeScanLocationID == location.id && model.isScanning,
                                    metric: model.sizeMetric,
                                    selectionNamespace: locationSelectionSurface,
                                    select: {
                                        withAnimation(reduceMotion ? nil : DiskVisualStyle.selectionMotion) {
                                            model.selectLocation(location.id)
                                        }
                                    },
                                    pin: { model.togglePin(location.id) },
                                    rename: { model.renameLocation(location.id) },
                                    reveal: { model.revealLocation(location.id) },
                                    remove: { model.removeLocation(location.id) }
                                )

                                if model.selectedLocationID == location.id {
                                    SidebarSnapshotHistory(location: location, metric: model.sizeMetric)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 7)
                }
                .frame(maxHeight: model.appDestination == .scan ? 260 : .infinity)
                .diskScrollChrome()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var scanBrowser: some View {
        if let location = model.selectedLocation {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                if model.activeScanLocationID == location.id, model.isScanning {
                    Button("Stop", action: model.cancelActiveScan)
                        .buttonStyle(.bordered)
                } else if model.isScanning {
                    Button("Another scan is running") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                } else {
                        Button(scanButtonTitle(for: location)) {
                            model.scanSelectedLocation()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Picker("Measure", selection: $model.sizeMetric) {
                        Text("On disk").tag(SizeMetric.allocated)
                        Text("Logical").tag(SizeMetric.logical)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                if let session = model.session {
                    HStack {
                        Text(searchText.isEmpty ? "LARGEST HERE" : "SEARCH RESULTS")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isSearching { ProgressView().controlSize(.mini) }
                        else { Text(displayRows(in: session).count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    SidebarSearchField(text: $searchText, focused: $searchFocused)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    HStack(spacing: 6) {
                        Menu {
                            ForEach(SidebarKindFilter.allCases) { filter in
                                Button { kindFilter = filter } label: {
                                    if kindFilter == filter { Label(filter.title, systemImage: "checkmark") }
                                    else { Text(filter.title) }
                                }
                            }
                        } label: { Label(kindFilter.title, systemImage: "line.3.horizontal.decrease") }
                        .menuStyle(.borderlessButton).fixedSize()
                        Menu {
                            ForEach(SidebarSizeFloor.allCases) { floor in
                                Button { minimumSize = floor.bytes } label: {
                                    if minimumSize == floor.bytes { Label(floor.title, systemImage: "checkmark") }
                                    else { Text(floor.title) }
                                }
                            }
                        } label: { Text(SidebarSizeFloor.matching(minimumSize).title) }
                        .menuStyle(.borderlessButton).fixedSize()
                        Spacer()
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(displayRows(in: session)) { row in
                                SidebarNodeRow(
                                    row: row,
                                    selected: selectedNodeID == row.id,
                                    selectionNamespace: nodeSelectionSurface
                                ) {
                                    withAnimation(reduceMotion ? nil : DiskVisualStyle.selectionMotion) {
                                        selectedNodeID = row.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 7)
                    }
                    .diskScrollChrome()
                } else {
                    VStack(spacing: 7) {
                        Text(model.locationStatusText(location))
                            .font(.subheadline.weight(.semibold))
                        Text("A saved location is access, not a scan. Start when you are ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var settingsDestination: some View {
        SidebarDestinationRow(
            title: model.appDestination == .settings ? "Back to Storage" : "Settings",
            symbol: model.appDestination == .settings ? "chevron.left" : "gearshape",
            isSelected: model.appDestination == .settings,
            badge: nil,
            selectionNamespace: destinationSelectionSurface
        ) {
            withAnimation(reduceMotion ? nil : DiskVisualStyle.selectionMotion) {
                model.appDestination == .settings ? model.closeSettings() : model.openSettings()
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private var searchTaskID: String {
        "\(model.sessionRevision):\(model.sizeMetric.rawValue):\(searchText)"
    }

    private func selectDestination(_ destination: AppDestination) {
        withAnimation(reduceMotion ? nil : DiskVisualStyle.selectionMotion) {
            model.selectDestination(destination)
        }
    }

    private func scanButtonTitle(for location: SavedLocation) -> String {
        guard location.availability == .ready else { return "Reconnect & Scan" }
        return model.snapshot(for: location.id) == nil ? "Scan" : "Refresh"
    }

    private func displayRows(in session: ScanSession) -> [SidebarNodeData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = query.isEmpty ? session.children(of: model.focusedNodeID) : searchResultIDs
        let ranked = ids.compactMap { id -> SidebarNodeData? in
            guard let node = session.node(id: id) else { return nil }
            let size = node.size(for: model.sizeMetric)
            guard size >= minimumSize, kindFilter.includes(node) else { return nil }
            return SidebarNodeData(id: id, node: node, size: size)
        }.sorted { $0.size > $1.size }
        return Array(ranked.prefix(query.isEmpty ? 30 : 80))
    }

    @MainActor private func updateSearchResults() async {
        guard let session = model.session else { searchResultIDs = []; return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchResultIDs = []; isSearching = false; return }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        searchResultIDs = SnapshotSearchRanking.make(session: session, query: query, metric: model.sizeMetric, limit: 80).map(\.nodeID)
        isSearching = false
    }
}
