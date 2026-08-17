import Foundation

/// Squarified treemap (Bruls et al.) in normalized coordinates.
public enum TreemapLayoutEngine {
    public struct WeightedRect: Equatable, Sendable {
        public var index: Int
        public var rect: NormalizedRect

        public init(index: Int, rect: NormalizedRect) {
            self.index = index
            self.rect = rect
        }
    }

    public static func layout(
        session: ScanSession,
        parent: NodeID,
        metric: SizeMetric,
        rect: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    ) -> [TreemapTile] {
        let childIDs = session.children(of: parent)
        var items: [(NodeID, Double)] = []
        for id in childIDs {
            guard let node = session.node(id: id) else { continue }
            let s = Double(node.size(for: metric))
            if s > 0 { items.append((id, s)) }
        }
        guard !items.isEmpty else { return [] }
        let total = items.reduce(0) { $0 + $1.1 }
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }

        items.sort { $0.1 > $1.1 }
        return weightedRects(
            values: items.map(\.1),
            rect: rect
        ).map { weighted in
            TreemapTile(nodeID: items[weighted.index].0, rect: weighted.rect)
        }
    }

    /// Resolves large branches into file/package leaves while collapsing only
    /// sub-pixel detail. Hierarchy is expressed through containment and small
    /// gutters instead of one opaque tile per directory.
    public static func leafLayout(
        session: ScanSession,
        parent: NodeID,
        metric: SizeMetric,
        rect: NormalizedRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1),
        viewportWidth: Double,
        viewportHeight: Double,
        maximumTiles: Int = 24_000
    ) -> [TreemapTile] {
        guard viewportWidth > 1, viewportHeight > 1, maximumTiles > 0 else { return [] }
        let viewportArea = viewportWidth * viewportHeight
        let minimumTileArea = max(14, viewportArea / Double(maximumTiles))
        var tiles: [TreemapTile] = []
        tiles.reserveCapacity(min(maximumTiles, 8_192))

        func inset(_ source: NormalizedRect, pixels: Double) -> NormalizedRect {
            let dx = min(source.width * 0.18, pixels / viewportWidth)
            let dy = min(source.height * 0.18, pixels / viewportHeight)
            return NormalizedRect(
                x: source.x + dx,
                y: source.y + dy,
                width: max(0, source.width - (2 * dx)),
                height: max(0, source.height - (2 * dy))
            )
        }

        func appendChildren(of parentID: NodeID, in region: NormalizedRect, depth: Int) {
            guard tiles.count < maximumTiles, depth < 96 else {
                tiles.append(TreemapTile(nodeID: parentID, rect: region, isAggregate: true, depth: depth))
                return
            }

            let childValues = session.children(of: parentID).compactMap { id -> (NodeID, Double)? in
                guard let node = session.node(id: id) else { return nil }
                let value = Double(node.size(for: metric))
                return value > 0 ? (id, value) : nil
            }.sorted { $0.1 > $1.1 }

            guard !childValues.isEmpty else {
                if parentID != parent {
                    tiles.append(TreemapTile(nodeID: parentID, rect: region, isAggregate: false, depth: depth))
                }
                return
            }

            let total = childValues.reduce(0) { $0 + $1.1 }
            let regionArea = region.width * viewportWidth * region.height * viewportHeight
            var visible: [(id: NodeID, value: Double, aggregate: Bool)] = []
            var collapsedValue = 0.0

            for child in childValues {
                let projectedArea = regionArea * (child.1 / total)
                if projectedArea < minimumTileArea || visible.count >= maximumTiles - tiles.count - 1 {
                    collapsedValue += child.1
                } else {
                    visible.append((child.0, child.1, false))
                }
            }
            if collapsedValue > 0 {
                visible.append((parentID, collapsedValue, true))
            }

            let rects = weightedRects(values: visible.map(\.value), rect: region)
            for weighted in rects {
                guard tiles.count < maximumTiles else { break }
                let entry = visible[weighted.index]
                let tileRect = weighted.rect

                if entry.aggregate {
                    tiles.append(TreemapTile(
                        nodeID: entry.id,
                        rect: tileRect,
                        isAggregate: true,
                        depth: depth
                    ))
                    continue
                }

                guard let node = session.node(id: entry.id) else { continue }
                let pixelWidth = tileRect.width * viewportWidth
                let pixelHeight = tileRect.height * viewportHeight
                let canResolveBranch = node.kind == .directory
                    && node.childCount > 0
                    && pixelWidth >= 7
                    && pixelHeight >= 7
                    && (pixelWidth * pixelHeight) >= minimumTileArea * 1.8

                if canResolveBranch {
                    let gutter = depth == 0 ? 2.0 : depth == 1 ? 1.0 : 0.4
                    appendChildren(of: entry.id, in: inset(tileRect, pixels: gutter), depth: depth + 1)
                } else {
                    tiles.append(TreemapTile(
                        nodeID: entry.id,
                        rect: tileRect,
                        isAggregate: node.kind == .directory,
                        depth: depth
                    ))
                }
            }
        }

        appendChildren(of: parent, in: rect, depth: 0)
        return tiles
    }

    /// Squarifies arbitrary values and preserves their caller-facing indices.
    public static func weightedRects(
        values: [Double],
        rect: NormalizedRect
    ) -> [WeightedRect] {
        let items = values.enumerated()
            .filter { $0.element > 0 && $0.element.isFinite }
            .map { ($0.offset, $0.element) }
            .sorted { $0.1 > $1.1 }
        let totalValue = items.reduce(0) { $0 + $1.1 }
        guard totalValue > 0, rect.width > 0, rect.height > 0 else { return [] }

        var tiles: [WeightedRect] = []
        var nextItemIndex = 0
        var remaining = rect
        var valueLeft = totalValue

        while nextItemIndex < items.count, valueLeft > 0 {
            var row: [(Int, Double)] = []
            var rowSum = 0.0

            func worstAspect(forRow r: [(Int, Double)], sum: Double) -> Double {
                guard !r.isEmpty, sum > 0 else { return .infinity }
                let horizontal = remaining.width >= remaining.height
                let short = horizontal ? remaining.height : remaining.width
                let long = horizontal ? remaining.width : remaining.height
                let thickness = short * (sum / valueLeft)
                var worst = 0.0
                for (_, v) in r {
                    let length = long * (v / sum)
                    let a = max(thickness, length)
                    let b = min(thickness, length)
                    if b > 0 { worst = max(worst, a / b) }
                }
                return worst
            }

            while nextItemIndex < items.count {
                let candidate = items[nextItemIndex]
                let candidateSum = rowSum + candidate.1
                if row.isEmpty {
                    row.append(candidate)
                    rowSum = candidateSum
                    nextItemIndex += 1
                    continue
                }

                let currentWorst = worstAspect(forRow: row, sum: rowSum)
                row.append(candidate)
                if worstAspect(forRow: row, sum: candidateSum) <= currentWorst {
                    rowSum = candidateSum
                    nextItemIndex += 1
                } else {
                    row.removeLast()
                    break
                }
            }

            let horizontal = remaining.width >= remaining.height
            if horizontal {
                let rowHeight = remaining.height * (rowSum / valueLeft)
                var x = remaining.x
                for (index, v) in row {
                    let w = remaining.width * (v / rowSum)
                    tiles.append(WeightedRect(
                        index: index,
                        rect: NormalizedRect(x: x, y: remaining.y, width: w, height: rowHeight)
                    ))
                    x += w
                }
                remaining = NormalizedRect(
                    x: remaining.x,
                    y: remaining.y + rowHeight,
                    width: remaining.width,
                    height: max(0, remaining.height - rowHeight)
                )
            } else {
                let rowWidth = remaining.width * (rowSum / valueLeft)
                var y = remaining.y
                for (index, v) in row {
                    let h = remaining.height * (v / rowSum)
                    tiles.append(WeightedRect(
                        index: index,
                        rect: NormalizedRect(x: remaining.x, y: y, width: rowWidth, height: h)
                    ))
                    y += h
                }
                remaining = NormalizedRect(
                    x: remaining.x + rowWidth,
                    y: remaining.y,
                    width: max(0, remaining.width - rowWidth),
                    height: remaining.height
                )
            }
            valueLeft -= rowSum
        }

        return tiles
    }
}
