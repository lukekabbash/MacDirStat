import AppKit
import Core
import SwiftUI

public struct TreemapView: NSViewRepresentable {
    @Binding public var session: ScanSession?
    public var sessionRevision: Int
    public var metric: SizeMetric
    public var colorMode: TreemapColorMode
    public var capacityContext: TreemapCapacityContext?
    public var showsCapacityContext: Bool
    public var selectedNodeID: NodeID?
    public var bridge: TreemapBridge
    public var onSelectionChange: (NodeID?) -> Void
    public var onZoomChange: (NodeID) -> Void
    public var onBreadcrumbChange: ([NodeID]) -> Void
    public var onHoverChange: (NodeID?) -> Void

    public init(
        session: Binding<ScanSession?>,
        sessionRevision: Int = 0,
        metric: SizeMetric,
        colorMode: TreemapColorMode = .fileCategory,
        capacityContext: TreemapCapacityContext? = nil,
        showsCapacityContext: Bool = false,
        selectedNodeID: NodeID? = nil,
        bridge: TreemapBridge,
        onSelectionChange: @escaping (NodeID?) -> Void = { _ in },
        onZoomChange: @escaping (NodeID) -> Void = { _ in },
        onBreadcrumbChange: @escaping ([NodeID]) -> Void = { _ in },
        onHoverChange: @escaping (NodeID?) -> Void = { _ in }
    ) {
        _session = session
        self.sessionRevision = sessionRevision
        self.metric = metric
        self.colorMode = colorMode
        self.capacityContext = capacityContext
        self.showsCapacityContext = showsCapacityContext
        self.selectedNodeID = selectedNodeID
        self.bridge = bridge
        self.onSelectionChange = onSelectionChange
        self.onZoomChange = onZoomChange
        self.onBreadcrumbChange = onBreadcrumbChange
        self.onHoverChange = onHoverChange
    }

    public func makeNSView(context: Context) -> TreemapNSView {
        let v = TreemapNSView()
        v.session = session
        context.coordinator.sessionRevision = sessionRevision
        v.metric = metric
        v.colorMode = colorMode
        v.capacityContext = capacityContext
        v.showsCapacityContext = showsCapacityContext
        v.setSelectedNodeID(selectedNodeID)
        v.onSelectionChange = onSelectionChange
        v.onZoomChange = onZoomChange
        v.onBreadcrumbChange = onBreadcrumbChange
        v.onHoverChange = onHoverChange
        bridge.view = v
        return v
    }

    public func updateNSView(_ nsView: TreemapNSView, context: Context) {
        bridge.view = nsView
        if context.coordinator.sessionRevision != sessionRevision {
            nsView.session = session
            context.coordinator.sessionRevision = sessionRevision
        }
        nsView.metric = metric
        nsView.colorMode = colorMode
        nsView.capacityContext = capacityContext
        nsView.showsCapacityContext = showsCapacityContext
        nsView.setSelectedNodeID(selectedNodeID)
        nsView.onSelectionChange = onSelectionChange
        nsView.onZoomChange = onZoomChange
        nsView.onBreadcrumbChange = onBreadcrumbChange
        nsView.onHoverChange = onHoverChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        fileprivate var sessionRevision: Int?
    }
}
