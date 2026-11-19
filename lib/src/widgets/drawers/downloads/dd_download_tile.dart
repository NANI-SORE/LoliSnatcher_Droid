import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/downloads/transfer_preparation.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_presentation.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_action_label.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

typedef DownloadItemAction = Future<void> Function(String command, DownloadTask item);

class DDDownloadTile extends StatefulWidget {
  const DDDownloadTile({required this.item, required this.onAction, this.onTap, this.busy = false, super.key});
  final DownloadTask item;
  final DownloadItemAction onAction;
  final VoidCallback? onTap;
  final bool busy;
  @override
  State<DDDownloadTile> createState() => _DDDownloadTileState();
}

class _DDDownloadTileState extends State<DDDownloadTile> {
  late BooruItem _preview;
  DateTime _sampledAt = DateTime.now(), _lastMovement = DateTime.now();
  double _speed = 0;

  List<({String command, String label, IconData icon})> get _actions {
    final item = widget.item;
    final primary = downloadPrimaryAction(item);
    return [
      if (primary != null && primary.command != 'details') primary,
      if (widget.onTap != null) (command: 'details', label: 'details', icon: Icons.info_outline),
      if (item.state.terminal)
        (command: 'redownload', label: 'redownload', icon: Icons.download_outlined)
      else if (item.state != .finalizing && item.stage != 'publishing')
        (command: 'cancel', label: 'cancel', icon: Icons.close),
    ];
  }

