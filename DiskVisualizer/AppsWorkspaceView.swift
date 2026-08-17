import Core
import SwiftUI

struct AppsWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    let requestTrash: (UUID, String, String, Bool) -> Void
    let requestMove: (UUID, String, String, Bool) -> Void

    private var selected: AppInventoryItem? {
        model.selectedAppInventoryID.flatMap { id in model.appInventory.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ContextualInspectorSplit(isPresented: selected != nil) {
                inventory
            } inspector: {
                AppInspector(
                    item: selected,
                    metric: model.sizeMetric,
                    deletionAllowed: selected.map { model.isDeletionAllowed(for: $0.reference.sourceLocationID) } ?? false,
                    close: { model.selectedAppInventoryID = nil },
                    quickLook: model.quickLookSelected,
                    reveal: revealSelected,
                    open: openSelected,
                    addReview: addSelectedToReview,
                    move: moveSelected,
                    trash: trashSelected
                )
            }
        }
        .background(DiskVisualStyle.canvas)
        .onAppear { model.prepareAppInventory() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Applications").font(.headline)
                Text("App bundles found in completed snapshots")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Scope", selection: $model.appInventoryScope) {
                ForEach(AppInventoryScope.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().frame(width: 205)
            Picker("Measure", selection: $model.sizeMetric) {
                Text("On disk").tag(SizeMetric.allocated)
                Text("Logical").tag(SizeMetric.logical)
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 142)
        }
        .padding(.horizontal, 18).frame(height: 54)
        .background(DiskVisualStyle.contentSurface.opacity(0.58))
    }

    @ViewBuilder private var inventory: some View {
        if model.isPreparingAppInventory && model.appInventory.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading app metadata…").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.appInventory.isEmpty {
            ContentUnavailableView(
                "No apps in completed snapshots",
                systemImage: "app.dashed",
                description: Text("Scan a saved location first, or choose All completed locations.")
            ).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                AppTableHeader(metric: model.sizeMetric)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.appInventory) { item in
                            AppInventoryRow(
                                item: item,
                                metric: model.sizeMetric,
                                selected: model.selectedAppInventoryID == item.id
                            ) { model.selectedAppInventoryID = item.id }
                            .contextMenu {
                                Button("Quick Look", action: { model.selectedAppInventoryID = item.id; model.quickLookSelected() })
                                Button("Reveal in Finder", action: { CleanupService().revealInFinder(path: item.reference.path) })
                                Button("Add to Review", action: { model.addAppToReview(item.id) })
                            }
                        }
                    }
                }
                .diskScrollChrome()
            }
        }
    }

    private func revealSelected() { selected.map { CleanupService().revealInFinder(path: $0.reference.path) } }
    private func openSelected() { selected.map { CleanupService().openFile(path: $0.reference.path) } }
    private func addSelectedToReview() { if let selected { model.addAppToReview(selected.id) } }
    private func moveSelected() { if let selected { requestMove(selected.reference.sourceLocationID, selected.reference.path, selected.displayName, true) } }
    private func trashSelected() { if let selected { requestTrash(selected.reference.sourceLocationID, selected.reference.path, selected.displayName, true) } }
}

private struct AppTableHeader: View {
    let metric: SizeMetric
    var body: some View {
        HStack(spacing: 10) {
            Text("APPLICATION").frame(maxWidth: .infinity, alignment: .leading)
            Text(StoragePresentation.label(for: metric).uppercased()).frame(width: 92, alignment: .trailing)
            Text("VERSION").frame(width: 70, alignment: .leading)
            Text("SOURCE").frame(width: 130, alignment: .leading)
        }
        .font(.caption2.weight(.semibold)).tracking(0.45).foregroundStyle(.secondary)
        .padding(.horizontal, 14).frame(height: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(DiskVisualStyle.hairline).frame(height: 1) }
    }
}

private struct AppInventoryRow: View {
    let item: AppInventoryItem
    let metric: SizeMetric
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(nsImage: item.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                    Text(item.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(StoragePresentation.bytes(item.reference.size(for: metric))).font(.caption.monospacedDigit()).frame(width: 92, alignment: .trailing)
                Text(item.version ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 70, alignment: .leading)
                Text(item.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 130, alignment: .leading)
            }
            .padding(.horizontal, 14).frame(height: 42).contentShape(Rectangle())
            .background(selected ? DiskVisualStyle.selection : hovered ? DiskVisualStyle.subtleSurface : .clear)
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(item.reference.path)
    }
}

private struct AppInspector: View {
    let item: AppInventoryItem?
    let metric: SizeMetric
    let deletionAllowed: Bool
    let close: () -> Void
    let quickLook: () -> Void
    let reveal: () -> Void
    let open: () -> Void
    let addReview: () -> Void
    let move: () -> Void
    let trash: () -> Void
    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(nsImage: item.icon).resizable().interpolation(.high).frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayName).font(.title3.weight(.semibold)).lineLimit(3)
                                Text(item.version.map { "Version \($0)" } ?? "Version unavailable").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button(action: close) {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.borderless)
                            .help("Close inspector")
                            .accessibilityLabel("Close inspector")
                        }
                        VStack(spacing: 8) {
                            metricRow("Source", item.sourceName)
                            metricRow(StoragePresentation.label(for: metric), StoragePresentation.bytes(item.reference.size(for: metric)))
                            metricRow("Last scanned", item.reference.scannedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        Text(item.reference.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack { Button("Quick Look", action: quickLook).buttonStyle(.borderedProminent); Button("Open", action: open).buttonStyle(.bordered) }
                        HStack { Button("Reveal", action: reveal).buttonStyle(.bordered); Button("Add to Review", action: addReview).buttonStyle(.bordered) }
                        if deletionAllowed {
                            HStack { Button("Move…", action: move).buttonStyle(.bordered); Button("Move to Trash…", role: .destructive, action: trash).buttonStyle(.bordered) }
                            Text("Only this app bundle moves. Related documents and support data may remain.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("Deletion is disabled for this source", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20)
                }
                .diskScrollChrome()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "app.badge.checkmark").font(.title2).foregroundStyle(DiskVisualStyle.iconAccent)
                    Text("Select an application").font(.subheadline.weight(.semibold))
                    Text("Size, source, snapshot age, and source-aware actions appear here.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(22)
            }
        }.background(DiskVisualStyle.inspector)
    }
    private func metricRow(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) }.font(.subheadline) }
}
