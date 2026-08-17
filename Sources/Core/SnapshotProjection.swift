import Foundation

public struct RankedNode: Equatable, Sendable {
    public let nodeID: NodeID
    public let size: UInt64

    public init(nodeID: NodeID, size: UInt64) {
        self.nodeID = nodeID
        self.size = size
    }
}

public enum DirectChildrenRanking {
    public static func make(
        session: ScanSession,
        parent: NodeID,
        metric: SizeMetric,
        limit: Int = 30
    ) -> [RankedNode] {
        rank(
            session.children(of: parent).compactMap { id in
                session.node(id: id).map { RankedNode(nodeID: id, size: $0.size(for: metric)) }
            },
            in: session,
            limit: limit
        )
    }

    fileprivate static func rank(
        _ rows: [RankedNode],
        in session: ScanSession,
        limit: Int
    ) -> [RankedNode] {
        rows.sorted { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            let leftName = session.node(id: lhs.nodeID)?.name.localizedLowercase ?? ""
            let rightName = session.node(id: rhs.nodeID)?.name.localizedLowercase ?? ""
            if leftName != rightName { return leftName < rightName }
            return lhs.nodeID.rawValue < rhs.nodeID.rawValue
        }
        .prefix(max(0, limit))
        .map { $0 }
    }
}

public enum SnapshotSearchRanking {
    public static func make(
        session: ScanSession,
        query: String,
        metric: SizeMetric,
        limit: Int = 60
    ) -> [RankedNode] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let matches = session.nodes.enumerated().compactMap { index, node -> RankedNode? in
            guard index > 0,
                  node.name.localizedCaseInsensitiveContains(needle)
                    || node.path.localizedCaseInsensitiveContains(needle)
            else { return nil }
            return RankedNode(nodeID: NodeID(rawValue: UInt32(index)), size: node.size(for: metric))
        }
        return DirectChildrenRanking.rank(matches, in: session, limit: limit)
    }
}

public struct AppPackageReference: Identifiable, Equatable, Sendable {
    public let sourceLocationID: UUID
    public let snapshotGeneration: UUID
    public let scannedAt: Date
    public let nodeID: NodeID
    public let path: String
    public let fallbackName: String
    public let allocatedSize: UInt64
    public let logicalSize: UInt64
    public let mayShareContent: Bool
    public let isSparse: Bool

    public var id: String { "\(sourceLocationID.uuidString)|\(path)" }

    public func size(for metric: SizeMetric) -> UInt64 {
        metric == .allocated ? allocatedSize : logicalSize
    }
}

public enum AppsProjectionBuilder {
    public static func make(
        locationID: UUID,
        generation: UUID,
        scannedAt: Date,
        session: ScanSession
    ) -> [AppPackageReference] {
        session.nodes.enumerated().compactMap { index, node in
            guard index > 0,
                  node.isPackage,
                  URL(fileURLWithPath: node.path).pathExtension.caseInsensitiveCompare("app") == .orderedSame
            else { return nil }
            return AppPackageReference(
                sourceLocationID: locationID,
                snapshotGeneration: generation,
                scannedAt: scannedAt,
                nodeID: NodeID(rawValue: UInt32(index)),
                path: node.path,
                fallbackName: node.name,
                allocatedSize: node.allocatedSize,
                logicalSize: node.logicalSize,
                mayShareContent: node.mayShareContent,
                isSparse: node.isSparse
            )
        }
    }
}
