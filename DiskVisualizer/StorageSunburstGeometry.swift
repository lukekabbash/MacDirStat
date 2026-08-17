import AppKit
import Core

struct SunburstRasterSignature: Equatable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let scale: CGFloat
}

struct SunburstRenderLayout {
    let center: CGPoint
    let innerRadius: CGFloat
    let ringWidth: CGFloat
    let ringGap: CGFloat
    let deepestDepth: Int

    init(bounds: CGRect, deepestDepth: Int) {
        let outerRadius = max(28, min(bounds.width, bounds.height) * 0.47)
        let resolvedDepth = max(1, deepestDepth)
        let targetCenter = max(34, min(70, outerRadius * 0.29))
        let gap = max(2, min(4, outerRadius * 0.022))
        let available = max(
            CGFloat(resolvedDepth) * 8,
            outerRadius - targetCenter - gap * CGFloat(resolvedDepth - 1)
        )
        center = CGPoint(x: bounds.midX, y: bounds.midY)
        innerRadius = targetCenter
        ringWidth = available / CGFloat(resolvedDepth)
        ringGap = gap
        self.deepestDepth = resolvedDepth
    }

    func radii(for depth: Int) -> (inner: CGFloat, outer: CGFloat) {
        let index = max(0, depth - 1)
        let inner = innerRadius + CGFloat(index) * (ringWidth + ringGap)
        return (inner, inner + ringWidth)
    }

    func depth(at point: CGPoint) -> Int? {
        let distance = hypot(point.x - center.x, point.y - center.y)
        for depth in 1 ... deepestDepth {
            let radii = radii(for: depth)
            if distance >= radii.inner, distance <= radii.outer { return depth }
        }
        return nil
    }

    func angleFraction(at point: CGPoint) -> Double {
        let angle = Double(atan2(point.y - center.y, point.x - center.x)) + Double.pi / 2
        let normalized = angle / (Double.pi * 2)
        return normalized < 0 ? normalized + 1 : normalized
    }
}

struct SunburstArcGeometry {
    let segment: StorageHierarchySegment
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startFraction: Double
    let endFraction: Double

    init(segment: StorageHierarchySegment, layout: SunburstRenderLayout) {
        let angularGap = min(0.006, segment.fraction * 0.16)
        let radii = layout.radii(for: segment.depth)
        self.segment = segment
        center = layout.center
        innerRadius = radii.inner + 0.6
        outerRadius = max(radii.inner + 1, radii.outer - 0.6)
        startFraction = segment.startFraction + angularGap / 2
        endFraction = segment.endFraction - angularGap / 2
    }

    func path() -> NSBezierPath {
        let path = NSBezierPath()
        let sweep = max(0, endFraction - startFraction)
        let steps = max(2, min(56, Int(ceil(sweep * 46))))
        path.move(to: point(radius: innerRadius, fraction: startFraction))
        path.line(to: point(radius: outerRadius, fraction: startFraction))

        for step in 1 ... steps {
            let fraction = startFraction + sweep * Double(step) / Double(steps)
            path.line(to: point(radius: outerRadius, fraction: fraction))
        }
        path.line(to: point(radius: innerRadius, fraction: endFraction))
        for step in stride(from: steps - 1, through: 0, by: -1) {
            let fraction = startFraction + sweep * Double(step) / Double(steps)
            path.line(to: point(radius: innerRadius, fraction: fraction))
        }
        path.close()
        return path
    }

    private func point(radius: CGFloat, fraction: Double) -> CGPoint {
        let angle = -Double.pi / 2 + fraction * Double.pi * 2
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
}
