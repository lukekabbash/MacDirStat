import Foundation

/// Stable index into the scan session arena.
public struct NodeID: Hashable, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let invalid = NodeID(rawValue: .max)
    public static let root = NodeID(rawValue: 0)
}
