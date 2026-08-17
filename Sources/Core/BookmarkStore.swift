import Foundation

/// Persists security-scoped roots and recent scan targets in the app container.
public actor BookmarkStore {
    public static let `default` = BookmarkStore()

    private let fileURL: URL
    private var roots: [ScanRoot] = []

    public init(appSupportSubpath: String = "DiskVisualizer/bookmarks.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.fileURL = base.appendingPathComponent(appSupportSubpath, isDirectory: false)
    }

    public func load() async throws {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            roots = []
            return
        }
        let data = try Data(contentsOf: url)
        roots = try JSONDecoder().decode([ScanRoot].self, from: data)
    }

    public func save() async throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(roots)
        try data.write(to: fileURL, options: .atomic)
    }

    public func allRoots() -> [ScanRoot] {
        roots
    }

    public func upsert(_ root: ScanRoot) async throws {
        if let i = roots.firstIndex(where: { $0.id == root.id }) {
            roots[i] = root
        } else {
            roots.append(root)
        }
        try await save()
    }

    public func remove(id: UUID) async throws {
        roots.removeAll { $0.id == id }
        try await save()
    }
}
