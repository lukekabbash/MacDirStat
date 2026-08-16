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
        let url = URL(fileURLWithPath: path)
        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    @MainActor
    func moveItem(path: String, to directoryPath: String) throws {
        let source = URL(fileURLWithPath: path)
        let destinationDirectory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        guard source.deletingLastPathComponent() != destinationDirectory else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }
}
