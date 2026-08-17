# Mac Directory Statistics

Mac Directory Statistics (`macdirstat`) is a native macOS storage explorer with a **SwiftUI** shell and a custom **AppKit** treemap. It launches idle, scans only after an explicit command, and keeps deletion controls locked until the user deliberately enables them. Built for **App Sandbox** using **user-selected read-write** access and **security-scoped bookmarks** (see [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/), [user-selected read-write](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.files.user-selected.read-write), [security-scoped URLs](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource%28%29)).

## Repository layout

| Area | Role |
|------|------|
| `Sources/Core` | Scanning, saved-location persistence, source-aware projections, review validation, treemap layout math, and shared action eligibility |
| `Sources/Treemap` | AppKit treemap surface + SwiftUI bridge |
| `DiskVisualizer/` | App target: saved-location rail, Scan, Apps, Review, Settings, inspectors, Quick Look, and guarded file actions |
| `DiskVisualizer.xcodeproj` | Ships the sandboxed `.app` and links local Swift packages |

**License:** MIT. **Platform:** macOS 14+ (universal binary when archived in Xcode).

## Build (contributors)

1. Open `DiskVisualizer.xcodeproj` in Xcode 15+ on a Mac.
2. Select the **DiskVisualizer** scheme and **Run**.

Swift Package tests (Core logic, no AppKit in tests):

```bash
swift test
```

## Product boundary

- No automatic scan: restoring or choosing a folder/volume only selects it. Scanning begins after an explicit Scan command.
- Saved locations persist access and compact scan summaries only. Each completed location keeps an independent in-memory snapshot; the app never combines unrelated roots into a misleading total or map.
- Default **allocated** bytes (`URLResourceKey.fileAllocatedSizeKey` / `totalFileAllocatedSizeKey`) with **logical** size shown alongside; APFS clones and shared content mean totals may not match Finder exactly—nodes can surface `mayShareFileContentKey` when the system provides it.
- **Symlinks are not followed.** **Packages** can be shown as one compact map tile (default), while their contents are measured so their displayed total remains meaningful.
- The map can color by **file type** or **top-level location**. The overview has a donut, ranked bar chart, aggregate inspectors, and a largest-items list, all grouped without directory double-counting.
- **Apps** is a projection of app bundles found in completed snapshots, with its source and snapshot date always visible. **Review** contains only items the user explicitly adds from Scan or Apps.
- The always-visible capacity strip shows physical used and available space for the containing volume. The optional **Capacity** map mode also represents free space and used space outside the selected scan without changing the underlying folder snapshot.
- Deletion is disabled independently for every source and resets to off on launch. Once enabled, an item is rechecked against its owning snapshot before Move… or Move to Trash; moves are limited to the same volume, every change requires confirmation, successful changes invalidate the source snapshot, and Trash is never emptied by the app.

## Responsiveness

- Scan snapshots arrive more frequently at the start, then back off sharply for large trees so the UI does not repeatedly copy and redraw the full index.
- Direct-child links are captured while scanning, so navigation and treemap rebuilds do not search the entire node list just to open a folder.
- Overview computation runs off the main actor and keeps only compact group totals and a small largest-item shortlist.

## Deliberate non-goals for this release

The app does not run background scans, build aggregate cross-volume maps, execute cross-volume transfers, find duplicates, or automate cleanup. Those workflows need separate state and recovery models; they are not disguised as extensions of the current source-scoped snapshot.

## CI

GitHub Actions (`.github/workflows/macos.yml`) runs `swift test` and `xcodebuild` on `macos-14`.
