import Compression
import CryptoKit
import Foundation

public struct SnapshotStoreLimits: Equatable, Sendable {
    public var maximumSnapshotsPerLocation: Int
    public var maximumBytesPerLocation: UInt64
    public var maximumTotalBytes: UInt64
    public var maximumUncompressedArchiveBytes: UInt64

    public init(
        maximumSnapshotsPerLocation: Int = 8,
        maximumBytesPerLocation: UInt64 = 384 * 1_024 * 1_024,
        maximumTotalBytes: UInt64 = 768 * 1_024 * 1_024,
        maximumUncompressedArchiveBytes: UInt64 = 512 * 1_024 * 1_024
    ) {
        self.maximumSnapshotsPerLocation = max(1, maximumSnapshotsPerLocation)
        self.maximumBytesPerLocation = max(1, maximumBytesPerLocation)
        self.maximumTotalBytes = max(1, maximumTotalBytes)
        self.maximumUncompressedArchiveBytes = max(1, maximumUncompressedArchiveBytes)
    }

    public static let `default` = SnapshotStoreLimits()
}

public enum SnapshotStoreError: LocalizedError, Equatable {
    case incompleteSnapshot
    case unsupportedVersion(Int)
    case corruptArchive
    case archiveTooLarge(UInt64, limit: UInt64)
    case snapshotNotFound
    case historyMaintenanceFailed

    public var errorDescription: String? {
        switch self {
        case .incompleteSnapshot:
            return "Only a completed scan can be saved."
        case let .unsupportedVersion(version):
            return "Snapshot format version \(version) is not supported by this version of the app."
        case .corruptArchive:
            return "The saved snapshot is damaged and was left untouched."
        case let .archiveTooLarge(bytes, limit):
            return "This snapshot needs \(bytes) stored bytes, above the \(limit)-byte history limit."
        case .snapshotNotFound:
            return "The saved snapshot is no longer available."
        case .historyMaintenanceFailed:
            return "Old scan-history files could not be pruned. No new snapshot was written."
        }
    }
}

private struct VerifiedArchiveIntegrity {
    let storedSize: UInt64
    let modificationDate: Date?
    let fileNumber: UInt64?
    let digest: String
}

private struct ArchiveFootprint {
    var count = 0
    var bytes: UInt64 = 0

    mutating func include(_ storedBytes: UInt64) {
        count += 1
        let addition = bytes.addingReportingOverflow(storedBytes)
        bytes = addition.overflow ? UInt64.max : addition.partialValue
    }
}

private struct SnapshotCatalogEnvelope: Codable {
    let version: Int
    var descriptors: [ScanSnapshotDescriptor]
}

private struct SnapshotArchiveEnvelope: Codable {
    let version: Int
    let snapshot: StoredScanSnapshot
}

