import Core
import XCTest

final class StorageHierarchyProjectionTests: XCTestCase {
    func testProjectionKeepsParentChildAnglesAndSizeOrder() {
        let fixture = hierarchyFixture()
        let projection = StorageHierarchyBuilder.make(
            in: fixture.session,
            metric: .allocated,
            maximumDepth: 3,
            minimumVisibleFraction: 0
        )

        XCTAssertEqual(projection.rootID, .root)
        XCTAssertEqual(projection.rootSize, 100)
        XCTAssertEqual(projection.segments.map(\.nodeID), [fixture.documents, fixture.media, fixture.report, fixture.archive, fixture.movie])

        let documents = tryUnwrap(projection.segments.first { $0.nodeID == fixture.documents })
        let report = tryUnwrap(projection.segments.first { $0.nodeID == fixture.report })
        let archive = tryUnwrap(projection.segments.first { $0.nodeID == fixture.archive })
        XCTAssertEqual(documents.startFraction, 0, accuracy: 0.000_001)
        XCTAssertEqual(documents.endFraction, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(report.startFraction, 0, accuracy: 0.000_001)
        XCTAssertEqual(report.endFraction, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(archive.startFraction, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(archive.endFraction, 0.6, accuracy: 0.000_001)
    }

    func testProjectionCanRebaseForDeeperInspection() {
        let fixture = hierarchyFixture()
        let projection = StorageHierarchyBuilder.make(
            in: fixture.session,
            root: fixture.documents,
            metric: .allocated,
            maximumDepth: 2,
            minimumVisibleFraction: 0
        )

        XCTAssertEqual(projection.rootID, fixture.documents)
        XCTAssertEqual(projection.rootSize, 60)
        XCTAssertEqual(projection.segments.map(\.nodeID), [fixture.report, fixture.archive])
        XCTAssertEqual(tryUnwrap(projection.segments.last).endFraction, 1, accuracy: 0.000_001)
    }

    func testProjectionHonorsDepthAndSegmentBudget() {
        let fixture = hierarchyFixture()
        let shallow = StorageHierarchyBuilder.make(
            in: fixture.session,
            metric: .allocated,
            maximumDepth: 1,
            minimumVisibleFraction: 0
        )
        let bounded = StorageHierarchyBuilder.make(
            in: fixture.session,
            metric: .allocated,
            maximumDepth: 4,
            segmentLimit: 2,
            minimumVisibleFraction: 0
        )

        XCTAssertEqual(shallow.segments.map(\.nodeID), [fixture.documents, fixture.media])
        XCTAssertTrue(shallow.hasOmittedSegments)
        XCTAssertLessThanOrEqual(bounded.segments.count, 2)
    }

    func testSegmentBudgetKeepsLargestDirectChildren() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
        let small = addFile(named: "small", size: 10, to: &arena)
        let large = addFile(named: "large", size: 30, to: &arena)
        let medium = addFile(named: "medium", size: 20, to: &arena)
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: true
        )

        let projection = StorageHierarchyBuilder.make(
            in: session,
            metric: .allocated,
            maximumDepth: 1,
            segmentLimit: 2,
            minimumVisibleFraction: 0
        )

        XCTAssertEqual(projection.directChildren, [large, medium])
        XCTAssertEqual(projection.segments.map(\.nodeID), [large, medium])
        XCTAssertFalse(projection.directChildren.contains(small))
        XCTAssertTrue(projection.hasOmittedSegments)
    }

    private func addFile(named name: String, size: UInt64, to arena: inout ScanNodeArena) -> NodeID {
        arena.addChild(
            parent: .root,
            kind: .file,
            name: name,
            path: "/Root/\(name)",
            logicalSize: size,
            allocatedSize: size,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
    }

    private func hierarchyFixture() -> (
        session: ScanSession,
        documents: NodeID,
        media: NodeID,
        report: NodeID,
        archive: NodeID,
        movie: NodeID
    ) {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
        let documents = arena.addChild(
            parent: .root, kind: .directory, name: "Documents", path: "/Root/Documents",
            logicalSize: 0, allocatedSize: 0, isPackage: false, mayShareContent: false,
            isSparse: false, isPurgeable: false, writeAccess: true
        )
        let media = arena.addChild(
            parent: .root, kind: .directory, name: "Media", path: "/Root/Media",
            logicalSize: 0, allocatedSize: 0, isPackage: false, mayShareContent: false,
            isSparse: false, isPurgeable: false, writeAccess: true
        )
        let report = arena.addChild(
            parent: documents, kind: .file, name: "report.pdf", path: "/Root/Documents/report.pdf",
            logicalSize: 40, allocatedSize: 40, isPackage: false, mayShareContent: false,
            isSparse: false, isPurgeable: false, writeAccess: true
        )
        let archive = arena.addChild(
            parent: documents, kind: .file, name: "archive.zip", path: "/Root/Documents/archive.zip",
            logicalSize: 20, allocatedSize: 20, isPackage: false, mayShareContent: false,
            isSparse: false, isPurgeable: false, writeAccess: true
        )
        let movie = arena.addChild(
            parent: media, kind: .file, name: "movie.mov", path: "/Root/Media/movie.mov",
            logicalSize: 40, allocatedSize: 40, isPackage: false, mayShareContent: false,
            isSparse: false, isPurgeable: false, writeAccess: true
        )
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: true
        )
        return (session, documents, media, report, archive, movie)
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected a value", file: file, line: line)
            fatalError("Expected a value")
        }
        return value
    }
}
