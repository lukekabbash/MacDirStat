import Core
import SwiftUI
import Treemap

/// The sidebar has one job: choose scope and navigate its contents. View-mode
/// controls live with the canvas they affect, keeping this column predictable.
struct StorageExplorerSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ScanSession?
    let activeRoot: ScanRoot?
    let focusNodeID: NodeID
    let isScanning: Bool
    @ObservedObject var scanTelemetry: ScanTelemetryState
    @Binding var selectedNodeID: NodeID?
    @Binding var metric: SizeMetric
    @Binding var cleanupControlsEnabled: Bool
    let chooseFullMac: () -> Void
    let chooseFolder: () -> Void
    let startScan: () -> Void
    let cancelScan: () -> Void
    let openSettings: () -> Void

    @State private var searchText = ""
    @State private var searchResultIDs: [NodeID] = []
    @State private var isSearching = false
    @Namespace private var selectionPill

    var body: some View {
        VStack(spacing: 0) {
            scopeSection
            browserSection
            preferencesSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DiskVisualStyle.sidebar)
        .task(id: searchTaskID) {
            await updateSearchResults()
        }
    }

    private var searchTaskID: String {
        [
            String(session?.nodes.count ?? 0),
            metric.rawValue,
            searchText.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: ":")
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: activeRoot == nil ? "folder.badge.questionmark" : "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(activeRoot == nil ? Color.secondary : DiskVisualStyle.accentStrong)
                    .frame(width: 30, height: 30)
                    .background(DiskVisualStyle.accent.opacity(activeRoot == nil ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeRoot?.displayName ?? "No location")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Label(
                        cleanupControlsEnabled ? "Cleanup unlocked" : "Browse only",
                        systemImage: cleanupControlsEnabled ? "lock.open.fill" : "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(cleanupControlsEnabled ? DiskVisualStyle.available : Color.secondary)

                    if let session {
                        Text("\(StoragePresentation.bytes(session.rootTotalAllocated)) · \(max(0, session.nodes.count - 1).formatted()) items")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
            }

            HStack(spacing: 8) {
                Button(action: chooseFullMac) {
                    Label("Full Mac", systemImage: "desktopcomputer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DiskGelButtonStyle())
                .help("Map the startup volume; macOS asks for access the first time")

                Button(action: chooseFolder) {
                    Label("Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DiskGelButtonStyle())
                .help("Map one folder or another volume")
            }

            Picker("Measure", selection: $metric) {
                Text("On disk").tag(SizeMetric.allocated)
                Text("Logical").tag(SizeMetric.logical)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            scanAction

            if let scanActivity = scanTelemetry.activity {
                SidebarScanActivity(activity: scanActivity)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DiskVisualStyle.sidebarPadding)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var scanAction: some View {
        if isScanning {
            Button(action: cancelScan) {
                Label("Stop scan", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Stop the scan and keep the latest usable snapshot")
        } else {
            Button(action: startScan) {
                Label(session == nil ? "Scan selected location" : "Refresh snapshot", systemImage: "play.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DiskVisualStyle.accent)
            .disabled(activeRoot == nil)
            .help(session == nil ? "Start mapping the selected location" : "Replace this snapshot with a new scan")
        }
    }

    @ViewBuilder
    private var browserSection: some View {
        if let session {
            let rows = displayRows(in: session)
            VStack(spacing: 0) {
                HStack {
                    Text(searchText.isEmpty ? "Largest here" : "Search results")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(rows.count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DiskVisualStyle.sidebarPadding)
                .padding(.top, 13)
                .padding(.bottom, 9)

                QuietSnapshotSearchField(text: $searchText)
                    .padding(.horizontal, DiskVisualStyle.sidebarPadding)
                    .padding(.bottom, 9)

                if rows.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Nothing mapped here" : "No matches",
                        systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Choose another folder in the map." : "Try a shorter file or folder name.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                StorageExplorerRow(
                                    row: row,
                                    isSelected: selectedNodeID == row.id,
                                    selectionNamespace: selectionPill,
                                    onSelect: {
                                        withAnimation(reduceMotion ? nil : DiskVisualStyle.settleMotion) {
                                            selectedNodeID = row.id
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                activeRoot == nil ? "Choose a location" : "Ready to scan",
                systemImage: activeRoot == nil ? "folder.badge.plus" : "play.circle",
                description: Text(
                    activeRoot == nil
                        ? "Select the full Mac or a folder above."
                        : "\(activeRoot?.displayName ?? "The selected location") is idle until you press Scan."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, DiskVisualStyle.sidebarPadding)
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            CleanupSafetyControl(isEnabled: $cleanupControlsEnabled)

            SidebarSettingsButton(action: openSettings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DiskVisualStyle.sidebarPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func displayRows(in session: ScanSession) -> [StorageExplorerRowData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateIDs: [NodeID]
        if query.isEmpty {
            let focus = session.node(id: focusNodeID) == nil ? NodeID.root : focusNodeID
            candidateIDs = session.children(of: focus)
        } else {
            candidateIDs = searchResultIDs
        }

        let candidates = candidateIDs.compactMap { id -> (NodeID, FileNode, UInt64)? in
            guard let node = session.node(id: id) else { return nil }
            return (id, node, node.size(for: metric))
        }
        .sorted { $0.2 > $1.2 }
        .prefix(query.isEmpty ? 30 : 80)

        let largest = candidates.first?.2 ?? 0
        return candidates.map { candidate in
            let (id, node, size) = candidate
            return StorageExplorerRowData(
                id: id,
                node: node,
                size: size,
                relativeFraction: largest == 0 ? 0 : Double(size) / Double(largest)
            )
        }
    }

    @MainActor
    private func updateSearchResults() async {
        guard let session else {
            searchResultIDs = []
            isSearching = false
            return
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResultIDs = []
            isSearching = false
            return
        }

        isSearching = true
        do {
            try await Task.sleep(nanoseconds: 180_000_000)
        } catch {
            return
        }

        let selectedMetric = metric
        let worker = Task.detached(priority: .userInitiated) {
            rankedSearchIDs(in: session, query: query, metric: selectedMetric, limit: 80)
        }
        let result = await withTaskCancellationHandler(
            operation: { await worker.value },
            onCancel: { worker.cancel() }
        )
        guard !Task.isCancelled else { return }
        searchResultIDs = result
        isSearching = false
    }
}

private struct CleanupSafetyControl: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isEnabled ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? DiskVisualStyle.available : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    (isEnabled ? DiskVisualStyle.available : DiskVisualStyle.neutral).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Cleanup")
                    .font(.subheadline.weight(.medium))
                Text(isEnabled ? "Confirm every move" : "Locked by default")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("Cleanup controls", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DiskVisualStyle.accent)
                .accessibilityValue(isEnabled ? "Unlocked" : "Locked")
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .animation(DiskVisualStyle.settleMotion, value: isEnabled)
    }
}

private struct SidebarSettingsButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                Text("Settings")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .contentShape(Rectangle())
            .diskInteractiveRow(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
        .help("Open appearance, scanning, and cleanup settings")
    }
}

private struct SidebarScanActivity: View {
    let activity: ScanActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(DiskVisualStyle.accent)

            HStack(spacing: 5) {
                Text(activity.phase.displayName)
                Text("·")
                Text(activity.inspectedItems.formatted())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                if activity.itemsPerSecond > 1 {
                    Text("\(Int(activity.itemsPerSecond).formatted())/s")
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan progress")
    }
}

private struct StorageExplorerRowData: Identifiable, Sendable {
    let id: NodeID
    let node: FileNode
    let size: UInt64
    let relativeFraction: Double
}

private struct StorageExplorerRow: View {
    let row: StorageExplorerRowData
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void
    @State private var isHovered = false

    private var category: StorageCategory { StorageCategory.classify(row.node) }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: row.node.kind == .directory ? "folder.fill" : category.systemImage)
                        .font(.caption)
                        .foregroundStyle(
                            row.node.kind == .directory
                                ? DiskVisualStyle.accentStrong
                                : Color(nsColor: TreemapColorPalette.color(forFileTypeKey: StorageFileType.key(for: row.node)))
                        )
                        .frame(width: 17)
                    Text(row.node.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(StoragePresentation.bytes(row.size))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered || isSelected ? 1 : 0)
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill((isSelected ? DiskVisualStyle.accent : Color.secondary).opacity(0.62))
                                .frame(width: proxy.size.width * row.relativeFraction)
                        }
                }
                .frame(height: 2)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DiskVisualStyle.selection)
                        .matchedGeometryEffect(id: "sidebar-selection", in: selectionNamespace)
                }
            }
            .diskInteractiveRow(isHovered: isHovered && !isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(row.node.path)
    }
}

private struct QuietSnapshotSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(isFocused ? Color.primary : Color.secondary)

            TextField("Search this snapshot", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .opacity(text.isEmpty ? 0 : 1)
            .allowsHitTesting(!text.isEmpty)
            .accessibilityHidden(text.isEmpty)
            .frame(width: 16)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            DiskVisualStyle.contentSurface.opacity(isFocused ? 0.80 : 0.55),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isFocused ? DiskVisualStyle.accent.opacity(0.42) : Color.clear,
                    lineWidth: 1
                )
        }
        .shadow(color: isFocused ? DiskVisualStyle.accent.opacity(0.10) : .clear, radius: 0, x: 0, y: 0)
        .animation(DiskVisualStyle.motion, value: isFocused)
    }
}

private func rankedSearchIDs(
    in session: ScanSession,
    query: String,
    metric: SizeMetric,
    limit: Int
) -> [NodeID] {
    var leaders: [(id: NodeID, size: UInt64)] = []
    leaders.reserveCapacity(limit)

    for index in session.nodes.indices {
        if index.isMultiple(of: 2_048), Task.isCancelled { return [] }
        let id = NodeID(rawValue: UInt32(index))
        guard let node = session.node(id: id), node.kind != .root else { continue }
        guard node.name.localizedCaseInsensitiveContains(query)
            || node.path.localizedCaseInsensitiveContains(query)
        else { continue }

        let size = node.size(for: metric)
        guard leaders.count < limit || size > (leaders.last?.size ?? 0) else { continue }
        let insertionIndex = leaders.firstIndex { size > $0.size } ?? leaders.endIndex
        leaders.insert((id, size), at: insertionIndex)
        if leaders.count > limit { leaders.removeLast() }
    }
    return leaders.map(\.id)
}
