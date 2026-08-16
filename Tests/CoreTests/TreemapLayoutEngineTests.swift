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

    func testLeafLayoutResolvesLargeDirectoriesIntoFiles() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "R", rootPath: "/R")
        let directory = arena.addChild(
            parent: .root,
            kind: .directory,
            name: "Library",
            path: "/R/Library",
            logicalSize: 0,
            allocatedSize: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: false
        )
        let firstFile = arena.addChild(
            parent: directory,
            kind: .file,
            name: "cache.db",
            path: "/R/Library/cache.db",
            logicalSize: 70,
            allocatedSize: 70,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: false
        )
        let secondFile = arena.addChild(
            parent: directory,
            kind: .file,
            name: "model.bin",
            path: "/R/Library/model.bin",
            logicalSize: 30,
            allocatedSize: 30,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: false
        )
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "R",
            options: .default,
            warnings: [],
            isComplete: true
        )

        let tiles = TreemapLayoutEngine.leafLayout(
            session: session,
            parent: .root,
            metric: .allocated,
            viewportWidth: 1_000,
            viewportHeight: 700
        )

        XCTAssertEqual(Set(tiles.filter { !$0.isAggregate }.map(\.nodeID)), Set([firstFile, secondFile]))
        XCTAssertFalse(tiles.contains { $0.nodeID == directory && !$0.isAggregate })
    }

    func testCapacityPartitionPreservesProportionalArea() {
        let values = [60.0, 25.0, 15.0]
        let partitions = TreemapLayoutEngine.weightedRects(
            values: values,
            rect: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        )
        XCTAssertEqual(partitions.count, 3)
        for partition in partitions {
            let area = partition.rect.width * partition.rect.height
            XCTAssertEqual(area, values[partition.index] / 100, accuracy: 0.0001)
        }
    }
}
