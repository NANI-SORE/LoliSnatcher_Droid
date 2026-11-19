# Download reliability and interaction recovery

Goal: downloads start from a user action on Wi-Fi/mobile/VPN, explain any wait or failure, and preserve the drawer's useful actions without verbose copy.

Implementation is inline on `downloads-background-rework` in `.worktrees/downloads-reliability`. The dirty `merge-2026-11-16` checkout is preserved. Narrow source-branch fixes are merged forward for integration checks; no unrelated feature branches are folded into the downloads branch.

Evidence:
- The Android job uses a default `NetworkRequest`, which includes `NOT_VPN`. Android documents clearing it to admit VPN networks: https://developer.android.com/reference/android/net/NetworkCapabilities#NET_CAPABILITY_NOT_VPN
- A scheduled but not running job is reported as `idle`. The drawer only displays `resumeRequired`.
- Explicit enqueue/resume retains an older pending job, including its system backoff.
- Failed headless initialization leaves an unusable Flutter engine cached. Runtime pump errors are persisted but never exposed.
- Enqueue/configuration capture sends refresh and start commands that both reload and quiesce an already running worker.
- The previous UI pass removed action icons/counts, download long press, and numeric steppers. The merged multi-share branch's select-by-query gesture was also lost. Existing multi-share/filter/offline controllers must remain intact.

Tasks:
- [x] Admit VPN networks, refresh pending user requests, report native scheduler/worker states and recover failed initialization.
- [x] Surface runtime failures and meaningful queue/batch status; avoid restarting unchanged active work on another enqueue; keep cooldown/attempt/publication rules intact.
- [x] Restore contextual icons/counts, safe long presses, item menus and number controls; preserve merged selection/share/filter contracts and English/Russian parity.
- [ ] Verify on emulator with controlled downloads, offline/reconnect, VPN admission, backgrounding, pause/resume/cancel and adding work during a transfer. Run scoped analysis/build checks. No automated test suite unless explicitly authorized.
- [ ] Review the final change, verify merge compatibility against current integration/feature heads, commit and push the downloads branch; integrate narrowly without losing existing checkout changes.

Acceptance evidence and any limitations will be recorded here before completion.

Integration constraints: retain source provenance/cooldowns, captured filter scopes, offline saved filenames and receipt hooks, sharing operation identities, restore quiescence, tab-group independence and native image channels. Never reconnect the legacy unscoped force-retry callback: it can overwrite all completed history. Only explicit item/batch redownload may do that.

Verification (2026-11-20):
- Pinned Flutter 3.47.9 builds the Android x64 debug APK. Scoped Dart analysis reports no issues. English/Russian download translations have 127 identical keys and matching placeholders.
- Android 17 emulator: ordinary controlled files start promptly; adding a second batch preserves the first attempt ID and increasing byte count; queued files complete with Home pressed and the screen off.
- Android reports a validated Wi-Fi/VPN network for the app. A controlled file completes with that VPN active. This app-scoped split-route fixture validates admission; it is not a full-tunnel/provider compatibility test. No network binding or proxy bypass was added to the app.
- With Wi-Fi/mobile disabled, a new task stays queued with zero attempts and the host reports `waitingNetwork`. Restoring connectivity completes it without another start action.
- Pause/resume checkpoints the partial transfer and retains the queued record. Source-branch review found and corrected desktop error-state clearing and numeric preset validation.
- No automated tests were run. Physical-device VPN provider/reconnect coverage and pre-Android-14 service lifecycle remain manual follow-ups.
