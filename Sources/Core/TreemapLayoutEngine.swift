import Foundation

/// Squarified treemap (Bruls et al.) in normalized coordinates.
public enum TreemapLayoutEngine {
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
        return squarify(
            items: items,
            rect: rect,
            totalValue: total
        )
    }

    private static func squarify(
        items: [(NodeID, Double)],
        rect: NormalizedRect,
        totalValue: Double
    ) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        var queue = items
        var remaining = rect
        var valueLeft = totalValue

        while !queue.isEmpty, valueLeft > 0 {
            var row: [(NodeID, Double)] = []
            var rowSum = 0.0

            func worstAspect(forRow r: [(NodeID, Double)], sum: Double) -> Double {
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

            while let first = queue.first {
                let candidate = row + [first]
                let candidateSum = rowSum + first.1
                if row.isEmpty {
                    row = candidate
                    rowSum = candidateSum
                    queue.removeFirst()
                    continue
                }
                if worstAspect(forRow: candidate, sum: candidateSum) <= worstAspect(forRow: row, sum: rowSum) {
                    row = candidate
                    rowSum = candidateSum
                    queue.removeFirst()
                } else {
                    break
                }
            }

            let horizontal = remaining.width >= remaining.height
            if horizontal {
                let rowHeight = remaining.height * (rowSum / valueLeft)
                var x = remaining.x
                for (id, v) in row {
                    let w = remaining.width * (v / rowSum)
                    tiles.append(TreemapTile(
                        nodeID: id,
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
                for (id, v) in row {
                    let h = remaining.height * (v / rowSum)
                    tiles.append(TreemapTile(
                        nodeID: id,
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
