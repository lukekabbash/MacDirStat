import AppKit
import Core
import Foundation

public enum TreemapColorMode: String, CaseIterable, Sendable {
    case fileCategory
    case location

    public var displayName: String {
        switch self {
        case .fileCategory: return "File type"
        case .location: return "Location"
        }
    }
}

/// Theme-owned chrome for the native storage renderers. Category hues remain
/// stable data encodings; these colors cover surfaces, boundaries, capacity,
/// and interaction so same-appearance theme changes can update immediately.
public struct TreemapRenderTheme {
    public let token: String
    public let canvas: NSColor
    public let surface: NSColor
    public let tileStroke: NSColor
    public let selectionFill: NSColor
    public let selectionStroke: NSColor
    public let hoverFill: NSColor
    public let availableFill: NSColor
    public let availableStroke: NSColor
    public let neutralFill: NSColor
    public let neutralStroke: NSColor

    public init(
        token: String,
        canvas: NSColor,
        surface: NSColor,
        tileStroke: NSColor,
        selectionFill: NSColor,
        selectionStroke: NSColor,
        hoverFill: NSColor,
        availableFill: NSColor,
        availableStroke: NSColor,
        neutralFill: NSColor,
        neutralStroke: NSColor
    ) {
        self.token = token
        self.canvas = canvas
        self.surface = surface
        self.tileStroke = tileStroke
        self.selectionFill = selectionFill
        self.selectionStroke = selectionStroke
        self.hoverFill = hoverFill
        self.availableFill = availableFill
        self.availableStroke = availableStroke
        self.neutralFill = neutralFill
        self.neutralStroke = neutralStroke
    }

    public static var system: TreemapRenderTheme {
        TreemapRenderTheme(
            token: "system",
            canvas: TreemapColorPalette.canvasBackground(),
            surface: NSColor.windowBackgroundColor,
            tileStroke: TreemapColorPalette.strokeColor(),
            selectionFill: TreemapColorPalette.selectionOverlay(),
            selectionStroke: TreemapColorPalette.selectionStroke(),
            hoverFill: TreemapColorPalette.hoverOverlay(),
            availableFill: TreemapColorPalette.availableFill(),
            availableStroke: TreemapColorPalette.availableStroke(),
            neutralFill: NSColor.tertiaryLabelColor.withAlphaComponent(0.13),
            neutralStroke: NSColor.separatorColor.withAlphaComponent(0.7)
        )
    }
}

public enum TreemapColorPalette {
    public static func color(
        for node: FileNode,
        nodeID: NodeID,
        session: ScanSession,
        mode: TreemapColorMode,
        scope: NodeID
    ) -> NSColor {
        switch mode {
        case .fileCategory:
            return fileTypeColor(for: node)
        case .location:
            let location = session.directDescendant(of: nodeID, under: scope) ?? nodeID
            return stableLocationColor(seed: session.node(id: location)?.path ?? node.path)
        }
    }

    public static func color(for category: StorageCategory) -> NSColor {
        switch category {
        case .applications: return paletteColor(at: 2)
        case .developer: return paletteColor(at: 0)
        case .video: return paletteColor(at: 7)
        case .audio: return paletteColor(at: 8)
        case .images: return paletteColor(at: 1)
        case .documents: return paletteColor(at: 4)
        case .archives: return paletteColor(at: 6)
        case .data: return paletteColor(at: 5)
        case .other: return paletteColor(at: 9)
        }
    }

    public static func color(forFileTypeKey key: String) -> NSColor {
        stablePaletteColor(seed: key)
    }

    public static func color(forLocationSeed seed: String) -> NSColor {
        stableLocationColor(seed: seed)
    }

    private static func fileTypeColor(for node: FileNode) -> NSColor {
        switch node.kind {
        case .root:
            return NSColor(calibratedWhite: 0.35, alpha: 1)
        case .directory:
            return stablePaletteColor(seed: node.path)
        case .packageLeaf:
            return color(forFileTypeKey: StorageFileType.key(for: node))
        case .file:
            return color(forFileTypeKey: StorageFileType.key(for: node))
        }
    }

    public static func strokeColor() -> NSColor {
        adaptive(light: 0x26313D, dark: 0x070A0E).withAlphaComponent(0.38)
    }

    public static func canvasBackground() -> NSColor {
        adaptive(light: 0xE8E9E7, dark: 0x111418)
    }

    public static func hoverOverlay() -> NSColor {
        NSColor(calibratedWhite: 1, alpha: 0.12)
    }

    public static func selectionOverlay() -> NSColor {
        NSColor(calibratedWhite: 1, alpha: 0.18)
    }

    public static func selectionStroke() -> NSColor {
        adaptive(light: 0xD9E7F5, dark: 0xC5DCF3).withAlphaComponent(0.98)
    }

    public static func labelColor() -> NSColor {
        NSColor.white.withAlphaComponent(0.94)
    }

    public static func secondaryLabelColor() -> NSColor {
        NSColor.white.withAlphaComponent(0.68)
    }

    public static func availableFill() -> NSColor {
        adaptive(light: 0x87B8AC, dark: 0x6BB7A5).withAlphaComponent(0.24)
    }

    public static func availableStroke() -> NSColor {
        adaptive(light: 0x4F8F82, dark: 0x8BD0C0).withAlphaComponent(0.7)
    }

    private static func stableLocationColor(seed: String) -> NSColor {
        stablePaletteColor(seed: seed)
    }

    private static let lightPalette: [UInt32] = [
        0x5D789C, // mineral blue
        0x4F8F82, // eucalyptus
        0x7F6B97, // dusty violet
        0x8A744B, // ochre
        0xA15F59, // muted coral
        0x5B858B, // oxidized teal
        0x6E805D, // sage
        0x6D7297, // soft indigo
        0x8D6E79, // clay rose
        0x6E7A82, // graphite
        0x967054, // warm umber
        0x557A86, // blue teal
    ]

    private static let darkPalette: [UInt32] = [
        0x7898BE,
        0x67AB99,
        0xA086B4,
        0xAA925F,
        0xBC7770,
        0x6C9EA2,
        0x879A72,
        0x858AB2,
        0xA98390,
        0x8B969D,
        0xAF8867,
        0x6B97A1,
    ]

    private static func stablePaletteColor(seed: String) -> NSColor {
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return paletteColor(at: Int(value % UInt64(lightPalette.count)))
    }

    private static func paletteColor(at index: Int) -> NSColor {
        let safeIndex = ((index % lightPalette.count) + lightPalette.count) % lightPalette.count
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return color(hex: match == .darkAqua ? darkPalette[safeIndex] : lightPalette[safeIndex])
        }
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return color(hex: match == .darkAqua ? dark : light)
        }
    }

    private static func color(hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
