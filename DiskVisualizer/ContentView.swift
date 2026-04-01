import AppKit
import Core
import SwiftUI
import Treemap

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var treemapBridge = TreemapBridge()
    @State private var breadcrumb: [NodeID] = [.root]
    @State private var searchText = ""
    @State private var confirmTrash = false
    @State private var pendingTrashPath: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Choose Folder…") { model.pickFolder() }
                Button("Scan") { model.startScan() }
                    .disabled(model.isScanning || model.activeRoot == nil)
                if model.isScanning {
                    Button("Cancel") { model.cancelActiveScan() }
                }
                Button("Zoom Out") { treemapBridge.zoomOut() }
                    .disabled(model.session == nil)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(onContinue: { model.dismissOnboarding() })
        }
        .alert("Move to Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) { pendingTrashPath = nil }
            Button("Move to Trash", role: .destructive) {
                if let p = pendingTrashPath {
                    performTrash(path: p)
                }
                pendingTrashPath = nil
            }
        } message: {
            Text("This moves the item to the Trash. You can undo from Finder.")
        }
    }

    private var sidebar: some View {
        List {
            Section("Root") {
                if let r = model.activeRoot {
                    Label(r.displayName, systemImage: "folder.fill")
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Metric") {
                Picker("Space metric", selection: $model.sizeMetric) {
                    Text("Allocated (disk)").tag(SizeMetric.allocated)
                    Text("Logical").tag(SizeMetric.logical)
                }
                .pickerStyle(.segmented)
            }
            Section("Scan options") {
                Toggle("Show hidden files", isOn: $model.showHiddenFiles)
                Toggle("Packages as single items", isOn: $model.treatPackagesAsLeaves)
            }
            Section("Largest items") {
                TextField("Search", text: $searchText)
                ForEach(largestRows, id: \.id) { row in
                    Button {
                        model.selectedNodeID = row.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .lineLimit(1)
                            Text(model.formattedBytes(row.size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
    }

    private var detail: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                breadcrumbBar
                TreemapView(
                    session: $model.session,
                    metric: model.sizeMetric,
                    bridge: treemapBridge,
                    onSelectionChange: { id in
                        model.selectedNodeID = id
                    },
                    onZoomChange: { _ in },
                    onBreadcrumbChange: { stack in
                        breadcrumb = stack
                    }
                )
            }
            .frame(minWidth: 360, minHeight: 320)

            inspector
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
    }

    private struct LargestRow: Identifiable {
        var id: NodeID
        var name: String
        var size: UInt64
    }

    private var largestRows: [LargestRow] {
        guard let s = model.session else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows: [LargestRow] = s.nodes.enumerated().compactMap { idx, n in
            guard n.kind != .root else { return nil }
            let id = NodeID(rawValue: UInt32(idx))
            if !q.isEmpty, !n.name.lowercased().contains(q) { return nil }
            return LargestRow(id: id, name: n.name, size: n.size(for: model.sizeMetric))
        }
        return rows.sorted { $0.size > $1.size }.prefix(80).map { $0 }
    }

    @ViewBuilder
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)
            if let s = model.session, let id = model.selectedNodeID, let node = s.node(id: id) {
                Text(node.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(node.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Allocated")
                        Text(model.formattedBytes(node.allocatedSize))
                    }
                    GridRow {
                        Text("Logical")
                        Text(model.formattedBytes(node.logicalSize))
                    }
                }
                .font(.subheadline)
                if node.mayShareContent {
                    Label("May share disk content (clone/dedup hint)", systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if node.isSparse {
                    Label("Sparse file", systemImage: "doc.text")
                        .font(.caption)
                }
                if node.isPackage {
                    Label("Package", systemImage: "shippingbox")
                        .font(.caption)
                }
                Divider()
                actionButtons(for: node)
            } else {
                Text("Select a tile or an item in the list.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if let s = model.session {
                    ForEach(Array(breadcrumb.enumerated()), id: \.offset) { index, id in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            let pops = breadcrumb.count - (index + 1)
                            for _ in 0 ..< max(0, pops) {
                                treemapBridge.zoomOut()
                            }
                        } label: {
                            Text(s.node(id: id)?.name ?? "…")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func actionButtons(for node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRow(.revealInFinder, node: node) {
                Task { @MainActor in
                    CleanupService().revealInFinder(path: node.path)
                }
            }
            actionRow(.open, node: node) {
                Task { @MainActor in
                    CleanupService().openFile(path: node.path)
                }
            }
            actionRow(.moveToTrash, node: node) {
                pendingTrashPath = node.path
                confirmTrash = true
            }
        }
    }

    private func actionRow(_ action: CleanupAction, node: FileNode, handler: @escaping () -> Void) -> some View {
        let enabled = node.allowedActions.contains(action)
        return Button(action.title) {
            handler()
        }
        .disabled(!enabled)
        .help(enabled ? "" : capabilityReason(action, node: node))
    }

    private func capabilityReason(_ action: CleanupAction, node: FileNode) -> String {
        let write = model.activeRoot?.accessMode == .readWrite
        return ActionCapability.derive(writeAccess: write, kind: node.kind)
            .first { $0.action == action }?
            .denialReason ?? "Unavailable"
    }

    private func performTrash(path: String) {
        Task { @MainActor in
            do {
                try CleanupService().moveToTrash(path: path)
                model.startScan()
            } catch {
                model.statusLine = "Trash failed: \(error.localizedDescription)"
            }
        }
    }
}

extension CleanupAction {
    fileprivate var title: String {
        switch self {
        case .revealInFinder: return "Reveal in Finder"
        case .open: return "Open"
        case .moveToTrash: return "Move to Trash…"
        case .moveToLocation: return "Move…"
        }
    }
}

struct OnboardingView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Disk Visualizer")
                .font(.title)
            Text(
                """
                This app runs inside the App Sandbox. It only sees folders you explicitly choose. \
                Access is restored after relaunch using a security-scoped bookmark.

                Allocated size is what we recommend for disk used; logical is the file’s byte length. \
                On APFS, clones and shared content mean allocated totals may not match Finder exactly; \
                that is expected.
                """
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Continue") { onContinue() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 320)
    }
}
