import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_action_label.dart';

class DDQueueControls extends StatefulWidget {
  const DDQueueControls({required this.controller, super.key});
  final DownloadsDrawerController controller;
  @override
  State<DDQueueControls> createState() => _DDQueueControlsState();
}

class _DDQueueControlsState extends State<DDQueueControls> {
  bool _busy = false, _failed = false;
  Future<void> _command(String command) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.controller.snatchHandler.command(command);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final handler = widget.controller.snatchHandler;
    final summary = handler.summary;
    int count(String state) => (summary[state] as num?)?.toInt() ?? 0;
    final pending = [
      'queued',
      'prepared',
      'transferring',
      'finalizing',
      'waitingNetwork',
      'waitingRate',
      'discovery',
    ].fold(0, (a, b) => a + count(b));
    final paused = count('paused') + count('discoveryPaused');
    final failed = count('failed') + count('needsAction') + count('discoveryAttention');
    final finished = count('completed') + count('skipped') + count('cancelled');
    final hostNeedsResume = const [
      'resumeRequired',
      'executionError',
      'storage',
      'waitingSystem',
      'scheduled',
    ].contains(handler.status.value);
    final needsResume = hostNeedsResume || pending == 0 && paused > 0;
    final command = needsResume
        ? 'resume'
        : pending > 0
        ? 'pause'
        : failed > 0
        ? 'retry'
        : null;
    final showPrimary =
        command != null && (hostNeedsResume || count('unfinishedBatches') > 1 && handler.focusedBatch.value == null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 6),
          child: Row(
            children: [
              Expanded(child: Text(downloadText('downloads'), style: Theme.of(context).textTheme.titleLarge)),
              if (showPrimary)
                IconButton(
                  tooltip: downloadText(
                    command == 'pause'
                        ? 'pauseAll'
                        : command == 'resume'
                        ? 'resumeAll'
                        : 'retry',
                  ),
                  onPressed: _busy ? null : () => _command(command),
                  icon: Icon(
                    command == 'pause'
                        ? Icons.pause_rounded
                        : command == 'resume'
                        ? Icons.play_arrow_rounded
                        : Icons.refresh,
                  ),
                ),
              if (pending + paused + failed + finished > 0)
                PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: downloadText('actions'),
                  onSelected: _command,
                  itemBuilder: (_) => [
                    if (pending > 0 && (!showPrimary || command != 'pause'))
                      PopupMenuItem(
                        value: 'pause',
                        child: DDActionLabel(icon: Icons.pause_rounded, label: downloadText('pauseAll')),
                      ),
                    if ((paused > 0 || needsResume) && (!showPrimary || command != 'resume'))
                      PopupMenuItem(
                        value: 'resume',
                        child: DDActionLabel(
                          icon: Icons.play_arrow_rounded,
                          label: downloadText('resumeAll'),
                          count: count('paused') > 0 ? count('paused') : null,
                        ),
                      ),
                    if (failed > 0 && (!showPrimary || command != 'retry'))
                      PopupMenuItem(
                        value: 'retry',
                        child: DDActionLabel(
                          icon: Icons.refresh,
                          label: downloadText('retry'),
                          count: count('failed') + count('needsAction') > 0
                              ? count('failed') + count('needsAction')
                              : null,
                        ),
                      ),
                    if (pending + paused + failed > 0)
                      PopupMenuItem(
                        value: 'cancel',
                        child: DDActionLabel(icon: Icons.close, label: downloadText('cancelAll')),
                      ),
                    if (finished > 0)
                      PopupMenuItem(
                        value: 'clear',
                        child: DDActionLabel(
                          icon: Icons.playlist_remove,
                          label: downloadText('clearHistory'),
                          count: finished,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (pending + paused + failed + finished > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final entry in [
                    ('activeItems', Icons.downloading_outlined, pending - count('discovery')),
                    ('paused', Icons.pause_circle_outline, count('paused')),
                    ('completed', Icons.check_circle_outline, count('completed')),
                    ('skipped', Icons.file_download_done, count('skipped')),
                    ('needsAction', Icons.error_outline, count('failed') + count('needsAction')),
                  ])
                    if (entry.$3 > 0) DDStatusCount(icon: entry.$2, label: downloadText(entry.$1), count: entry.$3),
                ],
              ),
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_failed) Padding(padding: const EdgeInsets.all(8), child: Text(downloadText('actionError'))),
      ],
    );
  });
}
