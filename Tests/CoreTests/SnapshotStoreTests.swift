import Core
import Foundation
import XCTest

final class SnapshotStoreTests: XCTestCase {
    func testRoundTripPreservesInteractiveScanAndStripsMutationCapabilities() async throws {
        try await withTemporaryStore { store, _ in
            let locationID = UUID()
            let snapshot = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1_000))

            let descriptor = try await store.save(snapshot)
            let storedSnapshot = try await store.load(snapshotID: descriptor.id, locationID: locationID)
            let loaded = try XCTUnwrap(storedSnapshot)

            XCTAssertEqual(descriptor.locationID, locationID)
            XCTAssertEqual(descriptor.fidelity, .interactiveScanSession)
            XCTAssertGreaterThan(descriptor.storedByteCount, 20)
            XCTAssertEqual(loaded.id, snapshot.id)
            XCTAssertEqual(loaded.session.rootTotalAllocated, snapshot.session.rootTotalAllocated)
            XCTAssertEqual(loaded.volumeSpace, snapshot.volumeSpace)
            XCTAssertFalse(loaded.session.nodes[1].allowedActions.contains(.moveToTrash))
            XCTAssertFalse(loaded.session.nodes[1].allowedActions.contains(.moveToLocation))
            XCTAssertTrue(loaded.session.nodes[1].allowedActions.contains(.revealInFinder))
        }
    }

    func testPerLocationCountPrunesOldestArchive() async throws {
        let limits = SnapshotStoreLimits(
            maximumSnapshotsPerLocation: 2,
            maximumBytesPerLocation: 32 * 1_024 * 1_024,
            maximumTotalBytes: 64 * 1_024 * 1_024,
            maximumUncompressedArchiveBytes: 32 * 1_024 * 1_024
        )
        try await withTemporaryStore(limits: limits) { store, _ in
            let locationID = UUID()
            let first = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            let second = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 2))
            let third = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 3))

            try await store.save(first)
            try await store.save(second)
            try await store.save(third)

            let descriptors = await store.descriptors(for: locationID)
            let prunedSnapshot = try await store.load(snapshotID: first.id, locationID: locationID)
            XCTAssertEqual(descriptors.map(\.id), [third.id, second.id])
            XCTAssertNil(prunedSnapshot)
        }
    }

    func testCorruptArchiveIsIsolatedFromOtherLocations() async throws {
        try await withTemporaryStore { store, directory in
            let firstLocationID = UUID()
            let secondLocationID = UUID()
            let first = makeSnapshot(locationID: firstLocationID, scannedAt: Date(timeIntervalSince1970: 1))
            let second = makeSnapshot(locationID: secondLocationID, scannedAt: Date(timeIntervalSince1970: 2))
            let firstDescriptor = try await store.save(first)
            try await store.save(second)

            let damagedURL = archiveURL(
                base: directory,
                locationID: firstLocationID,
                snapshotID: first.id
            )
            try Data(repeating: 0, count: Int(firstDescriptor.storedByteCount)).write(to: damagedURL, options: .atomic)

            let damagedDescriptors = await store.descriptors(for: firstLocationID)
            let intactDescriptors = await store.descriptors(for: secondLocationID)
            let intactSnapshot = try await store.load(snapshotID: second.id, locationID: secondLocationID)
            XCTAssertTrue(damagedDescriptors.isEmpty)
            XCTAssertEqual(intactDescriptors.map(\.id), [second.id])
            XCTAssertEqual(intactSnapshot?.id, second.id)
        }
    }

    func testSameSizePayloadCorruptionIsHiddenAndQuarantined() async throws {
        try await withTemporaryStore { store, directory in
            let locationID = UUID()
            let snapshot = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            try await store.save(snapshot)
            let url = archiveURL(base: directory, locationID: locationID, snapshotID: snapshot.id)
            var archive = try Data(contentsOf: url)
            archive[archive.index(before: archive.endIndex)] ^= 0x01
            try archive.write(to: url, options: .atomic)

            let damagedDescriptors = await store.descriptors(for: locationID)
            XCTAssertTrue(damagedDescriptors.isEmpty)
            do {
                _ = try await store.load(snapshotID: snapshot.id, locationID: locationID)
                XCTFail("A same-size payload mutation must fail integrity validation")
            } catch {
                XCTAssertEqual(error as? SnapshotStoreError, .corruptArchive)
            }
            let quarantinedDescriptors = await store.descriptors(for: locationID)
            XCTAssertTrue(quarantinedDescriptors.isEmpty)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: directory
                        .appendingPathComponent(locationID.uuidString.lowercased(), isDirectory: true)
                        .appendingPathComponent(snapshot.id.uuidString.lowercased())
                        .appendingPathExtension("quarantined")
                        .path
                )
            )
        }
    }

    func testUncataloguedArchiveIsSweptOnNextHistoryRead() async throws {
        try await withTemporaryStore { store, directory in
            let locationID = UUID()
            let snapshot = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            try await store.save(snapshot)
            let archive = archiveURL(base: directory, locationID: locationID, snapshotID: snapshot.id)
            let catalog = directory
                .appendingPathComponent(locationID.uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent("catalog-v1.plist")
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(TestSnapshotCatalog(version: 1, descriptors: []))
                .write(to: catalog, options: .atomic)

            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
            _ = await store.descriptors(for: locationID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        }
    }

    func testQuarantinedBytesReserveThePhysicalHistoryQuota() async throws {
        try await withTemporaryStore { initialStore, directory in
            let quarantinedLocationID = UUID()
            let quarantined = makeSnapshot(
                locationID: quarantinedLocationID,
                scannedAt: Date(timeIntervalSince1970: 1)
            )
            let descriptor = try await initialStore.save(quarantined)
            let damagedURL = archiveURL(
                base: directory,
                locationID: quarantinedLocationID,
                snapshotID: quarantined.id
            )
            var archive = try Data(contentsOf: damagedURL)
            archive[archive.index(before: archive.endIndex)] ^= 0x01
            try archive.write(to: damagedURL, options: .atomic)
            do {
                _ = try await initialStore.load(
                    snapshotID: quarantined.id,
                    locationID: quarantinedLocationID
                )
                XCTFail("The fixture must enter quarantine")
            } catch {
                XCTAssertEqual(error as? SnapshotStoreError, .corruptArchive)
            }

            let boundedStore = SnapshotStore(
                directoryURL: directory,
                limits: SnapshotStoreLimits(
                    maximumSnapshotsPerLocation: 8,
                    maximumBytesPerLocation: 32 * 1_024 * 1_024,
                    maximumTotalBytes: descriptor.storedByteCount + 1,
                    maximumUncompressedArchiveBytes: 32 * 1_024 * 1_024
                )
            )
            let nextLocationID = UUID()
            let next = makeSnapshot(
                locationID: nextLocationID,
                scannedAt: Date(timeIntervalSince1970: 2)
            )
            do {
                _ = try await boundedStore.save(next)
                XCTFail("Quarantined physical bytes must reserve total quota")
            } catch let error as SnapshotStoreError {
                guard case .archiveTooLarge = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: archiveURL(
                        base: directory,
                        locationID: nextLocationID,
                        snapshotID: next.id
                    ).path
                )
            )
        }
    }

    func testCatalogsRemainSeparatedByLocation() async throws {
        try await withTemporaryStore { store, _ in
            let firstLocationID = UUID()
            let secondLocationID = UUID()
            let first = makeSnapshot(locationID: firstLocationID, scannedAt: Date(timeIntervalSince1970: 1))
            let second = makeSnapshot(locationID: secondLocationID, scannedAt: Date(timeIntervalSince1970: 2))
            try await store.save(first)
            try await store.save(second)

            let firstDescriptors = await store.descriptors(for: firstLocationID)
            let secondDescriptors = await store.descriptors(for: secondLocationID)
            XCTAssertEqual(firstDescriptors.map(\.id), [first.id])
            XCTAssertEqual(secondDescriptors.map(\.id), [second.id])
        }
    }

    func testCatalogCannotClaimDescriptorsFromAnotherLocation() async throws {
        try await withTemporaryStore { store, directory in
            let firstLocationID = UUID()
            let secondLocationID = UUID()
            let first = makeSnapshot(locationID: firstLocationID, scannedAt: Date(timeIntervalSince1970: 1))
            let second = makeSnapshot(locationID: secondLocationID, scannedAt: Date(timeIntervalSince1970: 2))
            let firstDescriptor = try await store.save(first)
            try await store.save(second)

            let catalogURL = directory
                .appendingPathComponent(firstLocationID.uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent("catalog-v1.plist")
            let foreignDescriptor = ScanSnapshotDescriptor(
                id: firstDescriptor.id,
                locationID: secondLocationID,
                scannedAt: firstDescriptor.scannedAt,
                allocatedSize: firstDescriptor.allocatedSize,
                logicalSize: firstDescriptor.logicalSize,
                nodeCount: firstDescriptor.nodeCount,
                isComplete: firstDescriptor.isComplete,
                warningCount: firstDescriptor.warningCount,
                storedByteCount: firstDescriptor.storedByteCount,
                fidelity: firstDescriptor.fidelity,
                integrityDigest: firstDescriptor.integrityDigest
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(TestSnapshotCatalog(version: 1, descriptors: [foreignDescriptor]))
                .write(to: catalogURL, options: .atomic)

            let firstDescriptors = await store.descriptors(for: firstLocationID)
            let secondDescriptors = await store.descriptors(for: secondLocationID)
            let loadedSecond = try await store.load(snapshotID: second.id, locationID: secondLocationID)
            XCTAssertTrue(firstDescriptors.isEmpty)
            XCTAssertEqual(secondDescriptors.map(\.id), [second.id])
            XCTAssertEqual(
                loadedSecond?.id,
                second.id,
                "A damaged catalog must not reach another location's archive"
            )
        }
    }

    func testGlobalByteLimitPrunesOldestKnownArchive() async throws {
        try await withTemporaryStore { initialStore, directory in
            let firstLocationID = UUID()
            let secondLocationID = UUID()
            let thirdLocationID = UUID()
            let first = makeSnapshot(locationID: firstLocationID, scannedAt: Date(timeIntervalSince1970: 1))
            let firstDescriptor = try await initialStore.save(first)
            let byteLimit = firstDescriptor.storedByteCount * 2
            let boundedStore = SnapshotStore(
                directoryURL: directory,
                limits: SnapshotStoreLimits(
                    maximumSnapshotsPerLocation: 8,
                    maximumBytesPerLocation: byteLimit,
                    maximumTotalBytes: byteLimit,
                    maximumUncompressedArchiveBytes: 32 * 1_024 * 1_024
                )
            )
            let second = makeSnapshot(locationID: secondLocationID, scannedAt: Date(timeIntervalSince1970: 2))
            let third = makeSnapshot(locationID: thirdLocationID, scannedAt: Date(timeIntervalSince1970: 3))
            try await boundedStore.save(second)
            try await boundedStore.save(third)

            let firstDescriptors = await boundedStore.descriptors(for: firstLocationID)
            let secondDescriptors = await boundedStore.descriptors(for: secondLocationID)
            let thirdDescriptors = await boundedStore.descriptors(for: thirdLocationID)
            let retained = firstDescriptors + secondDescriptors + thirdDescriptors
            XCTAssertLessThanOrEqual(retained.reduce(UInt64(0)) { $0 + $1.storedByteCount }, byteLimit)
            XCTAssertEqual(thirdDescriptors.map(\.id), [third.id])
            XCTAssertFalse(retained.contains { $0.id == first.id }, "The oldest archive should yield first")
        }
    }

    func testFutureArchiveVersionIsIgnoredWithoutMutation() async throws {
        try await withTemporaryStore { store, directory in
            let locationID = UUID()
            let snapshot = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            try await store.save(snapshot)
            let url = archiveURL(base: directory, locationID: locationID, snapshotID: snapshot.id)
            var futureArchive = try Data(contentsOf: url)
            futureArchive.replaceSubrange(8..<12, with: [0, 0, 0, 99])
            try futureArchive.write(to: url, options: .atomic)
            let before = try Data(contentsOf: url)

            let descriptors = await store.descriptors(for: locationID)
            XCTAssertTrue(descriptors.isEmpty)
            do {
                _ = try await store.load(snapshotID: snapshot.id, locationID: locationID)
                XCTFail("A future archive version must not load as the current schema")
            } catch {
                XCTAssertEqual(error as? SnapshotStoreError, .unsupportedVersion(99))
            }
            XCTAssertEqual(try Data(contentsOf: url), before, "Unsupported data must remain available to a future migrator")
        }
    }

    func testImplausibleExpansionHeaderIsRejectedBeforeAllocation() async throws {
        try await withTemporaryStore { store, directory in
            let locationID = UUID()
            let snapshot = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            try await store.save(snapshot)
            let url = archiveURL(base: directory, locationID: locationID, snapshotID: snapshot.id)
            var archive = try Data(contentsOf: url)
            // Header bytes 12..<20 encode the claimed uncompressed size.
            // A tiny payload claiming 512 MiB must fail before Data(count:).
            archive.replaceSubrange(12..<20, with: [0, 0, 0, 0, 32, 0, 0, 0])
            try archive.write(to: url, options: .atomic)

            do {
                _ = try await store.load(snapshotID: snapshot.id, locationID: locationID)
                XCTFail("An implausible expansion ratio must not allocate or decode")
            } catch {
                XCTAssertEqual(error as? SnapshotStoreError, .corruptArchive)
            }
        }
    }

    func testSelfReferentialSiblingLinkIsRejectedBeforePersistence() async throws {
        try await withTemporaryStore { store, _ in
            let locationID = UUID()
            let valid = makeSnapshot(locationID: locationID, scannedAt: Date(timeIntervalSince1970: 1))
            var nodes = valid.session.nodes
            nodes[1].nextSiblingID = NodeID(rawValue: 1)
            let invalidSession = ScanSession(
                rootURLBookmarkID: valid.session.rootURLBookmarkID,
                rootDisplayName: valid.session.rootDisplayName,
                options: valid.session.options,
                nodes: nodes,
                rootTotalAllocated: valid.session.rootTotalAllocated,
                rootTotalLogical: valid.session.rootTotalLogical,
                warnings: valid.session.warnings,
                isComplete: true
            )
            let invalidSnapshot = StoredScanSnapshot(
                id: valid.id,
                locationID: locationID,
                scannedAt: valid.scannedAt,
                session: invalidSession,
                volumeSpace: valid.volumeSpace
            )

            do {
                _ = try await store.save(invalidSnapshot)
                XCTFail("A cyclic sibling list must never enter saved history")
            } catch {
                XCTAssertEqual(error as? SnapshotStoreError, .corruptArchive)
            }
        }
    }

    private func withTemporaryStore(
        limits: SnapshotStoreLimits = .default,
        operation: (SnapshotStore, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await operation(SnapshotStore(directoryURL: directory, limits: limits), directory)
    }

    private func makeSnapshot(locationID: UUID, scannedAt: Date) -> StoredScanSnapshot {
        let root = FileNode(
            parentID: .invalid,
            kind: .root,
            name: "Projects",
            path: "/Projects",
            logicalSize: 16_384,
            allocatedSize: 12_288,
            childCount: 1,
            firstChildID: NodeID(rawValue: 1),
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            allowedActions: []
        )
        let file = FileNode(
            parentID: .root,
            kind: .file,
            name: "main.swift",
            path: "/Projects/main.swift",
            logicalSize: 16_384,
            allocatedSize: 12_288,
            childCount: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            allowedActions: [.revealInFinder, .moveToTrash, .moveToLocation]
        )
        let session = ScanSession(
            rootURLBookmarkID: locationID,
            rootDisplayName: "Projects",
            options: .default,
            nodes: [root, file],
            rootTotalAllocated: 12_288,
            rootTotalLogical: 16_384,
            warnings: ["One unreadable item"],
            isComplete: true
        )
        return StoredScanSnapshot(
            id: UUID(),
            locationID: locationID,
            scannedAt: scannedAt,
            session: session,
            volumeSpace: ScanSnapshotVolumeSpace(name: "Macintosh HD", capacity: 1_000_000, available: 250_000)
        )
    }

    private func archiveURL(base: URL, locationID: UUID, snapshotID: UUID) -> URL {
        base
            .appendingPathComponent(locationID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(snapshotID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("mdsnapshot")
    }
}

private struct TestSnapshotCatalog: Codable {
    let version: Int
    let descriptors: [ScanSnapshotDescriptor]
}
