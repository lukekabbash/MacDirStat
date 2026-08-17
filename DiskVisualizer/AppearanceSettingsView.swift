import SwiftUI

/// Settings remains part of the storage workspace: the rail does not change,
/// and this single canvas keeps related choices visible without nested tabs.
struct SettingsCanvas: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                SettingsPageHeader()
                AppearanceSettingsSection()
                ScanningSettingsSection()
                DeletionSettingsSection()
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.top, 34)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(DiskVisualStyle.canvas)
    }
}

private struct SettingsPageHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.35)
            Text("Appearance, scan behavior, and deletion permissions for this Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsGroup(
            title: "Appearance",
            detail: "The frame stays quiet; storage categories keep their own stable colors."
        ) {
            SettingsRow(
                title: "Interface appearance",
                detail: "Follow macOS or hold a specific light or dark appearance."
            ) {
                InlineChoice(
                    choices: DiskAppearanceMode.allCases,
                    selection: $model.appearanceMode,
                    label: { $0.displayName }
                )
                .frame(width: 228)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Theme")
                        .font(.subheadline.weight(.semibold))
                    Text("Soft Glass is the default. Presets change every semantic surface together.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 182, maximum: 250), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(DiskThemeID.allCases) { theme in
                        ThemeChoiceCard(
                            theme: theme,
                            isSelected: model.themeID == theme,
                            action: { model.themeID = theme }
                        )
                    }
                }
            }
            .padding(.vertical, 14)
        }
    }
}

private struct ScanningSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsGroup(
            title: "Scanning",
            detail: "These choices apply to the next scan. Choosing a location never starts one."
        ) {
            SettingsToggleRow(
                title: "Include hidden items",
                detail: "Map dotfiles and hidden folders.",
                isOn: $model.showHiddenFiles
            )
            SettingsToggleRow(
                title: "Keep app bundles together",
                detail: "Measure each app fully, then present it as one map block.",
                isOn: $model.treatPackagesAsLeaves
            )
            SettingsToggleRow(
                title: "Detailed scan progress",
                detail: "Estimate from observed work first, then lock to a measured denominator while the map keeps growing.",
                isOn: $model.calculatesExactProgress
            )
            SettingsToggleRow(
                title: "Show capacity in the map",
                detail: "Represent free space and used space outside the selected scope as map regions.",
                isOn: $model.showFreeSpaceInMap
            )
        }
    }
}

private struct DeletionSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    private var fileChangesBinding: Binding<Bool> {
        Binding(
            get: { model.cleanupControlsEnabled },
            set: { model.setCleanupControls(enabled: $0) }
        )
    }

    var body: some View {
        SettingsGroup(
            title: "Deletion",
            detail: "Browsing is always available. Deletion requires explicit permission."
        ) {
            SettingsToggleRow(
                title: "Allow deletion",
                detail: model.cleanupControlsEnabled
                    ? "Move to Trash is available. Every deletion still asks first."
                    : "The app can inspect storage, but it does not offer deletion controls.",
                isOn: fileChangesBinding,
                symbol: model.cleanupControlsEnabled ? "lock.open.fill" : "lock.fill"
            )

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "shield.checkered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("Move to Trash remains recoverable in Finder. This app never permanently erases an item and never deletes without a confirmation step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 13)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 11)

            Rectangle()
                .fill(DiskVisualStyle.hairline)
                .frame(height: 1)

            content
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
                .frame(minWidth: 220, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DiskVisualStyle.hairline)
                .frame(height: 1)
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
        SettingsRow(title: title, detail: detail) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DiskVisualStyle.accent)
            }
        }
    }
}

private struct InlineChoice<Item: Hashable>: View {
    let choices: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    @Namespace private var selectedSurface

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.self) { item in
                Button {
                    withAnimation(DiskVisualStyle.settleMotion) { selection = item }
                } label: {
                    Text(label(item))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selection == item ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 27)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(DiskVisualStyle.raisedSurface)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "inline-choice", in: selectedSurface)
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

private struct ThemeChoiceCard: View {
    let theme: DiskThemeID
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ThemeSwatch(theme: theme, dark: colorScheme == .dark)
                    .frame(width: 52, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(theme.description)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DiskVisualStyle.accentStrong)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentShape(Rectangle())
            .background(
                isSelected ? DiskVisualStyle.selection : isHovered ? DiskVisualStyle.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: DiskVisualStyle.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DiskVisualStyle.rowRadius, style: .continuous)
                    .stroke(
                        isSelected ? DiskVisualStyle.accent.opacity(0.48) : DiskVisualStyle.hairline,
                        lineWidth: 1
                    )
            }
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
    let dark: Bool

    var body: some View {
        let colors = DiskVisualStyle.previewColors(for: theme, dark: dark)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colors[0])
            Rectangle()
                .fill(colors[1])
                .frame(width: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(colors[2])
                .padding(.leading, 19)
                .padding(.trailing, 5)
                .padding(.vertical, 5)
            Capsule()
                .fill(colors[3])
                .frame(width: 15, height: 3)
                .offset(x: 29, y: 9)
            Circle()
                .fill(colors[4])
                .frame(width: 5, height: 5)
                .offset(x: 22, y: -8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DiskVisualStyle.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
