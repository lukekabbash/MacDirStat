import AppKit
import Core
import SwiftUI
import Treemap

/// AppKit owns the radial chart's cached raster and hit regions. SwiftUI owns
/// navigation and surrounding context, keeping pointer interaction responsive
/// even when a projection contains hundreds of visible arcs.
struct StorageSunburstChart: NSViewRepresentable {
    let session: ScanSession
    let sessionToken: String
    let projection: StorageHierarchyProjection
    let projectionID: UUID
    let selectedNodeID: NodeID?
    let onSelectionChange: (NodeID?) -> Void
    let onDrillInto: (NodeID) -> Void
    let onNavigateBack: () -> Void

    @AppStorage("themeID") private var themeID = DiskThemeID.softGlass.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var renderTheme: TreemapRenderTheme {
        DiskVisualStyle.renderTheme(
            for: DiskThemeID(rawValue: themeID) ?? .softGlass,
            dark: colorScheme == .dark
        )
    }

    func makeNSView(context: Context) -> StorageSunburstNSView {
        let view = StorageSunburstNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: StorageSunburstNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: StorageSunburstNSView) {
        view.setData(
            session: session,
            sessionToken: sessionToken,
            projection: projection,
            projectionID: projectionID,
            renderTheme: renderTheme
        )
        view.setSelectedNodeID(selectedNodeID)
        view.onSelectionChange = onSelectionChange
        view.onDrillInto = onDrillInto
        view.onNavigateBack = onNavigateBack
    }
}

final class StorageSunburstNSView: NSView {
    private var session: ScanSession?
    private var sessionToken = ""
    private var projection: StorageHierarchyProjection?
    private var projectionID: UUID?
    private var renderTheme: TreemapRenderTheme = .system
    /// The chart body is painted eagerly into this bitmap. Interaction never
    /// asks AppKit to replay the full arc collection during a hover redraw.
    private var baseBitmap: NSBitmapImageRep?
    private var rasterSignature: SunburstRasterSignature?
    private var needsStaticContentRebuild = true
    private var renderLayout: SunburstRenderLayout?
    private var geometryByNodeID: [NodeID: SunburstArcGeometry] = [:]
    private var nodeIDsByDepth: [Int: [NodeID]] = [:]
    private var selectedNodeID: NodeID?
    private var hoveredNodeID: NodeID?
    private var trackingArea: NSTrackingArea?
    private var pendingSizeRebuild: DispatchWorkItem?
    private var sizeRebuildGeneration = UUID()

