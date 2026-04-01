import Foundation

/// Mutable builder for arena-backed nodes; produces immutable `ScanSession` snapshots.
public struct ScanNodeArena {
    private var nodes: [FileNode] = []

    public init() {}

    public mutating func reset(rootName: String, rootPath: String) {
        let rootNode = FileNode(
            parentID: .invalid,
            kind: .root,
            name: rootName,
            path: rootPath,
            logicalSize: 0,
            allocatedSize: 0,
            childCount: 0,
            isPackage: false,
            mayShareContent: false,
            isSparse: false,
            isPurgeable: false,
            allowedActions: [.revealInFinder]
        )
        nodes = [rootNode]
    }

    public var count: Int { nodes.count }

    public mutating func addChild(
        parent: NodeID,
        kind: FileKind,
        name: String,
        path: String,
        logicalSize: UInt64,
        allocatedSize: UInt64,
        isPackage: Bool,
        mayShareContent: Bool,
        isSparse: Bool,
        isPurgeable: Bool,
        writeAccess: Bool
    ) -> NodeID {
        let id = NodeID(rawValue: UInt32(nodes.count))
        let actions = ActionCapability.derive(writeAccess: writeAccess, kind: kind)
        if let pIndex = Int(exactly: parent.rawValue), nodes.indices.contains(pIndex) {
            nodes[pIndex].childCount += 1
        }
        let node = FileNode(
            parentID: parent,
            kind: kind,
            name: name,
            path: path,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            childCount: 0,
            isPackage: isPackage,
            mayShareContent: mayShareContent,
            isSparse: isSparse,
            isPurgeable: isPurgeable,
            allowedActions: Set(actions.filter(\.isEnabled).map(\.action))
        )
        nodes.append(node)
        return id
    }

    /// Recompute directory totals bottom-up (allocated and logical).
    public mutating func aggregateTotals() {
        guard !nodes.isEmpty else { return }
        var logical = nodes.map(\.logicalSize)
        var allocated = nodes.map(\.allocatedSize)
        for i in (1 ..< nodes.count).reversed() {
            let p = Int(nodes[i].parentID.rawValue)
            if p >= 0, p < nodes.count {
                logical[p] += logical[i]
                allocated[p] += allocated[i]
            }
        }
        for i in nodes.indices {
            if nodes[i].kind == .directory || nodes[i].kind == .root {
                nodes[i].logicalSize = logical[i]
                nodes[i].allocatedSize = allocated[i]
            }
        }
    }

    public func makeSnapshot(
        rootBookmarkID: UUID?,
        rootDisplayName: String,
        options: ScanOptions,
        warnings: [String],
        isComplete: Bool
    ) -> ScanSession {
        let rootAlloc = nodes.first?.allocatedSize ?? 0
        let rootLog = nodes.first?.logicalSize ?? 0
        return ScanSession(
            rootURLBookmarkID: rootBookmarkID,
            rootDisplayName: rootDisplayName,
            options: options,
            nodes: nodes,
            rootTotalAllocated: rootAlloc,
            rootTotalLogical: rootLog,
            warnings: warnings,
            isComplete: isComplete
        )
    }
}

extension ActionCapability {
    public static func derive(writeAccess: Bool, kind: FileKind) -> [ActionCapability] {
        let canOpen = kind != .root
        var caps: [ActionCapability] = [
            ActionCapability(action: .revealInFinder, isEnabled: canOpen, denialReason: canOpen ? nil : "Nothing to reveal."),
            ActionCapability(action: .open, isEnabled: canOpen && (kind == .file || kind == .packageLeaf), denialReason: openReason(kind: kind)),
        ]
        let trashEnabled = writeAccess && canOpen && (kind == .file || kind == .packageLeaf || kind == .directory)
        caps.append(ActionCapability(
            action: .moveToTrash,
            isEnabled: trashEnabled,
            denialReason: trashEnabled ? nil : (writeAccess ? "Cannot move this item." : "No write access to this location (sandbox).")
        ))
        caps.append(ActionCapability(
            action: .moveToLocation,
            isEnabled: trashEnabled,
            denialReason: trashEnabled ? nil : (writeAccess ? nil : "No write access to this location (sandbox).")
        ))
        return caps
    }

    private static func openReason(kind: FileKind) -> String? {
        switch kind {
        case .file, .packageLeaf: return nil
        case .directory: return "Use Reveal in Finder for folders."
        case .root: return "Nothing to open."
        }
    }
}
