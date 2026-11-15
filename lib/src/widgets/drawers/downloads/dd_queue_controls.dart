import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';

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
    final needsResume = handler.status.value == 'resumeRequired' || pending == 0 && paused > 0;
    final command = needsResume
        ? 'resume'
        : pending > 0
        ? 'pause'
        : failed > 0
        ? 'retry'
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 6),
          child: Row(
            children: [
              Expanded(child: Text(downloadText('downloads'), style: Theme.of(context).textTheme.titleLarge)),
              if (command != null)
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
                    if (paused > 0 && command != 'resume')
                      PopupMenuItem(value: 'resume', child: Text(downloadText('resumeAll'))),
                    if (failed > 0 && command != 'retry')
                      PopupMenuItem(value: 'retry', child: Text(downloadText('retry'))),
                    if (pending + paused + failed > 0)
                      PopupMenuItem(value: 'cancel', child: Text(downloadText('cancelAll'))),
                    if (finished > 0) PopupMenuItem(value: 'clear', child: Text(downloadText('clearHistory'))),
                  ],
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_failed) Padding(padding: const EdgeInsets.all(8), child: Text(downloadText('actionError'))),
      ],
    );
  });
}
