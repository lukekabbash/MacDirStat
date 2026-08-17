import Foundation

public enum CleanupAction: String, Codable, Hashable, Sendable, CaseIterable {
    case revealInFinder
    case open
    case moveToTrash
    case moveToLocation
}

/// Whether an action is allowed for the current node and sandbox access.
public struct ActionCapability: Equatable, Sendable {
    public var action: CleanupAction
    public var isEnabled: Bool
    public var denialReason: String?

    public init(action: CleanupAction, isEnabled: Bool, denialReason: String? = nil) {
        self.action = action
        self.isEnabled = isEnabled
        self.denialReason = denialReason
    }
}
