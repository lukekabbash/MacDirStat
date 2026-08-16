import SwiftUI

@main
struct DiskVisualizerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(model.appearanceMode.colorScheme)
        }
        .defaultSize(width: 1_280, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.openSettings(.appearance)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
