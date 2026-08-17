# Release acceptance

This checklist translates the current product specification into observable behavior. A checked item must be true in the built app, not only represented by a source type.

## Sources and snapshots

- [x] Launch is idle; selecting or restoring a source never starts a scan.
- [x] Full Mac, folder, and attached-volume entry points save source access.
- [x] Saved sources support select, pin, rename, reveal, and remove-from-list without changing filesystem content.
- [x] Legacy saved roots migrate without deleting the legacy file.
- [x] Only compact source summaries persist. File trees remain in memory.
- [x] Every source owns an independent snapshot, capacity context, scan date, and availability state.
- [x] Switching sources never combines totals or paints an aggregate map.
- [x] Only one source scans at a time; other source controls explain that state.

## Investigation

- [x] Scan, Apps, Review, and Settings are stable top-level destinations.
- [x] The selected source, map/list selection, breadcrumbs, and inspector share one selection model.
- [x] Search, kind, and minimum-size filters operate on the current snapshot.
- [x] The map can color by file type or location and can represent volume capacity explicitly.
- [x] The overview exposes exact non-overlapping groups and largest individual items.
- [x] Quick Look, open, reveal, and explicit Add to Review actions are available where relevant.
- [x] Keyboard access covers find, Quick Look, add to Review, zoom in, and zoom out.

## Apps and Review

- [x] Apps contains only application bundles projected from completed snapshots.
- [x] App rows identify size, version, source, and snapshot age without claiming system-wide inventory.
- [x] Review contains only explicit user-added references and persists no automatic recommendations.
- [x] Review shows source, snapshot date, reason, size, and a conservative current state.
- [x] Removing a Review reference requires no file operation and no confirmation.

## File safety

- [x] Allow deletion is source-specific, defaults off, and returns off on every launch.
- [x] Move and Trash actions share source, snapshot, permission, and item eligibility rules.
- [x] The path and cheap identity facts are rechecked immediately before mutation.
- [x] Move to Folder is restricted to a verified destination on the same volume.
- [x] Every mutation has a final confirmation and never performs a background refresh.
- [x] A successful mutation invalidates only its owning snapshot.
- [x] The app never permanently erases content or empties Trash.

## Quality boundary

- [x] High-frequency telemetry is isolated from map and inspector invalidation.
- [x] Empty, loading, partial, complete, unavailable, locked, and stale states use truthful language.
- [x] Layout uses one rail, one canvas, and one stable inspector rather than stacked modal surfaces.
- [x] Semantic themes, light/dark appearance, reduced motion, accessibility labels, hover states, and keyboard controls are present.
- [x] Optimized compilation, signature verification, source typecheck, core acceptance harness, and live macOS click-through pass.

## Explicitly deferred

- [ ] Cross-volume transfer execution and recovery.
- [ ] Scan queues, scan sets, or aggregate cross-source maps.
- [ ] Duplicate hashing, automatic cleanup, background scanning, and historical file trees.
- [ ] Distribution signing, notarization, and store packaging.
