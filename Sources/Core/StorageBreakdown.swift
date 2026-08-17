import Foundation

/// Semantic storage groups shared by the overview charts and treemap colors.
public enum StorageCategory: String, CaseIterable, Codable, Sendable {
    case applications
    case developer
    case video
    case audio
    case images
    case documents
    case archives
    case data
    case other

    public var displayName: String {
        switch self {
        case .applications: return "Apps & bundles"
        case .developer: return "Code & developer"
        case .video: return "Video"
        case .audio: return "Audio"
        case .images: return "Images"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .data: return "Data"
        case .other: return "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .applications: return "app.dashed"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .video: return "film"
        case .audio: return "waveform"
        case .images: return "photo"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .data: return "cylinder.split.1x2"
        case .other: return "square.grid.2x2"
        }
    }

    public static func classify(_ node: FileNode) -> StorageCategory {
        if node.kind == .packageLeaf || node.isPackage { return .applications }

        let extensionName = (node.name as NSString).pathExtension.lowercased()
        switch extensionName {
        case "app", "bundle", "plugin", "framework":
            return .applications
        case "swift", "m", "mm", "c", "cc", "cpp", "h", "hpp", "rs", "go", "py", "js", "jsx", "ts", "tsx", "java", "kt", "rb", "php", "cs", "sh", "zsh", "fish", "sql", "ipynb", "wasm", "wat", "glb", "blend", "xcodeproj", "playground", "xcworkspace", "pbxproj", "a", "o", "so", "dylib", "lib", "rlib", "node", "class", "jar", "gradle", "cmake", "make", "proto", "lrat", "cnf", "dimacs":
            return .developer
        case "mov", "mp4", "m4v", "mkv", "avi", "webm", "mpg", "mpeg":
            return .video
        case "mp3", "m4a", "wav", "aiff", "flac", "aac", "ogg", "mid", "midi":
            return .audio
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg", "psd", "raw":
            return .images
        case "pdf", "doc", "docx", "pages", "rtf", "txt", "md", "key", "ppt", "pptx", "numbers", "xls", "xlsx", "csv":
            return .documents
        case "zip", "tar", "gz", "bz2", "xz", "zst", "tgz", "tbz2", "lz4", "lzma", "7z", "rar", "dmg", "pkg", "iso":
            return .archives
        case "sqlite", "sqlite3", "db", "db-wal", "db-shm", "json", "jsonl", "plist", "cache", "log", "bin", "safetensors", "gguf", "onnx", "mlmodel", "mlpackage", "pt", "pth", "ckpt", "npy", "npz", "parquet", "arrow", "feather":
            return .data
        default:
            let path = node.path.lowercased()
            let developerMarkers = [
                "/node_modules/",
                "/target/debug/",
                "/target/release/",
                "/.build/",
                "/deriveddata/",
            ]
            return developerMarkers.contains(where: path.contains) ? .developer : .other
        }
    }
}

public enum StorageBreakdownGrouping: String, CaseIterable, Codable, Sendable {
    case fileType
    case location

    public var displayName: String {
        switch self {
        case .fileType: return "File type"
        case .location: return "Top-level location"
        }
    }
}

/// Stable file-extension identity shared by the map and its legend. Packages
/// keep their bundle extension, while extensionless files remain explicit.
public enum StorageFileType {
    public static func key(for node: FileNode) -> String {
        "type:\(normalizedExtension(for: node))"
    }

    public static func displayName(for node: FileNode) -> String {
        let value = normalizedExtension(for: node)
        return value == "none" ? "No extension" : ".\(value)"
    }

    private static func normalizedExtension(for node: FileNode) -> String {
        let value = (node.name as NSString).pathExtension.lowercased()
        return value.isEmpty ? "none" : value
    }
}

/// A compact, non-overlapping slice of a scan for overview charts.
public struct StorageBreakdownItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var category: StorageCategory?
    public var size: UInt64
    public var itemCount: Int
    public var memberKeys: [String]
    public var largestNodeID: NodeID?

    public init(
        id: String,
        title: String,
        category: StorageCategory?,
        size: UInt64,
        itemCount: Int,
        memberKeys: [String],
        largestNodeID: NodeID?
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.size = size
        self.itemCount = itemCount
        self.memberKeys = memberKeys
        self.largestNodeID = largestNodeID
    }
}

