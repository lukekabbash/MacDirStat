import AppKit
@preconcurrency import QuickLookUI

final class QuickLookService: NSObject, QLPreviewPanelDataSource {
    nonisolated(unsafe) private var previewURL: URL?

    @MainActor
    func preview(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let panel = QLPreviewPanel.shared()
        else { return false }

        previewURL = URL(fileURLWithPath: path)
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
