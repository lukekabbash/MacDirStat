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

/// A single, stable orientation strip. It carries identity, state, essential
/// totals, and the primary view switch without competing with the data canvas.
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
        HStack(spacing: 14) {
            orientation
                .frame(minWidth: 170, maxWidth: 260, alignment: .leading)

            Group {
                if let scanActivity = scanTelemetry.activity {
                    CompactScanActivity(activity: scanActivity)
                        .transition(.opacity)
                } else {
                    snapshotSummary
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Picker("View", selection: $dashboardMode) {
                ForEach(DashboardMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 154)

            ScanStateIndicator(isScanning: isScanning, isComplete: session.isComplete)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(DiskVisualStyle.contentSurface.opacity(0.72))
        .overlay(alignment: .bottom) {
            if isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(DiskVisualStyle.accent)
                    .frame(height: 2)
                    .transition(.opacity)
            }
        }
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var snapshotSummary: some View {
        Text("\(StoragePresentation.bytes(currentSize)) · \(visibleItemCount.formatted()) items")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.numericText())
            .help(statusLine)
    }
}

private struct CompactScanActivity: View {
    let activity: ScanActivity
    var body: some View {
        HStack(spacing: 6) {
            ScanningMark()
                .frame(width: 18, height: 18)
            Text(activity.phase.displayName)
                .fontWeight(.medium)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(activity.inspectedItems.formatted())
                .monospacedDigit()
                .contentTransition(.numericText())
            if activity.itemsPerSecond > 1 {
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

private struct ScanStateIndicator: View {
    let isScanning: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 7) {
            if isScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(isComplete ? DiskVisualStyle.available : DiskVisualStyle.attention)
                    .frame(width: 6, height: 6)
            }
            Text(isScanning ? "Refreshing" : isComplete ? "Current" : "Partial")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(width: 74, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

extension ScanProgress.Phase {
    var displayName: String {
        switch self {
        case .discovering: return "Scanning"
        case .measuringPackage: return "Measuring app"
        case .preparingMap: return "Preparing map"
        }
    }
}

struct ScanningMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActive = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(DiskVisualStyle.accent.opacity(0.20), lineWidth: 2)
            Circle()
                .trim(from: 0.08, to: 0.64)
                .stroke(DiskVisualStyle.accentStrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(isActive ? 360 : 0))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                isActive = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct ScanActivityDetails: View {
    let activity: ScanActivity

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 14) {
                detail(activity.phase.displayName, systemImage: "dot.radiowaves.left.and.right")
                detail(activity.inspectedItems.formatted(), systemImage: "doc.on.doc")
                if activity.itemsPerSecond > 1 {
                    detail("\(Int(activity.itemsPerSecond).formatted())/s", systemImage: "speedometer")
                }
                detail(elapsed(from: activity.startedAt, to: context.date), systemImage: "clock")
                detail(activity.currentLocation, systemImage: "folder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current scan activity")
    }

    private func detail(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .lineLimit(1)
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct EmptyDiskDashboard: View {
    let selectedRootName: String?
    let startScan: () -> Void
    let chooseFullMac: () -> Void
    let chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "internaldrive")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text(selectedRootName == nil ? "See where the space went" : "Ready when you are")
                    .font(.title2.weight(.semibold))
                Text(idleDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 470)
            }
            HStack(spacing: 10) {
                if let selectedRootName {
                    Button("Scan \(selectedRootName)", action: startScan)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Menu("Change location") {
                        Button("Full Mac…", systemImage: "desktopcomputer", action: chooseFullMac)
                        Button("Choose Folder…", systemImage: "folder.badge.plus", action: chooseFolder)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button("Scan Full Mac…", action: chooseFullMac)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Choose Folder…", action: chooseFolder)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }

            Label("Idle · no filesystem work is running", systemImage: "pause.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(DiskVisualStyle.available)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background(DiskVisualStyle.canvas)
    }

    private var idleDescription: String {
        if let selectedRootName {
            return "\(selectedRootName) is selected. Nothing scans until you start it; once running, progress stays out of the way."
        }
        return "Choose the full Mac or a folder to create a new snapshot. Cleanup remains locked until you explicitly enable it."
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

/// Compact tactile chrome. Reading surfaces stay flat; only controls receive
/// the short falloff, contact shadow, and small press displacement.
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
