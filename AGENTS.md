# AGENTS.md

## Cursor Cloud specific instructions

### Overview

Disk Visualizer (MacDirStat) is a **native macOS desktop app** (SwiftUI + AppKit) that visualizes disk usage as an interactive treemap. See `README.md` for the full repo layout.

### Linux Cloud VM limitations

- The full app target (`DiskVisualizer.xcodeproj`) requires **macOS 14+ and Xcode 15+**; it cannot be built or run in the Linux Cloud VM.
- The **Core** library and its tests compile and run on Linux using the Swift Package Manager. The **Treemap** module sources are guarded with `#if canImport(AppKit)` and compile to empty translation units on Linux.
- `ScanEngine.swift` uses macOS-only `URLResourceKey` members and is similarly guarded behind `#if canImport(Darwin)`.

### Build and test (Linux)

```bash
swift build   # builds Core + Treemap (empty on Linux)
swift test    # runs CoreTests (ScanNodeArenaTests, TreemapLayoutEngineTests)
```

### Swift toolchain

Swift 6.0.3 is installed at `/opt/swift/usr/bin`. The PATH is configured in `~/.bashrc`. If `swift` is not found, run:

```bash
export PATH="/opt/swift/usr/bin:$PATH"
```

### Key caveats

- There is no linter configured in the repo. Compilation (`swift build`) is the primary code-quality check on Linux.
- The CI workflow (`.github/workflows/macos.yml`) runs on a `macos-14` runner; it cannot be replicated locally in the Cloud VM.
- Test argument labels must match the source: `ScanNodeArena.reset(rootName:rootPath:)` — the tests originally had `path:` instead of `rootPath:` and were fixed.
