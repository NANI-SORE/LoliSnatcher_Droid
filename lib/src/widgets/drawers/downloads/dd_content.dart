import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_share_item.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_retryable_item.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_page.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_download_tile.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_presentation.dart';

class DDContent extends StatefulWidget {
  const DDContent({required this.controller, super.key});
  final DownloadsDrawerController controller;
  @override
  State<DDContent> createState() => _DDContentState();
}

class _DDContentState extends State<DDContent> {
  static const pageSize = 20;
  Worker? _listener, _focusListener;
  List<Map<String, dynamic>> _batches = [];
  List<DownloadTask> _items = [];
  String? _focused, _expanded, _filter, _error;
  int _batchPage = 0, _itemPage = 0, _generation = 0;
  bool _loading = false, _busy = false, _selectedOnce = false;
  bool _moreBatches = false, _moreItems = false, _reload = false;

  @override
  void initState() {
    super.initState();
    final handler = widget.controller.snatchHandler;
    _focused = _expanded = handler.focusedBatch.value;
    _listener = ever(handler.revision, (_) => unawaited(_load()));
    _focusListener = ever(
      handler.focusedBatch,
      (String? value) => _change(() {
        _focused = _expanded = value;
        _itemPage = _batchPage = 0;
        _filter = null;
        _items = [];
      }),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _listener?.dispose();
    _focusListener?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      _reload = true;
      return;
    }
    _loading = true;
    final generation = _generation;
    try {
      final store = await widget.controller.snatchHandler.store;
      final rows = await store.batches(
        batchId: _focused,
        offset: _focused == null ? _batchPage * pageSize : 0,
        limit: pageSize + 1,
      );
      var expanded = _expanded;
      if (!_selectedOnce && expanded == null) expanded = rows.firstOrNull?['id'] as String?;
      final items = expanded == null
          ? <DownloadTask>[]
          : await store.tasks(
              batchId: expanded,
              offset: _itemPage * pageSize,
              limit: pageSize + 1,
              filter: _filter,
            );
      if (mounted && generation == _generation) {
        setState(() {
          _batches = rows.take(pageSize).toList();
          _items = items.take(pageSize).toList();
          _moreBatches = rows.length > pageSize;
          _moreItems = items.length > pageSize;
          _expanded = expanded;
          _selectedOnce = _selectedOnce || rows.isNotEmpty;
          if (_error == downloadText('readError')) _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = downloadText('readError'));
    } finally {
      _loading = false;
      if (mounted && (_reload || generation != _generation)) {
        _reload = false;
        unawaited(_load());
      }
    }
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _error = null;
      _generation++;
    });
    unawaited(_load());
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

  Future<void> _sourceSettings(String? name) async {
    final source = SettingsHandler.instance.booruList.where((e) => e.name == name).firstOrNull;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => source == null ? const BooruPage() : BooruEdit.edit(source)));
  }

  Future<void> _itemAction(String command, DownloadTask item) async {
    switch (command) {
      case 'source':
        await _sourceSettings(item.transfer.sourceName);
      case 'storage':
        await setPermissions();
      case 'system':
        await openAppSettings();
      case 'photos':
        final confirmed = await showDialog<bool>(
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
        if (confirmed == true) await widget.controller.snatchHandler.retryPhotos(item.id);
      default:
        // Let the detail sheet show failures in the sheet, rather than behind it.
        await widget.controller.snatchHandler.command(command, taskId: item.id);
    }
    await _load();
  }

  Future<void> _rowAction(String command, DownloadTask item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _itemAction(command, item);
    } catch (_) {
      if (mounted) setState(() => _error = downloadText('actionError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _details(DownloadTask item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      builder: (_) => DDDownloadDetails(item: item, handler: widget.controller.snatchHandler, onAction: _itemAction),
    );
  }

  Widget _tile(DownloadTask item) => DDDownloadTile(
    key: ValueKey(item.id),
    item: item,
    busy: _busy,
    onTap: () => _details(item),
    onAction: _rowAction,
  );
  Widget _pager(int page, bool hasNext, ValueChanged<int> change) {
    if (page == 0 && !hasNext) return const SizedBox.shrink();
    return Row(
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
          onPressed: hasNext ? () => change(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _batch(Map<String, dynamic> batch) {
    final id = batch['id'] as String;
    final expanded = id == _expanded;
    final total = batchCount(batch, 'total');
    final done = batchCount(batch, 'saved') + batchCount(batch, 'skipped') + batchCount(batch, 'cancelled');
    final failed = batchCount(batch, 'failed');
    final finding = batchFinding(batch);
    final paused = batch['state'] == 'paused' || batchCount(batch, 'paused') > 0;
    final pending = batchPending(batch);
    final discoveryError = batch['discoveryState'] == 'needsAction' && batch['discoveryDone'] == 0;
    final primary = paused
        ? 'resume'
        : pending && !discoveryError
        ? 'pause'
        : failed > 0 || discoveryError
        ? 'retry'
        : null;
    final query = batch['query'] as String?;
    final title = query?.trim().isNotEmpty == true ? query! : batch['title'] as String? ?? downloadText('downloads');
    final count = finding
        ? downloadText('foundCount', {
            'count': batchCount(batch, 'selectedCount'),
            'total': batchCount(batch, 'requestedCount'),
          })
        : downloadText('doneCount', {'count': done, 'total': total});
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _change(() {
              _expanded = expanded ? null : id;
              _itemPage = 0;
              _items = [];
              _filter = null;
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                  const SizedBox(width: 8),
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
                        if (query?.trim().isNotEmpty == true)
                          Text(
                            batch['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Text('${batchStateText(batch)} · $count', style: Theme.of(context).textTheme.bodySmall),
                        if (failed > 0)
                          Text(
                            downloadText('failedCount', {'count': failed}),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Theme.of(context).colorScheme.error),
                          ),
                      ],
                    ),
                  ),
                  if (primary != null)
                    IconButton(
                      tooltip: downloadText(primary == 'retry' ? 'retry' : primary),
                      onPressed: _busy ? null : () => _command(primary, batch: id),
                      icon: Icon(
                        primary == 'pause'
                            ? Icons.pause_rounded
                            : primary == 'resume'
                            ? Icons.play_arrow_rounded
                            : Icons.refresh,
                      ),
                    ),
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    tooltip: downloadText('actions'),
                    onSelected: (value) => _command(value, batch: id),
                    itemBuilder: (_) => [
                      if (failed > 0 && primary != 'retry')
                        PopupMenuItem(value: 'retry', child: Text(downloadText('retry'))),
                      if (pending || paused || failed > 0 || discoveryError)
                        PopupMenuItem(value: 'cancel', child: Text(downloadText('cancelBatch')))
                      else ...[
                        PopupMenuItem(value: 'redownload', child: Text(downloadText('redownload'))),
                        PopupMenuItem(value: 'clear', child: Text(downloadText('clearHistory'))),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pending && total > 0)
            LinearProgressIndicator(value: finding ? null : (done / total).clamp(0, 1), minHeight: 2),
          if (discoveryError)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      downloadErrorText(batch['error'] as String?),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(onPressed: () => _sourceSettings(null), child: Text(downloadText('sourceSettings'))),
                ],
              ),
            ),
          if (expanded) ...[
            if (batch['discoveryDone'] == 1 && batchCount(batch, 'selectedCount') < batchCount(batch, 'requestedCount'))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  downloadText('exhausted', {'count': batchCount(batch, 'selectedCount')}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final filter in const [
                    ('all', 'allItems'),
                    ('active', 'activeItems'),
                    ('attention', 'needsAction'),
                    ('complete', 'finished'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(downloadText(filter.$2)),
                        selected: (_filter ?? 'all') == filter.$1,
                        onSelected: (_) => _change(() {
                          _filter = filter.$1 == 'all' ? null : filter.$1;
                          _itemPage = 0;
                          _items = [];
                        }),
                      ),
                    ),
                ],
              ),
            ),
            for (final item in _items) _tile(item),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  downloadText(
                    _loading
                        ? 'loading'
                        : finding
                        ? 'discovering'
                        : 'noMatchingItems',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            _pager(
              _itemPage,
              _moreItems,
              (value) => _change(() {
                _itemPage = value;
                _items = [];
              }),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = widget.controller.snatchHandler;
    return Column(
      children: [
        Obx(
          () => handler.status.value == 'resumeRequired'
              ? ListTile(
                  dense: true,
                  leading: const Icon(Icons.pause_circle_outline),
                  title: Text(downloadText('resumeRequired')),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _command('resume'),
                    child: Text(downloadText('resume')),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_focused != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _change(() {
                _focused = null;
                _batchPage = 0;
              }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(downloadText('allBatches')),
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Obx(() {
            final active = (handler.summary['activeTasks'] as List? ?? [])
                .map((row) => DownloadTask.fromRow(downloadMap(row)))
                .where((task) => !_items.any((item) => item.id == task.id))
                .toList();
            final share = handler.currentShare.value;
            final retries = [...handler.failedItems, ...handler.cancelledItems];
            if (_batches.isEmpty && active.isEmpty && share == null && retries.isEmpty) {
              return Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_outlined, size: 40),
                          const SizedBox(height: 12),
                          Text(downloadText('empty')),
                        ],
                      ),
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (share != null)
                  for (var index = handler.shareProgress.value; index < share.booruItems.length; index++)
                    DDShareItem(
                      item: share.booruItems[index],
                      handler: widget.controller.getHandler(share.booru),
                      index: index - handler.shareProgress.value,
                      isFirst: index == handler.shareProgress.value,
                      shareProgress: handler.shareProgress.value,
                      totalItems: share.booruItems.length,
                    ),
                for (final record in retries)
                  DDRetryableItem(
                    record: record,
                    type: handler.failedItems.contains(record) ? RetryableItemType.failed : RetryableItemType.cancelled,
                    handler: widget.controller.getHandler(record.booru),
                    onRetry: (_) => handler.onRetryShare(record),
                    onSkip: () => handler.onRemoveRetryItem(record),
                  ),
                if (active.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(downloadText('transferring'), style: Theme.of(context).textTheme.labelLarge),
                  ),
                  for (final item in active) _tile(item),
                ],
                for (final batch in _batches) _batch(batch),
                if (_focused == null)
                  _pager(
                    _batchPage,
                    _moreBatches,
                    (value) => _change(() {
                      _batchPage = value;
                      _expanded = null;
                      _items = [];
                    }),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
