import Core
import XCTest

final class ScanNodeArenaTests: XCTestCase {
    func testAggregateTotalsRollsUpToRoot() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", path: "/Root")
        let f1 = arena.addChild(
            parent: .root,
            kind: .file,
            name: "a",
            path: "/Root/a",
            logicalSize: 100,
            allocatedSize: 100,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        XCTAssertEqual(f1.rawValue, 1)
        let d = arena.addChild(
            parent: .root,
            kind: .directory,
            name: "d",
            path: "/Root/d",
            logicalSize: 0,
            allocatedSize: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        _ = arena.addChild(
            parent: d,
            kind: .file,
            name: "b",
            path: "/Root/d/b",
            logicalSize: 50,
            allocatedSize: 50,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        arena.aggregateTotals()
        let snap = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: true
        )
        XCTAssertEqual(snap.rootTotalLogical, 150)
        XCTAssertEqual(snap.rootTotalAllocated, 150)
    }
}