/// Builds chart-ready summaries from leaf nodes only, so no directory roll-up
/// is counted twice. It deliberately preserves only one representative node
/// per group for a lightweight overview.
public enum StorageBreakdownBuilder {
    public static func items(
        in session: ScanSession,
        scope: NodeID = .root,
        metric: SizeMetric,
        grouping: StorageBreakdownGrouping,
        limit: Int = 8
    ) -> [StorageBreakdownItem] {
        struct Bucket {
            var title: String
            var category: StorageCategory?
            var size: UInt64 = 0
            var itemCount = 0
            var largestNodeID: NodeID?
            var largestNodeSize: UInt64 = 0
        }

        guard limit > 0, session.node(id: scope) != nil else { return [] }
        var buckets: [String: Bucket] = [:]

        for index in session.nodes.indices {
            let nodeID = NodeID(rawValue: UInt32(index))
            guard session.isDescendant(nodeID, of: scope), let node = session.node(id: nodeID) else { continue }
            guard node.kind == .file || node.kind == .packageLeaf else { continue }

            let descriptor = groupDescriptor(
                for: nodeID,
                node: node,
                in: session,
                scope: scope,
                grouping: grouping
            )

            let nodeSize = node.size(for: metric)
            var bucket = buckets[descriptor.key] ?? Bucket(
                title: descriptor.title,
                category: descriptor.category
            )
            bucket.size += nodeSize
            bucket.itemCount += 1
            if nodeSize > bucket.largestNodeSize {
                bucket.largestNodeID = nodeID
                bucket.largestNodeSize = nodeSize
            }
            buckets[descriptor.key] = bucket
        }

        let sorted = buckets.map { key, bucket in
            StorageBreakdownItem(
                id: key,
                title: bucket.title,
                category: bucket.category,
                size: bucket.size,
                itemCount: bucket.itemCount,
                memberKeys: [key],
                largestNodeID: bucket.largestNodeID
            )
        }
        .sorted { $0.size > $1.size }

        guard sorted.count > limit else { return sorted }
        let head = Array(sorted.prefix(limit))
        let remainder = sorted.dropFirst(limit)
        let remainderSize = remainder.reduce(UInt64(0)) { $0 + $1.size }
        let remainderCount = remainder.reduce(0) { $0 + $1.itemCount }
        return head + [
            StorageBreakdownItem(
                id: "remainder",
                title: "Remaining",
                category: nil,
                size: remainderSize,
                itemCount: remainderCount,
                memberKeys: remainder.flatMap(\.memberKeys),
                largestNodeID: nil
            ),
        ]
    }

    /// Keeps a small ordered shortlist without sorting the full scan tree.
    public static func largestLeafNodeIDs(
        in session: ScanSession,
        scope: NodeID = .root,
        metric: SizeMetric,
        limit: Int = 14
    ) -> [NodeID] {
        guard limit > 0, session.node(id: scope) != nil else { return [] }
        var leaders: [(id: NodeID, size: UInt64)] = []

        for index in session.nodes.indices {
            let id = NodeID(rawValue: UInt32(index))
            guard session.isDescendant(id, of: scope), let node = session.node(id: id) else { continue }
            guard node.kind == .file || node.kind == .packageLeaf else { continue }

            let size = node.size(for: metric)
            guard leaders.count < limit || size > (leaders.last?.size ?? 0) else { continue }
            let insertionIndex = leaders.firstIndex { size > $0.size } ?? leaders.endIndex
            leaders.insert((id, size), at: insertionIndex)
            if leaders.count > limit { leaders.removeLast() }
        }

        return leaders.map(\.id)
    }

    /// Returns the largest concrete items represented by an overview group.
    /// Group membership comes from the summary item, so a collapsed
    /// "Remaining" group can still be inspected without pretending that one
    /// representative file is the whole aggregate.
    public static func largestLeafNodeIDs(
        in session: ScanSession,
        scope: NodeID = .root,
        metric: SizeMetric,
        grouping: StorageBreakdownGrouping,
        memberKeys: [String],
        limit: Int = 8
    ) -> [NodeID] {
        guard limit > 0, !memberKeys.isEmpty, session.node(id: scope) != nil else { return [] }
        let acceptedKeys = Set(memberKeys)
        var leaders: [(id: NodeID, size: UInt64)] = []

        for index in session.nodes.indices {
            if index.isMultiple(of: 2_048), Task.isCancelled { return [] }
            let nodeID = NodeID(rawValue: UInt32(index))
            guard session.isDescendant(nodeID, of: scope), let node = session.node(id: nodeID) else { continue }
            guard node.kind == .file || node.kind == .packageLeaf else { continue }

            let descriptor = groupDescriptor(
                for: nodeID,
                node: node,
                in: session,
                scope: scope,
                grouping: grouping
            )
            guard acceptedKeys.contains(descriptor.key) else { continue }

            let size = node.size(for: metric)
            guard leaders.count < limit || size > (leaders.last?.size ?? 0) else { continue }
            let insertionIndex = leaders.firstIndex { size > $0.size } ?? leaders.endIndex
            leaders.insert((nodeID, size), at: insertionIndex)
            if leaders.count > limit { leaders.removeLast() }
        }

        return leaders.map(\.id)
    }

    private static func groupDescriptor(
        for nodeID: NodeID,
        node: FileNode,
        in session: ScanSession,
        scope: NodeID,
        grouping: StorageBreakdownGrouping
    ) -> (key: String, title: String, category: StorageCategory?) {
        switch grouping {
        case .fileType:
            return (
                StorageFileType.key(for: node),
                StorageFileType.displayName(for: node),
                StorageCategory.classify(node)
            )
        case .location:
            let locationID = session.directDescendant(of: nodeID, under: scope) ?? nodeID
            let locationName = session.node(id: locationID)?.name ?? "Other"
            return ("location:\(locationID.rawValue)", locationName, nil)
        }
    }
}
