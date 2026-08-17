import AppKit
import Core
import Foundation
import QuartzCore

/// High-throughput treemap surface. The static mosaic is cached; pointer and
/// selection states redraw only their small overlays.
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
        }
    }

    public var metric: SizeMetric = .allocated {
        didSet {
            guard oldValue != metric else { return }
            if animatesMetricChanges {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.16
                transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer?.add(transition, forKey: "metric-crossfade")
            }
            rebuildTiles()
        }
    }

    public var animatesMetricChanges = true

    public var colorMode: TreemapColorMode = .fileCategory {
        didSet { if oldValue != colorMode { invalidateBaseImage() } }
    }

    public var capacityContext: TreemapCapacityContext? {
        didSet { if oldValue != capacityContext { rebuildTiles() } }
    }

    public var showsCapacityContext = false {
        didSet { if oldValue != showsCapacityContext { rebuildTiles() } }
    }

    public var renderTheme: TreemapRenderTheme = .system {
        didSet {
            guard oldValue.token != renderTheme.token else { return }
            invalidateBaseImage()
        }
    }

    /// Zoom stack: first is always `.root`.
    public private(set) var zoomStack: [NodeID] = [.root] {
        didSet { rebuildTiles() }
    }

    public var onSelectionChange: ((NodeID?) -> Void)?
    public var onZoomChange: ((NodeID) -> Void)?
    public var onBreadcrumbChange: (([NodeID]) -> Void)?
    public var onHoverChange: ((NodeID?) -> Void)?

    private var tiles: [TreemapTile] = []
    public private(set) var selectedNodeID: NodeID?
    private var hoveredTileIndex: Int?
    private var trackingArea: NSTrackingArea?
    private var lastLayoutSize: CGSize = .zero
    private var baseImage: NSImage?
    private var hitBuckets: [[Int]] = []
    private var tileIndicesByNodeID: [NodeID: [Int]] = [:]
    private var tileViewRects: [CGRect] = []
    private var pendingHoverCallback: DispatchWorkItem?
    private let hitGridColumns = 72
    private let hitGridRows = 48
    private let hoverReadoutDelay: TimeInterval = 0.035

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    public func setSelectedNodeID(_ id: NodeID?) {
        let validID = id.flatMap { session?.node(id: $0) == nil ? nil : $0 }
        guard validID != selectedNodeID else { return }
        let previousID = selectedNodeID
        selectedNodeID = validID
        invalidateInteraction(nodeIDs: [previousID, validID])
    }

    public func resetZoom() {
        zoomStack = [.root]
        selectedNodeID = nil
        onSelectionChange?(nil)
        onZoomChange?(.root)
        onBreadcrumbChange?(zoomStack)
    }

    public func zoomInto(_ id: NodeID) {
        guard let session, let node = session.node(id: id), id != zoomStack.last else { return }
        if node.childCount > 0 || node.kind == .root {
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

    public override func layout() {
        super.layout()
        let size = bounds.size
        if abs(size.width - lastLayoutSize.width) > 1 || abs(size.height - lastLayoutSize.height) > 1 {
            lastLayoutSize = size
            rebuildTiles()
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateBaseImage()
    }

    private func rebuildTiles() {
        guard let session, bounds.width > 1, bounds.height > 1 else {
            tiles = []
            rebuildHitGrid()
            invalidateBaseImage()
            return
        }

        let parent = zoomStack.last.flatMap { session.node(id: $0) == nil ? nil : $0 } ?? .root
        if parent != zoomStack.last {
            zoomStack = [.root]
            onBreadcrumbChange?(zoomStack)
            return
        }

        let fullRect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        if showsCapacityContext, parent == .root, let context = capacityContext, context.capacity > 0 {
            tiles = capacityTiles(session: session, context: context, fullRect: fullRect)
        } else {
            tiles = TreemapLayoutEngine.leafLayout(
                session: session,
                parent: parent,
                metric: metric,
                rect: fullRect,
                viewportWidth: bounds.width,
                viewportHeight: bounds.height
            )
        }
        hoveredTileIndex = nil
        pendingHoverCallback?.cancel()
        pendingHoverCallback = nil
        rebuildHitGrid()
        invalidateBaseImage()
    }

    private func capacityTiles(
        session: ScanSession,
        context: TreemapCapacityContext,
        fullRect: NormalizedRect
    ) -> [TreemapTile] {
        let values = [
            Double(context.mappedUsed),
            Double(context.usedOutsideScan),
            Double(context.available),
        ]
        let partitions = TreemapLayoutEngine.weightedRects(values: values, rect: fullRect)
        var result: [TreemapTile] = []
        for partition in partitions {
            switch partition.index {
            case 0:
                result.append(contentsOf: TreemapLayoutEngine.leafLayout(
                    session: session,
                    parent: .root,
                    metric: metric,
                    rect: partition.rect,
                    viewportWidth: bounds.width,
                    viewportHeight: bounds.height
                ))
            case 1:
                result.append(TreemapTile(
                    nodeID: .invalid,
                    rect: partition.rect,
                    isAggregate: true,
                    role: .usedOutsideScan
                ))
            case 2:
                result.append(TreemapTile(
                    nodeID: .invalid,
                    rect: partition.rect,
                    role: .freeSpace
                ))
            default:
                break
            }
        }
        return result
    }

    private func invalidateBaseImage() {
        baseImage = nil
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let session, bounds.width > 1, bounds.height > 1 else { return }

        if baseImage == nil {
            baseImage = renderBaseImage(session: session, size: bounds.size)
        }
        // The view and the cached image both use top-left coordinates. Respecting
        // that flipped orientation keeps painted cells, labels, and hit regions
        // on the same geometry instead of mirroring the bitmap vertically.
        baseImage?.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        if let hoveredTileIndex, tiles.indices.contains(hoveredTileIndex) {
            drawInteractionOverlay(for: tiles[hoveredTileIndex], selected: false)
        }
        if let selectedNodeID {
            for index in tileIndicesByNodeID[selectedNodeID] ?? [] where tiles.indices.contains(index) {
                drawInteractionOverlay(for: tiles[index], selected: true)
            }
        }
    }

    private func renderBaseImage(session: ScanSession, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { [weak self] imageBounds in
            guard let self else { return false }
            self.renderTheme.canvas.setFill()
            imageBounds.fill()

            for tile in self.tiles {
                let rect = self.rectInView(tile.rect, bounds: imageBounds)
                guard rect.width >= 0.35, rect.height >= 0.35 else { continue }
                self.drawBaseTile(tile, in: rect, session: session)
            }
            return true
        }
    }

    private func drawBaseTile(_ tile: TreemapTile, in rect: CGRect, session: ScanSession) {
        let tileRect = visibleTileRect(from: rect)
        let radius = min(1.25, min(tileRect.width, tileRect.height) * 0.12)
        let path = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)

        switch tile.role {
        case .node:
            guard let node = session.node(id: tile.nodeID) else { return }
            let fillColor = TreemapColorPalette.color(
                for: node,
                nodeID: tile.nodeID,
                session: session,
                mode: colorMode,
                scope: zoomStack.last ?? .root
            )
            fillColor.setFill()
            path.fill()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(
                starting: NSColor.white.withAlphaComponent(0.055),
                ending: NSColor.black.withAlphaComponent(0.075)
            )?.draw(in: tileRect, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
            renderTheme.tileStroke.setStroke()
            path.lineWidth = tile.depth < 2 ? 0.55 : 0.35
            path.stroke()
        case .freeSpace:
            renderTheme.availableFill.setFill()
            path.fill()
            renderTheme.availableStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
            drawSyntheticLabel(title: "Available", value: capacityContext?.available ?? 0, in: rect)
        case .usedOutsideScan:
            renderTheme.neutralFill.setFill()
            path.fill()
            renderTheme.neutralStroke.setStroke()
            path.lineWidth = 1
            path.stroke()
            drawSyntheticLabel(title: "Used outside this scan", value: capacityContext?.usedOutsideScan ?? 0, in: rect)
        }
    }

    private func drawInteractionOverlay(for tile: TreemapTile, selected: Bool) {
        let rect = rectInView(tile.rect, bounds: bounds)
        let tileRect = visibleTileRect(from: rect)
        let radius = min(1.25, min(tileRect.width, tileRect.height) * 0.12)
        let path = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
        if selected {
            renderTheme.selectionFill.setFill()
            path.fill()
            renderTheme.selectionStroke.setStroke()
            path.lineWidth = 2
            path.stroke()
        } else {
            renderTheme.hoverFill.setFill()
            path.fill()
        }
    }

    private func drawSyntheticLabel(title: String, value: UInt64, in rect: CGRect) {
        guard rect.width >= 108, rect.height >= 44 else { return }
        let labelRect = rect.insetBy(dx: 9, dy: 8)
        (title as NSString).draw(
            in: CGRect(x: labelRect.minX, y: labelRect.minY, width: labelRect.width, height: 17),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        guard rect.height >= 62 else { return }
        (formattedBytes(value) as NSString).draw(
            in: CGRect(x: labelRect.minX, y: labelRect.minY + 18, width: labelRect.width, height: 15),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
    }

    private func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    private func rectInView(_ normalized: NormalizedRect, bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + normalized.x * bounds.width,
            y: bounds.minY + normalized.y * bounds.height,
            width: normalized.width * bounds.width,
            height: normalized.height * bounds.height
        )
    }

    private func visibleTileRect(from rect: CGRect) -> CGRect {
        let insetAmount = min(0.42, min(rect.width, rect.height) * 0.06)
        return rect.insetBy(dx: insetAmount, dy: insetAmount)
    }

    private func rebuildHitGrid() {
        hitBuckets = Array(repeating: [], count: hitGridColumns * hitGridRows)
        tileIndicesByNodeID = [:]
        tileViewRects = tiles.map { visibleTileRect(from: rectInView($0.rect, bounds: bounds)) }
        for (index, tile) in tiles.enumerated() {
            if tile.role == .node {
                tileIndicesByNodeID[tile.nodeID, default: []].append(index)
            }
            let minColumn = max(0, min(hitGridColumns - 1, Int(tile.rect.x * Double(hitGridColumns))))
            let maxColumn = max(0, min(hitGridColumns - 1, Int((tile.rect.x + tile.rect.width) * Double(hitGridColumns))))
            let minRow = max(0, min(hitGridRows - 1, Int(tile.rect.y * Double(hitGridRows))))
            let maxRow = max(0, min(hitGridRows - 1, Int((tile.rect.y + tile.rect.height) * Double(hitGridRows))))
            guard minColumn <= maxColumn, minRow <= maxRow else { continue }
            for row in minRow ... maxRow {
                for column in minColumn ... maxColumn {
                    hitBuckets[(row * hitGridColumns) + column].append(index)
                }
            }
        }
    }

    private func hitTestTileIndex(at point: CGPoint) -> Int? {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(point),
              !hitBuckets.isEmpty
        else { return nil }
        let nx = min(0.999_999, max(0, Double((point.x - bounds.minX) / bounds.width)))
        let ny = min(0.999_999, max(0, Double((point.y - bounds.minY) / bounds.height)))
        let column = min(hitGridColumns - 1, Int(nx * Double(hitGridColumns)))
        let row = min(hitGridRows - 1, Int(ny * Double(hitGridRows)))
        for index in hitBuckets[(row * hitGridColumns) + column].reversed() {
            guard tileViewRects.indices.contains(index) else { continue }
            let rect = tileViewRects[index]
            if rect.contains(point) {
                return index
            }
        }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = hitTestTileIndex(at: point) else {
            let previousID = selectedNodeID
            selectedNodeID = nil
            onSelectionChange?(nil)
            invalidateInteraction(nodeIDs: [previousID])
            return
        }
        let tile = tiles[index]
        guard tile.role == .node else {
            let previousID = selectedNodeID
            selectedNodeID = nil
            onSelectionChange?(nil)
            invalidateInteraction(nodeIDs: [previousID])
            return
        }
        let previousID = selectedNodeID
        selectedNodeID = tile.nodeID
        onSelectionChange?(tile.nodeID)
        invalidateInteraction(nodeIDs: [previousID, tile.nodeID])
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextIndex = hitTestTileIndex(at: point)
        guard nextIndex != hoveredTileIndex else { return }
        let previousIndex = hoveredTileIndex
        hoveredTileIndex = nextIndex
        invalidateInteraction(tileIndices: [previousIndex, nextIndex])
        scheduleHoverReadout(for: nextIndex)
    }

    public override func mouseExited(with event: NSEvent) {
        guard hoveredTileIndex != nil else { return }
        let previousIndex = hoveredTileIndex
        hoveredTileIndex = nil
        pendingHoverCallback?.cancel()
        pendingHoverCallback = nil
        onHoverChange?(nil)
        invalidateInteraction(tileIndices: [previousIndex])
    }

    public override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = hitTestTileIndex(at: point) else { return }
        let tile = tiles[index]
        guard tile.role == .node, let node = session?.node(id: tile.nodeID), node.childCount > 0 else { return }
        zoomInto(tile.nodeID)
    }

    private func scheduleHoverReadout(for tileIndex: Int?) {
        pendingHoverCallback?.cancel()
        guard let tileIndex, tiles.indices.contains(tileIndex) else {
            onHoverChange?(nil)
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.hoveredTileIndex == tileIndex,
                  self.tiles.indices.contains(tileIndex)
            else { return }
            let tile = self.tiles[tileIndex]
            self.onHoverChange?(tile.role == .node ? tile.nodeID : nil)
        }
        pendingHoverCallback = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverReadoutDelay, execute: item)
    }

    private func invalidateInteraction(tileIndices: [Int?]) {
        var invalidRect = CGRect.null
        for optionalIndex in tileIndices {
            guard let index = optionalIndex, tileViewRects.indices.contains(index) else { continue }
            invalidRect = invalidRect.union(tileViewRects[index])
        }
        guard !invalidRect.isNull else { return }
        setNeedsDisplay(invalidRect.insetBy(dx: -3, dy: -3))
    }

    private func invalidateInteraction(nodeIDs: [NodeID?]) {
        let ids = Set(nodeIDs.compactMap { $0 })
        guard !ids.isEmpty else { return }
        var invalidRect = CGRect.null
        for id in ids {
            for index in tileIndicesByNodeID[id] ?? [] where tileViewRects.indices.contains(index) {
                invalidRect = invalidRect.union(tileViewRects[index])
            }
        }
        guard !invalidRect.isNull else { return }
        setNeedsDisplay(invalidRect.insetBy(dx: -3, dy: -3))
    }
}
