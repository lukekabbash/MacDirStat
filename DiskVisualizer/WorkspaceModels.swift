import AppKit
import Core
import Foundation

struct LocationSnapshot: Sendable {
    let locationID: UUID
    let session: ScanSession
    let scannedAt: Date
    let volumeSpace: VolumeSpaceSnapshot?
    let generation: UUID
}

enum AppInventoryScope: String, CaseIterable, Identifiable {
    case selectedLocation
    case allCompletedLocations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectedLocation: return "Selected location"
        case .allCompletedLocations: return "All completed locations"
        }
    }
}

struct AppInventoryItem: Identifiable {
    let reference: AppPackageReference
    let displayName: String
    let version: String?
    let bundleIdentifier: String?
    let sourceName: String
    let icon: NSImage

    var id: String { reference.id }
}

struct StorageActionRequest: Identifiable {
    enum Kind {
        case moveToFolder
        case moveToTrash
    }

    let id = UUID()
    let kind: Kind
    let locationID: UUID
    let path: String
    let displayName: String
    let isApplication: Bool
}

enum WorkspaceNotice: Identifiable {
    case information(title: String, message: String)
    case error(title: String, message: String)

    var id: String {
        switch self {
        case let .information(title, message), let .error(title, message):
            return title + message
        }
    }

    var title: String {
        switch self {
        case let .information(title, _), let .error(title, _): return title
        }
    }

    var message: String {
        switch self {
        case let .information(_, message), let .error(_, message): return message
        }
    }
}
