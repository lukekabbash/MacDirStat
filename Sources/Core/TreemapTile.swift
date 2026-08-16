import Foundation

/// Normalized rectangle in treemap space (0...1).
public struct NormalizedRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Layout result for one tile in the treemap.
public struct TreemapTile: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case node
        case freeSpace
        case usedOutsideScan
    }

    public var nodeID: NodeID
    public var rect: NormalizedRect
    /// Directories appear only when a branch is too small to resolve cleanly.
    public var isAggregate: Bool
    public var depth: Int
    public var role: Role

    public init(
        nodeID: NodeID,
        rect: NormalizedRect,
        isAggregate: Bool = false,
        depth: Int = 0,
        role: Role = .node
    ) {
        self.nodeID = nodeID
        self.rect = rect
        self.isAggregate = isAggregate
        self.depth = depth
        self.role = role
    }
}

/// Whole-volume values used to place scanned, unavailable, and free capacity
/// in one proportional map. Folder totals remain unchanged.
public struct TreemapCapacityContext: Equatable, Sendable {
    public var capacity: UInt64
    public var available: UInt64
    public var scannedAllocated: UInt64

    public init(capacity: UInt64, available: UInt64, scannedAllocated: UInt64) {
        self.capacity = capacity
        self.available = min(available, capacity)
        self.scannedAllocated = scannedAllocated
    }

    public var used: UInt64 { capacity - available }
    public var mappedUsed: UInt64 { min(scannedAllocated, used) }
    public var usedOutsideScan: UInt64 { used - mappedUsed }
}
