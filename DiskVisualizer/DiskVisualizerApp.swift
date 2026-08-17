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
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Find in Snapshot") { model.requestSearchFocus() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Quick Look") { model.quickLookSelected() }
                    .keyboardShortcut(" ", modifiers: [])
                Divider()
                Button("Add to Review") { model.addSelectedNodeToReview() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(
                        model.appDestination != .scan
                            || model.selectedNodeID == nil
                            || model.presentedSnapshotActionsAreDisabled
                    )
            }
        }
    }
}
