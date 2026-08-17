import Foundation

/// Compact source palettes keep theme growth deliberate: each preset defines
/// its material surfaces and signals, while shared derivation preserves the
/// same contrast and hierarchy across the application.
enum DiskThemeCatalog {
    private struct Seed {
        let canvas: UInt32
        let rail: UInt32
        let panel: UInt32
        let layer: UInt32
        let inspector: UInt32
        let accent: UInt32
        let available: UInt32
        let attention: UInt32
        let danger: UInt32
    }

    static func definition(for theme: DiskThemeID) -> DiskThemeDefinition {
        switch theme {
        case .softGlass:
            return paired(
                light: seed(0xF4F4F2, 0xECEDEB, 0xFBFBFA, 0xFFFFFF, 0xEFF0EE, 0x627C9D, 0x4F8F82, 0x806994),
                dark: seed(0x17191C, 0x202225, 0x292C30, 0x31343A, 0x1C1E21, 0x9BB8DC, 0x7CC8B6, 0xBEA0D5)
            )
        case .integrator:
            return DiskThemeDefinition(
                light: DiskThemeVariant(
                    accent: 0x4A4A4A, accentStrong: 0x191919,
                    available: 0x686868, attention: 0x858585, neutral: 0x777777,
                    canvas: 0xF5F5F3, rail: 0xEBEBE8, panel: 0xFAFAF8,
                    layer: 0xFFFFFF, inspector: 0xF0F0ED,
                    border: 0xD8D8D4, borderStrong: 0xAFAFAD, danger: 0x5C5C5C
                ),
                dark: DiskThemeVariant(
                    accent: 0xD6D6D6, accentStrong: 0xFFFFFF,
                    available: 0xA8A8A8, attention: 0xC0C0C0, neutral: 0x909090,
                    canvas: 0x050505, rail: 0x0E0E0E, panel: 0x131313,
                    layer: 0x1B1B1B, inspector: 0x101010,
                    border: 0x282828, borderStrong: 0x505050, danger: 0xB8B8B8
                )
            )
        case .usonian:
            return DiskThemeDefinition(
                light: DiskThemeVariant(
                    accent: 0x365F82, accentStrong: 0x223F59,
                    available: 0x3B7850, attention: 0x916814, neutral: 0x68717D,
                    canvas: 0xF3F1EC, rail: 0xE8E8E4, panel: 0xF8F7F3,
                    layer: 0xFCFBF8, inspector: 0xECEBE6,
                    border: 0xD7D8D6, borderStrong: 0xA8ADB2, danger: 0xA6504B,
                    interactionAccent: 0x315A7D, interactionStrong: 0x122638,
                    controlAccent: 0xA6504B, iconAccent: 0xA6504B
                ),
                dark: DiskThemeVariant(
                    accent: 0x83A9C8, accentStrong: 0xB3CCDE,
                    available: 0x78B389, attention: 0xD0A65A, neutral: 0x969CA4,
                    canvas: 0x17191D, rail: 0x202126, panel: 0x24262B,
                    layer: 0x2D3036, inspector: 0x1C1E22,
                    border: 0x34373C, borderStrong: 0x5E636A, danger: 0xD27B75,
                    interactionAccent: 0x83A9C8, interactionStrong: 0xB3CCDE,
                    controlAccent: 0xD27B75, iconAccent: 0xD27B75
                )
            )
        case .graphite:
            return paired(
                light: seed(0xF3F5F6, 0xE8ECEE, 0xFAFBFB, 0xFFFFFF, 0xEDF0F2, 0x547A98, 0x5F8B79, 0x8A7553),
                dark: seed(0x111315, 0x16191C, 0x1A1D21, 0x23282D, 0x15181B, 0x72A7D1, 0x70B58A, 0xD5A956)
            )
        case .ash:
            return paired(
                light: seed(0xEEF0F1, 0xE5E8E9, 0xF4F5F5, 0xFFFFFF, 0xE9ECED, 0x2F7398, 0x347A50, 0x956A13),
                dark: seed(0x121517, 0x181C1F, 0x1E2326, 0x282E32, 0x171A1D, 0x75A9C7, 0x74B38A, 0xD1AA62)
            )
        case .midnight:
            return paired(
                light: seed(0xEDF3F7, 0xE2EAF0, 0xF5F8FA, 0xFFFFFF, 0xE8EFF4, 0x397FA9, 0x3F7F5B, 0x8D6819),
                dark: seed(0x090F18, 0x0D1520, 0x101A27, 0x172534, 0x0B121C, 0x5EB4E6, 0x64BD91, 0xE0AD55)
            )
        case .ocean:
            return paired(
                light: seed(0xECF4F3, 0xE1EBEA, 0xF4F8F7, 0xFFFFFF, 0xE7F0EF, 0x2C7F83, 0x367D59, 0x8E691B),
                dark: seed(0x0A191B, 0x0D2023, 0x10272A, 0x17383B, 0x091C1E, 0x49B7BB, 0x63BD8B, 0xDEB05B)
            )
        case .forest:
            return paired(
                light: seed(0xEEF2ED, 0xE4EAE2, 0xF5F7F3, 0xFFFFFF, 0xE9EEE7, 0x627B45, 0x3E7951, 0x8E681B),
                dark: seed(0x101713, 0x151E19, 0x19251E, 0x24352B, 0x141D17, 0x8CAC68, 0x76B98A, 0xD8AE5D)
            )
        case .dusk:
            return paired(
                light: seed(0xF3EFEE, 0xEAE4E5, 0xF8F5F4, 0xFFFFFF, 0xEEE8EA, 0xA4603E, 0x447957, 0x8F6819),
                dark: seed(0x16141A, 0x1B1821, 0x201D28, 0x2C2838, 0x1A1720, 0xD99A6C, 0x7CB88C, 0xD9AB5B)
            )
        case .paper:
            return paired(
                light: seed(0xF4F0E7, 0xECE6DA, 0xFAF7F0, 0xFFFFFF, 0xEEE8DC, 0x2C6F92, 0x37784A, 0x916814),
                dark: seed(0x181612, 0x201D18, 0x27231D, 0x332E26, 0x1B1915, 0x75A9C7, 0x76B28A, 0xD4AA5B)
            )
        case .iris:
            return paired(
                light: seed(0xF0EEF4, 0xE6E2EC, 0xF7F5FA, 0xFFFFFF, 0xEBE7F0, 0x6A55A8, 0x39784C, 0x906811),
                dark: seed(0x131117, 0x17151D, 0x1B1922, 0x26222F, 0x151219, 0xA794D9, 0x72B48C, 0xD3A95C)
            )
        case .porcelain:
            return paired(
                light: seed(0xF2F2F2, 0xE9E9E9, 0xF7F7F7, 0xFFFFFF, 0xEDEDED, 0x3D3D3D, 0x5F7467, 0x7D7567),
                dark: seed(0x101010, 0x171717, 0x1D1D1D, 0x272727, 0x141414, 0xC9C9C9, 0xA9B9AE, 0xC0B8A8)
            )
        case .sage:
            return paired(
                light: seed(0xEEF2EC, 0xE4EAE1, 0xF4F7F2, 0xFFFFFF, 0xE8EEE5, 0x42815A, 0x357A4E, 0x926A12),
                dark: seed(0x111713, 0x171F19, 0x1D271F, 0x27342A, 0x151C17, 0x86B995, 0x74B78A, 0xD3AB5B)
            )
        case .highContrast:
            return DiskThemeDefinition(
                light: DiskThemeVariant(
                    accent: 0x005F8F, accentStrong: 0x003D5E,
                    available: 0x176A34, attention: 0x765500, neutral: 0x505050,
                    canvas: 0xFFFFFF, rail: 0xF1F1F1, panel: 0xFFFFFF,
                    layer: 0xFFFFFF, inspector: 0xF5F5F5,
                    border: 0x777777, borderStrong: 0x111111, danger: 0x8D201B
                ),
                dark: DiskThemeVariant(
                    accent: 0x64C7FF, accentStrong: 0xA7DEFF,
                    available: 0x70E296, attention: 0xFFD25D, neutral: 0xB8B8B8,
                    canvas: 0x000000, rail: 0x080808, panel: 0x101010,
                    layer: 0x1B1B1B, inspector: 0x050505,
                    border: 0x686868, borderStrong: 0xD0D0D0, danger: 0xFF817A
                )
            )
        }
    }

