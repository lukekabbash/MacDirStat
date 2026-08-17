import Foundation

public enum SizeMetric: String, Codable, Sendable, CaseIterable {
    case allocated
    case logical
}

public struct ScanOptions: Equatable, Sendable, Codable {
    public var metric: SizeMetric
    public var showHiddenFiles: Bool
    /// When true, directory entries marked as packages are not descended into.
    public var treatPackagesAsLeaves: Bool
    /// Runs a lightweight inventory beside measurement so progress can use a
    /// real denominator without delaying the first useful map snapshot.
    public var calculatesExactProgress: Bool

    public init(
        metric: SizeMetric = .allocated,
        showHiddenFiles: Bool = true,
        treatPackagesAsLeaves: Bool = true,
        calculatesExactProgress: Bool = true
    ) {
        self.metric = metric
        self.showHiddenFiles = showHiddenFiles
        self.treatPackagesAsLeaves = treatPackagesAsLeaves
        self.calculatesExactProgress = calculatesExactProgress
    }

    public static let `default` = ScanOptions()
}
