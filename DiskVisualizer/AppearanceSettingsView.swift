import SwiftUI

struct SettingsNavigationSidebar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SettingsSection
    let close: () -> Void
    @Namespace private var selectionSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: close) {
                Label("Back to storage", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(DiskGelButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 14)

            Text("SETTINGS")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(reduceMotion ? nil : DiskVisualStyle.settleMotion) {
                            selection = section
                        }
                    } label: {
                        Label(section.displayName, systemImage: section.symbolName)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                            .background {
                                if selection == section {
                                    RoundedRectangle(cornerRadius: DiskVisualStyle.rowRadius, style: .continuous)
                                        .fill(DiskVisualStyle.selection)
                                        .matchedGeometryEffect(id: "settings-selection", in: selectionSurface)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == section ? Color.primary : Color.secondary)
                }
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mac Directory Statistics")
                    .font(.caption.weight(.medium))
                Text("Private, local, and explicit by default")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DiskVisualStyle.sidebar)
    }
}

struct SettingsCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            DiskVisualStyle.canvas.ignoresSafeArea()
            Group {
                switch model.settingsSection {
                case .appearance: AppearanceSettingsView()
                case .scanning: ScanSettingsView()
                case .cleanup: CleanupSettingsView()
                }
            }
            .id(model.settingsSection)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .trailing))
            )
        }
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: model.settingsSection)
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsPage(
            title: "Appearance",
            detail: "Keep the frame quiet so the storage map can do the visual work."
        ) {
            SettingsSectionBlock(title: "Mode", detail: "Follow macOS or hold a specific appearance.") {
                HStack(spacing: 8) {
                    ForEach(DiskAppearanceMode.allCases) { mode in
                        AppearanceModeButton(
                            mode: mode,
                            isSelected: model.appearanceMode == mode,
                            action: { model.appearanceMode = mode }
                        )
                    }
                }
            }

            SettingsSectionBlock(
                title: "Theme",
                detail: "Themes change semantic roles together. File colors remain stable and readable."
            ) {
                VStack(spacing: 6) {
                    ForEach(DiskThemeID.allCases) { theme in
                        ThemeChoiceRow(
                            theme: theme,
                            isSelected: model.themeID == theme,
                            action: { model.themeID = theme }
                        )
                    }
                }
            }
        }
    }
}

private struct ScanSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsPage(
            title: "Scanning",
            detail: "Choose what the next scan includes. Nothing starts until you press Scan."
        ) {
            SettingsSectionBlock(title: "Contents", detail: "These choices apply on the next scan or refresh.") {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Include hidden items",
                        detail: "Map dotfiles and hidden folders.",
                        isOn: $model.showHiddenFiles
                    )
                    SettingsToggleRow(
                        title: "Keep app bundles together",
                        detail: "Measure each app fully, then present it as one block.",
                        isOn: $model.treatPackagesAsLeaves
                    )
                }
            }

            SettingsSectionBlock(title: "Map", detail: "Capacity context stays visible below the map.") {
                SettingsToggleRow(
                    title: "Include free space in the map",
                    detail: "Add proportional regions for free space and use outside the selected scan.",
                    isOn: $model.showFreeSpaceInMap
                )
            }
        }
    }
}

private struct CleanupSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var cleanupBinding: Binding<Bool> {
        Binding(
            get: { model.cleanupControlsEnabled },
            set: { model.setCleanupControls(enabled: $0) }
        )
    }

    var body: some View {
        SettingsPage(
            title: "Cleanup",
            detail: "Browsing is the default. File actions only appear after you deliberately unlock them."
        ) {
            SettingsSectionBlock(title: "File actions", detail: "Moving and Trash actions still ask for confirmation.") {
                SettingsToggleRow(
                    title: model.cleanupControlsEnabled ? "Cleanup controls enabled" : "Cleanup controls locked",
                    detail: model.cleanupControlsEnabled
                        ? "Reveal, open, move, and Trash controls are available in the inspector."
                        : "The app can inspect storage but cannot offer file-changing controls.",
                    isOn: cleanupBinding,
                    symbol: model.cleanupControlsEnabled ? "lock.open.fill" : "lock.fill"
                )
            }

            Text("Moving to Trash is recoverable through Finder. The app never permanently deletes a file and never performs an action without a confirmation step.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 38) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.5)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 42)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsSectionBlock<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 34, verticalSpacing: 0) {
            GridRow {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 178, alignment: .leading)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var symbol: String?

    init(title: String, detail: String, isOn: Binding<Bool>, symbol: String? = nil) {
        self.title = title
        self.detail = detail
        _isOn = isOn
        self.symbol = symbol
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 20)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(DiskVisualStyle.accent)
        .padding(.vertical, 10)
    }
}

private struct AppearanceModeButton: View {
    let mode: DiskAppearanceMode
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(mode.displayName)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isSelected ? DiskVisualStyle.selection : isHovered ? DiskVisualStyle.controlHover : Color.clear,
                in: RoundedRectangle(cornerRadius: DiskVisualStyle.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DiskVisualStyle.controlRadius, style: .continuous)
                    .stroke(isSelected ? DiskVisualStyle.accent.opacity(0.46) : DiskVisualStyle.hairline, lineWidth: 1)
            }
            .scaleEffect(isHovered ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DiskVisualStyle.motion, value: isHovered)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ThemeChoiceRow: View {
    let theme: DiskThemeID
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ThemeSwatch(theme: theme)
                    .frame(width: 64, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(theme.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DiskVisualStyle.accentStrong)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                isSelected ? DiskVisualStyle.selection : isHovered ? DiskVisualStyle.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: DiskVisualStyle.rowRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DiskVisualStyle.motion, value: isHovered)
        .animation(DiskVisualStyle.settleMotion, value: isSelected)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ThemeSwatch: View {
    let theme: DiskThemeID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = DiskVisualStyle.previewColors(for: theme, dark: colorScheme == .dark)
        HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
            }
        }
        .padding(5)
        .background(colors[0], in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DiskVisualStyle.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
