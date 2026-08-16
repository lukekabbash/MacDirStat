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

/// Appearance and palette are independent. A palette owns semantic roles, so
/// future themes never need to know which screen or component consumes them.
enum DiskThemeID: String, CaseIterable, Identifiable {
    case integrator
    case graphite
    case softGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .integrator: return "Integrator"
        case .graphite: return "Graphite"
        case .softGlass: return "Soft Glass"
        }
    }

    var description: String {
        switch self {
        case .integrator: return "Black, graphite, and silver. The data carries the color."
        case .graphite: return "Neutral mineral surfaces with a restrained steel-blue signal."
        case .softGlass: return "A quieter version of the icon palette: slate, mint, and lilac."
        }
    }

    fileprivate var definition: DiskThemeDefinition {
        switch self {
        case .integrator:
            return DiskThemeDefinition(
                light: .init(
                    accent: 0x42464B, accentStrong: 0x24272A,
                    available: 0x688071, attention: 0x8A7553, neutral: 0x777A7D,
                    canvas: 0xF5F5F2, rail: 0xECEDE9, panel: 0xFAFAF8,
                    layer: 0xFFFFFF, inspector: 0xF0F0ED,
                    border: 0xD9DAD6, borderStrong: 0xB9BBB7, danger: 0xA5544F
                ),
                dark: .init(
                    accent: 0xE6E6E6, accentStrong: 0xFFFFFF,
                    available: 0x98B6A2, attention: 0xCFAE72, neutral: 0xA3A3A3,
                    canvas: 0x050505, rail: 0x0E0E0E, panel: 0x131313,
                    layer: 0x1B1B1B, inspector: 0x101010,
                    border: 0x262626, borderStrong: 0x4A4A4A, danger: 0xD68983
                )
            )
        case .graphite:
            return DiskThemeDefinition(
                light: .init(
                    accent: 0x547A98, accentStrong: 0x365F7E,
                    available: 0x5F8B79, attention: 0x9A7750, neutral: 0x737B82,
                    canvas: 0xF3F5F6, rail: 0xE8ECEE, panel: 0xFAFBFB,
                    layer: 0xFFFFFF, inspector: 0xEDF0F2,
                    border: 0xD2D8DC, borderStrong: 0xAAB4BB, danger: 0xAD554F
                ),
                dark: .init(
                    accent: 0x72A7D1, accentStrong: 0xA7CCE7,
                    available: 0x70B58A, attention: 0xD5A956, neutral: 0x8B969E,
                    canvas: 0x111315, rail: 0x16191C, panel: 0x1A1D21,
                    layer: 0x23282D, inspector: 0x15181B,
                    border: 0x2A3035, borderStrong: 0x46515A, danger: 0xDC7771
                )
            )
        case .softGlass:
            return DiskThemeDefinition(
                light: .init(
                    accent: 0x627C9D, accentStrong: 0x496887,
                    available: 0x4F8F82, attention: 0x806994, neutral: 0x74777E,
                    canvas: 0xF4F4F2, rail: 0xECEDEB, panel: 0xFBFBFA,
                    layer: 0xFFFFFF, inspector: 0xEFF0EE,
                    border: 0xD5D7D8, borderStrong: 0xAEB4B8, danger: 0xA9514C
                ),
                dark: .init(
                    accent: 0x9BB8DC, accentStrong: 0xB1C9E5,
                    available: 0x7CC8B6, attention: 0xBEA0D5, neutral: 0xA9ADB5,
                    canvas: 0x17191C, rail: 0x202225, panel: 0x292C30,
                    layer: 0x31343A, inspector: 0x1C1E21,
                    border: 0x3E4248, borderStrong: 0x626974, danger: 0xD17D78
                )
            )
        }
    }
}

private struct DiskThemeVariant {
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

private struct DiskThemeDefinition {
    let light: DiskThemeVariant
    let dark: DiskThemeVariant
}

/// Semantic tokens shared by chrome and content. The active theme is resolved
/// lazily by AppKit's appearance provider; changing theme rebuilds the root
/// view, while changing light/dark mode does not require new token objects.
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

    static func previewColors(for theme: DiskThemeID, dark: Bool) -> [Color] {
        let variant = dark ? theme.definition.dark : theme.definition.light
        return [variant.canvas, variant.rail, variant.accent, variant.available, variant.attention]
            .map { Color(nsColor: nsColor(hex: $0)) }
    }

    private static func themed(_ role: Role) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let themeID = DiskThemeID(
                rawValue: UserDefaults.standard.string(forKey: "themeID") ?? ""
            ) ?? .integrator
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
