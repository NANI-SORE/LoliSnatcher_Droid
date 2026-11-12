import 'package:lolisnatcher/src/downloads/download_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_page.dart';

String downloadStateText(DownloadState state) => switch (state) {
  .queued => downloadText('queued'),
  .prepared => downloadText('prepared'),
  .discovering => downloadText('discovering'),
  .transferring => downloadText('transferring'),
  .finalizing => downloadText('finalizing'),
  .completed => downloadText('completed'),
  .skipped => downloadText('skipped'),
  .paused => downloadText('paused'),
  .cancelled => downloadText('cancelled'),
  .failed => downloadText('failed'),
  .waitingNetwork => downloadText('waitingNetwork'),
  .waitingRate => downloadText('waitingRate'),
  .needsAction => downloadText('needsAction'),
};

String downloadErrorText(String? error) {
  if (error == null) return '';
  if (const ['http401', 'http403', 'authentication'].contains(error)) return downloadText('authentication');
  if (error.contains('photosPermission')) return downloadText('photosPermission');
  if (error.contains('photosAmbiguous')) return downloadText('photosAmbiguous');
  if (error.contains('storage')) return downloadText('storage');
  return switch (error) {
    'network' => downloadText('network'),
    'foregroundOnly' => downloadText('foregroundOnly'),
    'sourceMissing' || 'sourceAmbiguous' => downloadText('sourceMissing'),
    'paginationStalled' => downloadText('paginationStalled'),
    'localNetworkPermission' => downloadText('localNetworkPermission'),
    'invalidSize' || 'checksum' || 'invalidContent' => downloadText('invalidContent'),
    'http429' || 'http503' => downloadText('siteCooldown'),
    'publicationAmbiguous' => downloadText('publicationAmbiguous'),
    'sourceRestricted' => downloadText('sourceRestricted'),
    'configurationChanged' => downloadText('configurationChanged'),
    _ => downloadText('unknownError'),
  };
}

String batchStateText(Map<String, dynamic> batch) {
  if (batch['state'] == 'paused' || batch['state'] == 'cancelled') return downloadText(batch['state'] as String);
  if (batch['discoveryState'] == 'needsAction') return downloadText('needsAction');
  if (batch['discoveryDone'] == 0) {
    if ((batch['nextEligible'] as int? ?? 0) > DateTime.now().millisecondsSinceEpoch) {
      return downloadText(batch['error'] == 'network' ? 'waitingNetwork' : 'waitingRate');
    }
    return downloadText('discovering');
  }
  return '';
}

String itemStateText(DownloadTask item) {
  if (item.state == .prepared) {
    if (item.error == 'network') return downloadText('waitingNetwork');
    if (item.nextEligible > DateTime.now().millisecondsSinceEpoch) return downloadText('waitingRate');
    if (item.stage == 'publishing') return downloadText('finalizing');
    if (item.received > 0) return downloadText('transferring');
  }
  return downloadStateText(item.state);
}

class DDContent extends StatefulWidget {
  const DDContent({required this.controller, super.key});
  final DownloadsDrawerController controller;
  @override
  State<DDContent> createState() => _DDContentState();
}

