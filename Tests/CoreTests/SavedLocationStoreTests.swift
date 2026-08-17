import Core
import Foundation
import XCTest

final class SavedLocationStoreTests: XCTestCase {
    func testLegacyRootsImportOnceAndPreserveIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("saved.json")
        let legacy = directory.appendingPathComponent("legacy.json")
        let root = ScanRoot(displayName: "Projects", volumeIdentifier: "volume", accessMode: .readWrite, bookmarkData: Data([1, 2, 3]))
        try JSONEncoder().encode([root]).write(to: legacy)

        let store = SavedLocationStore(fileURL: current, legacyFileURL: legacy)
        let imported = try await store.load()
        XCTAssertEqual(imported.map(\.id), [root.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "Migration must not destroy the legacy source")

        var renamed = imported
        renamed[0].customName = "Code"
        try await store.save(renamed)
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded[0].displayName, "Code")
    }

    func testSummaryPersistenceContainsNoFileTree() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("saved.json")
        let store = SavedLocationStore(fileURL: file, legacyFileURL: directory.appendingPathComponent("none"))
        let root = ScanRoot(displayName: "Home", volumeIdentifier: nil, accessMode: .readOnly, bookmarkData: Data([9]))
        let location = SavedLocation(
            scanRoot: root,
            lastScanSummary: ScanSummary(scannedAt: Date(), allocatedSize: 4_096, logicalSize: 8_192, nodeCount: 17, isComplete: true, warningCount: 0)
        )
        try await store.save([location])
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("allocatedSize"))
        XCTAssertFalse(text.contains("/Users/"), "Saved summaries must not persist a browsable file tree")
    }
}
