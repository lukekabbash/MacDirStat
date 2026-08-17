import Core
import Foundation
import SwiftUI

/// A selected location owns a compact timeline of explicit, read-only saves.
/// Catalog rows stay lightweight; the full arena loads only after selection.
struct SidebarSnapshotHistory: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let location: SavedLocation
    let metric: SizeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            heading

            if let current = model.snapshot(for: location.id) {
                SnapshotHistoryRow(
                    title: "Current scan",
                    subtitle: currentSubtitle(current),
                    symbol: "clock.arrow.circlepath",
                    isSelected: model.selectedHistoricalSnapshotID == nil,
                    isEnabled: !model.isSnapshotHistoryBusy,
                    action: model.selectCurrentSnapshot
                )
                .help("Return to the latest in-memory scan")
            }

            ForEach(Array(model.savedSnapshotDescriptors.enumerated()), id: \.element.id) { index, descriptor in
                SnapshotHistoryRow(
                    title: descriptor.scannedAt.formatted(date: .abbreviated, time: .shortened),
                    subtitle: descriptorSubtitle(descriptor, at: index),
                    symbol: "camera.fill",
                    isSelected: model.selectedHistoricalSnapshotID == descriptor.id,
                    isEnabled: !model.isScanning && !model.isSnapshotHistoryBusy,
                    action: {
                        Task { await model.selectHistoricalSnapshot(descriptor.id) }
                    }
                )
                .help(historyHelp(descriptor))
            }

            if model.savedSnapshotDescriptors.isEmpty, !model.isSnapshotHistoryBusy {
                Text("Save a completed scan to compare it later.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
            }

            if let error = model.snapshotHistoryError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(DiskVisualStyle.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 1)
        .padding(.bottom, 5)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved scans for \(location.displayName)")
    }

    private var heading: some View {
        HStack(spacing: 6) {
            Text("SCANS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(.tertiary)
            Spacer()
            if model.isSnapshotHistoryBusy {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Loading scan history")
            } else if !model.savedSnapshotDescriptors.isEmpty {
                Text(model.savedSnapshotDescriptors.count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 2)
    }

    private func currentSubtitle(_ snapshot: LocationSnapshot) -> String {
        let size = metric == .allocated
            ? snapshot.session.rootTotalAllocated
            : snapshot.session.rootTotalLogical
        return "\(StoragePresentation.bytes(size)) · \(snapshot.scannedAt.formatted(.relative(presentation: .named)))"
    }

    private func descriptorSubtitle(_ descriptor: ScanSnapshotDescriptor, at index: Int) -> String {
        let size = descriptorSize(descriptor)
        guard model.savedSnapshotDescriptors.indices.contains(index + 1) else {
            return StoragePresentation.bytes(size)
        }
        let olderSize = descriptorSize(model.savedSnapshotDescriptors[index + 1])
        return "\(StoragePresentation.bytes(size)) · \(changeText(from: olderSize, to: size))"
    }

    private func descriptorSize(_ descriptor: ScanSnapshotDescriptor) -> UInt64 {
        metric == .allocated ? descriptor.allocatedSize : descriptor.logicalSize
    }

    private func changeText(from older: UInt64, to newer: UInt64) -> String {
        if newer == older { return "No change" }
        if newer > older {
            return "+\(StoragePresentation.bytes(newer - older))"
        }
        return "−\(StoragePresentation.bytes(older - newer))"
    }

    private func historyHelp(_ descriptor: ScanSnapshotDescriptor) -> String {
        let archive = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: descriptor.storedByteCount),
            countStyle: .file
        )
        return "Open this interactive read-only snapshot · \(descriptor.nodeCount.formatted()) items · \(archive) stored"
    }
}

private struct SnapshotHistoryRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? DiskVisualStyle.iconAccent : Color.secondary)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                isSelected ? DiskVisualStyle.selection : isHovered ? DiskVisualStyle.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
