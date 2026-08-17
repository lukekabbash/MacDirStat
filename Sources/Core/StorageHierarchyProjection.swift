import Foundation

/// One visible arc in a bounded hierarchy projection. Angles are normalized
/// into the unit interval so visual clients can lay the same data out at any
/// size without touching the scan tree again.
public struct StorageHierarchySegment: Identifiable, Equatable, Sendable {
    public let nodeID: NodeID
    public let parentID: NodeID
    /// The first visible ring is depth 1; the projection root is its center.
    public let depth: Int
    public let startFraction: Double
    public let endFraction: Double
    public let size: UInt64
    public let hasChildren: Bool

    public var id: NodeID { nodeID }

    public init(
        nodeID: NodeID,
        parentID: NodeID,
        depth: Int,
        startFraction: Double,
        endFraction: Double,
        size: UInt64,
        hasChildren: Bool
    ) {
        self.nodeID = nodeID
        self.parentID = parentID
        self.depth = depth
        self.startFraction = startFraction
        self.endFraction = endFraction
        self.size = size
        self.hasChildren = hasChildren
    }

    public var fraction: Double { max(0, endFraction - startFraction) }
}

/// A compact, display-ready slice of one immutable scan tree. It deliberately
/// limits depth and segment count; deeper structure is reached by changing the
/// projection root instead of rendering an unreadable all-disk radial chart.
public struct StorageHierarchyProjection: Equatable, Sendable {
    public let rootID: NodeID
    public let metric: SizeMetric
    public let rootSize: UInt64
    public let maximumDepth: Int
    /// True when the bounded projection leaves measurable descendants out of
    /// individual arcs. Clients should explain that visible gaps are not free
    /// disk space.
    public let hasOmittedSegments: Bool
    /// Direct children of the current root, ordered once on the worker that
    /// built the projection. UI navigators can use this without re-sorting.
    public let directChildren: [NodeID]
    public let segments: [StorageHierarchySegment]

    public init(
        rootID: NodeID,
        metric: SizeMetric,
        rootSize: UInt64,
        maximumDepth: Int,
        hasOmittedSegments: Bool,
        directChildren: [NodeID],
        segments: [StorageHierarchySegment]
    ) {
        self.rootID = rootID
        self.metric = metric
        self.rootSize = rootSize
        self.maximumDepth = maximumDepth
        self.hasOmittedSegments = hasOmittedSegments
        self.directChildren = directChildren
        self.segments = segments
    }

    public var deepestVisibleDepth: Int {
        segments.map(\.depth).max() ?? 0
    }

    public var representedRootSize: UInt64 {
        segments.lazy.filter { $0.depth == 1 }.reduce(into: UInt64(0)) { total, segment in
            let (sum, overflow) = total.addingReportingOverflow(segment.size)
            total = overflow ? UInt64.max : sum
        }
    }

    public var representedRootFraction: Double {
        guard rootSize > 0 else { return 0 }
        return min(1, Double(representedRootSize) / Double(rootSize))
    }

    public func contains(_ nodeID: NodeID) -> Bool {
        nodeID == rootID || segments.contains { $0.nodeID == nodeID }
    }
}

/// Builds a radial hierarchy without mutating or reindexing a `ScanSession`.
/// Work is intentionally pure and Sendable so UI callers can prepare it on a
/// detached task, then use the result for cached drawing and hit testing.
public enum StorageHierarchyBuilder {
    private struct RankedChild {
        let id: NodeID
        let size: UInt64
    }

