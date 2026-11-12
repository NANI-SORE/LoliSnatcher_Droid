import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';

class DDQueueControls extends StatefulWidget {
  const DDQueueControls({required this.controller, super.key});
  final DownloadsDrawerController controller;
  @override
  State<DDQueueControls> createState() => _DDQueueControlsState();
}

class _DDQueueControlsState extends State<DDQueueControls> {
  bool _busy = false;
  bool _failed = false;

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
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_busy) const LinearProgressIndicator(),
      if (_failed) Padding(padding: const EdgeInsets.all(8), child: Text(downloadText('actionError'))),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final action in const [
            ('pause', 'pauseAll', Icons.pause),
            ('resume', 'resume', Icons.play_arrow),
            ('retry', 'retry', Icons.refresh),
            ('clear', 'clearHistory', Icons.history),
          ])
            TextButton.icon(
              onPressed: _busy ? null : () => _command(action.$1),
              icon: Icon(action.$3),
              label: Text(downloadText(action.$2)),
            ),
        ],
      ),
    ],
  );
}
