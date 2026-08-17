import Core
import XCTest

final class WorkspaceProjectionTests: XCTestCase {
    func testAppsProjectionIncludesOnlyApplicationPackages() {
        let session = fixtureSession()
        let items = AppsProjectionBuilder.make(locationID: UUID(), generation: UUID(), scannedAt: Date(), session: session)
        XCTAssertEqual(items.map(\.fallbackName), ["Studio.app"])
        XCTAssertEqual(items.first?.allocatedSize, 500)
    }

    func testSearchRankingIsDeterministicAndSizeOrdered() {
        let rows = SnapshotSearchRanking.make(session: fixtureSession(), query: "a", metric: .allocated, limit: 10)
        XCTAssertEqual(rows.map(\.size), rows.map(\.size).sorted(by: >))
    }

    func testMutationEligibilityRequiresSourceSnapshotAndPermission() {
        let node = fixtureSession().nodes[1]
        XCTAssertFalse(ActionEligibility.evaluate(.moveToTrash, node: node, sourceAvailable: true, snapshotCurrent: true, deletionAllowed: false).isEnabled)
        XCTAssertFalse(ActionEligibility.evaluate(.moveToFolder, node: node, sourceAvailable: true, snapshotCurrent: true, deletionAllowed: true, sameVolumeDestination: false).isEnabled)
        XCTAssertTrue(ActionEligibility.evaluate(.moveToTrash, node: node, sourceAvailable: true, snapshotCurrent: true, deletionAllowed: true).isEnabled)
    }

    func testReviewRevalidationBlocksChangedAndMissingItems() {
        let session = fixtureSession()
        let generation = UUID()
        let item = ReviewItem(
            sourceLocationID: UUID(), snapshotGeneration: generation, snapshotDate: Date(),
            originalNodeID: NodeID(rawValue: 1), node: session.nodes[1], reason: .addedFromScan
        )
        XCTAssertEqual(ReviewSnapshotValidator.state(for: item, currentSession: session, currentGeneration: generation, sourceAvailable: true, deletionAllowed: true), .ready)
        XCTAssertEqual(ReviewSnapshotValidator.state(for: item, currentSession: nil, currentGeneration: nil, sourceAvailable: true, deletionAllowed: true), .needsRecheck)
        XCTAssertEqual(ReviewSnapshotValidator.state(for: item, currentSession: session, currentGeneration: generation, sourceAvailable: false, deletionAllowed: true), .sourceUnavailable)
    }

    private func fixtureSession() -> ScanSession {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/fixture")
        _ = arena.addChild(parent: .root, kind: .file, name: "archive.zip", path: "/fixture/archive.zip", logicalSize: 600, allocatedSize: 600, isPackage: false, mayShareContent: false, isSparse: false, isPurgeable: false, writeAccess: true)
        _ = arena.addChild(parent: .root, kind: .packageLeaf, name: "Studio.app", path: "/fixture/Studio.app", logicalSize: 500, allocatedSize: 500, isPackage: true, mayShareContent: false, isSparse: false, isPurgeable: false, writeAccess: true)
        _ = arena.addChild(parent: .root, kind: .packageLeaf, name: "Archive.pkg", path: "/fixture/Archive.pkg", logicalSize: 400, allocatedSize: 400, isPackage: true, mayShareContent: false, isSparse: false, isPurgeable: false, writeAccess: true)
        arena.aggregateTotals()
        return arena.makeSnapshot(rootBookmarkID: nil, rootDisplayName: "Root", options: .default, warnings: [], isComplete: true)
    }
}
