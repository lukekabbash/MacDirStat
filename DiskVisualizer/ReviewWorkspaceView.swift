import Core
import SwiftUI

struct ReviewWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    let requestTrash: (UUID, String, String, Bool) -> Void
    let requestMove: (UUID, String, String, Bool) -> Void

    private var selected: ReviewItem? {
        model.selectedReviewItemID.flatMap { id in model.reviewItems.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review").font(.headline)
                    Text("Items you explicitly set aside; nothing is selected automatically")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.reviewItems.count.formatted()) items")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).frame(height: 54)
            .background(DiskVisualStyle.contentSurface.opacity(0.58))

            HStack(spacing: 0) {
                reviewList
                Rectangle().fill(DiskVisualStyle.hairline).frame(width: 1)
                ReviewInspector(
                    item: selected,
                    state: selected.map(model.reviewState(for:)),
                    sourceName: selected.map { model.sourceName(for: $0.sourceLocationID) },
                    metric: model.sizeMetric,
                    quickLook: model.quickLookSelected,
                    reveal: { selected.map { CleanupService().revealInFinder(path: $0.path) } },
                    remove: { if let selected { model.removeFromReview(selected.id) } },
                    move: { if let selected { requestMove(selected.sourceLocationID, selected.path, selected.name, selected.isPackage && selected.path.lowercased().hasSuffix(".app")) } },
                    trash: { if let selected { requestTrash(selected.sourceLocationID, selected.path, selected.name, selected.isPackage && selected.path.lowercased().hasSuffix(".app")) } }
                ).frame(width: 320)
            }
        }
        .background(DiskVisualStyle.canvas)
        .onAppear { model.refreshSelectedReviewStates() }
    }

    @ViewBuilder private var reviewList: some View {
        if model.reviewItems.isEmpty {
            ContentUnavailableView(
                "Nothing in Review",
                systemImage: "tray",
                description: Text("Select an item in Scan or Apps, then choose Add to Review.")
            ).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("ITEM").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SIZE").frame(width: 90, alignment: .trailing)
                    Text("SOURCE").frame(width: 130, alignment: .leading)
                    Text("STATE").frame(width: 100, alignment: .leading)
                }
                .font(.caption2.weight(.semibold)).tracking(0.45).foregroundStyle(.secondary)
                .padding(.horizontal, 14).frame(height: 30)
                .overlay(alignment: .bottom) { Rectangle().fill(DiskVisualStyle.hairline).frame(height: 1) }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.reviewItems) { item in
                            let state = model.reviewState(for: item)
                            Button { model.selectedReviewItemID = item.id } label: {
                                HStack(spacing: 10) {
                                    HStack(spacing: 8) {
                                        Image(systemName: item.kind == .directory ? "folder.fill" : item.isPackage ? "shippingbox.fill" : "doc.fill").foregroundStyle(item.kind == .file ? .secondary : DiskVisualStyle.accentStrong).frame(width: 18)
                                        Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(StoragePresentation.bytes(item.size(for: model.sizeMetric))).font(.caption.monospacedDigit()).frame(width: 90, alignment: .trailing)
                                    Text(model.sourceName(for: item.sourceLocationID)).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(width: 130, alignment: .leading)
                                    ReviewStateLabel(state: state).frame(width: 100, alignment: .leading)
                                }
                                .padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
                                .background(model.selectedReviewItemID == item.id ? DiskVisualStyle.selection : Color.clear)
                            }.buttonStyle(.plain).contextMenu { Button("Remove from Review") { model.removeFromReview(item.id) } }
                        }
                    }
                }
            }
        }
    }
}

private struct ReviewStateLabel: View {
    let state: ReviewItemState
    var body: some View {
        Label(title, systemImage: symbol).font(.caption2.weight(.medium)).foregroundStyle(color).lineLimit(1)
    }
    private var title: String {
        switch state {
        case .ready: return "Ready"
        case .deletionLocked: return "Locked"
        case .needsRecheck: return "Recheck"
        case .missing: return "Missing"
        case .sourceUnavailable: return "Offline"
        case .actionComplete: return "Complete"
        case .actionFailed: return "Failed"
        }
    }
    private var symbol: String { state == .ready ? "checkmark.circle.fill" : state == .actionComplete ? "checkmark.circle" : "exclamationmark.circle" }
    private var color: Color { state == .ready || state == .actionComplete ? DiskVisualStyle.available : .secondary }
}

private struct ReviewInspector: View {
    let item: ReviewItem?
    let state: ReviewItemState?
    let sourceName: String?
    let metric: SizeMetric
    let quickLook: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    let move: () -> Void
    let trash: () -> Void

    var body: some View {
        Group {
            if let item, let state {
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.title3.weight(.semibold)).lineLimit(3)
                            ReviewStateLabel(state: state)
                        }
                        VStack(spacing: 8) {
                            row("Source", sourceName ?? "Unavailable")
                            row(StoragePresentation.label(for: metric), StoragePresentation.bytes(item.size(for: metric)))
                            row("Added", item.addedAt.formatted(date: .abbreviated, time: .shortened))
                            row("Snapshot", item.snapshotDate.formatted(date: .abbreviated, time: .shortened))
                            row("Reason", item.reason.displayName)
                        }
                        Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack { Button("Quick Look", action: quickLook).buttonStyle(.borderedProminent); Button("Reveal", action: reveal).buttonStyle(.bordered) }
                        Button("Remove from Review", action: remove).buttonStyle(.bordered)
                        if state == .ready {
                            HStack { Button("Move…", action: move).buttonStyle(.bordered); Button("Move to Trash…", role: .destructive, action: trash).buttonStyle(.bordered) }
                            Text("The current snapshot will be invalidated after a successful change. It will not refresh automatically.").font(.caption).foregroundStyle(.secondary)
                        } else if state != .actionComplete {
                            Label(explanation(for: state), systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checklist").font(.title2).foregroundStyle(DiskVisualStyle.accent)
                    Text("Select a review item").font(.subheadline.weight(.semibold))
                    Text("Current source, snapshot state, and conservative actions appear here.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(22)
            }
        }.background(DiskVisualStyle.inspector)
    }
    private func row(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) }.font(.subheadline) }
    private func explanation(for state: ReviewItemState) -> String {
        switch state {
        case .deletionLocked: return "Allow deletion for this source in Settings before changing it."
        case .needsRecheck: return "Refresh the source and add the item again before changing it."
        case .missing: return "The item is not present in the current snapshot."
        case .sourceUnavailable: return "Reconnect or grant access to the source."
        case .actionFailed: return "The last action failed. Recheck the source before trying again."
        default: return "This item cannot be changed in its current state."
        }
    }
}
