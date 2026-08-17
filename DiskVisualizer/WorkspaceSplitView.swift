import AppKit
import Core
import SwiftUI
import Treemap

enum WorkspaceInspectorTarget: Hashable {
    case node(NodeID)
    case overviewGroup(String)
}

private enum MapSplitDirection {
    case opening
    case closing
}

/// Identifies the exact native map a transition preview represents.
private struct MapVisualIdentity: Equatable {
    let sessionRevision: Int
    let metric: SizeMetric
    let colorMode: TreemapColorMode
    let showsCapacity: Bool
    let focusedNodeID: NodeID
    let renderThemeToken: String
}

private struct MapSplitPreview {
    let image: NSImage
    let direction: MapSplitDirection
    let identity: MapVisualIdentity
}

private enum WorkspaceSplitLayout {
    static let inspectorWidth: CGFloat = 320
    static let primaryMinimumWidth: CGFloat = 520
    static let treemapHorizontalInset: CGFloat = 20
    static let transitionDuration: TimeInterval = 0.20
    static let previewFadeDuration: TimeInterval = 0.08
    static let inspectorReplacementDuration: TimeInterval = 0.14
}

/// Coordinates a real trailing split without asking the native treemap to
/// rebuild for every intermediate layout frame.
struct WorkspaceSplitView<MapCanvas: View, OverviewCanvas: View, InspectorContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: AppModel

    let session: ScanSession
    let bridge: TreemapBridge
    private let mapCanvas: () -> MapCanvas
    private let overviewCanvas: () -> OverviewCanvas
    private let inspectorContent: (WorkspaceInspectorTarget) -> InspectorContent

    @State private var presentedInspector: WorkspaceInspectorTarget?
    @State private var mapSplitPreview: MapSplitPreview?
    @State private var mapSplitProgress: CGFloat = 1
    @State private var mapSplitPreviewOpacity = 0.0
    @State private var inspectorMotionProgress: CGFloat = 1
    @State private var splitTransitionGeneration = UUID()

    init(
        session: ScanSession,
        bridge: TreemapBridge,
        @ViewBuilder mapCanvas: @escaping () -> MapCanvas,
        @ViewBuilder overviewCanvas: @escaping () -> OverviewCanvas,
        @ViewBuilder inspectorContent: @escaping (WorkspaceInspectorTarget) -> InspectorContent
    ) {
        self.session = session
        self.bridge = bridge
        self.mapCanvas = mapCanvas
        self.overviewCanvas = overviewCanvas
        self.inspectorContent = inspectorContent
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    primaryCanvas
                        .frame(
                            minWidth: WorkspaceSplitLayout.primaryMinimumWidth,
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                        .layoutPriority(1)
                        .allowsHitTesting(!isMapSplitTransitionInFlight)

                    if presentedInspector != nil {
                        Rectangle()
                            .fill(.clear)
                            .frame(width: WorkspaceSplitLayout.inspectorWidth)
                            .allowsHitTesting(false)
                    }
                }
                .animation(workspaceLayoutAnimation, value: presentedInspector != nil)

                if let preview = mapSplitPreview {
                    mapSplitPreviewLayer(preview, workspaceSize: proxy.size)
                        .opacity(mapSplitPreviewOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(1)
                }

                // Motion authority: this shell changes position only at the
                // visible/non-visible boundary. Selection replacement stays local.
                if let target = presentedInspector {
                    InspectorContentHandoff(selection: target, content: inspectorContent)
                        .frame(width: WorkspaceSplitLayout.inspectorWidth)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(DiskVisualStyle.strongHairline)
                                .frame(width: 1)
                        }
                        .offset(x: inspectorTransitionOffset)
                        .opacity(inspectorTransitionOpacity)
                        .transition(inspectorVisibilityTransition)
                        .allowsHitTesting(!isMapSplitTransitionInFlight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .zIndex(2)
                }
            }
            .clipped()
        }
        .onAppear { synchronizeInspectorPresentation(with: desiredInspectorTarget) }
        .onChange(of: desiredInspectorTarget) { _, target in
            synchronizeInspectorPresentation(with: target)
        }
        .onChange(of: mapVisualIdentity) { _, identity in
            guard let preview = mapSplitPreview, preview.identity != identity else { return }
            cancelMapSplitTransition()
            synchronizeInspectorPresentation(with: desiredInspectorTarget)
        }
        .onChange(of: model.dashboardMode) { _, _ in
            guard mapSplitPreview != nil else { return }
            cancelMapSplitTransition()
            synchronizeInspectorPresentation(with: desiredInspectorTarget)
        }
    }

    @ViewBuilder
    private var primaryCanvas: some View {
        ZStack {
            if model.dashboardMode == .map {
                mapCanvas()
                    .transition(canvasTransition)
            } else {
                overviewCanvas()
                    .transition(canvasTransition)
            }
        }
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: model.dashboardMode)
    }

    private var inspectorVisibilityTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    private var canvasTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 4))
    }

    private var workspaceLayoutAnimation: Animation? {
        guard !reduceMotion,
              model.dashboardMode == .overview,
              mapSplitPreview == nil
        else { return nil }
        return DiskVisualStyle.contentMotion
    }

    private var isMapSplitTransitionInFlight: Bool {
        mapSplitPreview != nil
    }

    private var inspectorTransitionOffset: CGFloat {
        guard mapSplitPreview != nil else { return 0 }
        return (1 - inspectorMotionProgress) * WorkspaceSplitLayout.inspectorWidth
    }

    private var inspectorTransitionOpacity: Double {
        guard mapSplitPreview != nil else { return 1 }
        return Double(inspectorMotionProgress)
    }

    private var mapVisualIdentity: MapVisualIdentity {
        MapVisualIdentity(
            sessionRevision: model.sessionRevision,
            metric: model.sizeMetric,
            colorMode: model.treemapColorMode,
            showsCapacity: model.showFreeSpaceInMap,
            focusedNodeID: model.focusedNodeID,
            renderThemeToken: currentRenderTheme.token
        )
    }

    private var currentRenderTheme: TreemapRenderTheme {
        DiskVisualStyle.renderTheme(for: model.themeID, dark: colorScheme == .dark)
    }

    private var desiredInspectorTarget: WorkspaceInspectorTarget? {
        inspectorTarget(in: session)
    }

    private var currentInspectorTarget: WorkspaceInspectorTarget? {
        guard let currentSession = model.session else { return nil }
        return inspectorTarget(in: currentSession)
    }

    private func inspectorTarget(in snapshot: ScanSession) -> WorkspaceInspectorTarget? {
        if model.dashboardMode == .overview,
           let selectedGroupID = model.selectedOverviewGroupID,
           model.overviewGroups.contains(where: { $0.id == selectedGroupID }) {
            return .overviewGroup(selectedGroupID)
        }

        guard let selectedNodeID = model.selectedNodeID,
              snapshot.node(id: selectedNodeID) != nil
        else { return nil }
        return .node(selectedNodeID)
    }

    private func mapSplitPreviewLayer(
        _ preview: MapSplitPreview,
        workspaceSize: CGSize
    ) -> some View {
        let availableMapWidth = max(1, workspaceSize.width - WorkspaceSplitLayout.treemapHorizontalInset)
        let destinationWidth: CGFloat
        switch preview.direction {
        case .opening:
            destinationWidth = max(1, availableMapWidth - WorkspaceSplitLayout.inspectorWidth)
        case .closing:
            destinationWidth = availableMapWidth
        }
        let destinationScale = destinationWidth / max(1, preview.image.size.width)
        let currentScale = 1 + ((destinationScale - 1) * mapSplitProgress)

        return Image(nsImage: preview.image)
            .resizable()
            .interpolation(.high)
            .frame(width: preview.image.size.width, height: preview.image.size.height)
            .scaleEffect(x: currentScale, y: 1, anchor: .topLeading)
            .offset(x: 10, y: 10)
    }

    private func synchronizeInspectorPresentation(with target: WorkspaceInspectorTarget?) {
        guard target != presentedInspector else { return }

        let isVisible = presentedInspector != nil
        let shouldBeVisible = target != nil
        if isVisible, shouldBeVisible, let target {
            replaceOpenInspectorContent(with: target)
            return
        }

        let cancelledMapTransition = mapSplitPreview != nil
        if cancelledMapTransition { cancelMapSplitTransition() }
        if cancelledMapTransition || reduceMotion {
            applyInspectorImmediately(target)
            return
        }

        if model.dashboardMode == .map {
            if presentedInspector == nil, let target {
                beginMapInspectorOpening(to: target)
                return
            }
            if target == nil, presentedInspector != nil {
                beginMapInspectorClosing()
                return
            }
            withAnimation(DiskVisualStyle.motion) { presentedInspector = target }
            return
        }

        withAnimation(DiskVisualStyle.contentMotion) {
            presentedInspector = target
        }
    }

    private func replaceOpenInspectorContent(with target: WorkspaceInspectorTarget) {
        if mapSplitPreview?.direction == .closing {
            cancelMapSplitTransition(preservingVisibility: true)
        }
        applyWithoutAnimation { presentedInspector = target }
    }

    private func beginMapInspectorOpening(to target: WorkspaceInspectorTarget) {
        guard let image = captureMapPreview() else {
            applyInspectorImmediately(target)
            return
        }

        let generation = UUID()
        applyWithoutAnimation {
            splitTransitionGeneration = generation
            mapSplitPreview = MapSplitPreview(
                image: image,
                direction: .opening,
                identity: mapVisualIdentity
            )
            mapSplitProgress = 0
            mapSplitPreviewOpacity = 1
            inspectorMotionProgress = 0
            presentedInspector = target
        }
        animateMapSplit(generation: generation, direction: .opening)
    }

    private func beginMapInspectorClosing() {
        guard let image = captureMapPreview() else {
            applyInspectorImmediately(nil)
            return
        }

        let generation = UUID()
        applyWithoutAnimation {
            splitTransitionGeneration = generation
            mapSplitPreview = MapSplitPreview(
                image: image,
                direction: .closing,
                identity: mapVisualIdentity
            )
            mapSplitProgress = 0
            mapSplitPreviewOpacity = 1
            inspectorMotionProgress = 1
        }
        animateMapSplit(generation: generation, direction: .closing)
    }

    private func animateMapSplit(generation: UUID, direction: MapSplitDirection) {
        DispatchQueue.main.async {
            guard isCurrentMapSplitTransition(generation) else { return }
            withAnimation(DiskVisualStyle.contentMotion) {
                mapSplitProgress = 1
                inspectorMotionProgress = direction == .opening ? 1 : 0
            }
            finishMapSplitAfterMotion(generation: generation, direction: direction)
        }
    }

    private func finishMapSplitAfterMotion(generation: UUID, direction: MapSplitDirection) {
        DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceSplitLayout.transitionDuration) {
            guard isCurrentMapSplitTransition(generation) else { return }

            let expectedTarget = direction == .opening ? presentedInspector : nil
            guard currentInspectorTarget == expectedTarget else {
                cancelMapSplitTransition()
                applyInspectorImmediately(currentInspectorTarget)
                return
            }

            if direction == .closing { applyInspectorImmediately(nil) }
            withAnimation(DiskVisualStyle.instantMotion) {
                mapSplitPreviewOpacity = 0
            }
            releaseMapSplitPreviewAfterFade(generation: generation)
        }
    }

    private func releaseMapSplitPreviewAfterFade(generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceSplitLayout.previewFadeDuration) {
            guard splitTransitionGeneration == generation else { return }
            applyWithoutAnimation {
                mapSplitPreview = nil
                mapSplitPreviewOpacity = 0
                mapSplitProgress = 1
                inspectorMotionProgress = presentedInspector == nil ? 0 : 1
            }
        }
    }

    private func captureMapPreview() -> NSImage? {
        guard let view = bridge.view,
              view.bounds.width > 1,
              view.bounds.height > 1,
              view.metric == model.sizeMetric,
              view.colorMode == model.treemapColorMode,
              view.showsCapacityContext == model.showFreeSpaceInMap,
              view.renderTheme.token == currentRenderTheme.token,
              view.zoomStack.last == model.focusedNodeID,
              let renderedSession = view.session,
              renderedSession.nodes.count == session.nodes.count,
              renderedSession.rootTotalAllocated == session.rootTotalAllocated,
              renderedSession.rootTotalLogical == session.rootTotalLogical
        else { return nil }

        let rect = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func isCurrentMapSplitTransition(_ generation: UUID) -> Bool {
        guard splitTransitionGeneration == generation,
              let preview = mapSplitPreview
        else { return false }
        return preview.identity == mapVisualIdentity
    }

    private func cancelMapSplitTransition(preservingVisibility: Bool = false) {
        let wasClosing = mapSplitPreview?.direction == .closing
        applyWithoutAnimation {
            splitTransitionGeneration = UUID()
            mapSplitPreview = nil
            mapSplitPreviewOpacity = 0
            mapSplitProgress = 1
            inspectorMotionProgress = 1
            if wasClosing, !preservingVisibility { presentedInspector = nil }
        }
    }

    private func applyInspectorImmediately(_ target: WorkspaceInspectorTarget?) {
        applyWithoutAnimation {
            presentedInspector = target
            inspectorMotionProgress = target == nil ? 0 : 1
        }
    }

    private func applyWithoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }
}

