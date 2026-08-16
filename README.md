# Mac Directory Statistics

Mac Directory Statistics (`macdirstat`) is a native macOS storage explorer with a **SwiftUI** shell and a custom **AppKit** treemap. It launches idle, scans only after an explicit command, and keeps cleanup controls locked until the user deliberately enables them. Built for **App Sandbox** using **user-selected read-write** access and **security-scoped bookmarks** (see [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox/), [user-selected read-write](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.files.user-selected.read-write), [security-scoped URLs](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource%28%29)).

## Repository layout

| Area | Role |
|------|------|
| `Sources/Core` | `ScanRoot`, `ScanOptions`, `ScanSession`, `FileNode`, `ScanEngine`, `BookmarkStore`, treemap layout math, types |
| `Sources/Treemap` | AppKit treemap surface + SwiftUI bridge |
| `DiskVisualizer/` | App target: onboarding, map/snapshot dashboard, inspector, guarded cleanup |
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
- Default **allocated** bytes (`URLResourceKey.fileAllocatedSizeKey` / `totalFileAllocatedSizeKey`) with **logical** size shown alongside; APFS clones and shared content mean totals may not match Finder exactly—nodes can surface `mayShareFileContentKey` when the system provides it.
- **Symlinks are not followed.** **Packages** can be shown as one compact map tile (default), while their contents are measured so their displayed total remains meaningful.
- The map can color by **file type** or **top-level location**. The overview has a donut, ranked bar chart, aggregate inspectors, and a largest-items list, all grouped without directory double-counting.
- The optional **Free space** strip shows physical used and available capacity for the containing volume without shrinking or rescaling the folder treemap.
- Cleanup is disabled by default. Once the user enables it for a selected root, Move… and Move to Trash both require a final confirmation; Trash is never emptied by the app.

## Responsiveness

- Scan snapshots arrive more frequently at the start, then back off sharply for large trees so the UI does not repeatedly copy and redraw the full index.
- Direct-child links are captured while scanning, so navigation and treemap rebuilds do not search the entire node list just to open a folder.
- Overview computation runs off the main actor and keeps only compact group totals and a small largest-item shortlist.

## Roadmap (summary)

The spec in your product brief maps to this repo as follows:

- **Phase 0 (foundation):** sandbox entitlements, bookmarks, progressive scan snapshots, treemap + drill-down — *in progress here*.
- **Phase 1 (MVP):** targeted rescan after cleanup, Move…, richer capability messaging, performance tuning.
- **Phase 2 (beta):** FSEvents “something changed” hints, exclusions, pinned roots, compaction.
- **Phase 3 (launch):** MAS vs direct lanes, privacy manifest, smart filters, marketing assets.

## CI

GitHub Actions (`.github/workflows/macos.yml`) runs `swift test` and `xcodebuild` on `macos-14`.