/// Versioned, compressed scan history. Each saved location owns an independent
/// catalog and archive directory so one damaged file cannot hide other sources.
/// Catalogs remain tiny; listing history never inflates a full scan arena.
public actor SnapshotStore {
    public static let `default` = SnapshotStore()

    private static let catalogVersion = 1
    private static let archiveVersion = 1
    private static let archiveMagic = Data("MDSNAP01".utf8)
    private static let archiveHeaderSize = 20
    private static let maximumCatalogBytes: UInt64 = 1 * 1_024 * 1_024

    private let baseDirectoryURL: URL
    private let limits: SnapshotStoreLimits
    private let fileManager: FileManager
    private var verifiedArchiveIntegrity: [URL: VerifiedArchiveIntegrity] = [:]

    public init(
        appSupportSubpath: String = "Mac Directory Statistics/Scan Snapshots",
        limits: SnapshotStoreLimits = .default
    ) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        self.baseDirectoryURL = base.appendingPathComponent(appSupportSubpath, isDirectory: true)
        self.limits = limits
        self.fileManager = .default
    }

    public init(
        directoryURL: URL,
        limits: SnapshotStoreLimits = .default,
        fileManager: FileManager = .default
    ) {
        self.baseDirectoryURL = directoryURL
        self.limits = limits
        self.fileManager = fileManager
    }

    /// Newest first. Unsupported or damaged archives are omitted without
    /// rewriting them, which keeps future-version data migration-safe.
    public func descriptors(for locationID: UUID) -> [ScanSnapshotDescriptor] {
        _ = sweepOrphanedArchives()
        guard let catalog = try? readCatalog(for: locationID) else { return [] }
        return ordered(catalog.descriptors.filter(archiveMatchesDescriptor))
    }

    @discardableResult
    public func save(_ snapshot: StoredScanSnapshot) throws -> ScanSnapshotDescriptor {
        guard snapshot.session.isComplete else { throw SnapshotStoreError.incompleteSnapshot }
        guard snapshot.session.hasValidTreeStructure else { throw SnapshotStoreError.corruptArchive }
        guard sweepOrphanedArchives() else { throw SnapshotStoreError.historyMaintenanceFailed }
        let archive = try encodeArchive(snapshot)
        let storedBytes = UInt64(archive.count)
        let singleArchiveLimit = min(limits.maximumBytesPerLocation, limits.maximumTotalBytes)
        guard storedBytes <= singleArchiveLimit else {
            throw SnapshotStoreError.archiveTooLarge(storedBytes, limit: singleArchiveLimit)
        }
        let replacement = (locationID: snapshot.locationID, snapshotID: snapshot.id)
        let locationReserve = unmanagedArchiveFootprint(
            for: snapshot.locationID,
            excluding: replacement
        )
        let globalReserve = unmanagedArchiveFootprint(excluding: replacement)
        guard locationReserve.count < limits.maximumSnapshotsPerLocation,
              storedBytes <= limits.maximumBytesPerLocation - min(
                  locationReserve.bytes,
                  limits.maximumBytesPerLocation
              )
        else {
            throw SnapshotStoreError.archiveTooLarge(
                locationReserve.bytes.addingReportingOverflow(storedBytes).partialValue,
                limit: limits.maximumBytesPerLocation
            )
        }
        guard storedBytes <= limits.maximumTotalBytes - min(
            globalReserve.bytes,
            limits.maximumTotalBytes
        ) else {
            throw SnapshotStoreError.archiveTooLarge(
                globalReserve.bytes.addingReportingOverflow(storedBytes).partialValue,
                limit: limits.maximumTotalBytes
            )
        }

        let locationDirectory = directory(for: snapshot.locationID)
        try fileManager.createDirectory(at: locationDirectory, withIntermediateDirectories: true)
        let archiveURL = archiveURL(locationID: snapshot.locationID, snapshotID: snapshot.id)
        try archive.write(to: archiveURL, options: .atomic)

        let descriptor = snapshot.descriptor(
            storedByteCount: storedBytes,
            integrityDigest: integrityDigest(for: archive)
        )
        try? fileManager.removeItem(
            at: quarantineMarkerURL(locationID: snapshot.locationID, snapshotID: snapshot.id)
        )
        var catalog: SnapshotCatalogEnvelope
        do {
            catalog = try readCatalog(for: snapshot.locationID)
        } catch CocoaError.fileReadNoSuchFile {
            catalog = SnapshotCatalogEnvelope(version: Self.catalogVersion, descriptors: [])
        } catch {
            // Do not overwrite an unreadable or future-version catalog.
            try? fileManager.removeItem(at: archiveURL)
            throw error
        }

        catalog.descriptors.removeAll { $0.id == descriptor.id }
        catalog.descriptors.append(descriptor)
        let locationPrune = prunedLocationCatalog(
            catalog,
            preserving: descriptor.id,
            reserved: locationReserve
        )
        try writeCatalog(locationPrune.kept, for: snapshot.locationID)
        removeArchives(locationPrune.removed)

        try pruneGlobalHistory(preserving: descriptor)
        _ = sweepOrphanedArchives()
        return descriptor
    }

    public func load(snapshotID: UUID, locationID: UUID) throws -> StoredScanSnapshot? {
        let url = archiveURL(locationID: locationID, snapshotID: snapshotID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let storedSize = (attributes[.size] as? NSNumber)?.uint64Value,
              storedSize >= UInt64(Self.archiveHeaderSize),
              storedSize <= maximumStoredArchiveBytes
        else { throw SnapshotStoreError.corruptArchive }
        let archive = try Data(contentsOf: url, options: [.mappedIfSafe])
        if archive.prefix(Self.archiveMagic.count) == Self.archiveMagic {
            let storedVersion = try archive.readBigEndianUInt32(at: Self.archiveMagic.count)
            guard storedVersion == Self.archiveVersion else {
                throw SnapshotStoreError.unsupportedVersion(Int(storedVersion))
            }
        }
        do {
            if let descriptor = try? readCatalog(for: locationID).descriptors.first(where: { $0.id == snapshotID }),
               let expectedDigest = descriptor.integrityDigest,
               integrityDigest(for: archive) != expectedDigest {
                throw SnapshotStoreError.corruptArchive
            }
            let snapshot = try decodeArchive(archive)
            guard snapshot.id == snapshotID, snapshot.locationID == locationID else {
                throw SnapshotStoreError.corruptArchive
            }
            return snapshot
        } catch let error as SnapshotStoreError {
            if case .unsupportedVersion = error { throw error }
            quarantineCurrentArchive(snapshotID: snapshotID, locationID: locationID)
            throw error
        } catch {
            quarantineCurrentArchive(snapshotID: snapshotID, locationID: locationID)
            throw SnapshotStoreError.corruptArchive
        }
    }

    private func directory(for locationID: UUID) -> URL {
        baseDirectoryURL.appendingPathComponent(locationID.uuidString.lowercased(), isDirectory: true)
    }

    private func catalogURL(for locationID: UUID) -> URL {
        directory(for: locationID).appendingPathComponent("catalog-v1.plist", isDirectory: false)
    }

    private func archiveURL(locationID: UUID, snapshotID: UUID) -> URL {
        directory(for: locationID)
            .appendingPathComponent(snapshotID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("mdsnapshot")
    }

    private func quarantineMarkerURL(locationID: UUID, snapshotID: UUID) -> URL {
        directory(for: locationID)
            .appendingPathComponent(snapshotID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("quarantined")
    }

    private func readCatalog(for locationID: UUID) throws -> SnapshotCatalogEnvelope {
        let url = catalogURL(for: locationID)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let storedSize = (attributes[.size] as? NSNumber)?.uint64Value,
              storedSize > 0,
              storedSize <= Self.maximumCatalogBytes
        else { throw SnapshotStoreError.corruptArchive }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let catalog: SnapshotCatalogEnvelope
        do {
            catalog = try PropertyListDecoder().decode(SnapshotCatalogEnvelope.self, from: data)
        } catch {
            throw SnapshotStoreError.corruptArchive
        }
        guard catalog.version == Self.catalogVersion else {
            throw SnapshotStoreError.unsupportedVersion(catalog.version)
        }
        var descriptorIDs = Set<UUID>()
        guard catalog.descriptors.allSatisfy({ descriptor in
            descriptor.locationID == locationID && descriptorIDs.insert(descriptor.id).inserted
        }) else {
            throw SnapshotStoreError.corruptArchive
        }
        return catalog
    }

    private func writeCatalog(_ catalog: SnapshotCatalogEnvelope, for locationID: UUID) throws {
        let locationDirectory = directory(for: locationID)
        try fileManager.createDirectory(at: locationDirectory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(catalog).write(to: catalogURL(for: locationID), options: .atomic)
    }

    private func encodeArchive(_ snapshot: StoredScanSnapshot) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let uncompressed = try encoder.encode(
            SnapshotArchiveEnvelope(version: Self.archiveVersion, snapshot: snapshot)
        )
        guard UInt64(uncompressed.count) <= limits.maximumUncompressedArchiveBytes else {
            throw SnapshotStoreError.archiveTooLarge(
                UInt64(uncompressed.count),
                limit: limits.maximumUncompressedArchiveBytes
            )
        }
        let compressed = try compress(uncompressed)
        var archive = Data()
        archive.reserveCapacity(Self.archiveHeaderSize + compressed.count)
        archive.append(Self.archiveMagic)
        archive.appendBigEndian(UInt32(Self.archiveVersion))
        archive.appendBigEndian(UInt64(uncompressed.count))
        archive.append(compressed)
        return archive
    }

    private func decodeArchive(_ archive: Data) throws -> StoredScanSnapshot {
        guard archive.count >= Self.archiveHeaderSize,
              archive.prefix(Self.archiveMagic.count) == Self.archiveMagic
        else { throw SnapshotStoreError.corruptArchive }
        let version = try archive.readBigEndianUInt32(at: Self.archiveMagic.count)
        guard version == Self.archiveVersion else {
            throw SnapshotStoreError.unsupportedVersion(Int(version))
        }
        let uncompressedSize = try archive.readBigEndianUInt64(at: Self.archiveMagic.count + 4)
        guard uncompressedSize > 0,
              uncompressedSize <= limits.maximumUncompressedArchiveBytes,
              uncompressedSize <= UInt64(Int.max)
        else { throw SnapshotStoreError.corruptArchive }

        let payload = archive.dropFirst(Self.archiveHeaderSize)
        let payloadBytes = UInt64(max(1, payload.count))
        let expansionAllowance = payloadBytes.multipliedReportingOverflow(by: 64)
        let maximumPlausibleSize = expansionAllowance.overflow
            ? UInt64.max
            : max(1_024 * 1_024, expansionAllowance.partialValue)
        guard uncompressedSize <= maximumPlausibleSize else {
            throw SnapshotStoreError.corruptArchive
        }
        let uncompressed = try decompress(Data(payload), expectedSize: Int(uncompressedSize))
        let envelope: SnapshotArchiveEnvelope
        do {
            envelope = try PropertyListDecoder().decode(SnapshotArchiveEnvelope.self, from: uncompressed)
        } catch {
            throw SnapshotStoreError.corruptArchive
        }
        guard envelope.version == Self.archiveVersion else {
            throw SnapshotStoreError.unsupportedVersion(envelope.version)
        }
        guard envelope.snapshot.session.hasValidTreeStructure else {
            throw SnapshotStoreError.corruptArchive
        }
        return envelope.snapshot
    }

    private func compress(_ source: Data) throws -> Data {
        var capacity = max(64 * 1_024, source.count + source.count / 16)
        for _ in 0..<4 {
            var destination = Data(count: capacity)
            let encodedCount = source.withUnsafeBytes { sourceBuffer in
                destination.withUnsafeMutableBytes { destinationBuffer in
                    compression_encode_buffer(
                        destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        source.count,
                        nil,
                        COMPRESSION_LZFSE
                    )
                }
            }
            if encodedCount > 0 {
                destination.count = encodedCount
                return destination
            }
            capacity *= 2
        }
        throw SnapshotStoreError.corruptArchive
    }

    private func decompress(_ source: Data, expectedSize: Int) throws -> Data {
        var destination = Data(count: expectedSize)
        let decodedCount = source.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                compression_decode_buffer(
                    destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    source.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard decodedCount == expectedSize else { throw SnapshotStoreError.corruptArchive }
        return destination
    }

    private func ordered(_ descriptors: [ScanSnapshotDescriptor]) -> [ScanSnapshotDescriptor] {
        descriptors.sorted { lhs, rhs in
            if lhs.scannedAt != rhs.scannedAt { return lhs.scannedAt > rhs.scannedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func archiveMatchesDescriptor(_ descriptor: ScanSnapshotDescriptor) -> Bool {
        let url = archiveURL(locationID: descriptor.locationID, snapshotID: descriptor.id)
        guard descriptor.storedByteCount >= UInt64(Self.archiveHeaderSize),
              descriptor.storedByteCount <= maximumStoredArchiveBytes,
              !fileManager.fileExists(atPath: quarantineMarkerURL(
                  locationID: descriptor.locationID,
                  snapshotID: descriptor.id
              ).path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size == descriptor.storedByteCount,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: Self.archiveHeaderSize),
              prefix.count == Self.archiveHeaderSize,
              prefix.prefix(Self.archiveMagic.count) == Self.archiveMagic,
              let version = try? prefix.readBigEndianUInt32(at: Self.archiveMagic.count)
        else { return false }
        guard version == Self.archiveVersion else { return false }
        guard let expectedDigest = descriptor.integrityDigest else { return true }

        let modificationDate = attributes[.modificationDate] as? Date
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        if let verified = verifiedArchiveIntegrity[url],
           verified.storedSize == size,
           verified.modificationDate == modificationDate,
           verified.fileNumber == fileNumber,
           verified.digest == expectedDigest {
            return true
        }
        guard let archive = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
        let digest = integrityDigest(for: archive)
        guard digest == expectedDigest else { return false }
        verifiedArchiveIntegrity[url] = VerifiedArchiveIntegrity(
            storedSize: size,
            modificationDate: modificationDate,
            fileNumber: fileNumber,
            digest: digest
        )
        return true
    }

    private var maximumStoredArchiveBytes: UInt64 {
        min(limits.maximumBytesPerLocation, limits.maximumTotalBytes)
    }

    private func prunedLocationCatalog(
        _ catalog: SnapshotCatalogEnvelope,
        preserving snapshotID: UUID,
        reserved: ArchiveFootprint
    ) -> (kept: SnapshotCatalogEnvelope, removed: [ScanSnapshotDescriptor]) {
        let protected = catalog.descriptors.filter {
            $0.id != snapshotID && !archiveMatchesDescriptor($0)
        }
        let candidates = catalog.descriptors.filter { $0.id == snapshotID }
            + ordered(catalog.descriptors.filter {
                $0.id != snapshotID && archiveMatchesDescriptor($0)
            })
        var kept: [ScanSnapshotDescriptor] = []
        var removed: [ScanSnapshotDescriptor] = []
        var bytes = reserved.bytes

        for descriptor in candidates {
            let fitsCount = kept.count + reserved.count < limits.maximumSnapshotsPerLocation
            let fitsBytes = bytes <= limits.maximumBytesPerLocation - min(
                descriptor.storedByteCount,
                limits.maximumBytesPerLocation
            )
            if descriptor.id == snapshotID || (fitsCount && fitsBytes) {
                kept.append(descriptor)
                bytes += descriptor.storedByteCount
            } else {
                removed.append(descriptor)
            }
        }
        return (
            SnapshotCatalogEnvelope(
                version: Self.catalogVersion,
                descriptors: ordered(protected + kept)
            ),
            removed
        )
    }

    private func pruneGlobalHistory(preserving descriptor: ScanSnapshotDescriptor) throws {
        var catalogs = loadAllCatalogs()
        var all: [ScanSnapshotDescriptor] = []
        for catalog in catalogs.values {
            all.append(contentsOf: catalog.descriptors.filter(archiveMatchesDescriptor))
        }
        let unmanaged = unmanagedArchiveFootprint()
        var total = all.reduce(unmanaged.bytes) { partial, item in
            partial.addingReportingOverflow(item.storedByteCount).overflow
                ? UInt64.max
                : partial + item.storedByteCount
        }
        guard total > limits.maximumTotalBytes else { return }

        all.sort { lhs, rhs in
            if lhs.scannedAt != rhs.scannedAt { return lhs.scannedAt < rhs.scannedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }
        var removed: [ScanSnapshotDescriptor] = []
        for candidate in all where total > limits.maximumTotalBytes {
            guard candidate.id != descriptor.id || candidate.locationID != descriptor.locationID else { continue }
            total = total >= candidate.storedByteCount ? total - candidate.storedByteCount : 0
            catalogs[candidate.locationID]?.descriptors.removeAll { $0.id == candidate.id }
            removed.append(candidate)
        }
        guard total <= limits.maximumTotalBytes else {
            throw SnapshotStoreError.archiveTooLarge(total, limit: limits.maximumTotalBytes)
        }

        for locationID in Set(removed.map(\.locationID)) {
            if let catalog = catalogs[locationID] {
                try writeCatalog(catalog, for: locationID)
            }
        }
        removeArchives(removed)
    }

    /// Bytes not represented by a readable current catalog—including
    /// quarantined payloads—reserve real quota so preservation cannot become
    /// an unbounded hidden storage channel.
    private func unmanagedArchiveFootprint(
        for requestedLocationID: UUID? = nil,
        excluding replacement: (locationID: UUID, snapshotID: UUID)? = nil
    ) -> ArchiveFootprint {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ArchiveFootprint() }

        var footprint = ArchiveFootprint()
        for locationDirectory in directories {
            guard let locationID = UUID(uuidString: locationDirectory.lastPathComponent),
                  requestedLocationID == nil || requestedLocationID == locationID,
                  let files = try? fileManager.contentsOfDirectory(
                      at: locationDirectory,
                      includingPropertiesForKeys: [.fileSizeKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }

            let catalogIDs: Set<UUID>
            if let catalog = try? readCatalog(for: locationID) {
                catalogIDs = Set(
                    catalog.descriptors
                        .filter(archiveMatchesDescriptor)
                        .map(\.id)
                )
            } else {
                catalogIDs = []
            }
            for file in files where file.pathExtension == "mdsnapshot" {
                let snapshotID = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                if let replacement,
                   replacement.locationID == locationID,
                   replacement.snapshotID == snapshotID {
                    continue
                }
                guard snapshotID == nil || !catalogIDs.contains(snapshotID!) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: file.path)
                let storedBytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
                footprint.include(storedBytes)
            }
        }
        return footprint
    }

    private func loadAllCatalogs() -> [UUID: SnapshotCatalogEnvelope] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var catalogs: [UUID: SnapshotCatalogEnvelope] = [:]
        for directory in directories {
            guard let locationID = UUID(uuidString: directory.lastPathComponent),
                  let catalog = try? readCatalog(for: locationID)
            else { continue }
            catalogs[locationID] = catalog
        }
        return catalogs
    }

    private func removeArchives(_ descriptors: [ScanSnapshotDescriptor]) {
        for descriptor in descriptors {
            let url = archiveURL(locationID: descriptor.locationID, snapshotID: descriptor.id)
            try? fileManager.removeItem(at: url)
            verifiedArchiveIntegrity[url] = nil
        }
    }

    /// Retries physical cleanup for files whose catalog entries were already
    /// pruned. A failure blocks the next save instead of allowing silent growth.
    private func sweepOrphanedArchives() -> Bool {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return true }

        var removedEveryOrphan = true
        for locationDirectory in directories {
            guard let locationID = UUID(uuidString: locationDirectory.lastPathComponent),
                  let catalog = try? readCatalog(for: locationID),
                  let files = try? fileManager.contentsOfDirectory(
                      at: locationDirectory,
                      includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles]
                  )
            else { continue }

            let catalogIDs = Set(catalog.descriptors.map(\.id))
            for file in files where file.pathExtension == "mdsnapshot" {
                guard let snapshotID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !catalogIDs.contains(snapshotID),
                      !fileManager.fileExists(atPath: quarantineMarkerURL(
                          locationID: locationID,
                          snapshotID: snapshotID
                      ).path)
                else { continue }
                do {
                    try fileManager.removeItem(at: file)
                    verifiedArchiveIntegrity[file] = nil
                } catch {
                    removedEveryOrphan = false
                }
            }
        }
        return removedEveryOrphan
    }

    /// A current-version payload that cannot decode is removed from navigation
    /// while its bytes remain untouched beside a small quarantine marker.
    private func quarantineCurrentArchive(snapshotID: UUID, locationID: UUID) {
        let marker = quarantineMarkerURL(locationID: locationID, snapshotID: snapshotID)
        guard (try? Data().write(to: marker, options: .atomic)) != nil else { return }

        let url = archiveURL(locationID: locationID, snapshotID: snapshotID)
        verifiedArchiveIntegrity[url] = nil
        guard var catalog = try? readCatalog(for: locationID) else { return }
        catalog.descriptors.removeAll { $0.id == snapshotID }
        try? writeCatalog(catalog, for: locationID)
    }

    private func integrityDigest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readBigEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, count >= offset + MemoryLayout<UInt32>.size else {
            throw SnapshotStoreError.corruptArchive
        }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + MemoryLayout<UInt32>.size))
        }
        return UInt32(bigEndian: value)
    }

    func readBigEndianUInt64(at offset: Int) throws -> UInt64 {
        guard offset >= 0, count >= offset + MemoryLayout<UInt64>.size else {
            throw SnapshotStoreError.corruptArchive
        }
        var value: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + MemoryLayout<UInt64>.size))
        }
        return UInt64(bigEndian: value)
    }
}
