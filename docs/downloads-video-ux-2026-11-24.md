# Video downloads and queue UX — 2026-11-24

Rule34 video metadata identifies the uploaded original, while the CDN can serve
a converted video. Using that MD5 as a transfer checksum caused complete files
to be discarded and retried. The exception now applies only to Rule34 video
metadata, retaining transport length, nonempty-content and error-page checks.
Other sources and images retain their checksum validation. Source evidence:
https://rule34.xxx/?id=4216&page=forum&pid=4620&s=view (administrator reply).

Videos always select the full file URL, including when image quality is Sample.

The drawer follows new unfinished batches until the user explicitly expands,
collapses, filters, pages, or inspects a file. Automatic expansion collapses on
completion; explicit inspection and notification focus remain open. Follow active
downloads restores automatic behavior. Completed history stays collapsed.
Transfers stay inside their batch; off-page active batches have a navigation link.
Quick actions are not repeated in item menus or the detail sheet, and single-item
batches avoid duplicate quick actions. Counts have labels and retry errors remain
visible. Drawer colors are checked for readable contrast, including button icons.

Validation (no automated tests run):

- FVM Flutter 3.47.9: targeted static analysis and merged Android x64 debug build.
- Android 17 emulator, local 61,584-byte MP4: Rule34 Original and Sample settings
  both saved on attempt one despite intentionally mismatched upload metadata.
  The sample URL received no requests.
- Another source's deliberately wrong checksum still triggered retries; its
  failure reason and countdown were visible during cooldown.
- New batches expanded and automatically completed batches collapsed. Thumbnails,
  byte progress, notification focus and light-theme errors were inspected.
- Halloween/AMOLED runtime contrast: body 16.29:1, actions/button text/icons
  21:1, error text 12.37:1. No Flutter runtime errors were reported.
- English/Russian download keys: 130 each, exact key parity.

Native iOS execution was not validated on this Windows host. The shared Dart
preparation changes also apply to newly submitted native transfers; already
submitted iOS transfers remain owned by their native ledger until reconciliation.
