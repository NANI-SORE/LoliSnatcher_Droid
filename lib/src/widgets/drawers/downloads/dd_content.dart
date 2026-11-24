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
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_action_label.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_download_tile.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_empty_state.dart';
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
  bool _loading = false, _busy = false, _automatic = true;
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
        _automatic = value == null;
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
      if (mounted && generation == _generation && _focused != null && rows.isEmpty) {
        widget.controller.snatchHandler.focusedBatch.value = null;
        return;
      }
      var expanded = _expanded;
      final visible = rows.take(pageSize).toList();
      var automatic = _automatic;
      if (expanded != null && !visible.any((row) => row['id'] == expanded)) {
        expanded = null;
        automatic = _focused == null;
      }
      if (_focused == null && automatic && _batchPage == 0) {
        final fresh = visible.where((row) => !_batches.any((old) => old['id'] == row['id']) && batchUnfinished(row));
        final current = visible.where((row) => row['id'] == expanded).firstOrNull;
        if (_batches.isNotEmpty && fresh.isNotEmpty) {
          expanded = fresh.first['id'] as String;
        } else if (current == null || !batchUnfinished(current)) {
          final candidates = visible.where(batchUnfinished);
          expanded =
              (candidates.where(batchAttention).firstOrNull ??
                      candidates.where(batchPending).firstOrNull ??
                      candidates.firstOrNull)?['id']
                  as String?;
        }
      }
      final switched = expanded != _expanded;
      final selected = visible.where((row) => row['id'] == expanded).firstOrNull;
      final filter = automatic && _focused == null
          ? selected != null && batchAttention(selected) && !batchPending(selected)
                ? 'attention'
                : 'active'
          : _filter;
      final itemPage = switched || filter != _filter ? 0 : _itemPage;
      final items = expanded == null
          ? <DownloadTask>[]
          : await store.tasks(
              batchId: expanded,
              offset: itemPage * pageSize,
              limit: pageSize + 1,
              filter: filter,
            );
      if (mounted && generation == _generation) {
        setState(() {
          _batches = rows.take(pageSize).toList();
          _items = items.take(pageSize).toList();
          _moreBatches = rows.length > pageSize;
          _moreItems = items.length > pageSize;
          _expanded = expanded;
          _automatic = automatic;
          _filter = filter;
          _itemPage = itemPage;
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
    setState(() => _automatic = false);
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
    final live = (widget.controller.snatchHandler.summary['activeTasks'] as List? ?? [])
        .map((row) => DownloadTask.fromRow(downloadMap(row)))
        .where((task) => task.transfer.batchId == id && !_items.any((item) => item.id == task.id))
        .toList();
    final primary = paused
        ? 'resume'
        : pending && !discoveryError
        ? 'pause'
        : failed > 0 || discoveryError
        ? 'retry'
        : null;
    final rowHasPrimary =
        expanded &&
        total == 1 &&
        !finding &&
        !discoveryError &&
        _items.length == 1 &&
        downloadPrimaryAction(_items.single)?.command == primary;
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
              _automatic = false;
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
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                          ),
                      ],
                    ),
                  ),
                  if (primary != null && !rowHasPrimary)
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
                      if (rowHasPrimary && primary != null)
                        PopupMenuItem(
                          value: primary,
                          child: DDActionLabel(
                            icon: primary == 'pause'
                                ? Icons.pause_rounded
                                : primary == 'resume'
                                ? Icons.play_arrow_rounded
                                : Icons.refresh,
                            label: downloadText(primary),
                          ),
                        ),
                      if (pending && primary != 'pause')
                        PopupMenuItem(
                          value: 'pause',
                          child: DDActionLabel(icon: Icons.pause_rounded, label: downloadText('pause')),
                        ),
                      if (failed > 0 && primary != 'retry')
                        PopupMenuItem(
                          value: 'retry',
                          child: DDActionLabel(icon: Icons.refresh, label: downloadText('retry'), count: failed),
                        ),
                      if (pending || paused || failed > 0 || discoveryError)
                        PopupMenuItem(
                          value: 'cancel',
                          child: DDActionLabel(icon: Icons.close, label: downloadText('cancelBatch')),
                        )
                      else ...[
                        PopupMenuItem(
                          value: 'redownload',
                          child: DDActionLabel(
                            icon: Icons.download_outlined,
                            label: downloadText('redownload'),
                            count: total,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: DDActionLabel(
                            icon: Icons.playlist_remove,
                            label: downloadText('clearHistory'),
                            count: done,
                          ),
                        ),
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
                          _automatic = false;
                          _filter = filter.$1 == 'all' ? null : filter.$1;
                          _itemPage = 0;
                          _items = [];
                        }),
                      ),
                    ),
                ],
              ),
            ),
            if (_filter == null || _filter == 'active')
              for (final item in live) _tile(item),
            for (final item in _items) _tile(item),
            if (_items.isEmpty && (live.isEmpty || _filter != null && _filter != 'active'))
              if (_loading || finding)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    downloadText(_loading ? 'loading' : 'discovering'),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                DDEmptyState(message: downloadText('noMatchingItems'), compact: true),
            _pager(
              _itemPage,
              _moreItems,
              (value) => _change(() {
                _automatic = false;
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
        Obx(() {
          final status = handler.status.value;
          final blocked = const ['resumeRequired', 'executionError', 'storage'].contains(status);
          final waiting = const ['scheduled', 'waitingSystem', 'starting', 'waitingNetwork'].contains(status);
          if (!blocked && (!waiting || !handler.active.value)) return const SizedBox.shrink();
          return ListTile(
            dense: true,
            leading: Icon(blocked ? Icons.error_outline : Icons.schedule),
            title: Text(downloadText(status == 'scheduled' ? 'waitingSystem' : status)),
            subtitle: status == 'executionError'
                ? Text(downloadErrorText(handler.summary['runtimeError'] as String?))
                : null,
          );
        }),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_focused != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => handler.focusedBatch.value = null,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(downloadText('allBatches')),
            ),
          ),
        if (_focused == null && !_automatic)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _change(() {
                _automatic = true;
                _batchPage = _itemPage = 0;
                _expanded = _filter = null;
                _items = [];
              }),
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(downloadText('followActive')),
            ),
          ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: Obx(() {
            final active = (handler.summary['activeTasks'] as List? ?? [])
                .map((row) => DownloadTask.fromRow(downloadMap(row)))
                .where((task) => _focused == null && !_batches.any((batch) => batch['id'] == task.transfer.batchId))
                .toList();
            if (_batches.isEmpty && active.isEmpty) {
              return _loading
                  ? const Center(child: CircularProgressIndicator())
                  : DDEmptyState(message: downloadText('empty'));
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final batchId in active.map((item) => item.transfer.batchId).toSet())
                  ListTile(
                    leading: const Icon(Icons.downloading_outlined),
                    title: Text(downloadText('otherActiveBatch')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => handler.focusedBatch.value = batchId,
                  ),
                for (final batch in _batches) _batch(batch),
                if (_focused == null)
                  _pager(
                    _batchPage,
                    _moreBatches,
                    (value) => _change(() {
                      _batchPage = value;
                      _automatic = value == 0;
                      _expanded = null;
                      _itemPage = 0;
                      _filter = null;
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
