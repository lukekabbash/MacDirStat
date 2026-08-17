import AppKit
import SwiftUI
import Treemap

enum DiskAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A theme owns semantic roles rather than screen-specific colors. New
/// palettes can therefore change the whole app without component exceptions.
enum DiskThemeID: String, CaseIterable, Identifiable {
    case softGlass
    case integrator
    case usonian
    case graphite
    case ash
    case midnight
    case ocean
    case forest
    case dusk
    case paper
    case iris
    case porcelain
    case sage
    case highContrast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .softGlass: return "Soft Glass"
        case .integrator: return "Integrator"
        case .usonian: return "Usonian"
        case .graphite: return "Graphite"
        case .ash: return "Ash"
        case .midnight: return "Midnight"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .dusk: return "Dusk"
        case .paper: return "Paper"
        case .iris: return "Iris"
        case .porcelain: return "Porcelain"
        case .sage: return "Sage"
        case .highContrast: return "High Contrast"
        }
    }

    var description: String {
        switch self {
        case .softGlass: return "Slate, mint, and lilac with quiet translucent depth."
        case .integrator: return "Pure black, white, graphite, and silver."
        case .usonian: return "Warm ivory with federal blue interaction and brick red controls."
        case .graphite: return "Near-black mineral surfaces with a steel-blue signal."
        case .ash: return "Pale mineral gray with quiet ink and lake-blue controls."
        case .midnight: return "Inky blue-black depth with glacial-blue interaction."
        case .ocean: return "Deep marine surfaces with a crisp cyan current."
        case .forest: return "Evergreen charcoal with moss and fern accents."
        case .dusk: return "Twilight plum-gray warmed by a restrained apricot."
        case .paper: return "Warm ivory, graphite ink, and editorial blue."
        case .iris: return "Charcoal-violet depth with soft amethyst emphasis."
        case .porcelain: return "White porcelain, ink text, and graphite controls."
        case .sage: return "Fresh pale greens with grounded herbal accents."
        case .highContrast: return "Maximum separation and explicit focus."
        }
    }

    var definition: DiskThemeDefinition { DiskThemeCatalog.definition(for: self) }

    /// Mirrors the reference catalog's dark-to-light progression for the
    /// presets this app supports, with Soft Glass at the light transition.
    static let settingsOrder: [DiskThemeID] = [
        .integrator,
        .dusk,
        .forest,
        .ocean,
        .highContrast,
        .midnight,
        .graphite,
        .iris,
        .softGlass,
        .usonian,
        .paper,
        .sage,
        .ash,
        .porcelain,
    ]

    var previewIsDark: Bool {
        switch self {
        case .integrator, .dusk, .forest, .ocean, .highContrast, .midnight, .graphite, .iris:
            return true
        case .softGlass, .usonian, .paper, .sage, .ash, .porcelain:
            return false
        }
    }
}

struct DiskThemeVariant {
    let accent: UInt32
    let accentStrong: UInt32
    let available: UInt32
    let attention: UInt32
    let neutral: UInt32
    let canvas: UInt32
    let rail: UInt32
    let panel: UInt32
    let layer: UInt32
    let inspector: UInt32
    let border: UInt32
    let borderStrong: UInt32
    let danger: UInt32

    /// Optional overrides keep the visual roles independently tunable without
    /// forcing every palette to repeat its existing primary accent.
    let interactionAccent: UInt32?
    let interactionStrong: UInt32?
    let controlAccent: UInt32?
    let iconAccent: UInt32?

