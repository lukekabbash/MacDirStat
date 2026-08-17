import AppKit
import SwiftUI

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
        case .usonian: return "Warm American white with federal blue and brick red."
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
}

struct DiskThemeDefinition {
    let light: DiskThemeVariant
    let dark: DiskThemeVariant
}

enum DiskVisualStyle {
    private enum Role {
        case accent, accentStrong, available, attention, neutral, danger
        case canvas, sidebar, contentSurface, raisedSurface, inspector
        case hairline, strongHairline
    }

    static var accent: Color { themed(.accent) }
    static var accentStrong: Color { themed(.accentStrong) }
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
    static var selection: Color { accent.opacity(0.15) }
    static var hover: Color { accent.opacity(0.085) }
    static var controlHover: Color { accent.opacity(0.075) }
    static var controlPressed: Color { accent.opacity(0.13) }

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

    static func previewColors(for theme: DiskThemeID, dark: Bool) -> [Color] {
        let variant = dark ? theme.definition.dark : theme.definition.light
        return [variant.canvas, variant.rail, variant.panel, variant.accent, variant.available]
            .map { Color(nsColor: nsColor(hex: $0)) }
    }

    private static func themed(_ role: Role) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let themeID = DiskThemeID(
                rawValue: UserDefaults.standard.string(forKey: "themeID") ?? ""
            ) ?? .softGlass
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let variant = isDark ? themeID.definition.dark : themeID.definition.light
            let value: UInt32
            switch role {
            case .accent: value = variant.accent
            case .accentStrong: value = variant.accentStrong
            case .available: value = variant.available
            case .attention: value = variant.attention
            case .neutral: value = variant.neutral
            case .danger: value = variant.danger
            case .canvas: value = variant.canvas
            case .sidebar: value = variant.rail
            case .contentSurface: value = variant.panel
            case .raisedSurface: value = variant.layer
            case .inspector: value = variant.inspector
            case .hairline: value = variant.border
            case .strongHairline: value = variant.borderStrong
            }
            return nsColor(hex: value)
        })
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
