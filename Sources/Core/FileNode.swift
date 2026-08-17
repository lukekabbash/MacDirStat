import Foundation

public enum FileKind: String, Codable, Sendable {
    case root
    case directory
    case file
    case packageLeaf
}

/// Single node in the arena-backed tree. Immutable after snapshot commit.
public struct FileNode: Equatable, Sendable {
    public var parentID: NodeID
    public var kind: FileKind
    /// Display name (last path component).
    public var name: String
    /// Full path for actions and reveal; may be empty for synthetic nodes.
    public var path: String
    public var logicalSize: UInt64
    public var allocatedSize: UInt64
    public var childCount: UInt32
    /// Direct-child index for O(child-count) tree navigation. `.invalid` means none.
    public var firstChildID: NodeID
    /// Linked-list successor among a parent's direct children.
    public var nextSiblingID: NodeID
    public var isPackage: Bool
    public var mayShareContent: Bool
    public var isSparse: Bool
    public var isPurgeable: Bool
    public var allowedActions: Set<CleanupAction>

    public init(
        parentID: NodeID,
        kind: FileKind,
        name: String,
        path: String,
        logicalSize: UInt64,
        allocatedSize: UInt64,
        childCount: UInt32,
        firstChildID: NodeID = .invalid,
        nextSiblingID: NodeID = .invalid,
        isPackage: Bool,
        mayShareContent: Bool,
        isSparse: Bool,
        isPurgeable: Bool,
        allowedActions: Set<CleanupAction>
    ) {
        self.parentID = parentID
        self.kind = kind
        self.name = name
        self.path = path
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.childCount = childCount
        self.firstChildID = firstChildID
        self.nextSiblingID = nextSiblingID
        self.isPackage = isPackage
        self.mayShareContent = mayShareContent
        self.isSparse = isSparse
        self.isPurgeable = isPurgeable
        self.allowedActions = allowedActions
    }

    public func size(for metric: SizeMetric) -> UInt64 {
        switch metric {
        case .allocated: return allocatedSize
        case .logical: return logicalSize
        }
    }
}
