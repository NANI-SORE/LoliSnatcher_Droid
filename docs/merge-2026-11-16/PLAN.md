# 2026-11-16 integration plan

Goal: combine the ten feature branches in the user's branch tree with local develop into merge-2026-11-16, preserving implemented features and documenting compatibility changes. No remote push.

## Scope and method

Use the existing local branch tips; do not substitute origin/develop for develop. Exclude server-favourites and historical/experimental branches outside the supplied tree. Keep all source branches intact and preserve unrelated untracked and ignored files. Implement in this session; parallel agents only analyze code and documentation.

Use ordinary merge commits so each source tip remains auditable. Resolve behavioral overlaps deliberately rather than accepting whole conflicting files from one side. Existing branch docs are evidence of intent; verify claims against current source. Planned but unimplemented work is not silently included as a new requirement.

Use only the FVM-pinned Flutter and Dart executables. Do not change project SDK constraints just to match this machine. The user explicitly requested comprehensive testing, authorizing tests for this integration. Use deterministic tests and isolated temporary storage; distinguish platform/live-service scenarios that cannot run here.

## Tasks

- [x] Capture exact branch tips, ancestry, changed paths and test inventory; read branch documentation and current implementation.
- [x] Establish baseline analysis/test/toolchain status and create merge-2026-11-16 from develop.
- [x] Merge settings-rework, page-aware-fetching, filtering-rework and offline-viewing; reconcile settings scopes, filtering generations, page coordinates and persisted media metadata.
- [x] Merge downloads-background-rework and tab-groups; preserve durable jobs and grouped page-aware tab snapshots.
- [x] Merge image-tiling-optimisation and multi-share-select; reconcile settings access, offline ownership, decode budgets and sharing/compare lifetimes.
- [x] Merge backups-sync-rework and enable-ios; preserve complete backup categories, grouped tabs, filter rules, scoped portability, native channels and platform configuration.
- [x] Add critical cross-feature regression coverage, run the available suite, analysis and platform builds, and document every failure or unavailable check.
- [x] Audit source-tip ancestry and feature preservation, review compatibility changes, refresh Repowise context and leave the integration branch local.

## Required compatibility checks

1. Grouped snapshots retain group metadata, tab identity, booru remapping and saved API pages through persistence and backups, including legacy input.
2. Filtering retains rule evaluation, timer invalidation, generation guards, source-scoped duplicate detection and correct empty-page/end-of-data behavior.
3. Offline database migration and media metadata survive downloads and backup restore; user-owned files are never treated as disposable decode cache.
4. Downloads, comparison and restored searches use the operation's source settings across awaits, independent of the foreground tab.
5. Backup/transfer includes filters and all portable settings scopes, coordinates writers during restore and defers automatic startup work.
6. Native iOS Photos/local networking/sharing and Android download/region/thumbnail workers retain all handlers and cleanup paths.

## Evidence and progress

Record merge resolutions and compatibility rulings in COMPATIBILITY.md, implemented feature checks in FEATURES.md, and actual commands/results plus remaining device scenarios in VALIDATION.md. Machine-readable branch inventory records pinned input revisions. These documents will be explicitly tracked despite the repository's broad docs ignore rule.

Initial state: develop bdadae81; no tracked modifications. Untracked .github/MANUAL_BUILD_SETUP.md, test_creds.txt and translation_editor.html belong to the user and are outside this task. The credentials file is not read. FVM pins Flutter 3.47.8 / Dart 3.13.7; develop's pubspec requires Flutter 3.47.9.

Completion evidence and remaining device-only validation are recorded in VALIDATION.md. The branch is prepared locally; these checks do not certify hardware scenarios that this Windows host cannot execute.
