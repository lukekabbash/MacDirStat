import AppKit
import Core
import Foundation

public enum TreemapColorPalette {
    public static func color(for node: FileNode) -> NSColor {
        switch node.kind {
        case .root:
            return NSColor(calibratedWhite: 0.35, alpha: 1)
        case .directory:
            return NSColor(calibratedHue: 0.58, saturation: 0.35, brightness: 0.55, alpha: 1)
        case .packageLeaf:
            return NSColor(calibratedHue: 0.12, saturation: 0.45, brightness: 0.72, alpha: 1)
        case .file:
            return fileAccent(for: node.name)
        }
    }

    public static func strokeColor() -> NSColor {
        NSColor(calibratedWhite: 0, alpha: 0.25)
    }

    public static func highlightOverlay() -> NSColor {
        NSColor(calibratedWhite: 1, alpha: 0.12)
    }

    private static func fileAccent(for name: String) -> NSColor {
        let ext = (name as NSString).pathExtension.lowercased()
        let hue: CGFloat
        switch ext {
        case "mp4", "mov", "mkv", "m4v", "avi":
            hue = 0.78
        case "mp3", "wav", "aac", "flac", "m4a":
            hue = 0.55
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            hue = 0.45
        case "zip", "gz", "tar", "7z", "rar":
            hue = 0.07
        case "pdf":
            hue = 0.02
        case "swift", "c", "h", "m", "mm", "rs", "go", "py", "js", "ts":
            hue = 0.28
        default:
            hue = CGFloat((name.hashValue & 0xFFFF).hashValue % 1000) / 1000 * 0.4 + 0.15
        }
        return NSColor(calibratedHue: hue, saturation: 0.42, brightness: 0.68, alpha: 1)
    }
}