  Future<void> _showActions() async {
    if (widget.busy || _actions.isEmpty) return;
    final command = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in _actions)
              ListTile(
                leading: Icon(action.icon),
                title: Text(downloadText(action.label)),
                onTap: () => Navigator.pop(context, action.command),
              ),
          ],
        ),
      ),
    );
    if (mounted && command != null) _act(command);
  }

  void _act(String command) {
    if (command == 'details') {
      widget.onTap?.call();
    } else {
      unawaited(widget.onAction(command, widget.item));
    }
  }

  void _readPreview() {
    final data = widget.item.transfer.item;
    _preview = BooruItem.fromMap({...data, 'tags': data['tags'] ?? []})
      ..rating = data['rating'] as String?
      ..fileNameExtras = data['fileNameExtras'] as String? ?? '';
  }

  @override
  void initState() {
    super.initState();
    _readPreview();
  }

  @override
  void didUpdateWidget(DDDownloadTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = DateTime.now();
    final elapsed = now.difference(_sampledAt).inMilliseconds;
    final delta = widget.item.received - oldWidget.item.received;
    if (oldWidget.item.attemptId != widget.item.attemptId || !downloadIsMoving(widget.item)) {
      _speed = 0;
    } else if (elapsed > 0 && delta > 0) {
      final speed = delta * 1000 / elapsed;
      _speed = _speed == 0 ? speed : _speed * .65 + speed * .35;
      _lastMovement = now;
    }
    _sampledAt = now;
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.transfer.item['thumbnailURL'] != widget.item.transfer.item['thumbnailURL']) {
      _readPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final transfer = item.transfer;
    final scheme = Theme.of(context).colorScheme;
    final source = SettingsHandler.instance.booruList.where((b) => b.name == transfer.sourceName).firstOrNull;
    final allowed =
        source != null && sourceIdentity(source) == transfer.sourceKey && ContentPolicy.isItemAllowed(source, _preview);
    final hasThumbnail = Uri.tryParse(_preview.thumbnailURL)?.hasAuthority == true;
    final primary = downloadPrimaryAction(item);
    final action = primary?.command == 'details' && widget.onTap == null ? null : primary;
    final size = item.total > 0 ? item.total : transfer.expectedSize ?? 0;
    final moving = downloadIsMoving(item);
    final saving = item.state == .finalizing || item.stage == 'publishing' && moving;
    final speed = moving && DateTime.now().difference(_lastMovement).inSeconds < 3 ? _speed : 0.0;
    final remaining = size > item.received && speed > 0 ? ((size - item.received) / speed).ceil() : 0;
    final progress = downloadProgressText(item);
    final needsHelp = item.state == .failed || item.state == .needsAction;
    final countdown = ((item.nextEligible - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final status = needsHelp ? downloadErrorText(item.error) : itemStateText(item);
    final postId = transfer.item['serverId']?.toString();
    final title = postId?.isNotEmpty == true ? '${transfer.sourceName} · #$postId' : transfer.filename;
    final sample = transfer.quality.toLowerCase() == 'sample';
    final metadata = [
      if (postId?.isNotEmpty != true) transfer.sourceName,
      p.extension(transfer.filename).replaceFirst('.', '').toUpperCase(),
      downloadText(sample ? 'sample' : 'original'),
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.busy ? null : _showActions,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 80,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: allowed && hasThumbnail
                      ? IgnorePointer(
                          child: Thumbnail(
                            item: _preview,
                            booru: source,
                            isStandalone: true,
                            useHero: false,
                            forceThumbnail: true,
                          ),
                        )
                      : Icon(
                          allowed ? Icons.image_outlined : Icons.hide_image_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    countdown > 0 && !item.state.terminal && item.state != .paused && !needsHelp
                        ? '$status · ${downloadDuration(countdown)}'
                        : status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: needsHelp ? scheme.error : scheme.primary),
                  ),
                  if (moving || saving) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: saving || size <= 0 ? null : (item.received / size).clamp(0, 1),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                  if (progress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(progress, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  if (speed > 0)
                    Text(
                      '${downloadBytes(speed.round())}/${loc.secondsShort}${remaining > 0 ? ' · ${downloadText('timeLeft', {'time': downloadDuration(remaining)})}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(downloadStateIcon(item), size: 20, color: scheme.onSurfaceVariant),
                    )
                  else
                    IconButton(
                      tooltip: downloadText(action.label),
                      onPressed: widget.busy
                          ? null
                          : action.command == 'details'
                          ? widget.onTap
                          : () => widget.onAction(action.command, item),
                      icon: Icon(action.icon),
                    ),
                  if (_actions.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: downloadText('actions'),
                      enabled: !widget.busy,
                      padding: EdgeInsets.zero,
                      onSelected: _act,
                      itemBuilder: (_) => [
                        for (final entry in _actions)
                          PopupMenuItem(
                            value: entry.command,
                            child: DDActionLabel(icon: entry.icon, label: downloadText(entry.label)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DDDownloadDetails extends StatefulWidget {
  const DDDownloadDetails({required this.item, required this.handler, required this.onAction, super.key});
  final DownloadTask item;
  final SnatchHandler handler;
  final DownloadItemAction onAction;
  @override
  State<DDDownloadDetails> createState() => _DDDownloadDetailsState();
}

class _DDDownloadDetailsState extends State<DDDownloadDetails> {
  late DownloadTask item = widget.item;
  Worker? _listener;
  bool _reading = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _listener = ever(widget.handler.revision, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final current = await (await widget.handler.store).task(item.id);
      if (mounted && current != null) setState(() => item = current);
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('readError'));
    } finally {
      _reading = false;
    }
  }

  Future<void> _act(String command, DownloadTask task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAction(command, task);
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('actionError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        SelectableText(value),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DDDownloadTile(item: item, busy: _busy, onAction: _act),
          const Divider(height: 1),
          _field(downloadText('file'), item.transfer.filename),
          _field(downloadText('destination'), item.result ?? item.transfer.destination.path),
          if (item.attempts > 1) _field(downloadText('attempts'), '${item.attempts} / 5'),
          if (item.warning?.isNotEmpty == true) _field(downloadText('notice'), downloadText('providerRenamed')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                if (downloadPrimaryAction(item)?.command == 'details' && item.error != 'photosAmbiguous')
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _act('retry', item),
                    icon: const Icon(Icons.refresh),
                    label: Text(downloadText('retryItem')),
                  ),
                if (item.state == .needsAction)
                  if (const [
                    'http401',
                    'http403',
                    'authentication',
                    'sourceMissing',
                    'sourceAmbiguous',
                    'proxyConfiguration',
                    'configurationChanged',
                  ].contains(item.error))
                    TextButton.icon(
                      onPressed: _busy ? null : () => _act('source', item),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(downloadText('sourceSettings')),
                    )
                  else if (item.error == 'photosAmbiguous')
                    TextButton(
                      onPressed: _busy ? null : () => _act('photos', item),
                      child: Text(downloadText('photosRetry')),
                    )
                  else if (item.error == 'storage')
                    TextButton(
                      onPressed: _busy ? null : () => _act('storage', item),
                      child: Text(downloadText('storageAccess')),
                    )
                  else if (item.error == 'photosPermission' || item.error == 'localNetworkPermission')
                    TextButton(
                      onPressed: _busy ? null : () => _act('system', item),
                      child: Text(downloadText('systemSettings')),
                    ),
                if (item.state.terminal)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _act('redownload', item),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(downloadText('redownload')),
                  )
                else if (item.state != .finalizing && item.stage != 'publishing')
                  TextButton(onPressed: _busy ? null : () => _act('cancel', item), child: Text(downloadText('cancel'))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
