import AppKit
import Core
import SwiftUI

enum StoragePresentation {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func itemCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func percentage(_ value: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "—" }
        return (Double(value) / Double(total)).formatted(.percent.precision(.fractionLength(1)))
    }

    static func icon(for kind: FileKind) -> String {
        switch kind {
        case .root, .directory: return "folder.fill"
        case .packageLeaf: return "shippingbox.fill"
        case .file: return "doc.fill"
        }
    }

    static func label(for metric: SizeMetric) -> String {
        metric == .allocated ? "On disk" : "Logical"
    }
}

/// One compact orientation strip carries location, live scan state, totals,
/// and the workspace view. The map remains the dominant visual surface.
struct DiskDashboardHeader: View {
    let session: ScanSession
    let metric: SizeMetric
    let isScanning: Bool
    let scannedNodeCount: Int
    let statusLine: String
    @ObservedObject var scanTelemetry: ScanTelemetryState
    let breadcrumb: [NodeID]
    @Binding var dashboardMode: DashboardMode

    private var currentSize: UInt64 {
        metric == .allocated ? session.rootTotalAllocated : session.rootTotalLogical
    }

    private var visibleItemCount: Int {
        scanTelemetry.activity?.inspectedItems
            ?? (scannedNodeCount > 0 ? scannedNodeCount : max(0, session.nodes.count - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                orientation
                    .frame(minWidth: 170, maxWidth: 310, alignment: .leading)

                Group {
                    if isScanning, let activity = scanTelemetry.activity {
                        CompactScanActivity(activity: activity)
                    } else {
                        Text("\(StoragePresentation.bytes(currentSize)) · \(visibleItemCount.formatted()) items")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help(statusLine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentTransition(.numericText())

                DashboardModeControl(selection: $dashboardMode)
                    .frame(width: 166)

                ScanStateBadge(activity: isScanning ? scanTelemetry.activity : nil, isComplete: session.isComplete)
                    .frame(width: 74, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 43)

            if isScanning, let activity = scanTelemetry.activity {
                ProgressView(value: activity.fractionCompleted ?? 0)
                    .progressViewStyle(.linear)
                    .tint(DiskVisualStyle.accent)
                    .frame(height: 2)
                    .transition(.opacity)
            }
        }
        .background(DiskVisualStyle.contentSurface.opacity(0.66))
        .animation(DiskVisualStyle.motion, value: isScanning)
    }

    @ViewBuilder
    private var orientation: some View {
        if dashboardMode == .map {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DiskVisualStyle.accentStrong)
                    ForEach(Array(breadcrumb.enumerated()), id: \.offset) { index, nodeID in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(session.node(id: nodeID)?.name ?? "Unknown")
                            .font(.caption.weight(index == breadcrumb.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == breadcrumb.count - 1 ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            Label("Storage overview", systemImage: "chart.bar.xaxis")
                .font(.caption.weight(.semibold))
        }
    }
}

private struct DashboardModeControl: View {
    @Binding var selection: DashboardMode
    @Namespace private var selectionSurface

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(DiskVisualStyle.selectionMotion) { selection = mode }
                } label: {
                    Label(mode.displayName, systemImage: mode == .map ? "square.grid.3x3" : "chart.bar.xaxis")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .background {
                            if selection == mode {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(DiskVisualStyle.raisedSurface)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "dashboard-mode", in: selectionSurface)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(DiskVisualStyle.subtleSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DiskVisualStyle.hairline, lineWidth: 1)
        }
    }
}

private struct CompactScanActivity: View {
    let activity: ScanActivity

    var body: some View {
        HStack(spacing: 6) {
            Text(activity.phase.displayName)
                .fontWeight(.medium)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(activity.inspectedItems.formatted())
                .monospacedDigit()
                .contentTransition(.numericText())
            if activity.itemsPerSecond > 1, activity.phase != .indexing {
                Text("· \(Int(activity.itemsPerSecond).formatted())/s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("· \(activity.currentLocation)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scan progress")
    }
}

private struct ScanStateBadge: View {
    let activity: ScanActivity?
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(activity == nil ? (isComplete ? DiskVisualStyle.available : DiskVisualStyle.attention) : DiskVisualStyle.accent)
                .frame(width: 6, height: 6)
            Text(activity?.percentageText ?? (activity == nil ? (isComplete ? "Current" : "Partial") : "0%"))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

extension ScanProgress.Phase {
    var displayName: String {
        switch self {
        case .indexing: return "Indexing"
        case .discovering: return "Scanning"
        case .measuringPackage: return "Measuring app"
        case .preparingMap: return "Preparing map"
        }
    }
}

/// Shared determinate treatment for first-scan and sidebar contexts.
struct ScanProgressPanel: View {
    let activity: ScanActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(activity.phase == .indexing ? "Calculating exact total" : activity.phase.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(activity.percentageText ?? "0%")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }

            ProgressView(value: activity.fractionCompleted ?? 0)
                .progressViewStyle(.linear)
                .tint(DiskVisualStyle.accent)

            HStack(spacing: 7) {
                Text("\(activity.inspectedItems.formatted()) items")
                    .monospacedDigit()
                if let total = activity.totalItems {
                    Text("of \(total.formatted())")
                        .monospacedDigit()
                }
                if activity.itemsPerSecond > 1, activity.phase != .indexing {
                    Text("· \(Int(activity.itemsPerSecond).formatted())/s")
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text(activity.currentLocation)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current scan activity")
    }
}

struct ScanActivityDetails: View {
    let activity: ScanActivity

    var body: some View {
        ScanProgressPanel(activity: activity)
    }
}

struct EmptyDiskDashboard: View {
    let selectedRootName: String?
    let selectedRootAvailability: LocationAvailability?
    let metric: SizeMetric
    let includesHiddenItems: Bool
    let groupsAppBundles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("STORAGE MAP")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.3)
                    Text(idleDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 32)
                Label(statusLabel, systemImage: statusSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Rectangle()
                .fill(DiskVisualStyle.hairline)
                .frame(height: 1)

            HStack(spacing: 22) {
                IdleTreemapPreview(scopeName: selectedRootName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 0) {
                    SnapshotAttribute(label: "Scope", value: selectedRootName ?? "Not selected")
                    SnapshotAttribute(label: "Measure", value: StoragePresentation.label(for: metric))
                    SnapshotAttribute(label: "Hidden items", value: includesHiddenItems ? "Included" : "Excluded")
                    SnapshotAttribute(label: "App bundles", value: groupsAppBundles ? "Grouped" : "Expanded")
                    SnapshotAttribute(label: "Deletion", value: "Disabled")
                }
                .frame(width: 248)
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiskVisualStyle.canvas)
    }

    private var idleDescription: String {
        guard selectedRootName != nil else {
            return "Select the full Mac or a focused folder in the sidebar."
        }
        switch selectedRootAvailability {
        case .needsAccess:
            return "Press Reconnect & Scan to renew macOS access and begin."
        case .disconnected:
            return "Reconnect the drive, then press Reconnect & Scan."
        case .ready, .none:
            return "Nothing runs until you press Scan in the sidebar."
        }
    }

    private var title: String {
        guard let selectedRootName else { return "Choose a scope" }
        switch selectedRootAvailability {
        case .needsAccess: return "Reconnect \(selectedRootName)"
        case .disconnected: return "\(selectedRootName) is offline"
        case .ready, .none: return "\(selectedRootName) is ready"
        }
    }

    private var statusLabel: String {
        switch selectedRootAvailability {
        case .needsAccess: return "Access needed"
        case .disconnected: return "Offline"
        case .ready, .none: return "Idle"
        }
    }

    private var statusSymbol: String {
        switch selectedRootAvailability {
        case .needsAccess: return "key.fill"
        case .disconnected: return "externaldrive.badge.xmark"
        case .ready, .none: return "pause.fill"
        }
    }

    private var statusColor: Color {
        switch selectedRootAvailability {
        case .needsAccess, .disconnected: return DiskVisualStyle.attention
        case .ready, .none: return DiskVisualStyle.available
        }
    }
}

private struct IdleTreemapPreview: View {
    let scopeName: String?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DiskVisualStyle.contentSurface)

                Group {
                    previewBlock(x: 0.018, y: 0.025, width: 0.47, height: 0.59, color: DiskVisualStyle.accent)
                    previewBlock(x: 0.018, y: 0.645, width: 0.47, height: 0.33, color: DiskVisualStyle.attention)
                    previewBlock(x: 0.505, y: 0.025, width: 0.477, height: 0.37, color: DiskVisualStyle.available)
                    previewBlock(x: 0.505, y: 0.415, width: 0.285, height: 0.56, color: DiskVisualStyle.neutral)
                    previewBlock(x: 0.808, y: 0.415, width: 0.174, height: 0.265, color: DiskVisualStyle.accentStrong)
                    previewBlock(x: 0.808, y: 0.70, width: 0.174, height: 0.275, color: DiskVisualStyle.available)
                }
                .opacity(scopeName == nil ? 0.10 : 0.16)

                VStack(spacing: 7) {
                    Image(systemName: scopeName == nil ? "folder.badge.plus" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DiskVisualStyle.accentStrong)
                    Text(scopeName == nil ? "Choose what to map" : "Ready to scan")
                        .font(.headline)
                    Text(scopeName == nil ? "Full Mac or a focused folder" : "The map will fill here as files are measured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DiskVisualStyle.hairline, lineWidth: 1)
            }
            .frame(width: width, height: height)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scopeName == nil ? "Choose a location to map" : "Ready to scan \(scopeName ?? "location")")
    }

    private func previewBlock(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .padding(2)
                .frame(width: proxy.size.width * width, height: proxy.size.height * height)
                .offset(x: proxy.size.width * x, y: proxy.size.height * y)
        }
    }
}

private struct SnapshotAttribute: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DiskVisualStyle.hairline).frame(height: 1)
        }
    }
}

struct TagPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.11), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.16), lineWidth: 0.5) }
    }
}

