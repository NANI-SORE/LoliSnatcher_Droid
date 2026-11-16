# Compatibility changes for merge-2026-11-16

## Inputs and merge policy

The integration starts at local `develop` (`bdadae81`), using the ten feature tips recorded in [branch-inventory.json](branch-inventory.json). Source refs are preserved. No fetch or push is part of this work. `server-favourites` is excluded. Ordinary merge commits retain source ancestry; `enable-ios` is already an ancestor of `downloads-background-rework` and needs no duplicate merge.

The November 16 compact tag-preview layout on develop is retained. Older preview layouts from feature branches were adapted to it. Plans and archived reports describe intent, but current source defines which features existed at the pinned tips. In particular, developer iOS storage migration and recurring download scheduling were not implemented by their source branches and are not added here.

## Settings, paging and groups

- All integrated controls use the typed settings registry. Existing key aliases, explicit source overrides (including values equal to the global value), draft profile editing, canonical-key precedence, and full-reset versus partial-import behavior remain.
- Drawer layout and ordered bottom-bar/main-drawer configuration keep their CSV persistence format. Settings remains pinned; typed notifiers replace obsolete GetX observation for these values.
- Page coordinates are API coordinates. Fetch completion retains each item's `fetchedPage` and the handler's fetched-page set. Tracked database flags are awaited before filtering, and each appended page is filtered once.
- Saved pages are valid only for the source/page-size snapshot that created the tab. Changes to global or source-specific limits invalidate pending restoration and automatic search for affected tabs. Settings/profile backup imports explicitly perform this invalidation because registry loading suppresses ordinary edit callbacks.
- Tab identity and group membership survive source replacement and reordering. Group envelopes retain `v:2`, `groups`, `g`, `cl`, `uc`, selected tabs, secondary boorus, and `p/sp`. Empty groups survive import/export. Legacy delimited strings and JSON arrays remain accepted. External imports strictly reject malformed fields, duplicate groups, invalid group colors and dangling membership; startup recovery remains tolerant.
- Backup source-name remapping preserves the entire grouped envelope, rather than flattening it to a tab array. Startup restoration switches the selected tab without triggering a competing search. DB-disabled tab persistence remains atomic and bounded.

## Filtering, hidden items and operation context

- Hide/Blur/Mark rules, scopes, exclusions, metadata predicates, ordered precedence, temporary rule suspension, Hide-as-Blur, AI/marked/favourite/snatched timers, and diagnostics coexist with page-aware incremental filtering.
- Duplicate server IDs are qualified by source. Full refilters yield and publish only a complete current generation. Selection and temporary restore exceptions use object identity rather than mutable item equality.
- Manually restoring a rule-hidden item affects its display in that tab. The raw rule result and diagnostic matches remain available; unattended downloads still reject hidden/blurred items. Hidden-item previews can show a blurred placeholder and open the explicit viewer. Reveal state is invalidated when the relevant rule signature changes.
- Hidden-item viewers retain saved filenames, source identity and tracked flags when cloning or refreshing a post. The compact preview observes filtered results and selection, retains drag selection, and exposes hidden items even after all results have been hidden.
- Durable discovery snapshots the filter configuration. Headless evaluation requires that snapshot and evaluates expiration against the current clock without relying on UI timers. Missing snapshots block with `configurationChanged`; recapture through the foreground runtime provides a valid configuration.
- Request scopes carry settings, filters, cookies, cancellation and transport. Detail requests for items traversed through Favourites/Downloads use the resolved original source's proxy/TLS/rate policy. Their filter view remains the local traversal.
- Offline, discovery and drawer source lookup now share origin/port/path-aware resolution, explicit identity and supported Sankaku aliases. Ambiguous accounts are not silently resolved to the first matching hostname. A preferred account is accepted only among valid matches.
- Comparison retains the originating view separately from each source, so Favourites/Downloads rules remain effective. It re-evaluates filter revisions, invalidates explicit reveal state on matching-rule changes, and resolves quality/preload/cache settings for each input source. Comparison-order thumbnails use the same filter context.

## Durable downloads and offline storage

- The durable queue supersedes the old foreground batch-write loop. SQLite jobs/checkpoints, generation/attempt ownership, retries, receipts, platform execution, notices and presets remain. Sharing has independent progress/cancellation/retry state; durable queue refreshes do not overwrite it.
- `serverId` and `savedFileName` are both persisted and migrated idempotently. Numeric JSON IDs become strings. Sync/import merges favourite/download flags, fills missing metadata, and preserves a nonempty local filename/ID. Sparse remote rows no longer erase local download identity.
- Rating, score, uploader and source identity remain outside the main SQLite post schema, matching the later filtering design. They can be absent for old local posts; no historical metadata is fabricated.
- Completed receipts record the actual provider filename, preserve favourites, update loaded items and refilter affected handlers. Overwrite invalidation covers old/new derived copies and thumbnails. SAF cache notification uses the actual destination. Thumbnails are best-effort; receipts are acknowledged individually after the completion hook succeeds.
- Destination snapshots carry storage identity, with a fallback for older queue records. Completion against another directory does not create a thumbnail under the current storage selection. Android/iOS/Dart sidecars include the actual saved filename.
- Durable and foreground filename generation now share one algorithm: preserve supported source extras/hashes, honor the selected variant extension, and use stable post-URL hashes when necessary. Names exceeding 200 UTF-8 bytes get a deterministic hash suffix; ordinary names remain unchanged. Exact saved filenames remain the preferred offline lookup.
- Local media remains local-first, including comparison. Actual file headers choose AVIF versus ordinary decoding when a filename is misleading. Private copies may be deleted; user-owned originals are borrowed and survive codec/viewer disposal. Missing/inaccessible local files fall back to network behavior.

