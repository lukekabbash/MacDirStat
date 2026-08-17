import AppKit
import Core

/// One optional navigation affordance lets each visualization describe its
/// own hierarchy action while every file action keeps the same order and copy.
struct StorageNodeNavigationAction {
    let title: String
    let systemImage: String
    let perform: () -> Void
}

typealias StorageNodeContextMenuProvider = (
    _ nodeID: NodeID,
    _ navigationAction: StorageNodeNavigationAction?
) -> NSMenu?

enum StorageNodeContextMenu {
    static func make(
        node: FileNode,
        navigationAction: StorageNodeNavigationAction?,
        allowsReview: Bool,
        quickLook: @escaping () -> Void,
        open: @escaping () -> Void,
        reveal: @escaping () -> Void,
        addToReview: @escaping () -> Void
    ) -> NSMenu {
        let handler = StorageNodeMenuHandler()
        let menu = StorageNodeMenu(handler: handler)
        menu.minimumWidth = 210
        menu.autoenablesItems = false

        if let navigationAction {
            menu.addAction(
                title: navigationAction.title,
                systemImage: navigationAction.systemImage,
                handler: handler,
                action: navigationAction.perform
            )
            menu.addItem(.separator())
        }

        menu.addAction(
            title: "Open",
            systemImage: "arrow.up.right.square",
            handler: handler,
            action: open
        )
        menu.addAction(
            title: "Quick Look",
            systemImage: "eye",
            handler: handler,
            action: quickLook
        )
        menu.addAction(
            title: "Reveal in Finder",
            systemImage: "folder",
            handler: handler,
            action: reveal
        )

        menu.addItem(.separator())
        menu.addAction(
            title: "Copy Path",
            systemImage: "doc.on.doc",
            handler: handler
        ) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(node.path, forType: .string)
        }

        if allowsReview, node.kind != .root {
            menu.addAction(
                title: "Add to Review",
                systemImage: "tray.and.arrow.down",
                handler: handler,
                action: addToReview
            )
        }

        return menu
    }
}

private final class StorageNodeMenu: NSMenu {
    /// AppKit menu-item targets are not an ownership boundary. The menu keeps
    /// its callback target alive for exactly as long as the contextual surface.
    let actionHandler: StorageNodeMenuHandler

    init(handler: StorageNodeMenuHandler) {
        actionHandler = handler
        super.init(title: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class StorageNodeMenuHandler: NSObject {
    private var actions: [Int: () -> Void] = [:]
    private var nextTag = 1

    func register(_ action: @escaping () -> Void) -> Int {
        let tag = nextTag
        nextTag += 1
        actions[tag] = action
        return tag
    }

    @objc func performAction(_ sender: NSMenuItem) {
        actions[sender.tag]?()
    }
}

private extension NSMenu {
    func addAction(
        title: String,
        systemImage: String,
        handler: StorageNodeMenuHandler,
        action: @escaping () -> Void
    ) {
        let item = NSMenuItem(
            title: title,
            action: #selector(StorageNodeMenuHandler.performAction(_:)),
            keyEquivalent: ""
        )
        item.target = handler
        item.tag = handler.register(action)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        addItem(item)
    }
}