/// Tactile chrome is reserved for controls; reading surfaces stay flat.
struct DiskGelButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        DiskControlButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isSelected: isSelected,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion
        )
    }
}

private struct DiskControlButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isSelected: Bool
    let isEnabled: Bool
    let reduceMotion: Bool
    @State private var isHovered = false

    var body: some View {
        label
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? DiskVisualStyle.accentStrong : Color.secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: DiskVisualStyle.controlHeight)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: DiskVisualStyle.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DiskVisualStyle.controlRadius, style: .continuous)
                    .stroke(isSelected ? DiskVisualStyle.accent.opacity(0.48) : DiskVisualStyle.hairline, lineWidth: 1)
            }
            .offset(y: isPressed ? 0.5 : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(RoundedRectangle(cornerRadius: DiskVisualStyle.controlRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : DiskVisualStyle.motion, value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.07), value: isPressed)
    }

    private var backgroundColor: Color {
        if isPressed { return DiskVisualStyle.controlPressed }
        if isSelected { return DiskVisualStyle.selection }
        if isHovered && isEnabled { return DiskVisualStyle.controlHover }
        return DiskVisualStyle.contentSurface.opacity(0.58)
    }
}

private struct InteractiveRowSurface: ViewModifier {
    let isHovered: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? DiskVisualStyle.selection : isHovered ? DiskVisualStyle.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .animation(DiskVisualStyle.motion, value: isHovered)
            .animation(DiskVisualStyle.settleMotion, value: isSelected)
    }
}

extension View {
    func diskInteractiveRow(isHovered: Bool, isSelected: Bool = false) -> some View {
        modifier(InteractiveRowSurface(isHovered: isHovered, isSelected: isSelected))
    }
}