class _DDContentState extends State<DDContent> {
  static const pageSize = 20;
  Worker? _listener;
  Worker? _focusListener;
  String? _focused;
  List<Map<String, dynamic>> _batches = [];
  List<DownloadTask> _items = [];
  String? _expanded, _filter;
  String? _error;
  int _batchPage = 0, _itemPage = 0;
  bool _loading = false, _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _expanded = widget.controller.snatchHandler.focusedBatch.value;
    _focused = _expanded;
    _listener = ever(widget.controller.snatchHandler.revision, (_) => unawaited(_load()));
    _focusListener = ever(widget.controller.snatchHandler.focusedBatch, (String? value) {
      _change(() {
        _focused = value;
        _expanded = value;
        _itemPage = 0;
        _filter = null;
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _listener?.dispose();
    _focusListener?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final generation = _generation;
    try {
      final store = await widget.controller.snatchHandler.store;
      final batches = await store.batches(
        batchId: _focused,
        offset: _focused == null ? _batchPage * pageSize : 0,
        limit: pageSize,
      );
      final items = _expanded == null
          ? <DownloadTask>[]
          : await store.tasks(batchId: _expanded, offset: _itemPage * pageSize, limit: pageSize, filter: _filter);
      if (mounted && generation == _generation) {
        setState(() {
          _batches = batches;
          _items = items;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('readError'));
    } finally {
      _loading = false;
    }
  }

  Future<void> _command(String command, {String? batch, String? task}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.snatchHandler.command(command, batchId: batch, taskId: task);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('actionError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _generation++;
    });
    unawaited(_load());
  }

  Widget _menu({String? batch, DownloadTask? task}) => PopupMenuButton<String>(
    enabled: !_busy,
    tooltip: downloadText('actions'),
    onSelected: (value) => _command(value, batch: batch, task: task?.id),
    itemBuilder: (_) => [
      if (task == null || !task.state.terminal) PopupMenuItem(value: 'pause', child: Text(downloadText('pause'))),
      if (task == null || task.state == .paused || task.state == .waitingRate || task.state == .waitingNetwork)
        PopupMenuItem(value: 'resume', child: Text(downloadText('resume'))),
      if (task == null || task.state == .failed || task.state == .needsAction)
        PopupMenuItem(value: 'retry', child: Text(downloadText('retry'))),
      if (task == null || task.state.terminal || task.state == .needsAction)
        PopupMenuItem(value: 'redownload', child: Text(downloadText('redownload'))),
      if (task == null || !task.state.terminal) PopupMenuItem(value: 'cancel', child: Text(downloadText('cancel'))),
    ],
  );
  Widget _pager(int page, bool hasNext, void Function(int) change) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: downloadText('previous'),
        onPressed: page == 0 ? null : () => change(page - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      Text(downloadText('page', {'page': page + 1})),
      IconButton(
        tooltip: downloadText('next'),
        onPressed: !hasNext ? null : () => change(page + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Future<void> _retryPhotos(DownloadTask item) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(downloadText('photosRetryTitle')),
        content: Text(downloadText('photosRetryWarning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(downloadText('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(downloadText('exportAgain'))),
        ],
      ),
    );
    if (retry != true) return;
    try {
      await widget.controller.snatchHandler.retryPhotos(item.id);
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('actionError'));
    }
  }

  Future<void> _sourceSettings(String? name) async {
    final source = SettingsHandler.instance.booruList.where((e) => e.name == name).firstOrNull;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => source == null ? const BooruPage() : BooruEdit.edit(source)));
  }

  @override
  Widget build(BuildContext context) {
    final handler = widget.controller.snatchHandler;
    return Column(
      children: [
        Obx(
          () => handler.status.value == 'resumeRequired'
              ? ListTile(
                  leading: const Icon(Icons.pause_circle_outline),
                  title: Text(downloadText('resumeRequired')),
                  subtitle: Text(downloadText('systemStopped')),
                  trailing: TextButton(onPressed: () => _command('resume'), child: Text(downloadText('resume'))),
                )
              : const SizedBox.shrink(),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        if (_focused != null)
          TextButton.icon(
            onPressed: () => _change(() {
              _focused = null;
              _batchPage = 0;
            }),
            icon: const Icon(Icons.arrow_back),
            label: Text(downloadText('allBatches')),
          ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _batches.isEmpty
              ? Center(child: _loading ? const CircularProgressIndicator() : Text(downloadText('empty')))
              : ListView.builder(
                  itemCount: _batches.length,
                  itemBuilder: (context, index) {
                    final batch = _batches[index];
                    final id = batch['id'] as String;
                    final expanded = id == _expanded;
                    final finding = batch['discoveryDone'] == 0;
                    final total = (batch['total'] as num?)?.toInt() ?? 0;
                    final selected = (batch['selectedCount'] as num?)?.toInt() ?? 0;
                    final saved = (batch['saved'] as num?)?.toInt() ?? 0;
                    final skipped = (batch['skipped'] as num?)?.toInt() ?? 0;
                    final failed = (batch['failed'] as num?)?.toInt() ?? 0;
                    return Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            onTap: () => _change(() {
                              _expanded = expanded ? null : id;
                              _itemPage = 0;
                              _items = [];
                            }),
                            leading: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                            title: Text(
                              batch['title'] as String? ?? downloadText('downloads'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${batchStateText(batch).isEmpty ? "" : "${batchStateText(batch)} · "}'
                              '${downloadText('selected', {'selected': selected, 'requested': batch['requestedCount'] as int, 'files': total})}\n'
                              '${downloadText('counts', {'saved': saved, 'skipped': skipped, 'failed': failed})}',
                            ),
                            trailing: _menu(batch: id),
                          ),
                          if (batch['error'] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(downloadErrorText(batch['error'] as String?)),
                                  if (batch['discoveryState'] == 'needsAction')
                                    TextButton(
                                      onPressed: () => _sourceSettings(null),
                                      child: Text(downloadText('sourceSettings')),
                                    ),
                                ],
                              ),
                            ),
                          if (!finding && selected < (batch['requestedCount'] as num))
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(downloadText('exhausted', {'count': selected})),
                            ),
                          if (expanded) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: DropdownButton<String>(
                                value: _filter ?? 'all',
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(value: 'all', child: Text(downloadText('allItems'))),
                                  DropdownMenuItem(value: 'active', child: Text(downloadText('activeItems'))),
                                  DropdownMenuItem(value: 'attention', child: Text(downloadText('needsAction'))),
                                  DropdownMenuItem(value: 'complete', child: Text(downloadText('finishedItems'))),
                                ],
                                onChanged: (value) => _change(() {
                                  _filter = value == 'all' ? null : value;
                                  _itemPage = 0;
                                }),
                              ),
                            ),
                            for (final item in _items)
                              ListTile(
                                dense: true,
                                title: Text(item.transfer.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(itemStateText(item)),
                                    if (item.total > 0 && !item.state.terminal)
                                      LinearProgressIndicator(value: (item.received / item.total).clamp(0, 1)),
                                    if (item.error != null) Text(downloadErrorText(item.error)),
                                    if (item.state == .needsAction)
                                      Wrap(
                                        children: [
                                          if (const [
                                            'http401',
                                            'http403',
                                            'authentication',
                                            'sourceMissing',
                                            'sourceAmbiguous',
                                            'proxyConfiguration',
                                          ].contains(item.error))
                                            TextButton(
                                              onPressed: () => _sourceSettings(item.transfer.sourceName),
                                              child: Text(downloadText('sourceSettings')),
                                            ),
                                          if (item.error == 'photosAmbiguous')
                                            TextButton(
                                              onPressed: () => _retryPhotos(item),
                                              child: Text(downloadText('photosRetry')),
                                            ),
                                          if (item.error?.contains('storage') == true)
                                            TextButton(
                                              onPressed: () async {
                                                await setPermissions();
                                              },
                                              child: Text(downloadText('storageAccess')),
                                            ),
                                          if (item.error?.contains('photos') == true ||
                                              item.error == 'localNetworkPermission')
                                            TextButton(
                                              onPressed: openAppSettings,
                                              child: Text(downloadText('systemSettings')),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                                trailing: _menu(task: item),
                              ),
                            _pager(
                              _itemPage,
                              _items.length == pageSize,
                              (value) => _change(() {
                                _itemPage = value;
                              }),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (_focused == null)
          _pager(
            _batchPage,
            _batches.length == pageSize,
            (value) => _change(() {
              _batchPage = value;
              _expanded = null;
            }),
          ),
      ],
    );
  }
}
