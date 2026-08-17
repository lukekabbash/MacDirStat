import Foundation

private struct SavedLocationEnvelope: Codable {
    let version: Int
    var locations: [SavedLocation]
}

/// Versioned persistence with a conservative import from the legacy root list.
public actor SavedLocationStore {
    public static let `default` = SavedLocationStore()

    private let fileURL: URL
    private let legacyFileURL: URL
    private var locations: [SavedLocation] = []

    public init(
        appSupportSubpath: String = "DiskVisualizer/saved-locations-v1.json",
        legacySubpath: String = "DiskVisualizer/bookmarks.json"
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        fileURL = base.appendingPathComponent(appSupportSubpath, isDirectory: false)
        legacyFileURL = base.appendingPathComponent(legacySubpath, isDirectory: false)
    }

    public init(fileURL: URL, legacyFileURL: URL) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    @discardableResult
    public func load() async throws -> [SavedLocation] {
        if FileManager.default.fileExists(atPath: fileURL.path),
           let envelope = try? JSONDecoder().decode(
               SavedLocationEnvelope.self,
               from: Data(contentsOf: fileURL)
           ),
           envelope.version == 1 {
            locations = envelope.locations
            return locations
        }

        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else {
            locations = []
            return []
        }

        let legacyData = try Data(contentsOf: legacyFileURL)
        let roots = try JSONDecoder().decode([ScanRoot].self, from: legacyData)
        locations = roots.enumerated().map { index, root in
            SavedLocation(scanRoot: root, sortOrder: index)
        }
        try save(locations)
        return locations
    }

    public func allLocations() -> [SavedLocation] {
        locations
    }

    public func save(_ newLocations: [SavedLocation]) throws {
        locations = newLocations
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(SavedLocationEnvelope(version: 1, locations: locations))
        try data.write(to: fileURL, options: .atomic)
    }
}
