import Core
import SwiftUI

/// A contextual inspector for an explicit selection. Its parent gives it a
/// real trailing split only while detail is visible.
struct StorageInspectorView: View {
    let session: ScanSession
    let selectedNodeID: NodeID
    let metric: SizeMetric
    let cleanupControlsEnabled: Bool
    let close: () -> Void
    let quickLook: (String) -> Void
    let addToReview: () -> Void
    let reveal: (String) -> Void
    let open: (String) -> Void
    let move: (String) -> Void
    let trash: (String) -> Void

    private var node: FileNode? { session.node(id: selectedNodeID) }

    private var rootSize: UInt64 {
        metric == .allocated ? session.rootTotalAllocated : session.rootTotalLogical
    }

    var body: some View {
        VStack(spacing: 0) {
            if let node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        identity(for: node)
                        path(for: node)
                        metrics(for: node)
                        attributes(for: node)
                        actions(for: node)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .diskScrollChrome()
            }
        }
        .background(DiskVisualStyle.inspector)
    }

    private func identity(for node: FileNode) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: StoragePresentation.icon(for: node.kind))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(node.kind == .file ? Color.secondary : DiskVisualStyle.iconAccent)
                .frame(width: 34, height: 34)
                .background(DiskVisualStyle.selection, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(kindDescription(node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func path(for node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            InspectorSectionLabel("Location")
            Text(node.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metrics(for node: FileNode) -> some View {
        VStack(spacing: 9) {
            DetailMetricRow(
                label: StoragePresentation.label(for: metric),
                value: StoragePresentation.bytes(node.size(for: metric)),
                emphasis: true
            )
            DetailMetricRow(label: "Allocated", value: StoragePresentation.bytes(node.allocatedSize))
            DetailMetricRow(label: "Logical", value: StoragePresentation.bytes(node.logicalSize))
            DetailMetricRow(
                label: "Share of scan",
                value: StoragePresentation.percentage(node.size(for: metric), of: rootSize)
            )
            if node.childCount > 0 {
                DetailMetricRow(label: "Direct children", value: node.childCount.formatted())
            }
            ProgressView(value: rootSize == 0 ? 0 : Double(node.size(for: metric)) / Double(rootSize))
                .tint(DiskVisualStyle.interactionAccent)
                .accessibilityLabel("Share of scan")
        }
    }

    @ViewBuilder
    private func attributes(for node: FileNode) -> some View {
        let hasAttributes = node.isPackage || node.mayShareContent || node.isSparse || node.isPurgeable
        if hasAttributes {
            VStack(alignment: .leading, spacing: 7) {
                InspectorSectionLabel("Attributes")
                HStack(spacing: 6) {
                    if node.isPackage { TagPill(title: "Package", color: DiskVisualStyle.attention) }
                    if node.mayShareContent { TagPill(title: "Shared blocks possible", color: DiskVisualStyle.neutral) }
                    if node.isSparse { TagPill(title: "Sparse", color: DiskVisualStyle.available) }
                    if node.isPurgeable { TagPill(title: "Purgeable", color: DiskVisualStyle.available) }
                }
            }
        }
    }

    private func actions(for node: FileNode) -> some View {
        let hasPath = !node.path.isEmpty
        let canMutate = hasPath && node.kind != .root

        return VStack(alignment: .leading, spacing: 11) {
            InspectorSectionLabel("Actions")

            HStack(spacing: 8) {
                Button("Quick Look") { quickLook(node.path) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasPath)
                Button("Open") { open(node.path) }
                    .buttonStyle(.bordered)
                    .disabled(!hasPath)
            }

            HStack(spacing: 8) {
                Button("Reveal in Finder") { reveal(node.path) }
                    .buttonStyle(.bordered)
                    .disabled(!hasPath)
                Button("Add to Review", action: addToReview)
                    .buttonStyle(.bordered)
                    .disabled(!canMutate)
            }

            if cleanupControlsEnabled {
                HStack(spacing: 8) {
                    Button("Move…") { move(node.path) }
                        .buttonStyle(.bordered)
                        .disabled(!canMutate)
                    Button("Move to Trash…", role: .destructive) { trash(node.path) }
                        .buttonStyle(.bordered)
                        .disabled(!canMutate)
                }
                Text("You will confirm before the item changes location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Deletion is disabled", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Allow deletion in Settings to move this item or send it to Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindDescription(_ node: FileNode) -> String {
        switch node.kind {
        case .root: return "Scan root"
        case .directory: return "Folder"
        case .file: return "File"
        case .packageLeaf: return "App package or bundle"
        }
    }
}

private struct InspectorSectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct DetailMetricRow: View {
    let label: String
    let value: String
    var emphasis = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
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
