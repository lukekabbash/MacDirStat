import SwiftUI

/// Whole-volume context for a folder-level treemap. The treemap keeps its full
/// working area; this proportional strip answers the separate question of how
/// much physical capacity is currently available on the containing volume.
struct VolumeSpaceContextView: View {
    let snapshot: VolumeSpaceSnapshot
    let scopeName: String
    let scopeAllocatedSize: UInt64
    let isIncludedInMap: Bool

    private var usedFraction: Double {
        guard snapshot.capacity > 0 else { return 0 }
        return min(1, Double(snapshot.used) / Double(snapshot.capacity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(snapshot.name, systemImage: "internaldrive")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(isIncludedInMap ? "Shown proportionally in map" : "Whole-volume context")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                VolumeLegendDot(color: .secondary, label: "Used", value: snapshot.used)
                VolumeLegendDot(color: DiskVisualStyle.available, label: "Available", value: snapshot.available)
            }

            GeometryReader { proxy in
                let usedWidth = proxy.size.width * usedFraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DiskVisualStyle.available.opacity(0.20))
                    Capsule()
                        .fill(Color.secondary.opacity(0.48))
                        .frame(width: usedWidth)
                }
                .overlay {
                    Capsule().stroke(DiskVisualStyle.hairline, lineWidth: 1)
                }
                .animation(DiskVisualStyle.settleMotion, value: usedFraction)
            }
            .frame(height: 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume capacity")
            .accessibilityValue(
                "\(StoragePresentation.bytes(snapshot.used)) used, \(StoragePresentation.bytes(snapshot.available)) available"
            )

            Text(isIncludedInMap
                ? "Available space and volume use outside \(scopeName) are included as map regions above."
                : "The map above is \(scopeName) (\(StoragePresentation.bytes(scopeAllocatedSize)) on disk); this strip is the full \(StoragePresentation.bytes(snapshot.capacity)) volume."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

private struct VolumeLegendDot: View {
    let color: Color
    let label: String
    let value: UInt64

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(StoragePresentation.bytes(value))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption2)
    }
}
