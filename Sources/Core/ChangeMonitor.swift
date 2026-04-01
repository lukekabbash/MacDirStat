import Foundation

/// Placeholder for FSEvents-based "something changed" detection (beta milestone).
public protocol ChangeMonitor: AnyObject {
    func startWatching(url: URL, onChange: @escaping () -> Void)
    func stop()
}

public final class NoOpChangeMonitor: ChangeMonitor {
    public init() {}
    public func startWatching(url: URL, onChange: @escaping () -> Void) {}
    public func stop() {}
}