## Images, comparison and sharing

- Image-tiling budgets, metadata checks, native region decoding, serialized decode/download work, cancellation, foreground priority and retained ownership are retained. Local thumbnails and comparison inputs use `SafeResizeImage` and the bounded custom providers.
- Memory-policy refusals are not treated as corrupt files: thumbnails do not delete derived files or restart a network download for an `ImageMemoryException`. Gallery pressure listeners, neighbor suppression and retry disposal are preserved.
- Comparison retains a completer handle with each cloned image, keeping its memory reservation alive. Inputs are bounded to 2048 pixels per side. Pixel extraction/calculation runs through the decode admission queue; heatmap output has a separate retained reservation. Cancellation releases all owned images/leases.
- Share staging is separate from routine media cache eviction, retains handed-off files for receivers, and preserves captured item/source order. Retry callbacks and timeout progress use share-operation identity independently of durable downloads.
- Non-Windows clipboard byte reads obey the 64 MiB encoded-image limit; native file-based mobile sharing keeps its existing behavior. Gallery keyboard snatching captures the item before awaiting queue submission so a refilter cannot favourite a different item.

## Backup, restore and secure transfer

- Package format remains version 1. LAN transfer remains protocol 5 with commitment/reveal, X25519-derived directional authenticated records, replay rejection and the shared six-emoji verification phrase. No legacy protocol downgrade was introduced.
- `filters` and `downloadPresets` are new independent category IDs serialized by name. They are included in default/full/scheduled/update backups and transfers, even when the main database category suppresses its own child entries.
- Filter import replaces the rule configuration after strict preflight. Scope target/exclusion names follow profile collision remapping while type/base URL identity remains intact. Export uses the live handler's serialized operation queue.
- Presets merge/upsert by ID and export only portable form fields: query, amount, delay, startPage, sourceNames, quality and overwrite. Storage paths, jobs, receipts and transient transfer state are excluded. Field types are checked before mutation; source names are remapped.
- Restore journal version 2 adds filter primary/tmp/bak files and preset primary/tmp files. Version 1 journals remain recoverable. Checksummed recovery validates snapshots before changing live files.
- Restore pauses filter timers/refilter publication and durable download activity, drains tab/settings/tag/filter writers, and reloads filter/preset state after rollback. A successful finish publishes one coherent filter revision. Failed recovery retains the existing recovery barrier rather than resuming writes.

## Platform, dependencies and localization

- The iOS union preserves Photos, document-picker backup access, local networking/Bonjour, sharing, background downloads, region decoding, SceneDelegate setup and native permission localization; deployment target remains iOS 14. Android retains notification intents, application-context workers, SAF publication and region cleanup.
- The normal dependency is real `native_dio_adapter ^1.8.0`; the stub is selected only by the explicit no-Cronet build override. Default, embedded/no-GMS and no-Cronet build choices remain. The build script now restores the complete dependency/plugin graph via offline pub resolution after the temporary override, preserving the original build failure status and reporting restoration failures.
- AGP 9 rejects the pinned Cronet api/shared AARs because both declare `org.chromium.net`. `android.uniquePackageNames=false` preserves the prior manifest behavior until that dependency packaging is corrected; it does not remove Cronet or alter HTTP policy. See the [upstream Cronet issue](https://github.com/dart-lang/http/issues/1932) and [Android's documented compatibility flag](https://developer.android.com/build/releases/agp-9-0-0-release-notes#behavior-changes). The duplicate Kotlin incremental setting from the merge was removed.
- FVM pins Flutter 3.47.8 while the project requires Flutter 3.47.9. Project constraints were not relaxed. Local verification used the pinned SDK, a temporary diagnostic manifest for offline dependency resolution, and the SDK's plugin refresh routine. Those temporary environment files are not committed.
- Localization generation failed on that existing SDK constraint mismatch and was not retried, per project instructions. English/Russian generated unions were reconciled, including 206 missing dynamic lookup entries per language and the Russian startup getter. Preset category text reuses localized download strings. **Regenerate localization files manually with the project's supported SDK before release.**

## Remaining validation boundaries

See [VALIDATION.md](VALIDATION.md) for executed commands and [FEATURES.md](FEATURES.md) for branch coverage. Passing unit/widget tests and native compilation do not establish device lifecycle behavior. iOS/macOS signing and runtime, physical Android background/SAF flows, real LAN discovery/firewalls, clipboard receivers, and sustained memory-pressure/tiling gestures still require the documented device checks.
