import Foundation

/// Collapses repeated bookmark records without conflating two known paths that
/// happen to share a display name. Historical inaccessible records are merged
/// when their volume/name evidence is unambiguous; the newest compact summary
/// survives, while two distinct known canonical paths always remain separate.
public enum SavedLocationDeduplicator {
    public static func collapse(_ locations: [SavedLocation]) -> [SavedLocation] {
        let fallbackFacts = Dictionary(grouping: locations, by: fallbackIdentity)
        var collapsed: [SavedLocation] = []
        collapsed.reserveCapacity(locations.count)

        for location in locations.sorted(by: sourceOrder) {
            if let match = collapsed.firstIndex(where: { sameKnownSource($0, location) }) {
                collapsed[match] = merge(collapsed[match], location)
                continue
            }

            guard let fallback = fallbackIdentity(location),
                  let peers = fallbackFacts[fallback],
                  canUseFallback(peers),
                  let match = collapsed.firstIndex(where: { fallbackIdentity($0) == fallback })
            else {
                collapsed.append(location)
                continue
            }
            collapsed[match] = merge(collapsed[match], location)
        }

        return collapsed
            .sorted(by: sourceOrder)
            .enumerated()
            .map { index, location in
                var normalized = location
                normalized.sortOrder = index
                return normalized
            }
    }

    private static func sameKnownSource(_ left: SavedLocation, _ right: SavedLocation) -> Bool {
        if let leftPath = normalizedPath(left.canonicalPath),
           let rightPath = normalizedPath(right.canonicalPath) {
            return leftPath == rightPath
        }
        return left.scanRoot.bookmarkData == right.scanRoot.bookmarkData
    }

    private static func canUseFallback(_ peers: [SavedLocation]) -> Bool {
        let knownPaths = Set(peers.compactMap { normalizedPath($0.canonicalPath) })
        return knownPaths.count <= 1
    }

    private static func fallbackIdentity(_ location: SavedLocation) -> String? {
        guard let volume = location.scanRoot.volumeIdentifier?.lowercased(), !volume.isEmpty else {
            return nil
        }
        let rawName = location.scanRoot.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let sourceName = rawName == "/" || rawName == "macintosh hd"
            ? "__startup_volume_root__"
            : rawName
        guard !sourceName.isEmpty else { return nil }
        return volume + "\u{1F}" + sourceName
    }

    private static func merge(_ left: SavedLocation, _ right: SavedLocation) -> SavedLocation {
        let prefersRight = isPreferred(right, over: left)
        var winner = prefersRight ? right : left
        let other = prefersRight ? left : right
        winner.canonicalPath = normalizedPath(winner.canonicalPath)
            ?? normalizedPath(other.canonicalPath)
        winner.customName = meaningfulName(winner.customName) ?? meaningfulName(other.customName)
        winner.isPinned = left.isPinned || right.isPinned
        winner.sortOrder = min(left.sortOrder, right.sortOrder)
        winner.lastScanSummary = newestSummary(left.lastScanSummary, right.lastScanSummary)
        winner.lastSelectedAt = [left.lastSelectedAt, right.lastSelectedAt].compactMap { $0 }.max()
        return winner
    }

    private static func isPreferred(_ candidate: SavedLocation, over current: SavedLocation) -> Bool {
        if (candidate.canonicalPath != nil) != (current.canonicalPath != nil) {
            return candidate.canonicalPath != nil
        }
        if availabilityRank(candidate.availability) != availabilityRank(current.availability) {
            return availabilityRank(candidate.availability) > availabilityRank(current.availability)
        }
        if (candidate.lastScanSummary != nil) != (current.lastScanSummary != nil) {
            return candidate.lastScanSummary != nil
        }
        return (candidate.lastSelectedAt ?? .distantPast) > (current.lastSelectedAt ?? .distantPast)
    }

    private static func availabilityRank(_ availability: LocationAvailability) -> Int {
        switch availability {
        case .ready: return 2
        case .disconnected: return 1
        case .needsAccess: return 0
        }
    }

    private static func newestSummary(_ left: ScanSummary?, _ right: ScanSummary?) -> ScanSummary? {
        switch (left, right) {
        case let (left?, right?): return left.scannedAt >= right.scannedAt ? left : right
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }

    private static func meaningfulName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func sourceOrder(_ left: SavedLocation, _ right: SavedLocation) -> Bool {
        if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
        return left.id.uuidString < right.id.uuidString
    }
}
