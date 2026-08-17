import AppKit
import Core
import SwiftUI
import Treemap

/// A comparison surface for the complete snapshot. Bars carry the precise
/// ranking; the ring supplies proportion at a glance without competing with it.
struct StorageInsightsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ScanSession
    let sessionRevision: Int
    let metric: SizeMetric
    @Binding var grouping: StorageBreakdownGrouping
    let groups: [StorageBreakdownItem]
    let largestNodeIDs: [NodeID]
    let isPreparing: Bool
    let selectedNodeID: NodeID?
    let selectedGroupID: String?
    let onSelectNode: (NodeID?) -> Void
    let onSelectGroup: (StorageBreakdownItem) -> Void
    let contextMenuProvider: StorageNodeContextMenuProvider
    @State private var chartsVisible = false
    @State private var presentation: StorageOverviewPresentation = .summary
    @State private var sunburstScopeNodeID: NodeID = .root
    @Namespace private var groupSelectionPill

    private var largestItems: [StorageReviewItem] {
        largestNodeIDs.compactMap { id in
            guard let node = session.node(id: id) else { return nil }
            return StorageReviewItem(id: id, node: node, size: node.size(for: metric))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    presentationHeader

                    Group {
                        switch presentation {
                        case .summary:
                            summaryContent
                        case .sunburst:
                            StorageHierarchyView(
                                session: session,
                                sessionRevision: sessionRevision,
                                metric: metric,
                                selectedNodeID: selectedNodeID,
                                scopeNodeID: $sunburstScopeNodeID,
                                onSelectNode: onSelectNode,
                                contextMenuProvider: contextMenuProvider
                            )
                        }
                    }
                    .id(presentation)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
                }
                .padding(22)
            }
            .diskScrollChrome()
        }
        .background(DiskVisualStyle.canvas)
        .onAppear { revealCharts() }
        .onChange(of: groups) { revealCharts() }
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: presentation)
    }

    private var presentationHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation == .summary ? "Storage summary" : "Sunburst hierarchy")
                    .font(.title3.weight(.semibold))
                Text(
                    presentation == .summary
                        ? "A precise category breakdown of this snapshot."
                        : "Explore the actual folder layers in this snapshot."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            OverviewPresentationControl(selection: $presentation)
            .frame(width: 208)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if groups.isEmpty && isPreparing {
            ProgressView("Preparing summary…")
                .frame(maxWidth: .infinity, minHeight: 310)
        } else if groups.isEmpty {
            ContentUnavailableView(
                "Nothing to chart",
                systemImage: "chart.bar.xaxis",
                description: Text("This snapshot does not contain measurable files or packages.")
            )
            .frame(maxWidth: .infinity, minHeight: 310)
        } else {
            VStack(alignment: .leading, spacing: 28) {
                distributionSection
                largestItemsSection
            }
        }
    }

    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                SectionHeading(
                    title: grouping == .fileType ? "Space by file type" : "Space by location",
                    detail: "Ranked by \(StoragePresentation.label(for: metric).lowercased()) size"
                )
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                }
                Picker("Group", selection: $grouping) {
                    Text("File type").tag(StorageBreakdownGrouping.fileType)
                    Text("Location").tag(StorageBreakdownGrouping.location)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 166)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 28) {
                    donutChart

                    breakdownBars
                        .frame(minWidth: 380, maxWidth: .infinity)
                }

                VStack(spacing: 20) {
                    donutChart
                        .frame(maxWidth: .infinity)
                    breakdownBars
                }
            }
        }
    }

    private var donutChart: some View {
        StorageDonut(items: groups, metric: metric, reveal: chartsVisible ? 1 : 0)
            .frame(width: 220, height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Distribution chart")
            .accessibilityValue(accessibilityDistribution)
    }

    private var breakdownBars: some View {
        StorageBreakdownBars(
            items: groups,
            metric: metric,
            reveal: chartsVisible ? 1 : 0,
            selectedGroupID: selectedGroupID,
            selectionNamespace: groupSelectionPill,
            onSelectGroup: onSelectGroup
        )
    }

    private var largestItemsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(
                title: "Largest individual items",
                detail: "Select a row to inspect it without leaving the overview"
            )

            VStack(spacing: 0) {
                HStack {
                    Text("Name")
                    Spacer()
                    Text("Kind").frame(width: 92, alignment: .leading)
                    Text(StoragePresentation.label(for: metric)).frame(width: 92, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 7)

                ForEach(largestItems) { item in
                    LargestItemRow(
                        item: item,
                        metric: metric,
                        isSelected: selectedNodeID == item.id,
                        onSelect: { onSelectNode(item.id) }
                    )
                }
            }
        }
    }

    private var accessibilityDistribution: String {
        groups.prefix(5).map {
            "\($0.title), \(StoragePresentation.bytes($0.size))"
        }.joined(separator: "; ")
    }

    private func revealCharts() {
        chartsVisible = false
        guard !reduceMotion else {
            chartsVisible = true
            return
        }
        withAnimation(.easeOut(duration: 0.28)) {
            chartsVisible = true
        }
    }
}

