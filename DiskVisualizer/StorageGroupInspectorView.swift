import Core
import SwiftUI
import Treemap

/// Inspector for an aggregate selected from the overview. It reports the
/// aggregate as a group and only offers file-level actions after the user
/// chooses a concrete member.
struct StorageGroupInspectorView: View {
    let session: ScanSession
    let item: StorageBreakdownItem
    let grouping: StorageBreakdownGrouping
    let metric: SizeMetric
    let largestNodeIDs: [NodeID]
    let isPreparing: Bool
    let close: () -> Void
    let selectNode: (NodeID) -> Void

    private var rootSize: UInt64 {
        metric == .allocated ? session.rootTotalAllocated : session.rootTotalLogical
    }

    private var concreteItems: [(NodeID, FileNode)] {
        largestNodeIDs.compactMap { id in
            session.node(id: id).map { (id, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identity
                    summary
                    largestItems
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .background(DiskVisualStyle.inspector)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: groupIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(groupColor)
                .frame(width: 34, height: 34)
                .background(groupColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(groupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Close Inspector")
            .accessibilityLabel("Close Inspector")
        }
    }

    private var summary: some View {
        VStack(spacing: 9) {
            GroupMetricRow(
                label: StoragePresentation.label(for: metric),
                value: StoragePresentation.bytes(item.size),
                emphasis: true
            )
            GroupMetricRow(
                label: "Share of snapshot",
                value: StoragePresentation.percentage(item.size, of: rootSize)
            )
            GroupMetricRow(
                label: "Files and packages",
                value: item.itemCount.formatted()
            )
            ProgressView(value: rootSize == 0 ? 0 : Double(item.size) / Double(rootSize))
                .tint(groupColor)
                .accessibilityLabel("Share of snapshot")
        }
    }

    private var largestItems: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("LARGEST IN THIS GROUP")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            if isPreparing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding the largest members…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 34)
            } else if concreteItems.isEmpty {
                Text("No individual files are available in this group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(concreteItems, id: \.0) { id, node in
                        GroupMemberRow(
                            node: node,
                            size: node.size(for: metric),
                            action: { selectNode(id) }
                        )
                    }
                }

                Text("Select an item to inspect its path, attributes, and available actions.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var groupIcon: String {
        item.category?.systemImage ?? (grouping == .location ? "folder.fill" : "square.grid.2x2")
    }

    private var groupColor: Color {
        if item.id.hasPrefix("type:") {
            return Color(nsColor: TreemapColorPalette.color(forFileTypeKey: item.id))
        }
        if let category = item.category {
            return Color(nsColor: TreemapColorPalette.color(for: category))
        }
        return DiskVisualStyle.accent
    }

    private var groupDescription: String {
        switch grouping {
        case .fileType:
            return "Files with this extension, counted once. Directory rollups are excluded so the percentage stays exact."
        case .location:
            return item.id == "remainder"
                ? "Combined smaller top-level locations in this snapshot."
                : "A top-level location inside the selected snapshot."
        }
    }
}

private struct GroupMetricRow: View {
    let label: String
    let value: String
    var emphasis = false

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(emphasis ? .subheadline.weight(.semibold) : .subheadline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)
        }
        .font(.subheadline)
    }
}

private struct GroupMemberRow: View {
    let node: FileNode
    let size: UInt64
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: node.isPackage ? "app.dashed" : StorageCategory.classify(node).systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(node.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(StoragePresentation.bytes(size))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .diskInteractiveRow(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(node.path)
    }
}
