import Core
import XCTest

final class ScanNodeArenaTests: XCTestCase {
    func testAggregateTotalsRollsUpToRoot() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
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

    func testAggregateTotalsIsStableAcrossProgressSnapshots() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
        let directory = arena.addChild(
            parent: .root,
            kind: .directory,
            name: "nested",
            path: "/Root/nested",
            logicalSize: 0,
            allocatedSize: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: false
        )
        _ = arena.addChild(
            parent: directory,
            kind: .file,
            name: "payload",
            path: "/Root/nested/payload",
            logicalSize: 256,
            allocatedSize: 512,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: false
        )

        arena.aggregateTotals()
        arena.aggregateTotals()
        let snapshot = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: false
        )

        XCTAssertEqual(snapshot.rootTotalLogical, 256)
        XCTAssertEqual(snapshot.rootTotalAllocated, 512)
    }

    func testStorageBreakdownCountsLeavesOnceAndKeepsLargestItems() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
        let downloads = arena.addChild(
            parent: .root,
            kind: .directory,
            name: "Downloads",
            path: "/Root/Downloads",
            logicalSize: 0,
            allocatedSize: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        let film = arena.addChild(
            parent: downloads,
            kind: .file,
            name: "film.mp4",
            path: "/Root/Downloads/film.mp4",
            logicalSize: 100,
            allocatedSize: 100,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        let source = arena.addChild(
            parent: downloads,
            kind: .file,
            name: "scene.swift",
            path: "/Root/Downloads/scene.swift",
            logicalSize: 20,
            allocatedSize: 20,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        let app = arena.addChild(
            parent: .root,
            kind: .packageLeaf,
            name: "Viewer.app",
            path: "/Root/Viewer.app",
            logicalSize: 80,
            allocatedSize: 80,
            isPackage: true,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            writeAccess: true
        )
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: true
        )

        XCTAssertEqual(session.children(of: .root), [downloads, app])
        XCTAssertEqual(session.children(of: downloads), [film, source])

        let byFileType = StorageBreakdownBuilder.items(
            in: session,
            metric: .allocated,
            grouping: .fileType
        )
        XCTAssertEqual(byFileType.reduce(UInt64(0)) { $0 + $1.size }, 200)
        XCTAssertEqual(byFileType.first { $0.title == ".mp4" }?.size, 100)
        XCTAssertEqual(byFileType.first { $0.title == ".app" }?.size, 80)
        XCTAssertEqual(byFileType.first { $0.title == ".swift" }?.size, 20)
        XCTAssertEqual(byFileType.first { $0.title == ".mp4" }?.itemCount, 1)

        let byLocation = StorageBreakdownBuilder.items(
            in: session,
            metric: .allocated,
            grouping: .location
        )
        XCTAssertEqual(byLocation.reduce(UInt64(0)) { $0 + $1.size }, 200)
        XCTAssertEqual(byLocation.first { $0.title == "Downloads" }?.size, 120)
        XCTAssertEqual(byLocation.first { $0.title == "Viewer.app" }?.size, 80)
        XCTAssertEqual(
            StorageBreakdownBuilder.largestLeafNodeIDs(in: session, metric: .allocated, limit: 3),
            [film, app, source]
        )
        XCTAssertEqual(
            StorageBreakdownBuilder.largestLeafNodeIDs(
                in: session,
                metric: .allocated,
                grouping: .location,
                memberKeys: byLocation.first { $0.title == "Downloads" }?.memberKeys ?? [],
                limit: 3
            ),
            [film, source]
        )
    }

    func testStorageBreakdownRemainderNeverCollidesWithOtherCategory() {
        var arena = ScanNodeArena()
        arena.reset(rootName: "Root", rootPath: "/Root")
        let samples: [(String, UInt64)] = [
            ("payload", 500),
            ("photo.jpg", 400),
            ("source.swift", 300),
            ("archive.zip", 200),
            ("film.mp4", 100),
        ]
        for (name, size) in samples {
            _ = arena.addChild(
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
                writeAccess: false
            )
        }
        arena.aggregateTotals()
        let session = arena.makeSnapshot(
            rootBookmarkID: nil,
            rootDisplayName: "Root",
            options: .default,
            warnings: [],
            isComplete: true
        )

        let groups = StorageBreakdownBuilder.items(
            in: session,
            metric: .allocated,
            grouping: .fileType,
            limit: 3
        )

        XCTAssertEqual(Set(groups.map(\.id)).count, groups.count)
        XCTAssertEqual(groups.last?.id, "remainder")
        XCTAssertEqual(groups.last?.title, "Remaining")
        XCTAssertEqual(groups.reduce(UInt64(0)) { $0 + $1.size }, 1_500)
    }

    func testFileTypeClassificationRecognizesBuildAndCompressedArtifacts() {
        let buildArtifact = FileNode(
            parentID: .root,
            kind: .file,
            name: "library.rlib",
            path: "/Project/target/debug/deps/library.rlib",
            logicalSize: 10,
            allocatedSize: 10,
            childCount: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            allowedActions: []
        )
        let compressedProof = FileNode(
            parentID: .root,
            kind: .file,
            name: "proof.lrat.zst",
            path: "/Research/proof.lrat.zst",
            logicalSize: 10,
            allocatedSize: 10,
            childCount: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            allowedActions: []
        )

        XCTAssertEqual(StorageCategory.classify(buildArtifact), .developer)
        XCTAssertEqual(StorageCategory.classify(compressedProof), .archives)
    }
}