    public static func make(
        in session: ScanSession,
        root: NodeID = .root,
        metric: SizeMetric,
        maximumDepth: Int = 4,
        segmentLimit: Int = 1_200,
        minimumVisibleFraction: Double = 0.0015
    ) -> StorageHierarchyProjection {
        guard let rootNode = session.node(id: root) else {
            return emptyProjection(root: root, metric: metric, maximumDepth: maximumDepth)
        }

        let safeMaximumDepth = max(1, maximumDepth)
        let safeSegmentLimit = max(1, segmentLimit)
        let minimumFraction = min(1, max(0, minimumVisibleFraction))
        let rootSize = rootNode.size(for: metric)
        guard rootSize > 0 else {
            return StorageHierarchyProjection(
                rootID: root,
                metric: metric,
                rootSize: 0,
                maximumDepth: safeMaximumDepth,
                hasOmittedSegments: false,
                directChildren: [],
                segments: []
            )
        }

        struct PendingBranch {
            let id: NodeID
            let depth: Int
            let start: Double
            let end: Double
        }

        var pending = [PendingBranch(id: root, depth: 0, start: 0, end: 1)]
        let directChildren = orderedChildren(
            of: root,
            in: session,
            metric: metric,
            limit: safeSegmentLimit
        )
        var hasOmittedSegments = Int(rootNode.childCount) > directChildren.count
        var cursor = 0
        var segments: [StorageHierarchySegment] = []
        segments.reserveCapacity(min(safeSegmentLimit, 256))

        while cursor < pending.count, segments.count < safeSegmentLimit {
            if cursor.isMultiple(of: 128), Task.isCancelled { break }

            let branch = pending[cursor]
            cursor += 1
            guard let parent = session.node(id: branch.id) else { continue }
            guard branch.depth < safeMaximumDepth else {
                if parent.childCount > 0 { hasOmittedSegments = true }
                continue
            }

            let parentSize = parent.size(for: metric)
            guard parentSize > 0 else { continue }

            let children = branch.id == root
                ? directChildren
                : orderedChildren(
                    of: branch.id,
                    in: session,
                    metric: metric,
                    limit: safeSegmentLimit - segments.count
                )
            if Int(parent.childCount) > children.count {
                hasOmittedSegments = true
            }
            guard !children.isEmpty else { continue }

            let span = branch.end - branch.start
            var childStart = branch.start
            for childID in children {
                guard segments.count < safeSegmentLimit,
                      let child = session.node(id: childID)
                else { break }

                let childSize = child.size(for: metric)
                guard childSize > 0 else { continue }

                let expectedSpan = span * Double(childSize) / Double(parentSize)
                let childEnd = min(branch.end, childStart + expectedSpan)
                let childSpan = max(0, childEnd - childStart)
                defer { childStart = childEnd }

                guard childSpan >= minimumFraction else {
                    hasOmittedSegments = true
                    continue
                }

                let segment = StorageHierarchySegment(
                    nodeID: childID,
                    parentID: branch.id,
                    depth: branch.depth + 1,
                    startFraction: childStart,
                    endFraction: childEnd,
                    size: childSize,
                    hasChildren: child.childCount > 0
                )
                segments.append(segment)

                if child.childCount > 0 {
                    pending.append(PendingBranch(
                        id: childID,
                        depth: branch.depth + 1,
                        start: childStart,
                        end: childEnd
                    ))
                }
            }
        }

        if cursor < pending.count { hasOmittedSegments = true }

        return StorageHierarchyProjection(
            rootID: root,
            metric: metric,
            rootSize: rootSize,
            maximumDepth: safeMaximumDepth,
            hasOmittedSegments: hasOmittedSegments,
            directChildren: directChildren,
            segments: segments
        )
    }

    private static func orderedChildren(
        of parentID: NodeID,
        in session: ScanSession,
        metric: SizeMetric,
        limit: Int
    ) -> [NodeID] {
        guard limit > 0,
              let parent = session.node(id: parentID),
              parent.firstChildID != .invalid
        else { return [] }

        var heap: [RankedChild] = []
        heap.reserveCapacity(min(Int(parent.childCount), limit))
        var current = parent.firstChildID
        var inspected = 0

        while current != .invalid, let child = session.node(id: current) {
            if inspected.isMultiple(of: 256), Task.isCancelled { return [] }
            inspected += 1

            let candidate = RankedChild(id: current, size: child.size(for: metric))
            if candidate.size > 0 {
                if heap.count < limit {
                    heap.append(candidate)
                    siftWorstUp(in: &heap, from: heap.count - 1)
                } else if ranksBefore(candidate, heap[0]) {
                    heap[0] = candidate
                    siftWorstDown(in: &heap, from: 0)
                }
            }
            current = child.nextSiblingID
        }

        return heap.sorted(by: ranksBefore).map(\.id)
    }

    /// Keeps the least desirable retained child at the root, allowing a
    /// bounded top-K pass over directories with very large fan-out.
    private static func siftWorstUp(in heap: inout [RankedChild], from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard ranksAfter(heap[child], heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private static func siftWorstDown(in heap: inout [RankedChild], from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worseChild = left
            if right < heap.count, ranksAfter(heap[right], heap[left]) {
                worseChild = right
            }
            guard ranksAfter(heap[worseChild], heap[parent]) else { return }
            heap.swapAt(parent, worseChild)
            parent = worseChild
        }
    }

    private static func ranksBefore(_ lhs: RankedChild, _ rhs: RankedChild) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func ranksAfter(_ lhs: RankedChild, _ rhs: RankedChild) -> Bool {
        if lhs.size != rhs.size { return lhs.size < rhs.size }
        return lhs.id.rawValue > rhs.id.rawValue
    }

    private static func emptyProjection(
        root: NodeID,
        metric: SizeMetric,
        maximumDepth: Int
    ) -> StorageHierarchyProjection {
        StorageHierarchyProjection(
            rootID: root,
            metric: metric,
            rootSize: 0,
            maximumDepth: max(1, maximumDepth),
            hasOmittedSegments: false,
            directChildren: [],
            segments: []
        )
    }
}
