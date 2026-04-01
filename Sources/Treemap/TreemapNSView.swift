import AppKit
import Core
import Foundation

/// AppKit surface for treemap drawing, hit-testing, and zoom (drill-down).
public final class TreemapNSView: NSView {
    public var session: ScanSession? {
        didSet {
            let newPath = session?.node(id: .root)?.path
            let oldPath = oldValue?.node(id: .root)?.path
            if newPath != oldPath {
                zoomStack = [.root]
                selectedNodeID = nil
                onBreadcrumbChange?(zoomStack)
            }
            rebuildTiles()
            needsDisplay = true
        }
    }

    public var metric: SizeMetric = .allocated {
        didSet { if oldValue != metric { rebuildTiles(); needsDisplay = true } }
    }

    /// Zoom stack: first is always `.root`.
    public private(set) var zoomStack: [NodeID] = [.root] {
        didSet { rebuildTiles(); needsDisplay = true }
    }

    public var onSelectionChange: ((NodeID?) -> Void)?
    public var onZoomChange: ((NodeID) -> Void)?
    public var onBreadcrumbChange: (([NodeID]) -> Void)?

    private var tiles: [TreemapTile] = []
    public private(set) var selectedNodeID: NodeID?

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    public func resetZoom() {
        zoomStack = [.root]
        selectedNodeID = nil
        onSelectionChange?(nil)
        onZoomChange?(.root)
        onBreadcrumbChange?(zoomStack)
    }

    public func zoomInto(_ id: NodeID) {
        guard let s = session, let node = s.node(id: id) else { return }
        if id == zoomStack.last { return }
        let hasKids = !s.children(of: id).isEmpty
        if hasKids || node.kind == .root {
            zoomStack.append(id)
            selectedNodeID = id
            onSelectionChange?(id)
            onZoomChange?(id)
            onBreadcrumbChange?(zoomStack)
        }
    }

    public func zoomOut() {
        guard zoomStack.count > 1 else { return }
        zoomStack.removeLast()
        let top = zoomStack.last ?? .root
        selectedNodeID = top
        onSelectionChange?(top)
        onZoomChange?(top)
        onBreadcrumbChange?(zoomStack)
    }

    private func rebuildTiles() {
        guard let s = session else {
            tiles = []
            return
        }
        let parent = zoomStack.last ?? .root
        tiles = TreemapLayoutEngine.layout(session: s, parent: parent, metric: metric)
    }

    public override func layout() {
        super.layout()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let s = session else { return }
        let bounds = self.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        bounds.fill()

        for tile in tiles {
            guard let node = s.node(id: tile.nodeID) else { continue }
            let r = rectInView(tile.rect, bounds: bounds)
            if r.width < 0.5 || r.height < 0.5 { continue }
            let path = NSBezierPath(rect: r)
            TreemapColorPalette.color(for: node).setFill()
            path.fill()
            TreemapColorPalette.strokeColor().setStroke()
            path.lineWidth = 0.5
            path.stroke()

            if tile.nodeID == selectedNodeID {
                TreemapColorPalette.highlightOverlay().setFill()
                path.fill()
            }
        }
    }

    private func rectInView(_ n: NormalizedRect, bounds: CGRect) -> CGRect {
        CGRect(
            x: n.x * bounds.width,
            y: n.y * bounds.height,
            width: n.width * bounds.width,
            height: n.height * bounds.height
        )
    }

    private func normalizedPoint(_ point: CGPoint, bounds: CGRect) -> (Double, Double) {
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        return (Double(point.x / bounds.width), Double(point.y / bounds.height))
    }

    private func hitTestTile(at viewPoint: CGPoint) -> TreemapTile? {
        let b = bounds
        let (nx, ny) = normalizedPoint(viewPoint, bounds: b)
        for tile in tiles {
            let r = tile.rect
            if nx >= r.x, nx <= r.x + r.width, ny >= r.y, ny <= r.y + r.height {
                return tile
            }
        }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestTile(at: p) else {
            selectedNodeID = nil
            onSelectionChange?(nil)
            needsDisplay = true
            return
        }
        selectedNodeID = hit.nodeID
        onSelectionChange?(hit.nodeID)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestTile(at: p), let s = session else { return }
        let id = hit.nodeID
        let kids = s.children(of: id)
        if !kids.isEmpty || s.node(id: id)?.kind == .root {
            zoomInto(id)
        }
    }
}
