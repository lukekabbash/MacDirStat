import AppKit
import SwiftUI

/// Bridges the semantic theme into the native titlebar and native menus. A
/// single window-level authority prevents dark presets from falling back to a
/// generic black toolbar that is disconnected from the workspace palette.
struct ThemedWindowChrome: NSViewRepresentable {
    let theme: DiskThemeID
    let isDark: Bool

    func makeNSView(context: Context) -> ThemedWindowChromeProbe {
        let view = ThemedWindowChromeProbe()
        view.configuration = configuration
        return view
    }

    func updateNSView(_ nsView: ThemedWindowChromeProbe, context: Context) {
        nsView.configuration = configuration
    }

    private var configuration: ThemedWindowChromeConfiguration {
        ThemedWindowChromeConfiguration(
            theme: theme,
            isDark: isDark
        )
    }
}

private struct ThemedWindowChromeConfiguration: Equatable {
    let theme: DiskThemeID
    let isDark: Bool
}

final class ThemedWindowChromeProbe: NSView {
    fileprivate var configuration: ThemedWindowChromeConfiguration? {
        didSet { scheduleConfiguration() }
    }

    private var appliedConfiguration: ThemedWindowChromeConfiguration?
    private var configurationGeneration = UUID()
    private var hasFitInitialWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    private func scheduleConfiguration() {
        guard configuration != appliedConfiguration else { return }
        let generation = UUID()
        configurationGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.configurationGeneration == generation,
                  let configuration = self.configuration,
                  let window = self.window
            else { return }

            window.backgroundColor = DiskVisualStyle.windowChromeColor(
                for: configuration.theme,
                dark: configuration.isDark
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar?.showsBaselineSeparator = false
            self.fitInitialWindowIfNeeded(window)
            self.appliedConfiguration = configuration

            // Applying native chrome while SwiftUI is constructing the first
            // frame can leave one stale compositor strip until another state
            // change. A single post-layout invalidation keeps the initial frame
            // and subsequent live theme changes visually atomic.
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            window.viewsNeedDisplay = true
            window.displayIfNeeded()
        }
    }

    /// Restored window frames may have been saved on a taller display or by
    /// an earlier build with a larger default. Fit once at launch so the
    /// complete chrome and fixed sidebar footer remain visible without
    /// interfering with later user-driven window placement.
    private func fitInitialWindowIfNeeded(_ window: NSWindow) {
        guard !hasFitInitialWindow,
              let screen = window.screen ?? NSScreen.main
        else { return }

        hasFitInitialWindow = true
        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var fittedFrame = window.frame
        fittedFrame.size.width = min(fittedFrame.width, visibleFrame.width)
        fittedFrame.size.height = min(fittedFrame.height, visibleFrame.height)
        fittedFrame.origin.x = min(
            max(fittedFrame.minX, visibleFrame.minX),
            visibleFrame.maxX - fittedFrame.width
        )
        fittedFrame.origin.y = min(
            max(fittedFrame.minY, visibleFrame.minY),
            visibleFrame.maxY - fittedFrame.height
        )

        guard fittedFrame != window.frame else { return }
        window.setFrame(fittedFrame, display: true, animate: false)
    }
}
