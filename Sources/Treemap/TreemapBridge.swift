#if canImport(AppKit)
import AppKit
import Combine
import Core
import Foundation

/// Holds a weak reference to the AppKit treemap for toolbar/sidebar actions.
@MainActor
public final class TreemapBridge: ObservableObject {
    public weak var view: TreemapNSView?

    public init() {}

    public func zoomOut() {
        view?.zoomOut()
    }

    public func resetZoom() {
        view?.resetZoom()
    }
}
#endif
