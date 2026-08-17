# Changelog

## Unreleased

- Standardized public copy and release tooling on the full Mac Directory Statistics product name.
- Added explicit, compressed, read-only scan snapshots beneath each saved location, with bounded retention and corruption isolation.
- Added a drillable Sunburst hierarchy alongside the summary overview.
- Added native context menus to map blocks and Sunburst sections for opening, previewing, revealing in Finder, copying paths, and adding items to Review.
- Moved Map/Overview and live snapshot state into the native titlebar toolbar.
- Extended each active theme through the native titlebar and window chrome.
- Added purpose-made raster app-mark variants for every theme and live theme updates in Settings.
- Made the sidebar collapsible, slimmed native scrollbars, and stabilized trailing-inspector transitions across selection changes.
- Removed redundant scan progress from the sidebar and kept one determinate workspace progress bar.
- Reduced Apps workspace entry work with keyed caches, in-flight deduplication, and bounded icon loading.

## 0.1.0 — 2026-08-17

- First packaged macOS preview.
- Native storage scanning with allocated and logical sizes, live progress, and a responsive treemap.
- Saved source collection with Scan, Apps, Review, Map, Overview, and Settings workspaces.
- File-type and location grouping, volume-capacity context, search, navigation, and Quick Look.
- Explicit, source-scoped, confirmation-gated Move to Trash controls that default to off.
- Universal Apple silicon and Intel release packaging with DMG, ZIP, checksums, and optional Developer ID notarization.