private struct SectionHeading: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OverviewPresentationControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: StorageOverviewPresentation
    @Namespace private var selectionSurface

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StorageOverviewPresentation.allCases) { style in
                Button {
                    select(style)
                } label: {
                    Label(style.displayName, systemImage: style.symbolName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(selection == style ? DiskVisualStyle.interactionStrong : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .contentShape(Rectangle())
                        .background {
                            if selection == style {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(DiskVisualStyle.raisedSurface)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "overview-presentation", in: selectionSurface)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityValue(selection == style ? "Selected" : "Not selected")
                .accessibilityAddTraits(selection == style ? .isSelected : [])
            }
        }
        .padding(2)
        .background(DiskVisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DiskVisualStyle.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview presentation")
    }

    private func select(_ style: StorageOverviewPresentation) {
        guard style != selection else { return }
        if reduceMotion {
            selection = style
        } else {
            withAnimation(DiskVisualStyle.contentMotion) {
                selection = style
            }
        }
    }
}

private struct StorageReviewItem: Identifiable {
    let id: NodeID
    let node: FileNode
    let size: UInt64
}

private struct StorageDonut: View {
    let items: [StorageBreakdownItem]
    let metric: SizeMetric
    let reveal: Double

    private var total: UInt64 { items.reduce(0) { $0 + $1.size } }

    private var segments: [StorageDonutSegment] {
        guard total > 0 else { return [] }
        var cursor = 0.0
        return items.map { item in
            let start = cursor
            let end = min(1, start + Double(item.size) / Double(total))
            cursor = end
            return StorageDonutSegment(item: item, start: start, end: end)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.065), lineWidth: 24)

            ForEach(segments) { segment in
                Circle()
                    .trim(
                        from: min(1, segment.start + 0.003),
                        to: max(0, min(segment.end - 0.003, segment.start + (segment.end - segment.start) * reveal))
                    )
                    .stroke(
                        StorageVisualPalette.color(for: segment.item),
                        style: StrokeStyle(lineWidth: 24, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 3) {
                Text(StoragePresentation.bytes(total))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(StoragePresentation.label(for: metric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct StorageDonutSegment: Identifiable {
    let item: StorageBreakdownItem
    let start: Double
    let end: Double
    var id: String { item.id }
}

private struct StorageBreakdownBars: View {
    let items: [StorageBreakdownItem]
    let metric: SizeMetric
    let reveal: Double
    let selectedGroupID: String?
    let selectionNamespace: Namespace.ID
    let onSelectGroup: (StorageBreakdownItem) -> Void

    private var total: UInt64 { items.reduce(0) { $0 + $1.size } }
    private var largest: UInt64 { items.map(\.size).max() ?? 0 }

    var body: some View {
        VStack(spacing: 7) {
            ForEach(items) { item in
                BreakdownRow(
                    item: item,
                    total: total,
                    largest: largest,
                    reveal: reveal,
                    isSelected: selectedGroupID == item.id,
                    selectionNamespace: selectionNamespace,
                    onSelect: { onSelectGroup(item) }
                )
            }
        }
    }
}

private struct BreakdownRow: View {
    let item: StorageBreakdownItem
    let total: UInt64
    let largest: UInt64
    let reveal: Double
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(StorageVisualPalette.color(for: item))
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("\(item.itemCount.formatted()) items")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Text(StoragePresentation.bytes(item.size))
                        .font(.caption.monospacedDigit())
                    Text(StoragePresentation.percentage(item.size, of: total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.065))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(StorageVisualPalette.color(for: item))
                                .frame(width: proxy.size.width * relativeWidth * reveal)
                        }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DiskVisualStyle.selection)
                        .matchedGeometryEffect(id: "overview-group-selection", in: selectionNamespace)
                }
            }
            .diskInteractiveRow(isHovered: isHovered && !isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Inspect \(item.title) as a group")
        .accessibilityLabel(item.title)
        .accessibilityValue("\(StoragePresentation.bytes(item.size)), \(StoragePresentation.percentage(item.size, of: total))")
    }

    private var relativeWidth: Double {
        largest == 0 ? 0 : Double(item.size) / Double(largest)
    }
}

private struct LargestItemRow: View {
    let item: StorageReviewItem
    let metric: SizeMetric
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: item.node.isPackage ? "app.dashed" : StorageCategory.classify(item.node).systemImage)
                    .font(.caption)
                    .foregroundStyle(StorageVisualPalette.color(for: StorageCategory.classify(item.node)))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.node.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.node.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(kindLabel(item.node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                Text(StoragePresentation.bytes(item.size))
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .diskInteractiveRow(isHovered: isHovered, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.node.path)
    }

    private func kindLabel(_ node: FileNode) -> String {
        switch node.kind {
        case .root: return "Root"
        case .directory: return "Folder"
        case .file: return "File"
        case .packageLeaf: return "Package"
        }
    }
}

private enum StorageVisualPalette {
    static func color(for item: StorageBreakdownItem) -> Color {
        if item.id.hasPrefix("type:") {
            return Color(nsColor: TreemapColorPalette.color(forFileTypeKey: item.id))
        }
        if let category = item.category { return color(for: category) }
        return Color(hue: hue(for: item.id), saturation: 0.58, brightness: 0.78)
    }

    static func color(for category: StorageCategory) -> Color {
        Color(nsColor: TreemapColorPalette.color(for: category))
    }

    private static func hue(for seed: String) -> Double {
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return Double(value % 360) / 360
    }
}
