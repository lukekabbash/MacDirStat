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
        guard let parentNode = node(id: parent), parentNode.firstChildID != .invalid else { return [] }
        var children: [NodeID] = []
        children.reserveCapacity(Int(parentNode.childCount))
        var current = parentNode.firstChildID
        while current != .invalid, let child = node(id: current) {
            children.append(current)
            current = child.nextSiblingID
        }
        return children
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

    /// Returns true when `candidate` is below `ancestor` in the scan tree.
    /// A node is not considered a descendant of itself.
    public func isDescendant(_ candidate: NodeID, of ancestor: NodeID) -> Bool {
        guard candidate != ancestor else { return false }
        var current = candidate
        while current != .invalid, let node = node(id: current) {
            if node.parentID == ancestor { return true }
            current = node.parentID
        }
        return false
    }

    /// Finds the immediate child of `ancestor` that contains `candidate`.
    public func directDescendant(of candidate: NodeID, under ancestor: NodeID) -> NodeID? {
        guard isDescendant(candidate, of: ancestor) else { return nil }
        var current = candidate
        while let node = node(id: current), node.parentID != ancestor {
            current = node.parentID
        }
        return current
    }
}
