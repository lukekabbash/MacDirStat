import Foundation

public enum AccessMode: String, Codable, Sendable {
    case readWrite
    case readOnly
}

/// User-selected scan root with persisted security-scoped bookmark.
public struct ScanRoot: Equatable, Sendable, Codable {
    public var id: UUID
    public var displayName: String
    /// Stable volume identifier when available (e.g. volume UUID string).
    public var volumeIdentifier: String?
    public var accessMode: AccessMode
    /// Bookmark data from `url.bookmarkData(...)`.
    public var bookmarkData: Data

    public init(
        id: UUID = UUID(),
        displayName: String,
        volumeIdentifier: String?,
        accessMode: AccessMode,
        bookmarkData: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.volumeIdentifier = volumeIdentifier
        self.accessMode = accessMode
        self.bookmarkData = bookmarkData
    }
}
