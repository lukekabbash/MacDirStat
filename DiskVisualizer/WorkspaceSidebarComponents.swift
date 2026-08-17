import Core
import SwiftUI

enum SidebarKindFilter: String, CaseIterable, Identifiable {
    case all, folders, files, apps
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "All kinds"; case .folders: return "Folders"; case .files: return "Files"; case .apps: return "Apps" }
    }
    func includes(_ node: FileNode) -> Bool {
        switch self {
        case .all: return true
        case .folders: return node.kind == .directory
        case .files: return node.kind == .file
        case .apps: return node.isPackage && node.path.lowercased().hasSuffix(".app")
        }
    }
}

enum SidebarSizeFloor: UInt64, CaseIterable, Identifiable {
    case any = 0
    case oneMB = 1_000_000
    case tenMB = 10_000_000
    case hundredMB = 100_000_000
    case oneGB = 1_000_000_000
    var id: UInt64 { rawValue }
    var bytes: UInt64 { rawValue }
    var title: String {
        switch self { case .any: return "Any size"; case .oneMB: return "≥ 1 MB"; case .tenMB: return "≥ 10 MB"; case .hundredMB: return "≥ 100 MB"; case .oneGB: return "≥ 1 GB" }
    }
    static func matching(_ bytes: UInt64) -> Self { allCases.first { $0.rawValue == bytes } ?? .any }
}

struct SidebarDestinationRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let badge: String?
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 20)
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .medium))
                Spacer()
                if let badge { Text(badge).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background {
                SidebarSelectionBackground(
                    selected: isSelected,
                    hovered: hovered,
                    id: "destination-selection",
                    namespace: selectionNamespace,
                    cornerRadius: 8
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct SavedLocationRow: View {
    let location: SavedLocation
    let selected: Bool
    let scanning: Bool
    let metric: SizeMetric
    let selectionNamespace: Namespace.ID
    let select: () -> Void
    let pin: () -> Void
    let rename: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: location.isPinned ? "pin.fill" : location.availability == .ready ? "internaldrive" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(location.availability == .ready ? DiskVisualStyle.accentStrong : DiskVisualStyle.attention)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(location.displayName).font(.caption.weight(.medium)).lineLimit(1)
                    Text(scanning ? "Scanning…" : location.lastScanSummary.map { "\(StoragePresentation.bytes($0.size(for: metric))) · \($0.scannedAt.formatted(.relative(presentation: .named)))" } ?? "Ready to scan")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                if scanning { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .contentShape(Rectangle())
            .background {
                SidebarSelectionBackground(
                    selected: selected,
                    hovered: hovered,
                    id: "location-selection",
                    namespace: selectionNamespace,
                    cornerRadius: 8
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(location.isPinned ? "Unpin" : "Pin", action: pin)
            Button("Rename…", action: rename)
            Button("Reveal in Finder", action: reveal)
            Divider()
            Button("Remove from List", role: .destructive, action: remove)
        }
    }
}

struct SidebarProgress: View {
    let activity: ScanActivity
    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: activity.fractionCompleted ?? 0).progressViewStyle(.linear)
            HStack {
                Text(activity.phase.displayName)
                Spacer()
                Text(activity.percentageText ?? "0%").fontWeight(.semibold).monospacedDigit()
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan progress \(activity.percentageText ?? "0 percent")")
    }
}

struct SidebarSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search snapshot", text: $text).textFieldStyle(.plain).focused(focused)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 9).frame(height: 29)
        .background(DiskVisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SidebarNodeData: Identifiable {
    let id: NodeID
    let node: FileNode
    let size: UInt64
}

struct SidebarNodeRow: View {
    let row: SidebarNodeData
    let selected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: StoragePresentation.icon(for: row.node.kind)).font(.caption).foregroundStyle(row.node.kind == .file ? .secondary : DiskVisualStyle.accentStrong).frame(width: 17)
                Text(row.node.name).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text(StoragePresentation.bytes(row.size)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).frame(height: 31).contentShape(Rectangle())
            .background {
                SidebarSelectionBackground(
                    selected: selected,
                    hovered: hovered,
                    id: "node-selection",
                    namespace: selectionNamespace,
                    cornerRadius: 7
                )
            }
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.help(row.node.path)
    }
}

private struct SidebarSelectionBackground: View {
    let selected: Bool
    let hovered: Bool
    let id: String
    let namespace: Namespace.ID
    let cornerRadius: CGFloat

    var body: some View {
        if selected {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DiskVisualStyle.selection)
                .matchedGeometryEffect(id: id, in: namespace)
        } else if hovered {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DiskVisualStyle.subtleSurface)
        }
    }
}

struct NewLocationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Scan").font(.title2.weight(.semibold))
                Text("Save a location now. Scanning begins only when you press Scan.").font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                choice("Full Mac", "desktopcomputer", "Map the startup volume after macOS grants access") { dismiss(); model.pickFullMac() }
                choice("Folder", "folder", "Map one project, home folder, or directory") { dismiss(); model.pickFolder() }
                choice("Attached Volume", "externaldrive", "Map the root of an external or mounted volume") { dismiss(); model.pickAttachedVolume() }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 470)
    }
    private func choice(_ title: String, _ symbol: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(DiskVisualStyle.accentStrong).frame(width: 34, height: 34).background(DiskVisualStyle.selection, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
