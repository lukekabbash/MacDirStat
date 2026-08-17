import Foundation

public enum FileKind: String, Codable, Sendable {
    case root
    case directory
    case file
    case packageLeaf
}

/// Single node in the arena-backed tree. Immutable after snapshot commit.
public struct FileNode: Equatable, Sendable, Codable {
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

    private enum CodingKeys: String, CodingKey {
        case parentID
        case kind
        case name
        case path
        case logicalSize
        case allocatedSize
        case childCount
        case firstChildID
        case nextSiblingID
        case isPackage
        case mayShareContent
        case isSparse
        case isPurgeable
        case allowedActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parentID = try container.decode(NodeID.self, forKey: .parentID)
        kind = try container.decode(FileKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        logicalSize = try container.decode(UInt64.self, forKey: .logicalSize)
        allocatedSize = try container.decode(UInt64.self, forKey: .allocatedSize)
        childCount = try container.decode(UInt32.self, forKey: .childCount)
        firstChildID = try container.decode(NodeID.self, forKey: .firstChildID)
        nextSiblingID = try container.decode(NodeID.self, forKey: .nextSiblingID)
        isPackage = try container.decode(Bool.self, forKey: .isPackage)
        mayShareContent = try container.decode(Bool.self, forKey: .mayShareContent)
        isSparse = try container.decode(Bool.self, forKey: .isSparse)
        isPurgeable = try container.decode(Bool.self, forKey: .isPurgeable)
        allowedActions = try container.decodeIfPresent(Set<CleanupAction>.self, forKey: .allowedActions) ?? []
        allowedActions.remove(.moveToTrash)
        allowedActions.remove(.moveToLocation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parentID, forKey: .parentID)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(logicalSize, forKey: .logicalSize)
        try container.encode(allocatedSize, forKey: .allocatedSize)
        try container.encode(childCount, forKey: .childCount)
        try container.encode(firstChildID, forKey: .firstChildID)
        try container.encode(nextSiblingID, forKey: .nextSiblingID)
        try container.encode(isPackage, forKey: .isPackage)
        try container.encode(mayShareContent, forKey: .mayShareContent)
        try container.encode(isSparse, forKey: .isSparse)
        try container.encode(isPurgeable, forKey: .isPurgeable)
        let readOnlyActions = allowedActions.subtracting([.moveToTrash, .moveToLocation])
        try container.encode(readOnlyActions, forKey: .allowedActions)
    }

    public func size(for metric: SizeMetric) -> UInt64 {
        switch metric {
        case .allocated: return allocatedSize
        case .logical: return logicalSize
        }
    }
}