    private static func seed(
        _ canvas: UInt32,
        _ rail: UInt32,
        _ panel: UInt32,
        _ layer: UInt32,
        _ inspector: UInt32,
        _ accent: UInt32,
        _ available: UInt32,
        _ attention: UInt32,
        danger: UInt32 = 0xB0524D
    ) -> Seed {
        Seed(
            canvas: canvas,
            rail: rail,
            panel: panel,
            layer: layer,
            inspector: inspector,
            accent: accent,
            available: available,
            attention: attention,
            danger: danger
        )
    }

    private static func paired(light: Seed, dark: Seed) -> DiskThemeDefinition {
        DiskThemeDefinition(
            light: variant(from: light, dark: false),
            dark: variant(from: dark, dark: true)
        )
    }

    private static func variant(from seed: Seed, dark: Bool) -> DiskThemeVariant {
        let text = dark ? UInt32(0xFFFFFF) : 0x000000
        return DiskThemeVariant(
            accent: seed.accent,
            accentStrong: mix(seed.accent, text, amount: dark ? 0.22 : 0.28),
            available: seed.available,
            attention: seed.attention,
            neutral: mix(seed.rail, text, amount: dark ? 0.55 : 0.48),
            canvas: seed.canvas,
            rail: seed.rail,
            panel: seed.panel,
            layer: seed.layer,
            inspector: seed.inspector,
            border: mix(seed.rail, text, amount: dark ? 0.13 : 0.10),
            borderStrong: mix(seed.rail, text, amount: dark ? 0.30 : 0.24),
            danger: dark ? mix(seed.danger, 0xFFFFFF, amount: 0.14) : seed.danger
        )
    }

    private static func mix(_ first: UInt32, _ second: UInt32, amount: Double) -> UInt32 {
        let clamped = min(1, max(0, amount))
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((first >> shift) & 0xFF)
            let b = Double((second >> shift) & 0xFF)
            return UInt32((a + (b - a) * clamped).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}
