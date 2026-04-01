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
    public var nodeID: NodeID
    public var rect: NormalizedRect

    public init(nodeID: NodeID, rect: NormalizedRect) {
        self.nodeID = nodeID
        self.rect = rect
    }
}
