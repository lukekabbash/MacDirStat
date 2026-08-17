import Core
import SwiftUI
import Treemap

/// The navigable hierarchy view behind the Sunburst presentation. It keeps a
/// deliberately shallow, readable set of rings on screen and changes scope
/// instead of forcing the user to parse an entire disk in one radial diagram.
struct StorageHierarchyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: ScanSession
    let sessionRevision: Int
    let metric: SizeMetric
    let selectedNodeID: NodeID?
    @Binding var scopeNodeID: NodeID
    let onSelectNode: (NodeID?) -> Void

    @State private var projection: StorageHierarchyProjection?
    @State private var preparedProjectionToken: String?
    @State private var projectionID = UUID()
    @State private var isPreparing = true
    @State private var showsAllChildren = false

    private var sessionToken: String {
        String(sessionRevision)
    }

    private var projectionInputToken: String {
        "\(sessionToken)|\(scopeNodeID.rawValue)|\(metric.rawValue)"
    }

    private var breadcrumb: [NodeID] {
        session.breadcrumb(to: validScopeNodeID)
    }

    private var validScopeNodeID: NodeID {
        session.node(id: scopeNodeID) == nil ? .root : scopeNodeID
    }

    private var scopeNode: FileNode? {
        session.node(id: validScopeNodeID)
    }

    private var currentProjection: StorageHierarchyProjection? {
        guard preparedProjectionToken == projectionInputToken else { return nil }
        return projection
    }

    private var isProjectionPreparing: Bool {
        isPreparing || preparedProjectionToken != projectionInputToken
    }

    private var visibleChildIDs: [NodeID] {
        guard let currentProjection else { return [] }
        return showsAllChildren
            ? currentProjection.directChildren
            : Array(currentProjection.directChildren.prefix(8))
    }

    private var totalDirectChildCount: Int {
        Int(scopeNode?.childCount ?? 0)
    }

    private var rootChildrenAreCapped: Bool {
        guard let currentProjection else { return false }
        return totalDirectChildCount > currentProjection.directChildren.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            breadcrumbBar
            chart
            selectedDetail
            childNavigator
        }
        .task(id: projectionInputToken) {
            await prepareProjection(for: validScopeNodeID)
        }
        .onChange(of: sessionToken) {
            guard scopeNodeID != .root else { return }
            scopeNodeID = .root
        }
        .onChange(of: projectionInputToken) {
            showsAllChildren = false
        }
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: scopeNodeID)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Folder hierarchy")
                    .font(.title3.weight(.semibold))
                Text("Each ring is one folder layer. Open a folder to inspect its contents at full scale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(hierarchyGuide)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 16)
            if let projection = currentProjection {
                Text("\(projection.deepestVisibleDepth) layers")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 8) {
            Button(action: navigateBack) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(validScopeNodeID == .root)
            .help("Back to parent folder")
            .accessibilityLabel("Back to parent folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(breadcrumb.enumerated()), id: \.element) { index, nodeID in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            setScope(nodeID)
                        } label: {
                            Text(session.node(id: nodeID)?.name ?? "Unknown")
                                .font(.caption.weight(nodeID == validScopeNodeID ? .semibold : .regular))
                                .foregroundStyle(nodeID == validScopeNodeID ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Open this layer")
                    }
                }
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var chart: some View {
        if let projection = currentProjection, projection.rootSize > 0 {
            StorageSunburstChart(
                session: session,
                sessionToken: sessionToken,
                projection: projection,
                projectionID: projectionID,
                selectedNodeID: selectedNodeID,
                onSelectionChange: onSelectNode,
                onDrillInto: openLayer,
                onNavigateBack: navigateBack
            )
            .frame(minHeight: 310, idealHeight: 370, maxHeight: 440)
            .background(DiskVisualStyle.raisedSurface.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DiskVisualStyle.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sunburst hierarchy for \(scopeNode?.name ?? session.rootDisplayName)")
            .accessibilityValue(chartAccessibilityValue(projection))
            .accessibilityHint("Select an item below to inspect it. Double-click a folder in the chart, or press Return, to open its next layer.")
            .accessibilityAction(named: "Open selected folder") {
                if let selectedNodeID { openLayer(selectedNodeID) }
            }
        } else if isProjectionPreparing {
            ProgressView("Preparing hierarchy…")
                .frame(maxWidth: .infinity, minHeight: 310)
        } else {
            ContentUnavailableView(
                "Nothing to show here",
                systemImage: "circle.dotted",
                description: Text("This folder does not contain measurable items in the current snapshot.")
            )
            .frame(maxWidth: .infinity, minHeight: 310)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let projection = currentProjection,
           let selectedNodeID,
           projection.contains(selectedNodeID),
           let node = session.node(id: selectedNodeID) {
            let depth = projection.segments.first(where: { $0.nodeID == selectedNodeID })?.depth ?? 0
            HStack(spacing: 9) {
                Image(systemName: StoragePresentation.icon(for: node.kind))
                    .foregroundStyle(
                        node.kind == .file
                            ? Color.secondary
                            : Color(nsColor: TreemapColorPalette.color(for: StorageCategory.classify(node)))
                    )
                Text(node.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(StorageCategory.classify(node).displayName)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                Text("Layer \(depth)")
                    .foregroundStyle(.secondary)
                Text(StoragePresentation.bytes(node.size(for: metric)))
                    .font(.caption.monospacedDigit())
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(DiskVisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var childNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inside \(scopeNode?.name ?? session.rootDisplayName)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Group {
                    if let projection = currentProjection, projection.directChildren.count > 8 {
                        Text("Showing \(visibleChildIDs.count) of \(totalDirectChildCount)\(rootChildrenAreCapped ? " · largest \(projection.directChildren.count) available" : "")")
                    } else {
                        Text("Select to inspect · Open to continue")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let projection = currentProjection, projection.directChildren.isEmpty {
                Text("No direct items have measurable size in this layer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let projection = currentProjection {
                LazyVStack(spacing: 2) {
                    ForEach(visibleChildIDs, id: \.self) { nodeID in
                        if let node = session.node(id: nodeID) {
                            HierarchyChildRow(
                                node: node,
                                size: node.size(for: metric),
                                isSelected: selectedNodeID == nodeID,
                                select: { onSelectNode(nodeID) },
                                open: { openLayer(nodeID) }
                            )
                        }
                    }
                }

                if projection.directChildren.count > 8 {
                    Button(childDisclosureTitle(for: projection)) {
                        withAnimation(reduceMotion ? nil : DiskVisualStyle.contentMotion) {
                            showsAllChildren.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                }
            }
        }
    }

    private func prepareProjection(for root: NodeID) async {
        isPreparing = true
        let inputToken = projectionInputToken
        let session = session
        let metric = metric
        let worker = Task.detached(priority: .userInitiated) {
            StorageHierarchyBuilder.make(
                in: session,
                root: root,
                metric: metric,
                maximumDepth: 4,
                segmentLimit: 1_200,
                minimumVisibleFraction: 0.0015
            )
        }
        let result = await withTaskCancellationHandler(
            operation: { await worker.value },
            onCancel: { worker.cancel() }
        )

        guard !Task.isCancelled, inputToken == projectionInputToken else { return }
        withAnimation(reduceMotion ? nil : DiskVisualStyle.contentMotion) {
            projection = result
            preparedProjectionToken = inputToken
            projectionID = UUID()
            isPreparing = false
        }
    }

    private func setScope(_ nodeID: NodeID) {
        guard session.node(id: nodeID) != nil else { return }
        withAnimation(reduceMotion ? nil : DiskVisualStyle.contentMotion) {
            scopeNodeID = nodeID
        }
        onSelectNode(nodeID)
    }

    private func openLayer(_ nodeID: NodeID) {
        guard let node = session.node(id: nodeID), node.childCount > 0 else {
            onSelectNode(nodeID)
            return
        }
        setScope(nodeID)
    }

    private func navigateBack() {
        guard validScopeNodeID != .root,
              let node = session.node(id: validScopeNodeID),
              node.parentID != .invalid
        else { return }
        setScope(node.parentID)
    }

    private func chartAccessibilityValue(_ projection: StorageHierarchyProjection) -> String {
        let visible = projection.segments.count.formatted()
        let total = StoragePresentation.bytes(projection.rootSize)
        let selectedDescription: String
        if let selectedNodeID,
           let node = session.node(id: selectedNodeID),
           projection.contains(selectedNodeID) {
            let depth = projection.segments.first(where: { $0.nodeID == selectedNodeID })?.depth ?? 0
            selectedDescription = " Selected \(node.name), layer \(depth), \(StoragePresentation.bytes(node.size(for: metric)))."
        } else {
            selectedDescription = ""
        }
        let coverage = projection.representedRootFraction.formatted(.percent.precision(.fractionLength(1)))
        let omission = projection.hasOmittedSegments
            ? " The largest visible root items represent \(coverage) of the \(total) scope total; deeper descendants and smaller items beyond the readability limits are omitted."
            : " Scope total \(total)."
        return "\(visible) visible items across \(projection.deepestVisibleDepth) layers.\(omission)\(selectedDescription)"
    }

    private var hierarchyGuide: String {
        guard let projection = currentProjection else {
            return "File colors follow type; folders use stable path hues. Ring position identifies depth."
        }
        guard projection.hasOmittedSegments else {
            return "File colors follow type; folders use stable path hues. Ring position identifies depth. Gaps visually separate arcs; they never represent free disk space."
        }
        let coverage = projection.representedRootFraction.formatted(.percent.precision(.fractionLength(1)))
        return "Largest visible root items represent \(coverage) of this scope. Gaps visually separate arcs or indicate descendants omitted by the four-layer depth, 1,200-arc, or minimum-visible-size limit; they never represent free disk space."
    }

    private func childDisclosureTitle(for projection: StorageHierarchyProjection) -> String {
        if showsAllChildren { return "Show fewer items" }
        if rootChildrenAreCapped {
            return "Show top \(projection.directChildren.count) items by size"
        }
        return "Show all \(projection.directChildren.count) items"
    }
}

private struct HierarchyChildRow: View {
    let node: FileNode
    let size: UInt64
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Image(systemName: StoragePresentation.icon(for: node.kind))
                        .font(.caption)
                        .foregroundStyle(
                            node.kind == .file
                                ? Color.secondary
                                : Color(nsColor: TreemapColorPalette.color(for: StorageCategory.classify(node)))
                        )
                        .frame(width: 17)
                    Text(node.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(StoragePresentation.bytes(size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .diskInteractiveRow(isHovered: isHovered, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .help(node.path)

            if node.childCount > 0 {
                Button(action: open) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.borderless)
                .help("Open \(node.name)")
                .accessibilityLabel("Open \(node.name)")
            } else {
                Color.clear.frame(width: 25, height: 25)
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
    }
}
