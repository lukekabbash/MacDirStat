import AppKit
import Combine
import Core
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var session: ScanSession?
    @Published var sizeMetric: SizeMetric = .allocated
    @Published var showHiddenFiles = false
    @Published var treatPackagesAsLeaves = true
    @Published var isScanning = false
    @Published var statusLine = "Choose a folder to analyze. Sandbox access uses security-scoped bookmarks."
    @Published var selectedNodeID: NodeID?
    @Published var activeRoot: ScanRoot?
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    private let engine = ScanEngine()
    private var scanTask: Task<Void, Never>?
    private var cancelScan = false

    init() {
        Task {
            try? await BookmarkStore.default.load()
            let roots = await BookmarkStore.default.allRoots()
            await MainActor.run {
                if let last = roots.last {
                    self.activeRoot = last
                    self.statusLine = "Restored “\(last.displayName)”. Choose Scan or pick a different folder."
                }
            }
        }
    }

    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        showOnboarding = false
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Grant read/write access so Disk Visualizer can scan and perform cleanup actions you confirm."
        panel.prompt = "Select"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            statusLine = "Could not create security-scoped bookmark: \(error.localizedDescription)"
            return
        }

        var stale = false
        let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let volId: String? = resolved.flatMap { url in
            guard let id = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return nil }
            return String(describing: id)
        }

        let root = ScanRoot(
            displayName: url.lastPathComponent,
            volumeIdentifier: volId,
            accessMode: .readWrite,
            bookmarkData: bookmark
        )
        activeRoot = root
        Task {
            try? await BookmarkStore.default.upsert(root)
        }
        statusLine = "Selected “\(root.displayName)”. Choose Scan to build the treemap."
    }

    func startScan() {
        guard let root = activeRoot else {
            statusLine = "Select a folder first."
            return
        }
        cancelScan = false
        isScanning = true
        statusLine = "Scanning…"
        session = nil
        selectedNodeID = nil

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: root.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            isScanning = false
            statusLine = "Could not resolve bookmark. Re-select the folder."
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            isScanning = false
            statusLine = "Security-scoped access was denied. Re-select the folder in Settings > Privacy."
            return
        }

        let opts = ScanOptions(
            metric: sizeMetric,
            showHiddenFiles: showHiddenFiles,
            treatPackagesAsLeaves: treatPackagesAsLeaves
        )
        let bid = root.id
        let writeAccess = root.accessMode == .readWrite

        scanTask = Task {
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let final = try await engine.scan(
                    rootURL: url,
                    rootBookmarkID: bid,
                    options: opts,
                    writeAccess: writeAccess,
                    progress: { [weak self] prog in
                        Task { @MainActor in
                            guard let self else { return }
                            self.session = prog.partialSession
                            self.statusLine = prog.partialSession.isComplete
                                ? "Scan complete — \(prog.scannedNodes) items."
                                : "Scanning… \(prog.scannedNodes) items"
                        }
                    },
                    shouldCancel: { [weak self] in
                        self?.cancelScan == true
                    }
                )
                await MainActor.run {
                    self.session = final
                    self.isScanning = false
                    if stale {
                        self.statusLine = (self.statusLine) + " (bookmark may be stale — re-select if paths fail.)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.statusLine = "Scan failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelActiveScan() {
        cancelScan = true
    }

    func formattedBytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(clamping: value))
    }
}
