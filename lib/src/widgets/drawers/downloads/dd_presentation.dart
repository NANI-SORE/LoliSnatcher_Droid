import 'package:flutter/material.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

String downloadStateText(DownloadState state) => downloadText(switch (state) {
  .prepared => 'queued',
  _ => state.name,
});

String downloadErrorText(String? error) => downloadText(switch (error) {
  'http401' || 'http403' || 'authentication' => 'authentication',
  'photosPermission' ||
  'photosAmbiguous' ||
  'storage' ||
  'network' ||
  'foregroundOnly' ||
  'paginationStalled' ||
  'localNetworkPermission' ||
  'publicationAmbiguous' ||
  'sourceRestricted' ||
  'configurationChanged' => error!,
  'sourceMissing' || 'sourceAmbiguous' => 'sourceMissing',
  'proxyConfiguration' => 'proxyError',
  'invalidSize' || 'checksum' || 'invalidContent' || 'incompleteFile' => 'invalidContent',
  'http429' || 'http503' => 'siteCooldown',
  'timeout' => 'timeout',
  _ => 'unknownError',
});

bool downloadIsMoving(DownloadTask item) =>
    item.state == .transferring ||
    item.state == .prepared &&
        item.received > 0 &&
        item.error == null &&
        item.nextEligible <= DateTime.now().millisecondsSinceEpoch;

String itemStateText(DownloadTask item) {
  if (item.state == .prepared || item.state == .queued) {
    if (item.error == 'network') return downloadText('waitingNetwork');
    if (item.nextEligible > DateTime.now().millisecondsSinceEpoch) return downloadText('retrying');
    if (item.stage == 'publishing') return downloadText('finalizing');
    if (downloadIsMoving(item)) return downloadText('transferring');
  }
  return downloadStateText(item.state);
}

String downloadBytes(int value) => Tools.formatBytes(value, 1, withTrailingZeroes: false);
String downloadDuration(int seconds) => seconds < 60
    ? '$seconds${loc.secondsShort}'
    : seconds < 3600
    ? '${seconds ~/ 60}${loc.minutesShort} ${seconds % 60}${loc.secondsShort}'
    : '${seconds ~/ 3600}${loc.hoursShort} ${(seconds % 3600) ~/ 60}${loc.minutesShort}';

String downloadProgressText(DownloadTask item) {
  final size = item.total > 0 ? item.total : item.transfer.expectedSize ?? 0;
  if (item.state == .completed || item.state == .skipped) return size > 0 ? downloadBytes(size) : '';
  if (size > 0 && item.received > 0) {
    return '${downloadBytes(item.received)} / ${downloadBytes(size)} · ${(item.received * 100 / size).clamp(0, 100).round()}%';
  }
  return item.received > 0
      ? downloadBytes(item.received)
      : size > 0
      ? downloadBytes(size)
      : '';
}

({String command, String label, IconData icon})? downloadPrimaryAction(DownloadTask item) {
  if (item.state == .needsAction &&
      const [
        'storage',
        'authentication',
        'http401',
        'http403',
        'photosPermission',
        'photosAmbiguous',
        'sourceMissing',
        'sourceAmbiguous',
        'configurationChanged',
        'proxyConfiguration',
        'localNetworkPermission',
      ].contains(item.error)) {
    return (command: 'details', label: 'fixIssue', icon: Icons.build_circle_outlined);
  }
  if (item.state == .failed || item.state == .needsAction) {
    return (command: 'retry', label: 'retryItem', icon: Icons.refresh);
  }
  if (item.state == .paused) return (command: 'resume', label: 'resume', icon: Icons.play_arrow_rounded);
  if (!item.state.terminal && item.state != .finalizing && item.stage != 'publishing') {
    return (command: 'pause', label: 'pause', icon: Icons.pause_rounded);
  }
  return null;
}

IconData downloadStateIcon(DownloadTask item) => switch (item.state) {
  .completed => Icons.check_circle_outline,
  .skipped => Icons.file_download_done,
  .cancelled => Icons.block,
  .failed || .needsAction => Icons.error_outline,
  .paused => Icons.pause_circle_outline,
  .finalizing => Icons.save_outlined,
  .waitingNetwork || .waitingRate => Icons.schedule,
  _ => Icons.downloading_outlined,
};

int batchCount(Map<String, dynamic> batch, String key) => (batch[key] as num?)?.toInt() ?? 0;
bool batchFinding(Map<String, dynamic> batch) =>
    batch['discoveryDone'] == 0 && batch['state'] == 'active' && batch['discoveryState'] == 'active';
bool batchPending(Map<String, dynamic> batch) =>
    batchFinding(batch) || batchCount(batch, 'running') + batchCount(batch, 'waiting') > 0;

String batchStateText(Map<String, dynamic> batch) {
  if (batch['state'] == 'paused' || batch['state'] == 'cancelled') return downloadText(batch['state'] as String);
  if (batch['discoveryState'] == 'needsAction' && batch['discoveryDone'] == 0) return downloadText('needsAction');
  if (batchCount(batch, 'running') > 0) return downloadText('transferring');
  if (batchFinding(batch) && batchCount(batch, 'nextEligible') > DateTime.now().millisecondsSinceEpoch) {
    return downloadText(batch['error'] == 'network' ? 'waitingNetwork' : 'retrying');
  }
  if (batchFinding(batch)) return downloadText('discovering');
  if (batchCount(batch, 'waitingNetwork') > 0) return downloadText('waitingNetwork');
  if (batchCount(batch, 'waitingRate') > 0) return downloadText('waitingRate');
  if (batchCount(batch, 'waiting') > 0) return downloadText('queued');
  if (batchCount(batch, 'failed') > 0) return downloadText('needsAction');
  if (batchCount(batch, 'paused') > 0) return downloadText('paused');
  return downloadText('finished');
}
