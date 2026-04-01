#if canImport(AppKit)
import AppKit
import Core
import SwiftUI

public struct TreemapView: NSViewRepresentable {
    @Binding public var session: ScanSession?
    public var metric: SizeMetric
    public var bridge: TreemapBridge
    public var onSelectionChange: (NodeID?) -> Void
    public var onZoomChange: (NodeID) -> Void
    public var onBreadcrumbChange: ([NodeID]) -> Void

    public init(
        session: Binding<ScanSession?>,
        metric: SizeMetric,
        bridge: TreemapBridge,
        onSelectionChange: @escaping (NodeID?) -> Void = { _ in },
        onZoomChange: @escaping (NodeID) -> Void = { _ in },
        onBreadcrumbChange: @escaping ([NodeID]) -> Void = { _ in }
    ) {
        _session = session
        self.metric = metric
        self.bridge = bridge
        self.onSelectionChange = onSelectionChange
        self.onZoomChange = onZoomChange
        self.onBreadcrumbChange = onBreadcrumbChange
    }

    public func makeNSView(context: Context) -> TreemapNSView {
        let v = TreemapNSView()
        v.session = session
        v.metric = metric
        v.onSelectionChange = onSelectionChange
        v.onZoomChange = onZoomChange
        v.onBreadcrumbChange = onBreadcrumbChange
        bridge.view = v
        return v
    }

    public func updateNSView(_ nsView: TreemapNSView, context: Context) {
        bridge.view = nsView
        nsView.session = session
        nsView.metric = metric
        nsView.onSelectionChange = onSelectionChange
        nsView.onZoomChange = onZoomChange
        nsView.onBreadcrumbChange = onBreadcrumbChange
    }
}
#endif