    init(
        accent: UInt32,
        accentStrong: UInt32,
        available: UInt32,
        attention: UInt32,
        neutral: UInt32,
        canvas: UInt32,
        rail: UInt32,
        panel: UInt32,
        layer: UInt32,
        inspector: UInt32,
        border: UInt32,
        borderStrong: UInt32,
        danger: UInt32,
        interactionAccent: UInt32? = nil,
        interactionStrong: UInt32? = nil,
        controlAccent: UInt32? = nil,
        iconAccent: UInt32? = nil
    ) {
        self.accent = accent
        self.accentStrong = accentStrong
        self.available = available
        self.attention = attention
        self.neutral = neutral
        self.canvas = canvas
        self.rail = rail
        self.panel = panel
        self.layer = layer
        self.inspector = inspector
        self.border = border
        self.borderStrong = borderStrong
        self.danger = danger
        self.interactionAccent = interactionAccent
        self.interactionStrong = interactionStrong
        self.controlAccent = controlAccent
        self.iconAccent = iconAccent
    }
}

struct DiskThemeDefinition {
    let light: DiskThemeVariant
    let dark: DiskThemeVariant
}

/// The compact palette used by previews and the runtime app mark. It exposes
/// semantic colors rather than positional swatch indices, so future themes do
/// not have to coordinate with individual view layouts.
struct DiskThemePreviewPalette {
    let canvas: Color
    let rail: Color
    let panel: Color
    let layer: Color
    let border: Color
    let interactionAccent: Color
    let controlAccent: Color
    let iconAccent: Color
    let available: Color
}

enum DiskVisualStyle {
    private enum Role {
        case accent, accentStrong
        case interactionAccent, interactionStrong, controlAccent, iconAccent
        case available, attention, neutral, danger
        case canvas, sidebar, contentSurface, raisedSurface, inspector
        case hairline, strongHairline
    }

    /// Compatibility aliases map existing views to their intended visual role.
    /// New code should choose an explicit role below.
    static var accent: Color { themed(.accent) }
    static var accentStrong: Color { themed(.accentStrong) }
    static var interactionAccent: Color { themed(.interactionAccent) }
    static var interactionStrong: Color { themed(.interactionStrong) }
    static var controlAccent: Color { themed(.controlAccent) }
    static var iconAccent: Color { themed(.iconAccent) }
    static var available: Color { themed(.available) }
    static var attention: Color { themed(.attention) }
    static var neutral: Color { themed(.neutral) }
    static var danger: Color { themed(.danger) }
    static var canvas: Color { themed(.canvas) }
    static var sidebar: Color { themed(.sidebar) }
    static var contentSurface: Color { themed(.contentSurface) }
    static var raisedSurface: Color { themed(.raisedSurface) }
    static var inspector: Color { themed(.inspector) }
    static var hairline: Color { themed(.hairline) }
    static var strongHairline: Color { themed(.strongHairline) }
    static let quietText = Color(nsColor: .secondaryLabelColor)

    static var subtleSurface: Color { Color.primary.opacity(0.045) }
    /// Selection and hover stay tied to the interaction role, allowing a
    /// palette to separate wayfinding from action controls.
    static var selection: Color { interactionAccent.opacity(0.15) }
    static var hover: Color { interactionAccent.opacity(0.085) }
    static var controlHover: Color { interactionAccent.opacity(0.075) }
    static var controlPressed: Color { interactionAccent.opacity(0.13) }

    static let controlHeight: CGFloat = 30
    static let controlRadius: CGFloat = 8
    static let rowRadius: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let edgePadding: CGFloat = 14
    static let sidebarPadding: CGFloat = 16

