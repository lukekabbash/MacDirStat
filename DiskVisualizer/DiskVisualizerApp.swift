import SwiftUI

@main
struct DiskVisualizerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
