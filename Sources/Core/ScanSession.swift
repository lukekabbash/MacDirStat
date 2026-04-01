import Foundation

/// Immutable snapshot of a scan at a point in time.
public struct ScanSession: Equatable, Sendable {
    public var rootURLBookmarkID: UUID?
    public var rootDisplayName: String
    public var options: ScanOptions
    public var nodes: [FileNode]
    public var rootTotalAllocated: UInt64
    public var rootTotalLogical: UInt64
    public var warnings: [String]
    public var isComplete: Bool

    public init(
        rootURLBookmarkID: UUID?,
        rootDisplayName: String,
        options: ScanOptions,
        nodes: [FileNode],
        rootTotalAllocated: UInt64,
        rootTotalLogical: UInt64,
        warnings: [String],
        isComplete: Bool
    ) {
        self.rootURLBookmarkID = rootURLBookmarkID
        self.rootDisplayName = rootDisplayName
        self.options = options
        self.nodes = nodes
        self.rootTotalAllocated = rootTotalAllocated
        self.rootTotalLogical = rootTotalLogical
        self.warnings = warnings
        self.isComplete = isComplete
    }

    public func node(id: NodeID) -> FileNode? {
        let idx = Int(id.rawValue)
        guard nodes.indices.contains(idx) else { return nil }
        return nodes[idx]
    }

    public func children(of parent: NodeID) -> [NodeID] {
        nodes.enumerated().compactMap { index, node in
            node.parentID == parent ? NodeID(rawValue: UInt32(index)) : nil
        }
    }

    public func breadcrumb(to selected: NodeID) -> [NodeID] {
        var out: [NodeID] = []
        var current = selected
        while current != .invalid, let n = node(id: current) {
            out.append(current)
            if current == .root { break }
            current = n.parentID
        }
        return out.reversed()
    }
}
