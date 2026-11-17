# Image tiling recovery and limits

Transient overview/detail failures retry the missing work without discarding the image, already decoded tiles or zoom. Retry timers pause while hidden and are cancelled on disposal. Permanent failures still surface normally.

The visible native decoder remains reusable during memory-pressure cooldown, within accounted memory limits. Source file length determines admission estimates, rather than charging every operation for the maximum permitted file size. Native decoding remains serialized with one retained source.

Detail tile output returns to 1024 pixels per side. Tiled PhotoView layout uses its actual constraints and clips painting to those bounds, preventing zoomed/rotated tiles from painting over surrounding UI.

Compatibility changes:
- Encoded source ceiling: 64 to 256 MiB (Dart and Android native guards).
- Tracked retained/transient limits: 128/256 to 256/512 MiB.
- Reusable Flutter cache remains 64 MiB and optional tile cache remains 32 MiB.
- Dimension, texture, animation, AVIF, selected quality and preload policies remain unchanged.
- No file-format or settings migration and no new dependency.

Critical regressions cover retry/reuse/disposal and a valid 65 MiB encoded source; a 257 MiB source is still rejected without deleting the original. Profiling/synthetic-app tools remain in local documentation only.

Validation: 11 tests passed across `region_image_recovery_test.dart`, `image_memory_limits_test.dart`, `image_cache_lifecycle_test.dart` and `thumbnail_lifecycle_test.dart`; targeted Dart analysis reported no issues. Sustained pressure and gesture behavior on the affected physical device remain to be confirmed.


## Explicit viewer reveal

`Load anyway` now rebuilds the viewer when recording its per-item reveal choice. Loading/provider notifications rebuild only parts of the viewer; a painting layer outside those builders otherwise retains the previous blur state when combined with `filtering-rework`.

The reveal-state implementation originates on this branch, so its rebuild notification is fixed here. The symptom requires the combined filter UI. Integration regressions cover real loaded pixels for Blur and Hide-as-Blur, unchanged filter results and a newly opened post remaining blocked. The regression fixture belongs to the combined branch because it uses its filter/offline/standalone viewer APIs. No filter rules, persistent settings or storage formats change.