    static let instantMotion = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.08)
    static let motion = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    static let contentMotion = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.20)
    static let settleMotion = Animation.spring(response: 0.26, dampingFraction: 0.9, blendDuration: 0.06)
    static let selectionMotion = Animation.interpolatingSpring(
        mass: 0.7,
        stiffness: 460,
        damping: 38,
        initialVelocity: 0
    )
    static let themeMotion = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.18)

    static func previewPalette(for theme: DiskThemeID, dark: Bool) -> DiskThemePreviewPalette {
        let variant = dark ? theme.definition.dark : theme.definition.light
        return DiskThemePreviewPalette(
            canvas: color(hex: variant.canvas),
            rail: color(hex: variant.rail),
            panel: color(hex: variant.panel),
            layer: color(hex: variant.layer),
            border: color(hex: variant.borderStrong),
            interactionAccent: color(hex: value(for: .interactionAccent, in: variant)),
            controlAccent: color(hex: value(for: .controlAccent, in: variant)),
            iconAccent: color(hex: value(for: .iconAccent, in: variant)),
            available: color(hex: variant.available)
        )
    }

    static func renderTheme(for theme: DiskThemeID, dark: Bool) -> TreemapRenderTheme {
        let variant = dark ? theme.definition.dark : theme.definition.light
        let interaction = nsColor(hex: value(for: .interactionAccent, in: variant))
        let available = nsColor(hex: variant.available)
        let neutral = nsColor(hex: variant.neutral)
        return TreemapRenderTheme(
            token: "\(theme.rawValue)-\(dark ? "dark" : "light")",
            canvas: nsColor(hex: variant.canvas),
            surface: nsColor(hex: variant.layer),
            tileStroke: nsColor(hex: variant.borderStrong).withAlphaComponent(0.46),
            selectionFill: interaction.withAlphaComponent(0.16),
            selectionStroke: interaction.withAlphaComponent(0.98),
            hoverFill: interaction.withAlphaComponent(0.10),
            availableFill: available.withAlphaComponent(0.24),
            availableStroke: available.withAlphaComponent(0.74),
            neutralFill: neutral.withAlphaComponent(0.13),
            neutralStroke: neutral.withAlphaComponent(0.66)
        )
    }

    private static func themed(_ role: Role) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let themeID = DiskThemeID(
                rawValue: UserDefaults.standard.string(forKey: "themeID") ?? ""
            ) ?? .softGlass
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let variant = isDark ? themeID.definition.dark : themeID.definition.light
            return nsColor(hex: value(for: role, in: variant))
        })
    }

    private static func value(for role: Role, in variant: DiskThemeVariant) -> UInt32 {
        switch role {
        case .accent, .controlAccent:
            return variant.controlAccent ?? variant.accent
        case .accentStrong, .iconAccent:
            return variant.iconAccent ?? variant.accentStrong
        case .interactionAccent:
            return variant.interactionAccent ?? variant.accent
        case .interactionStrong:
            return variant.interactionStrong ?? variant.accentStrong
        case .available:
            return variant.available
        case .attention:
            return variant.attention
        case .neutral:
            return variant.neutral
        case .danger:
            return variant.danger
        case .canvas:
            return variant.canvas
        case .sidebar:
            return variant.rail
        case .contentSurface:
            return variant.panel
        case .raisedSurface:
            return variant.layer
        case .inspector:
            return variant.inspector
        case .hairline:
            return variant.border
        case .strongHairline:
            return variant.borderStrong
        }
    }

    private static func color(hex: UInt32) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }

    private static func nsColor(hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A small, runtime-rendered application mark that carries the active
/// palette without changing the signed Dock and Finder icon asset.
struct ThemedAppMark: View {
    let theme: DiskThemeID
    var dark: Bool? = nil
    var size: CGFloat = 24

    @Environment(\.colorScheme) private var colorScheme

    private var usesDarkVariant: Bool {
        dark ?? (colorScheme == .dark)
    }

    var body: some View {
        let palette = DiskVisualStyle.previewPalette(for: theme, dark: usesDarkVariant)

        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let outerRadius = side * 0.26
            let innerRadius = side * 0.10
            let gap = side * 0.065

            ZStack {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(palette.layer)

                HStack(spacing: gap) {
                    VStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .fill(palette.interactionAccent)
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .fill(palette.panel)
                    }
                    .frame(width: side * 0.34)

                    VStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .fill(palette.controlAccent)
                        HStack(spacing: gap) {
                            RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                .fill(palette.iconAccent)
                            RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                .fill(palette.available)
                        }
                    }
                }
                .padding(side * 0.19)
            }
            .overlay {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .stroke(palette.border.opacity(0.72), lineWidth: max(1, side * 0.035))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName) theme mark")
    }
}
