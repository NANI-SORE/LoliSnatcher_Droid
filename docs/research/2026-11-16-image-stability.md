# Image lifecycle stability — 2026-11-16

The fix applies to `merge-2026-11-16` (starting at `86f9efe3`) and
`image-tiling-optimisation` (starting at `48608055`). It preserves native tiling,
selected viewer resolution, animation limits, filtering and offline media support.
The other feature branches do not contain this image-memory implementation.

## Confirmed causes and corrections

- With animated thumbnails enabled, opening/closing a viewer or entering/leaving
  memory pressure replaced **every** thumbnail provider, even for static PNG/JPEG
  payloads. It removed visible pixels, started new downloads/decodes and animated
  the entire grid back in. Playback changes now use actual decoded frame counts;
  completed static images and their widget keys survive these transitions.
- Grid disposal evicted completed static images immediately. They now remain in
  Flutter's existing bounded LRU, permitting reuse on scrolling/route return.
  Explicit reloads still evict; failed image streams still leave the cache.
- Equivalent HTTP header maps compared by object identity. Cache keys now compare
  header contents independent of insertion order. Different credentials still
  produce different cache entries. Request cancellation remains consumer-scoped.
- An animation could emit its first frame to the cache after its last consumer
  disappeared, bypassing pending-load abandonment and retaining its codec.
  The shared completer now abandons animations without consumers both before
  and after frame one. Another active consumer prevents cancellation. Static
  images and poster-only decodes remain reusable.
- Pressure fallback recovery now retains retry intent while loading a temporary
  thumbnail, then restores the selected sample quality when pressure clears,
  including when thumbnail animation is disabled. The merged branch also disposes
  the bookkeeping image clone from the offline fallback listener.

## Compatibility

No settings/database migration, dependency update, image quality downgrade or
native decoder change is introduced. Cache capacity (64 MiB), tracked retention
limit (128 MiB), source limits and decode/download concurrency are unchanged.
Completed static thumbnails can remain resident longer; the bounded cache and
pressure handling control their lifetime. These admission estimates are not an
RSS/GPU limit. Animated thumbnails still switch to posters while a viewer is
active or memory is pressured; those legitimate animation-policy replacements
can reload the source when disk caching is disabled.

The source branch retains its existing settings/filter API. Its thumbnail tests
use uniquely named, temporary disk-cache fixtures because it predates the merged
request-scope transport seam. The fixtures are deleted after each test.

Validation used the current workspace's FVM Flutter 3.47.9 / Dart 3.13.7 SDK.
The source branch's pre-existing `.fvmrc` says 3.47.8 while its manifest requires
3.47.9; the worktree SDK link was configured for validation without changing
project metadata. The user's uncommitted main-worktree `.fvmrc` change is preserved.

## Reproduction and measured comparison

`tool/image_lifecycle_probe.dart` on the merge branch renders real `Thumbnail`
and `ImageViewer` widgets with an in-process HTTP fixture server. It uses a
60-item grid, 320×200 thumbnails and a 6000×4000 static source, forces animated
thumbnail playback on, and disables disk caching. Three viewer open/zoom/pan/close
cycles are followed by pressure, its 30-second cooldown, and a scroll round trip.
It initializes isolated in-memory settings rather than reading/saving user settings.

Measurements came from Android `emulator-5554`, x86_64, 1080×2400, profile mode,
with the repository's existing Skia configuration. The baseline used unchanged
production code at `86f9efe3`; the same probe was used for the static-image fix.

| Measurement | Baseline | Fixed |
| --- | ---: | ---: |
| Thumbnail requests through pressure recovery | 354 | 42 |
| Thumbnail requests after scroll return | 396 | 84 |
| Frames rendered during the three viewer returns | 76 / 32 / 40 | 2 / 2 / 2 |
| Viewer-return frames over 32 ms | 6 / 2 / 1 | 0 / 0 / 0 |
| Viewer-return maximum build+raster time, ms | 78.8 / 165.5 / 68.3 | 20.3 / 30.1 / 5.4 |

The remaining three thumbnail requests during the viewer cycles come from the
viewer placeholders. After pressure clears the image cache, scrolling can
legitimately require images again. Frame counts/times exclude idle time and use
Flutter build+raster duration, not input-to-display latency. Emulator results
do not establish physical-device frame-rate guarantees.

The final stress variant (`--dart-define IMAGE_PROBE_STRESS=true`) makes every
fifth thumbnail a two-frame GIF behind a PNG URL. It additionally applies pressure
while native tiles are visible, rapidly creates/disposes viewers 12 times, waits
for recovery, removes all image widgets and clears the cache. Its sampled viewed
images remained loaded and tiled, with no stop reason, memory rejection or
queued work at settled checkpoints. Final tracked retained bytes returned to zero.
One run overlapped a host build and included a 408.6 ms outlier; it is retained
in the evidence rather than presented as smooth. The separate idle-host replay
completed with a 60.5 ms overall maximum (34.2 ms across zoom phases), zero memory
rejections and zero retained image bytes after disposal. Some emulator frames
still exceed 32 ms; the evidence supports removal of the reload cascade, not
elimination of all frame-time variability.

Structured measurements are in
[`2026-11-16-image-stability-metrics.json`](2026-11-16-image-stability-metrics.json).
Raw local logs/APKs/screenshots remain ignored under
`docs/image-stability-2026-11-16/`.

For a separate emulator installation, temporarily set the Android defaultConfig
application ID to `"$packageName.imageprobe"`, build the probe with the pinned
`flutter.bat build apk --profile --no-pub --target tool/image_lifecycle_probe.dart
--target-platform android-x64`, and restore the Gradle file. Install/start component
`com.noaisu.loliSnatcher.imageprobe/com.noaisu.loliSnatcher.MainActivity` and collect
the `IMAGE_PROBE` logcat records. This avoids the installed app's signing-certificate
conflict and preserves its data. Do not distribute the diagnostic APK as the app.

## Validation and limits

- Regression tests first failed on disappearing pixels, lost cache reuse,
  equivalent-request duplicate decodes, abandoned animation retention and sample
  quality recovery. The final deterministic merged suite passes **133 tests**.
- The source branch passes **7** provider/widget regressions, covering static
  viewer/pressure/remount reuse, shared animation cancellation, mislabeled animated
  posters, and credential-separated cache reuse.
- Pinned Dart analysis is clean on both branches. Normal Android debug and
  diagnostic Android profile builds pass. `git diff --check` passes.
- An independent read-only review identified the fallback and animation-lifetime
  cases; both were reproduced, fixed and re-reviewed without further findings.
- Repowise was refreshed and changed-file health consulted. Its large-class/churn
  findings remain architectural context, not runtime validation or measured coverage.
- The unrestricted suite also ran `test/booru_test.dart`: **143 passed, 12 failed**.
  That file sets `runWithImages=false`, initializes actual application storage and
  contacts live services. Failures include parsing/authentication/network responses
  and legacy expected-page-size checks (for example 20 versus 21/42/70 results).
  They are recorded separately; this work does not claim live-site compatibility.
- Physical Android hardware, iOS/desktop rendering, long-running background use,
  all codecs and arbitrary real-world media remain outside this emulator sample.
  Existing Kotlin/Impeller migration warnings are unchanged.