private enum InspectorContentSlot<Selection: Hashable>: Hashable {
    case outgoing(Selection)
    case current(Selection)
}

/// Keeps a visible inspector's split geometry stable while its contents change.
private struct InspectorContentHandoff<Selection: Hashable, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let selection: Selection?
    private let content: (Selection) -> Content

    @State private var displayedSelection: Selection?
    @State private var outgoingSelection: Selection?
    @State private var replacementProgress: CGFloat = 1
    @State private var replacementGeneration = UUID()

    init(
        selection: Selection?,
        @ViewBuilder content: @escaping (Selection) -> Content
    ) {
        self.selection = selection
        self.content = content
        _displayedSelection = State(initialValue: selection)
    }

    var body: some View {
        ZStack {
            if let outgoingSelection {
                content(outgoingSelection)
                    .id(InspectorContentSlot.outgoing(outgoingSelection))
                    .opacity(1 - replacementProgress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let displayedSelection {
                content(displayedSelection)
                    .id(InspectorContentSlot.current(displayedSelection))
                    .opacity(replacementProgress)
                    .offset(y: reduceMotion ? 0 : (1 - replacementProgress) * 3)
                    .allowsHitTesting(outgoingSelection == nil)
            }
        }
        .onAppear { synchronizeContent(with: selection) }
        .onChange(of: selection) { _, selection in
            synchronizeContent(with: selection)
        }
    }

    private func synchronizeContent(with selection: Selection?) {
        guard selection != displayedSelection else { return }
        guard let selection, let displayedSelection, !reduceMotion else {
            applyImmediately(selection)
            return
        }

        let generation = UUID()
        applyWithoutAnimation {
            replacementGeneration = generation
            outgoingSelection = displayedSelection
            self.displayedSelection = selection
            replacementProgress = 0
        }
        animateReplacement(generation: generation)
    }

    private func animateReplacement(generation: UUID) {
        DispatchQueue.main.async {
            guard replacementGeneration == generation else { return }
            withAnimation(DiskVisualStyle.motion) {
                replacementProgress = 1
            }
            releaseOutgoingContent(after: generation)
        }
    }

    private func releaseOutgoingContent(after generation: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceSplitLayout.inspectorReplacementDuration) {
            guard replacementGeneration == generation else { return }
            applyWithoutAnimation {
                outgoingSelection = nil
                replacementProgress = 1
            }
        }
    }

    private func applyImmediately(_ selection: Selection?) {
        applyWithoutAnimation {
            replacementGeneration = UUID()
            displayedSelection = selection
            outgoingSelection = nil
            replacementProgress = 1
        }
    }

    private func applyWithoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }
}

/// A lightweight split for list workspaces whose primary content is cheap to
/// resize. The inspector occupies no layout space until a valid selection
/// exists, then enters as a real trailing column rather than an overlay.
struct ContextualInspectorSplit<Selection: Hashable, Primary: View, Inspector: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let selection: Selection?
    private let primary: () -> Primary
    private let inspector: (Selection) -> Inspector

    init(
        selection: Selection?,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder inspector: @escaping (Selection) -> Inspector
    ) {
        self.selection = selection
        self.primary = primary
        self.inspector = inspector
    }

    var body: some View {
        HStack(spacing: 0) {
            primary()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            // The visible boundary owns split motion; handoff owns replacement.
            if let selection {
                Rectangle()
                    .fill(DiskVisualStyle.strongHairline)
                    .frame(width: 1)
                    .transition(.opacity)

                InspectorContentHandoff(selection: selection, content: inspector)
                    .frame(width: WorkspaceSplitLayout.inspectorWidth)
                    .frame(maxHeight: .infinity)
                    .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : DiskVisualStyle.contentMotion, value: selection != nil)
    }
}
