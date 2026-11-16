# Validation of merge-2026-11-16

Validation date: 2026-11-16. Implementation merge: `91b0f3c6`, followed by documentation and the user-confirmed regenerated localization output. No remote push was performed.

## Results

| Check | Result |
|---|---|
| Pinned Dart analysis (`lib test`) | **Passed: no issues** |
| Deterministic Flutter suite | **Passed: 124 tests** across existing unit/widget tests and eight integration test files |
| Android debug, complete real-Cronet/plugin graph | **Passed**, after the documented AGP namespace compatibility fix |
| Windows debug, complete plugin graph | **Passed** |
| Bash syntax (`build.sh`) | **Passed** |
| No-Cronet cleanup logic harness | **Passed: 4 cases** combining successful/failed build and successful/failed graph restoration; original lock/override restoration and exit status checked |
| Source-tip ancestry/ref preservation | **Passed:** develop and all ten requested feature tips are unchanged and ancestors of integration HEAD |
| Excluded branch | **Passed:** server-favourites tip is not an ancestor |
| Merge/conflict check | **Passed:** no unmerged index entries or conflict markers; `git diff --check` clean |
| Independent analysis/review | Completed read-only passes; concrete integration findings corrected, including comparison view/source context |
| Localization generator | **Completed by the user:** regenerated output preserved and revalidated |
| Real-device / iOS / release validation | **Not executed**; procedures and boundaries below |

The aggregate passing suite includes 48 new cross-feature tests (the two page/filter tests were added earlier in the merge sequence). These use temporary SQLite/filesystem fixtures, controlled loopback HTTP/TCP peers, and Flutter widget bindings. No user credentials were read and no real application profile was launched.

## Executed commands

PowerShell from the repository root, using only the project-pinned executables:

```powershell
.\.fvm\flutter_sdk\bin\cache\dart-sdk\bin\dart.exe analyze lib test

$tests = @(rg --files test -g '*_test.dart' |
  Where-Object { $_ -ne 'test\booru_test.dart' })
& .\.fvm\flutter_sdk\bin\flutter.bat test --no-pub --reporter expanded @tests

.\.fvm\flutter_sdk\bin\flutter.bat build apk --debug --no-pub
.\.fvm\flutter_sdk\bin\flutter.bat build windows --debug --no-pub
```

Artifacts left locally:

- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/windows/x64/runner/Debug/lolisnatcher.exe` (with its adjacent runtime files)

Detailed command output remains in the ignored local integration directory: `regenerated-tests.log`, `final-analysis.log`, `regenerated-android-build.log`, `regenerated-windows-build.log`, and `toolchains.log`. Earlier failed logs are retained as diagnosis history and are superseded by these final results. They are not bundled as source artifacts.

## Regression coverage added

| Test file | Covered failure boundaries |
|---|---|
| `filter_page_merge_test.dart` | Numeric IDs with saved filenames; each appended page evaluated once; API page coordinates preserved |
| `filter_scope_merge_test.dart` | Headless rule expiry; local-view scope during discovery and comparison; restored display versus raw diagnostics; Hide-as-Blur download exclusion; absent snapshot rejection; restore pauses publication and resumes once |
| `database_offline_merge_test.dart` | Idempotent schema upgrade; single/batch sync flag merge; local ID/filename preservation; duplicate rows in streamed import |
| `image_memory_merge_test.dart` | Owned/borrowed/retained file lifetime; budget refusal semantics and release; queue cancellation/serialization/request Zone; predecode limits; real local SafeResize decode and misleading file suffix |
| `backup_merge_test.dart` | Group/page/selection/empty-group remapping; legacy/BOM formats; malformed tab fields; journal v1/v2 rollback/commit/corruption; streamed UTF-8/nested JSON; filter schema preflight |
| `secure_transfer_merge_test.dart` | Authenticated record direction, tampering, replay, kind/order/size bounds; actual loopback protocol-5 commitment handshake and matching verification phrase |
| `session_selection_merge_test.dart` | Source-specific pending-page invalidation; mutable-item ordered selection; exact path/port/account resolution |
| `backup_registry_merge_test.dart` | New category/full-backup defaults; preset type preflight and legacy numeric form values; English/Russian typed/dynamic localization |

Existing tests retain settings/profile/draft UI behavior, group codecs, source replacement, favicon/tools/shimmer behavior, durable ownership/receipt/rate invariants, and HTTP range/checksum validation.

Failures found and repaired during integration included numeric ID decoding, double page filtering, invalid HTTP-date exception handling, test binding initialization, sparse metadata overwrite, restore-time intermediate refilters, missing dynamic localization entries, a Russian inherited English getter, and Android dependency manifest compatibility. Additional static-review fixes are enumerated in [COMPATIBILITY.md](COMPATIBILITY.md).

## Environment and limits

- FVM provides Flutter **3.47.8 / Dart 3.13.7**; `pubspec.yaml` requires Flutter **3.47.9**. The project constraint/pin was not changed. Ordinary dependency/localization commands encounter that pre-existing mismatch.
- To make this machine's verification concrete, dependencies were resolved offline using a temporary diagnostic manifest with an environment-only SDK accommodation. The environment-resolution lockfile preserved the project constraint; the user's later normal resolution superseded it with the exact Flutter 3.47.9 SDK entry. Local package configuration and graph were corrected together, and the pinned Flutter tools refreshed plugin metadata/symlinks. The temporary manifest and helper are ignored and not committed. A clean checkout should resolve normally once the supported project SDK is available.
- `dart run slang` initially failed on the mismatch and was not retried by the agent, as instructed. During final checks, the user regenerated the localization files and confirmed doing so. That output and the refreshed lockfile were preserved, re-analyzed, tested and rebuilt; no manual localization follow-up remains.
- Initial Windows builds exposed stale Bonsoir plugin metadata. The first Android build used an incomplete graph; it is not the final validation result. Rebuilding with the complete graph exposed Cronet's duplicate AAR namespace; the documented AGP compatibility flag fixed it, and the final real-Cronet build passed.
- Toolchain warnings remain: Kotlin plugin migration warnings for the app/dependencies, Flutter InAppWebView CMake CMP0175 warning, and FVP linker incremental warning. They did not fail the final debug builds. Doctor also reports unaccepted Android licenses and multiple adb installations; no licenses were accepted by this task.
- `test/booru_test.dart` was excluded because it initializes actual app storage and contacts live third-party sites. Its results would depend on current services, authentication and captcha state. Controlled HTTP/TCP tests provide deterministic network coverage; this is not a claim of live-site compatibility.
- No connected Android/iOS device was available. iOS compilation/signing/CocoaPods requires macOS/Xcode. Release/AAB builds, explicit embedded/no-GMS/no-Cronet artifact builds, actual background/process-death/SAF/Photos behavior, native share receivers, real LAN discovery/firewalls/VPN, gestures and sustained memory pressure are **unverified**. See the detailed disposable-profile procedure in [FEATURES.md](FEATURES.md).
- Ordinary source ancestry proves inclusion of source history, not behavior equivalence. The feature matrix, integration fixes, tests, builds and remaining device matrix provide the separate behavioral evidence.

## Repository state

The integration branch is kept locally. All source branches remain at their recorded tips, and server-favourites is excluded. Unrelated untracked `.github/MANUAL_BUILD_SETUP.md`, `test_creds.txt`, and `translation_editor.html` are preserved. Temporary environment files/logs remain ignored; generated editor recommendations are removed. Repowise was refreshed before the final code-health check; its structural findings are review guidance, not test results.
