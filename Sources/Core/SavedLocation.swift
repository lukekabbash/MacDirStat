import Foundation

public enum LocationAvailability: String, Codable, Sendable {
    case ready
    case needsAccess
    case disconnected
}

public struct ScanSummary: Equatable, Codable, Sendable {
    public var scannedAt: Date
    public var allocatedSize: UInt64
    public var logicalSize: UInt64
    public var nodeCount: Int
    public var isComplete: Bool
    public var warningCount: Int
    public var volumeName: String?
    public var volumeCapacity: UInt64?
    public var volumeAvailable: UInt64?

    public init(
        scannedAt: Date,
        allocatedSize: UInt64,
        logicalSize: UInt64,
        nodeCount: Int,
        isComplete: Bool,
        warningCount: Int,
        volumeName: String? = nil,
        volumeCapacity: UInt64? = nil,
        volumeAvailable: UInt64? = nil
    ) {
        self.scannedAt = scannedAt
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.nodeCount = nodeCount
        self.isComplete = isComplete
        self.warningCount = warningCount
        self.volumeName = volumeName
        self.volumeCapacity = volumeCapacity
        self.volumeAvailable = volumeAvailable
    }

    public func size(for metric: SizeMetric) -> UInt64 {
        metric == .allocated ? allocatedSize : logicalSize
    }
}

/// A user-visible source whose bookmark remains the sole access authority.
public struct SavedLocation: Identifiable, Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public var scanRoot: ScanRoot
    public var customName: String?
    public var isPinned: Bool
    public var sortOrder: Int
    public var availability: LocationAvailability
    public var lastScanSummary: ScanSummary?
    public var lastSelectedAt: Date?

    public var id: UUID { scanRoot.id }

    public var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? scanRoot.displayName : trimmed
    }

    public init(
        scanRoot: ScanRoot,
        customName: String? = nil,
        isPinned: Bool = false,
        sortOrder: Int = 0,
        availability: LocationAvailability = .ready,
        lastScanSummary: ScanSummary? = nil,
        lastSelectedAt: Date? = nil,
        schemaVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.scanRoot = scanRoot
        self.customName = customName
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.availability = availability
        self.lastScanSummary = lastScanSummary
        self.lastSelectedAt = lastSelectedAt
    }
}
