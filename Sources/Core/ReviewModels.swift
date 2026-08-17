import Foundation

public enum ReviewReason: String, Codable, Sendable {
    case addedFromScan
    case addedFromApps

    public var displayName: String {
        switch self {
        case .addedFromScan: return "Added from Scan"
        case .addedFromApps: return "Added from Apps"
        }
    }
}

public enum ReviewItemState: String, Codable, Sendable {
    case ready
    case deletionLocked
    case needsRecheck
    case missing
    case sourceUnavailable
    case actionComplete
    case actionFailed
}

public struct ReviewItem: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public let sourceLocationID: UUID
    public let snapshotGeneration: UUID
    public let snapshotDate: Date
    public let originalNodeID: NodeID
    public let path: String
    public let name: String
    public let kind: FileKind
    public let isPackage: Bool
    public let allocatedSize: UInt64
    public let logicalSize: UInt64
    public let mayShareContent: Bool
    public let isSparse: Bool
    public let reason: ReviewReason
    public let addedAt: Date
    public var state: ReviewItemState
    public var actionNote: String?

    public init(
        id: UUID = UUID(),
        sourceLocationID: UUID,
        snapshotGeneration: UUID,
        snapshotDate: Date,
        originalNodeID: NodeID,
        node: FileNode,
        reason: ReviewReason,
        addedAt: Date = Date(),
        state: ReviewItemState = .ready,
        actionNote: String? = nil
    ) {
        self.id = id
        self.sourceLocationID = sourceLocationID
        self.snapshotGeneration = snapshotGeneration
        self.snapshotDate = snapshotDate
        self.originalNodeID = originalNodeID
        path = node.path
        name = node.name
        kind = node.kind
        isPackage = node.isPackage
        allocatedSize = node.allocatedSize
        logicalSize = node.logicalSize
        mayShareContent = node.mayShareContent
        isSparse = node.isSparse
        self.reason = reason
        self.addedAt = addedAt
        self.state = state
        self.actionNote = actionNote
    }

    public func size(for metric: SizeMetric) -> UInt64 {
        metric == .allocated ? allocatedSize : logicalSize
    }
}

public actor ReviewStore {
    public static let `default` = ReviewStore()
    private let fileURL: URL

    public init(appSupportSubpath: String = "DiskVisualizer/review-items-v1.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        fileURL = base.appendingPathComponent(appSupportSubpath, isDirectory: false)
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [ReviewItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ReviewItem].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ items: [ReviewItem]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(items).write(to: fileURL, options: .atomic)
    }
}

public enum ReviewSnapshotValidator {
    public static func state(
        for item: ReviewItem,
        currentSession: ScanSession?,
        currentGeneration: UUID?,
        sourceAvailable: Bool,
        deletionAllowed: Bool
    ) -> ReviewItemState {
        guard sourceAvailable else { return .sourceUnavailable }
        guard let currentSession, let currentGeneration else { return .needsRecheck }
        guard let node = currentSession.nodes.first(where: { $0.path == item.path }) else { return .missing }
        if currentGeneration != item.snapshotGeneration,
           (node.kind != item.kind
               || node.isPackage != item.isPackage
               || node.allocatedSize != item.allocatedSize
               || node.logicalSize != item.logicalSize) {
            return .needsRecheck
        }
        return deletionAllowed ? .ready : .deletionLocked
    }
}

public enum StorageAction: Equatable, Sendable {
    case quickLook
    case open
    case reveal
    case addToReview
    case moveToFolder
    case moveToTrash
}

public struct StorageActionEligibility: Equatable, Sendable {
    public let isEnabled: Bool
    public let reason: String?

    public init(isEnabled: Bool, reason: String? = nil) {
        self.isEnabled = isEnabled
        self.reason = reason
    }
}

public enum ActionEligibility {
    public static func evaluate(
        _ action: StorageAction,
        node: FileNode,
        sourceAvailable: Bool,
        snapshotCurrent: Bool,
        deletionAllowed: Bool,
        sameVolumeDestination: Bool? = nil
    ) -> StorageActionEligibility {
        guard sourceAvailable else {
            return StorageActionEligibility(isEnabled: false, reason: "Source unavailable")
        }
        switch action {
        case .quickLook, .open, .reveal:
            return StorageActionEligibility(isEnabled: !node.path.isEmpty)
        case .addToReview:
            return StorageActionEligibility(isEnabled: node.kind != .root && !node.path.isEmpty)
        case .moveToFolder, .moveToTrash:
            guard deletionAllowed else {
                return StorageActionEligibility(isEnabled: false, reason: "Deletion is disabled")
            }
            guard snapshotCurrent else {
                return StorageActionEligibility(isEnabled: false, reason: "Item needs recheck")
            }
            guard node.kind != .root else {
                return StorageActionEligibility(isEnabled: false, reason: "The selected location cannot be moved")
            }
            let required: CleanupAction = action == .moveToFolder ? .moveToLocation : .moveToTrash
            guard node.allowedActions.contains(required) else {
                return StorageActionEligibility(isEnabled: false, reason: "Action is unavailable for this item")
            }
            if action == .moveToFolder, sameVolumeDestination == false {
                return StorageActionEligibility(
                    isEnabled: false,
                    reason: "Transfer between volumes is not available yet"
                )
            }
            return StorageActionEligibility(isEnabled: true)
        }
    }
}
