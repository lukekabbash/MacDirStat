import AppKit
import Foundation

struct CleanupService {
    @MainActor
    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    func openFile(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @MainActor
    func moveToTrash(path: String) throws {
        var url = URL(fileURLWithPath: path)
        try FileManager.default.trashItem(at: &url, resultingItemURL: nil)
    }
}
