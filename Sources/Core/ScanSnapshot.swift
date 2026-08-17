import Foundation

/// Describes what a saved scan can truthfully reproduce. The first archive
/// format stores the immutable scan arena, so Map and Overview remain fully
/// interactive without touching the source filesystem.
public enum ScanSnapshotFidelity: String, Codable, Sendable {
    case interactiveScanSession
}

/// Lightweight catalog metadata. Listing history never decodes a full arena.
public struct ScanSnapshotDescriptor: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let locationID: UUID
    public let scannedAt: Date
    public let allocatedSize: UInt64
    public let logicalSize: UInt64
    public let nodeCount: Int
    public let isComplete: Bool
    public let warningCount: Int
    public let storedByteCount: UInt64
    public let fidelity: ScanSnapshotFidelity
    /// SHA-256 of the complete compressed archive. Older v1 catalogs decode
    /// without this field and are quarantined after any decode failure.
    public let integrityDigest: String?

    public init(
        id: UUID,
        locationID: UUID,
        scannedAt: Date,
        allocatedSize: UInt64,
        logicalSize: UInt64,
        nodeCount: Int,
        isComplete: Bool,
        warningCount: Int,
        storedByteCount: UInt64,
        fidelity: ScanSnapshotFidelity,
        integrityDigest: String? = nil
    ) {
        self.id = id
        self.locationID = locationID
        self.scannedAt = scannedAt
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.nodeCount = nodeCount
        self.isComplete = isComplete
        self.warningCount = warningCount
        self.storedByteCount = storedByteCount
        self.fidelity = fidelity
        self.integrityDigest = integrityDigest
    }
}

/// Capacity values captured with the scan. This intentionally excludes live
/// volume APIs; a historical value must remain visibly historical.
public struct ScanSnapshotVolumeSpace: Equatable, Codable, Sendable {
    public let name: String
    public let capacity: UInt64
    public let available: UInt64

    public init(name: String, capacity: UInt64, available: UInt64) {
        self.name = name
        self.capacity = capacity
        self.available = min(available, capacity)
    }
}

/// The persisted payload contains only scan truth needed by Map and Overview.
/// Bookmarks, view selection, layout caches, and deletion permission are never
/// archived. Mutating capabilities are stripped at this boundary as a second
/// lock behind the app model's explicit historical state.
public struct StoredScanSnapshot: Equatable, Codable, Sendable {
    public let id: UUID
    public let locationID: UUID
    public let scannedAt: Date
    public let fidelity: ScanSnapshotFidelity
    public let session: ScanSession
    public let volumeSpace: ScanSnapshotVolumeSpace?

    public init(
        id: UUID = UUID(),
        locationID: UUID,
        scannedAt: Date,
        session: ScanSession,
        volumeSpace: ScanSnapshotVolumeSpace?
    ) {
        self.id = id
        self.locationID = locationID
        self.scannedAt = scannedAt
        self.fidelity = .interactiveScanSession
        self.session = session
        self.volumeSpace = volumeSpace
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case locationID
        case scannedAt
        case fidelity
        case session
        case volumeSpace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        locationID = try container.decode(UUID.self, forKey: .locationID)
        scannedAt = try container.decode(Date.self, forKey: .scannedAt)
        fidelity = try container.decode(ScanSnapshotFidelity.self, forKey: .fidelity)
        session = try container.decode(ScanSession.self, forKey: .session)
        volumeSpace = try container.decodeIfPresent(ScanSnapshotVolumeSpace.self, forKey: .volumeSpace)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(locationID, forKey: .locationID)
        try container.encode(scannedAt, forKey: .scannedAt)
        try container.encode(fidelity, forKey: .fidelity)
        try container.encode(session, forKey: .session)
        try container.encodeIfPresent(volumeSpace, forKey: .volumeSpace)
    }

    func descriptor(storedByteCount: UInt64, integrityDigest: String) -> ScanSnapshotDescriptor {
        ScanSnapshotDescriptor(
            id: id,
            locationID: locationID,
            scannedAt: scannedAt,
            allocatedSize: session.rootTotalAllocated,
            logicalSize: session.rootTotalLogical,
            nodeCount: max(0, session.nodes.count - 1),
            isComplete: session.isComplete,
            warningCount: session.warnings.count,
            storedByteCount: storedByteCount,
            fidelity: fidelity,
            integrityDigest: integrityDigest
        )
    }
}
