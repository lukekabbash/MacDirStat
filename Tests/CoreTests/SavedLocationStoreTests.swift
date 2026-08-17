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

    func testDuplicateMigrationKeepsBestAuthorityAndMergedMetadata() {
        let volume = "startup-volume"
        let oldRoot = ScanRoot(
            displayName: "Documents",
            volumeIdentifier: volume,
            accessMode: .readOnly,
            bookmarkData: Data([1])
        )
        let currentRoot = ScanRoot(
            displayName: "Documents",
            volumeIdentifier: volume,
            accessMode: .readOnly,
            bookmarkData: Data([2])
        )
        let selectedAt = Date()
        let oldScan = Date(timeIntervalSinceReferenceDate: 100)
        let currentScan = Date(timeIntervalSinceReferenceDate: 200)
        let old = SavedLocation(
            scanRoot: oldRoot,
            isPinned: true,
            sortOrder: 0,
            availability: .needsAccess,
            lastScanSummary: ScanSummary(
                scannedAt: oldScan,
                allocatedSize: 1,
                logicalSize: 1,
                nodeCount: 1,
                isComplete: true,
                warningCount: 0
            )
        )
        let current = SavedLocation(
            scanRoot: currentRoot,
            canonicalPath: "/Users/luke/Documents",
            sortOrder: 4,
            availability: .ready,
            lastScanSummary: ScanSummary(
                scannedAt: currentScan,
                allocatedSize: 2,
                logicalSize: 2,
                nodeCount: 2,
                isComplete: true,
                warningCount: 0
            ),
            lastSelectedAt: selectedAt
        )

        let collapsed = SavedLocationDeduplicator.collapse([old, current])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed[0].id, current.id)
        XCTAssertEqual(collapsed[0].canonicalPath, "/Users/luke/Documents")
        XCTAssertTrue(collapsed[0].isPinned)
        XCTAssertEqual(collapsed[0].lastScanSummary?.scannedAt, currentScan)
        XCTAssertEqual(collapsed[0].lastSelectedAt, selectedAt)
        XCTAssertEqual(collapsed[0].sortOrder, 0)
    }

    func testDuplicateMigrationPreservesDistinctKnownPathsWithTheSameName() {
        let first = SavedLocation(
            scanRoot: ScanRoot(
                displayName: "Documents",
                volumeIdentifier: "volume",
                accessMode: .readOnly,
                bookmarkData: Data([1])
            ),
            canonicalPath: "/Users/one/Documents",
            sortOrder: 0
        )
        let second = SavedLocation(
            scanRoot: ScanRoot(
                displayName: "Documents",
                volumeIdentifier: "volume",
                accessMode: .readOnly,
                bookmarkData: Data([2])
            ),
            canonicalPath: "/Users/two/Documents",
            sortOrder: 1
        )

        let collapsed = SavedLocationDeduplicator.collapse([first, second])

        XCTAssertEqual(collapsed.map(\.id), [first.id, second.id])
    }

    func testDuplicateMigrationTreatsStartupVolumeAliasesAsOneSource() {
        let slash = SavedLocation(
            scanRoot: ScanRoot(
                displayName: "/",
                volumeIdentifier: "volume",
                accessMode: .readOnly,
                bookmarkData: Data([1])
            ),
            sortOrder: 0,
            availability: .needsAccess
        )
        let named = SavedLocation(
            scanRoot: ScanRoot(
                displayName: "Macintosh HD",
                volumeIdentifier: "volume",
                accessMode: .readOnly,
                bookmarkData: Data([2])
            ),
            sortOrder: 1,
            availability: .needsAccess,
            lastSelectedAt: Date()
        )

        let collapsed = SavedLocationDeduplicator.collapse([slash, named])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed[0].scanRoot.displayName, "Macintosh HD")
    }
}