    var onSelectionChange: ((NodeID?) -> Void)?
    var onDrillInto: ((NodeID) -> Void)?
    var onNavigateBack: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }

    func setData(
        session: ScanSession,
        sessionToken: String,
        projection: StorageHierarchyProjection,
        projectionID: UUID,
        renderTheme: TreemapRenderTheme
    ) {
        let needsNewProjection = self.projectionID != projectionID
        let needsNewSession = self.sessionToken != sessionToken
        let needsNewTheme = self.renderTheme.token != renderTheme.token

        self.session = session
        self.sessionToken = sessionToken
        self.projection = projection
        self.projectionID = projectionID
        self.renderTheme = renderTheme

        if needsNewProjection || needsNewSession || needsNewTheme {
            invalidateStaticContent()
            rebuildStaticContentIfNeeded()
        }
    }

    func setSelectedNodeID(_ nodeID: NodeID?) {
        let validID = nodeID.flatMap { session?.node(id: $0) == nil ? nil : $0 }
        guard validID != selectedNodeID else { return }
        selectedNodeID = validID
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        scheduleSizeRebuildIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateStaticContent()
        rebuildStaticContentIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scheduleSizeRebuildIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 1, bounds.height > 1 else { return }

        if baseBitmap == nil || needsStaticContentRebuild {
            rebuildStaticContentIfNeeded()
        }
        drawCachedBitmap()

        if pendingSizeRebuild == nil {
            drawInteractionOverlay()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard pendingSizeRebuild == nil else { return }
        window?.makeFirstResponder(self)
        let nodeID = hitNode(at: convert(event.locationInWindow, from: nil))
        guard nodeID != selectedNodeID else { return }
        selectedNodeID = nodeID
        onSelectionChange?(nodeID)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pendingSizeRebuild == nil else { return }
        guard event.clickCount == 2,
              let nodeID = hitNode(at: convert(event.locationInWindow, from: nil)),
              session?.node(id: nodeID)?.childCount ?? 0 > 0
        else { return }
        onDrillInto?(nodeID)
    }

    override func mouseMoved(with event: NSEvent) {
        guard pendingSizeRebuild == nil else {
            if hoveredNodeID != nil {
                hoveredNodeID = nil
                toolTip = nil
                needsDisplay = true
            }
            return
        }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredNodeID != nil else { return }
        hoveredNodeID = nil
        toolTip = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return and keypad Enter
            if let selectedNodeID, session?.node(id: selectedNodeID)?.childCount ?? 0 > 0 {
                onDrillInto?(selectedNodeID)
                return
            }
        case 53: // Escape
            onNavigateBack?()
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    private var currentRasterSignature: SunburstRasterSignature? {
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = currentBackingScale
        let pixelsWide = max(1, Int((bounds.width * scale).rounded(.up)))
        let pixelsHigh = max(1, Int((bounds.height * scale).rounded(.up)))
        return SunburstRasterSignature(
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            scale: scale
        )
    }

    private var currentBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    private func invalidateStaticContent() {
        pendingSizeRebuild?.cancel()
        pendingSizeRebuild = nil
        sizeRebuildGeneration = UUID()
        needsStaticContentRebuild = true
    }

    /// Width can animate while the contextual inspector opens. Keep drawing
    /// the existing bitmap scaled to the intermediate bounds, then rasterize
    /// once after layout settles instead of replaying every arc per frame.
    private func scheduleSizeRebuildIfNeeded() {
        guard baseBitmap != nil else {
            rebuildStaticContentIfNeeded()
            return
        }
        guard currentRasterSignature != rasterSignature else {
            pendingSizeRebuild?.cancel()
            pendingSizeRebuild = nil
            sizeRebuildGeneration = UUID()
            return
        }

        pendingSizeRebuild?.cancel()
        let generation = UUID()
        sizeRebuildGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sizeRebuildGeneration == generation else { return }
            self.pendingSizeRebuild = nil
            self.needsStaticContentRebuild = true
            self.rebuildStaticContentIfNeeded()
        }
        pendingSizeRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: work)
    }

    private func rebuildStaticContentIfNeeded() {
        guard let raster = currentRasterSignature,
              let projection
        else {
            baseBitmap = nil
            rasterSignature = nil
            renderLayout = nil
            geometryByNodeID = [:]
            nodeIDsByDepth = [:]
            needsStaticContentRebuild = false
            needsDisplay = true
            return
        }

        guard needsStaticContentRebuild || raster != rasterSignature else { return }

        rebuildStaticContent(projection: projection, raster: raster)
    }

    private func rebuildStaticContent(
        projection: StorageHierarchyProjection,
        raster: SunburstRasterSignature
    ) {
        let layout = SunburstRenderLayout(bounds: bounds, deepestDepth: projection.deepestVisibleDepth)
        renderLayout = layout
        var nextGeometry: [NodeID: SunburstArcGeometry] = [:]
        var nextNodeIDsByDepth: [Int: [NodeID]] = [:]
        for segment in projection.segments {
            let geometry = SunburstArcGeometry(segment: segment, layout: layout)
            guard geometry.endFraction > geometry.startFraction else { continue }
            nextGeometry[segment.nodeID] = geometry
            nextNodeIDsByDepth[segment.depth, default: []].append(segment.nodeID)
        }
        for depth in nextNodeIDsByDepth.keys {
            nextNodeIDsByDepth[depth]?.sort {
                (nextGeometry[$0]?.startFraction ?? 0) < (nextGeometry[$1]?.startFraction ?? 0)
            }
        }
        geometryByNodeID = nextGeometry
        nodeIDsByDepth = nextNodeIDsByDepth
        let rendered = renderEagerBitmap(layout: layout, raster: raster)
        baseBitmap = rendered
        rasterSignature = raster
        needsStaticContentRebuild = false
        needsDisplay = true
    }

    private func renderEagerBitmap(
        layout: SunburstRenderLayout,
        raster: SunburstRasterSignature
    ) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: raster.pixelsWide,
            pixelsHigh: raster.pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        bitmap.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let graphicsContext = context.cgContext
        graphicsContext.saveGState()
        defer { graphicsContext.restoreGState() }
        // NSGraphicsContext already maps points to the bitmap's backing
        // resolution. Only flip its point-space origin to match this view;
        // applying the backing scale again would double-scale Retina output.
        graphicsContext.translateBy(x: 0, y: bounds.height)
        graphicsContext.scaleBy(x: 1, y: -1)
        context.imageInterpolation = .high
        context.shouldAntialias = true

        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: bounds.size)).fill()
        for geometry in geometryByNodeID.values {
            drawBaseArc(geometry)
        }
        drawCenter(layout: layout)

        return bitmap
    }

    private func drawCachedBitmap() {
        guard let baseBitmap else { return }
        let sourceSize = baseBitmap.size
        let scale = min(
            bounds.width / max(1, sourceSize.width),
            bounds.height / max(1, sourceSize.height)
        )
        let destinationSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let destination = CGRect(
            x: bounds.midX - destinationSize.width / 2,
            y: bounds.midY - destinationSize.height / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )
        baseBitmap.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private func drawBaseArc(_ geometry: SunburstArcGeometry) {
        guard let session, let node = session.node(id: geometry.segment.nodeID) else { return }
        let path = geometry.path()
        let fillColor = TreemapColorPalette.color(
            for: node,
            nodeID: geometry.segment.nodeID,
            session: session,
            mode: .fileCategory,
            scope: projection?.rootID ?? .root
        )

        fillColor.withAlphaComponent(0.93).setFill()
        path.fill()
        renderTheme.tileStroke.setStroke()
        path.lineWidth = geometry.segment.depth == 1 ? 0.8 : 0.52
        path.stroke()
    }

    private func drawCenter(layout: SunburstRenderLayout) {
        guard let session, let projection else { return }
        let centerRadius = max(0, layout.innerRadius - 5)
        let centerRect = CGRect(
            x: layout.center.x - centerRadius,
            y: layout.center.y - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        )
        let centerPath = NSBezierPath(ovalIn: centerRect)
        renderTheme.surface.withAlphaComponent(0.96).setFill()
        centerPath.fill()
        renderTheme.tileStroke.setStroke()
        centerPath.lineWidth = 0.7
        centerPath.stroke()

        let title = session.node(id: projection.rootID)?.name ?? session.rootDisplayName
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: projection.rootSize),
            countStyle: .file
        )
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        drawCentered(title, attributes: titleAttributes, at: CGPoint(x: layout.center.x, y: layout.center.y - 11), width: centerRadius * 1.5)
        drawCentered(total, attributes: totalAttributes, at: CGPoint(x: layout.center.x, y: layout.center.y + 4), width: centerRadius * 1.5)
    }

    private func drawCentered(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        at point: CGPoint,
        width: CGFloat
    ) {
        let text = string as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: point.x - min(width, size.width) / 2, y: point.y),
            withAttributes: attributes
        )
    }

    /// The redraw path consists of the bitmap above plus this one lightweight
    /// interaction pass. It never replays the static arc collection.
    private func drawInteractionOverlay() {
        if let hoveredNodeID, hoveredNodeID != selectedNodeID,
           let geometry = geometryByNodeID[hoveredNodeID] {
            drawInteractionArc(geometry, selected: false)
        }
        if let selectedNodeID, let geometry = geometryByNodeID[selectedNodeID] {
            drawInteractionArc(geometry, selected: true)
        }
    }

    private func drawInteractionArc(_ geometry: SunburstArcGeometry, selected: Bool) {
        let path = geometry.path()
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

    private func updateHover(at point: CGPoint) {
        let nodeID = hitNode(at: point)
        guard nodeID != hoveredNodeID else { return }
        hoveredNodeID = nodeID
        toolTip = nodeID.flatMap(tooltip(for:))
        needsDisplay = true
    }

    private func tooltip(for nodeID: NodeID) -> String? {
        guard let session, let node = session.node(id: nodeID) else { return nil }
        let metric = projection?.metric ?? .allocated
        let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: node.size(for: metric)), countStyle: .file)
        let action = node.childCount > 0 ? " Double-click or press Return to open its layer." : ""
        return "\(node.name) · \(size)\(action)"
    }

    private func hitNode(at point: CGPoint) -> NodeID? {
        guard let layout = renderLayout,
              let depth = layout.depth(at: point),
              let nodeIDs = nodeIDsByDepth[depth]
        else { return nil }

        let fraction = layout.angleFraction(at: point)
        var lower = 0
        var upper = nodeIDs.count
        while lower < upper {
            let midpoint = (lower + upper) / 2
            let nodeID = nodeIDs[midpoint]
            let start = geometryByNodeID[nodeID]?.startFraction ?? 0
            if start <= fraction {
                lower = midpoint + 1
            } else {
                upper = midpoint
            }
        }

        let candidateIndex = lower - 1
        guard nodeIDs.indices.contains(candidateIndex) else { return nil }
        let candidate = nodeIDs[candidateIndex]
        guard let geometry = geometryByNodeID[candidate],
              fraction >= geometry.startFraction,
              fraction <= geometry.endFraction
        else { return nil }
        return candidate
    }
}
