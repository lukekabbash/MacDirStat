import AppKit
import SwiftUI

/// A component-local vertical scroller with a quiet visual thumb inside the
/// standard AppKit interaction lane. AppKit continues to own scrolling,
/// tracking, paging, keyboard navigation, accessibility, and overlay fading.
final class DiskSlimScroller: NSScroller {
    private enum Metrics {
        static let knobWidth: CGFloat = 3
        static let legacyTrackWidth: CGFloat = 1
    }

    private var themeToken = ""
    private var usesDarkAppearance = false
    private var usesHighContrast = false
    private var accessibilityObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeAccessibilityDisplayOptions()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeAccessibilityDisplayOptions()
    }

    deinit {
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    /// The drawing/event override contract required for native overlay
    /// behavior: only the part drawing hooks below are customized.
    override class var isCompatibleWithOverlayScrollers: Bool {
        self == DiskSlimScroller.self
    }

    /// Installs once into one scroll view, retaining the original frame
    /// geometry so content width and the native pointer target do not change.
    static func install(in scrollView: NSScrollView) -> DiskSlimScroller? {
        if let scroller = scrollView.verticalScroller as? DiskSlimScroller {
            return scroller
        }
        guard let existingScroller = scrollView.verticalScroller else { return nil }

        let scroller = DiskSlimScroller(frame: existingScroller.frame)
        scroller.controlSize = .mini
        scroller.scrollerStyle = existingScroller.scrollerStyle
        scroller.knobStyle = existingScroller.knobStyle
        scroller.isEnabled = existingScroller.isEnabled
        scroller.doubleValue = existingScroller.doubleValue
        scroller.knobProportion = existingScroller.knobProportion

        scrollView.verticalScroller = scroller
        scrollView.tile()
        return scroller
    }

    func applyChrome(
        themeToken: String,
        colorScheme: ColorScheme,
        usesHighContrast: Bool
    ) {
        let usesDarkAppearance = colorScheme == .dark
        guard self.themeToken != themeToken
            || self.usesDarkAppearance != usesDarkAppearance
            || self.usesHighContrast != usesHighContrast
        else { return }

        self.themeToken = themeToken
        self.usesDarkAppearance = usesDarkAppearance
        self.usesHighContrast = usesHighContrast
        needsDisplay = true
    }

    override func drawKnob() {
        let knobRect = slimRect(in: rect(for: .knob), width: Metrics.knobWidth)
        guard !knobRect.isEmpty else { return }

        knobColor.setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobRect.width / 2,
            yRadius: knobRect.width / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Overlay scrollers own their own fade and intentionally have no
        // persistent track. A one-point legacy track preserves the visible
        // range cue when macOS is configured to always show scroll bars.
        guard scrollerStyle == .legacy else { return }

        let trackRect = slimRect(in: slotRect, width: Metrics.legacyTrackWidth)
        guard !trackRect.isEmpty else { return }

        trackColor(isHighlighted: flag).setFill()
        NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.width / 2,
            yRadius: trackRect.width / 2
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func observeAccessibilityDisplayOptions() {
        usesHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.usesHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            self.needsDisplay = true
        }
    }

    private var knobColor: NSColor {
        if usesHighContrast {
            return NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.96 : 0.82)
        }

        let color = isHighlighted
            ? NSColor(DiskVisualStyle.controlAccent)
            : NSColor(DiskVisualStyle.strongHairline)
        let opacity: CGFloat = isHighlighted ? 0.86 : (scrollerStyle == .overlay ? 0.58 : 0.46)
        return resolved(color).withAlphaComponent(opacity)
    }

    private func trackColor(isHighlighted: Bool) -> NSColor {
        if usesHighContrast {
            return NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.54 : 0.34)
        }

        let opacity: CGFloat = isHighlighted ? 0.5 : 0.22
        return resolved(NSColor(DiskVisualStyle.hairline)).withAlphaComponent(opacity)
    }

    private func resolved(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.deviceRGB)
            ?? (usesDarkAppearance ? .white : .black)
    }

    private func slimRect(in rect: NSRect, width: CGFloat) -> NSRect {
        let resolvedWidth = min(width, rect.width)
        return NSRect(
            x: rect.midX - resolvedWidth / 2,
            y: rect.minY,
            width: resolvedWidth,
            height: rect.height
        )
    }
}
