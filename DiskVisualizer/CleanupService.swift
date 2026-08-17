import AppKit
import Core
import Foundation

struct CleanupService {
    enum VolumeRelationship {
        case same
        case different
        case unknown
    }

    func volumeRelationship(sourcePath: String, destinationPath: String) -> VolumeRelationship {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let sourceID = try? URL(fileURLWithPath: sourcePath).resourceValues(forKeys: keys).volumeIdentifier,
              let destinationID = try? URL(fileURLWithPath: destinationPath).resourceValues(forKeys: keys).volumeIdentifier
        else { return .unknown }
        return String(describing: sourceID) == String(describing: destinationID) ? .same : .different
    }

    /// Rechecks the path and cheap identity facts immediately before a change.
    /// Folder rollups are intentionally not recomputed here; doing so would be
    /// an implicit scan. Files receive an exact logical-size check.
    func matchesSnapshot(path: String, node: FileNode) -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .fileSizeKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { return false }
        switch node.kind {
        case .root:
            return false
        case .file:
            guard values.isRegularFile == true else { return false }
            return UInt64(max(0, values.fileSize ?? 0)) == node.logicalSize
        case .directory:
            return values.isDirectory == true && values.isPackage != true
        case .packageLeaf:
            return values.isDirectory == true && values.isPackage == true
        }
    }

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
