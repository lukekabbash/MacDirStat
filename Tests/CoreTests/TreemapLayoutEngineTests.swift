import Core
import XCTest

final class TreemapLayoutEngineTests: XCTestCase {
    func testLayoutFillsUnitSquare() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "R", rootPath: "/R")
        _ = arena.addChild(
            parent: .root,
            kind: .file,
            name: "a",
            path: "/R/a",
            logicalSize: 10,
            allocatedSize: 10,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        _ = arena.addChild(
            parent: .root,
            kind: .file,
            name: "b",
            path: "/R/b",
            logicalSize: 30,
            allocatedSize: 30,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "R",
            options: .default,
            warnings: [],
            isComplete: true
        )
        let tiles = TreemapLayoutEngine.layout(session: session, parent: .root, metric: .allocated)
        XCTAssertEqual(tiles.count, 2)
        let area = tiles.reduce(0.0) { $0 + $1.rect.width * $1.rect.height }
        XCTAssertEqual(area, 1.0, accuracy: 0.0001)
    }
}
