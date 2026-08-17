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
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
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
}
