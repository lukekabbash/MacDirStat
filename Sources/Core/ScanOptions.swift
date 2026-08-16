import Foundation

public enum SizeMetric: String, Codable, Sendable, CaseIterable {
    case allocated
    case logical
}

public struct ScanOptions: Equatable, Sendable {
    public var metric: SizeMetric
    public var showHiddenFiles: Bool
    /// When true, directory entries marked as packages are not descended into.
    public var treatPackagesAsLeaves: Bool

    public init(
        metric: SizeMetric = .allocated,
        showHiddenFiles: Bool = true,
        treatPackagesAsLeaves: Bool = true
    ) {
        self.metric = metric
        self.showHiddenFiles = showHiddenFiles
        self.treatPackagesAsLeaves = treatPackagesAsLeaves
    }

    public static let `default` = ScanOptions()
}
