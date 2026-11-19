import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_discovery.dart';
import 'package:lolisnatcher/src/downloads/download_network.dart';
import 'package:lolisnatcher/src/downloads/download_notices.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';
import 'package:lolisnatcher/src/downloads/download_transfer.dart';
import 'package:lolisnatcher/src/downloads/transfer_preparation.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';

class DownloadRuntime {
  DownloadRuntime(this.store, this.paths, this.configuration, this.settings, {this.headless = false})
    : gate = DownloadRateGate(store);
  final DownloadStore store;
  final DownloadPaths paths;
  DownloadConfiguration configuration;
  SettingsHandler settings;
  final bool headless;
  final DownloadRateGate gate;
  late final notices = DownloadNotices(store);
  final Map<String, ({CancelToken token, DownloadTask task})> _running = {};
  ({String id, CancelToken token})? _discovery;
  CancelToken? _preparation;
  Timer? _timer;
  bool _pumping = false;
  bool _enabled = false;
  String? _lastRuntimeError;
  bool _settingsReleased = false;
  int _nativeBatchOffset = 0;
  bool _foreground = true;
  bool get foreground => _foreground;
  set foreground(bool value) {
    _foreground = value;
    if (!value && Platform.isIOS) _discovery?.token.cancel();
  }

  Future<void> Function(Map<String, dynamic>)? onSummary;

  Future<void> start({bool enabled = true}) async {
    await store.recover(nativeTransfers: Platform.isIOS);
    _enabled = enabled;
    _timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(pump()));
    await pump();
  }

  Future<void> suspend() async {
    _enabled = false;
    _discovery?.token.cancel();
    _preparation?.cancel();
    for (final entry in _running.values.toList()) {
      final current = await store.task(entry.task.id);
      if (current?.state != DownloadState.finalizing) entry.token.cancel();
    }
  }

  Future<void> reload() async {
    final latest = await DownloadConfiguration.load();
    if (latest != null) {
      final replaceSettings =
          headless && (_settingsReleased || latest.executionIdentity != configuration.executionIdentity);
      if (replaceSettings) await quiesce();
      configuration = latest;
      await configuration.attachCookies(store.db);
      if (replaceSettings) {
        final previous = settings;
        settings = await configuration.backgroundSettings();
        _settingsReleased = false;
        if (previous.dbHandler.db?.isOpen == true) await previous.dbHandler.db?.close();
      }
    }
    _enabled = true;
    _timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(pump()));
  }

  /// Acknowledgement is a barrier: no caller can still read the settings DB.
  Future<void> quiesce() async {
    _timer?.cancel();
    _timer = null;
    await suspend();
    while (_pumping || _discovery != null || _running.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (headless && settings.dbHandler.db?.isOpen == true) await settings.dbHandler.db?.close();
    if (headless) _settingsReleased = true;
  }

  Future<void> pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      if (Platform.isIOS) await _reconcileNative();
      for (final entry in _running.values.toList()) {
        final current = await store.task(entry.task.id);
        if (current == null || current.state == DownloadState.paused || current.state == DownloadState.cancelled) {
          entry.token.cancel();
        }
      }
      final discovery = _discovery;
      if (discovery != null) {
        final row = await store.batch(discovery.id);
        if (row?['state'] != 'active') discovery.token.cancel();
      }
      if (_enabled) {
        if (_discovery == null && (!Platform.isIOS || foreground)) {
          final rows = await store.discoveries();
          if (rows.isNotEmpty) {
            final row = rows.first;
            final token = CancelToken();
            _discovery = (id: row['id'] as String, token: token);
            unawaited(_discover(row, token));
          }
        }
        final ready = await store.ready(preparationOnly: Platform.isIOS);
        final sites = _running.values.map((e) => e.task.transfer.sourceKey).toSet();
        for (final candidate in ready) {
          if (Platform.isIOS && !candidate.transfer.foregroundOnly) {
            final task = await store.claim(candidate.id, native: true);
            if (task != null) {
              // Persist intent in Dart before native task creation. Native submit
              // is idempotent for the attempt ID, including relaunch recovery.
              try {
                final token = CancelToken();
                _preparation = token;
                final fresh = await DioNetwork.runWithCancellation(token, () => _refreshDescriptor(task));
                if (fresh == null) continue;
                if (fresh.transfer.foregroundOnly) {
                  await store.db.update(
                    'tasks',
                    {'state': 'queued', 'attempts': task.attempts - 1},
                    where: "id = ? AND attemptId = ? AND state = 'prepared'",
                    whereArgs: [task.id, task.attemptId],
                  );
                } else {
                  await downloadPlatform.invokeMethod<void>('submit', fresh.toJson());
                }
              } catch (error) {
                final code = DownloadNetwork.errorCode(error);
                await store.db.update(
                  'tasks',
                  {
                    'state': code == 'interrupted' ? 'queued' : 'needsAction',
                    'error': code,
                    if (code == 'interrupted') 'attempts': task.attempts - 1,
                  },
                  where: "id = ? AND attemptId = ? AND state = 'prepared'",
                  whereArgs: [task.id, task.attemptId],
                );
              } finally {
                _preparation = null;
              }
            }
            continue;
          }
          if (_running.length >= 3) break;
          if (_running.containsKey(candidate.id) || sites.contains(candidate.transfer.sourceKey)) continue;
          if (Platform.isIOS && !foreground) {
            await store.setState(candidate.id, DownloadState.needsAction, error: 'foregroundOnly');
            continue;
          }
          final deadline = await store.deadline([
            'site:${candidate.transfer.sourceKey}',
            'host:${candidate.transfer.host}',
          ]);
          if (deadline > DateTime.now().millisecondsSinceEpoch) continue;
          final task = await store.claim(candidate.id);
          if (task == null) continue;
          final token = CancelToken();
          _running[task.id] = (token: token, task: task);
          sites.add(task.transfer.sourceKey);
          unawaited(_transfer(task, token));
        }
      }
      final summary = await store.summary();
      final pending = [
        'queued',
        'prepared',
        'transferring',
        'finalizing',
        'waitingNetwork',
        'waitingRate',
        'discovery',
      ].fold(0, (sum, key) => sum + (summary[key] as int? ?? 0));
      await notices.check(force: _enabled && pending == 0);
      if (Platform.isIOS) {
        await downloadPlatform.invokeMethod<void>('discoveryProgress', {
          'selected': summary['discoverySelected'],
          'requested': summary['discoveryRequested'],
          'done': summary['discovery'] == 0,
        });
      }
      await onSummary?.call(summary);
      if (Platform.isAndroid) {
        await downloadPlatform.invokeMethod<void>('progress', summary);
      }
      if (_lastRuntimeError != null || summary['runtimeError'] != null) {
        await store.db.delete('metadata', where: 'key = ?', whereArgs: ['runtimeError']);
        _lastRuntimeError = null;
      }
    } catch (error) {
      // Persist a generic cause; URLs and credentials never enter notifications.
      final code = DownloadNetwork.errorCode(error);
      if (code != _lastRuntimeError) {
        try {
          await store.db.insert('metadata', {
            'key': 'runtimeError',
            'value': code,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          _lastRuntimeError = code;
        } catch (_) {
          // The foreground store poll reports inaccessible queue storage.
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _discover(Map<String, dynamic> row, CancelToken token) async {
    try {
      await DownloadDiscovery(store, configuration, settings, gate).advance(row, token);
    } catch (error) {
      final code = DownloadNetwork.errorCode(error);
      if (code != 'interrupted') {
        final transient = const [
          'network',
          'timeout',
          'http429',
          'http503',
          'http500',
          'http502',
          'http504',
        ].contains(code);
        final key = 'discoveryAttempts:${row['id']}';
        final attempts = await store.db.query('metadata', where: 'key = ?', whereArgs: [key]);
        final count =
            (int.tryParse(attempts.firstOrNull?['value'] as String? ?? '') ?? 0) + (code == 'network' ? 0 : 1);
        await store.db.insert('metadata', {
          'key': key,
          'value': '$count',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final retryAfter = error is DioException
            ? RateLimitPolicy.retryAfter(error.response?.headers.value('retry-after'), DateTime.now())
            : null;
        final until = DateTime.now().add(
          code == 'network' ? const Duration(seconds: 30) : RateLimitPolicy.backoff(count),
        );
        await store.discoveryError(
          row['id'] as String,
          code,
          actionable: !transient || count >= 5,
          retryAt: retryAfter != null && retryAfter.isAfter(until)
              ? retryAfter.millisecondsSinceEpoch
              : until.millisecondsSinceEpoch,
        );
      }
    } finally {
      _discovery = null;
    }
  }

  Future<void> _transfer(DownloadTask task, CancelToken token) async {
    final network = DownloadNetwork(
      configuration: configuration,
      gate: gate,
      site: task.transfer.sourceKey,
      cooldown: task.transfer.cooldownMs,
      sourceName: task.transfer.sourceName,
    );
    final transfer = DownloadTransfer(store, paths, network);
    try {
      final scope = RequestScope(
        client: network.client,
        cookies: configuration.cookies,
        saveCookies: configuration.saveCookies,
        settings: settings,
        headless: headless,
      );
      await scope.run(
        () => DioNetwork.runWithCancellation(token, () async {
          final fresh = await _refreshDescriptor(task);
          if (fresh == null) return;
          await transfer.run(fresh, token);
          final after = await store.task(task.id);
          if (after?.state == DownloadState.needsAction &&
              const ['http403', 'http404', 'http410'].contains(after?.error) &&
              _canRefresh(task.transfer) &&
              task.attempts < 5) {
            final marker = 'urlRefresh:${task.id}:${task.generation}';
            if ((await store.db.query('metadata', where: 'key = ?', whereArgs: [marker])).isEmpty) {
              await store.db.insert('metadata', {
                'key': 'refreshPending:${task.id}',
                'value': '1',
              }, conflictAlgorithm: ConflictAlgorithm.replace);
              await store.setState(task.id, DownloadState.queued);
            }
          }
        }),
      );
    } catch (error) {
      await transfer.fail(task, error);
    } finally {
      _running.remove(task.id);
    }
  }

  Future<DownloadTask?> _refreshDescriptor(DownloadTask task) async {
    if (task.stage == 'publishing' || task.stage == 'downloaded') return task;
    final descriptor = task.transfer;
    final source = configuration.source(descriptor.sourceName);
    if (source == null || sourceIdentity(source) != descriptor.sourceKey) throw const DownloadBlocked('sourceMissing');
    final network = DownloadNetwork(
      configuration: configuration,
      gate: gate,
      site: descriptor.sourceKey,
      sourceName: descriptor.sourceName,
      cooldown: descriptor.cooldownMs,
    );
    final scope = RequestScope(
      client: network.client,
      cookies: configuration.cookies,
      saveCookies: configuration.saveCookies,
      settings: settings,
      headless: headless,
    );
    return scope.run(() async {
      var item = BooruItem.fromMap(descriptor.item)
        ..serverId = descriptor.item['serverId'] as String?
        ..rating = descriptor.item['rating'] as String?
        ..fileExt = descriptor.item['fileExt'] as String?
        ..fileNameExtras = descriptor.item['fileNameExtras'] as String? ?? ''
        ..fileSize = (descriptor.item['fileSize'] as num?)?.toInt()
        ..md5String = descriptor.item['md5String'] as String?;
      final pending = await store.db.query('metadata', where: 'key = ?', whereArgs: ['refreshPending:${task.id}']);
      final needsDetail = descriptor.item['needsDetail'] == true;
      var refreshed = false;
      if (needsDetail || pending.isNotEmpty) {
        final handler = BooruHandlerFactory().getBooruHandler([source], 100).booruHandler;
        final marker = 'urlRefresh:${task.id}:${task.generation}';
        final used = await store.db.query('metadata', where: 'key = ?', whereArgs: [marker]);
        if (needsDetail || used.isEmpty) {
          await store.db.insert('metadata', {
            'key': marker,
            'value': '1',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          if (!handler.hasLoadItemSupport) throw const DownloadBlocked('detailRequired');
          final response = await handler.loadItem(item: item, withCapcthaCheck: false);
          if (response.failed || response.item == null) throw const DownloadBlocked('detailRequired');
          item = response.item!;
          refreshed = true;
        }
        await store.db.delete('metadata', where: 'key = ?', whereArgs: ['refreshPending:${task.id}']);
      }
      if (!ContentPolicy.isItemAllowed(source, item)) throw const DownloadBlocked('sourceRestricted');
      final prepared = await prepareTransfer(
        source: source,
        item: item,
        batchId: descriptor.batchId,
        configuration: configuration,
        overwrite: descriptor.overwrite,
        cooldownMs: descriptor.cooldownMs,
        policy: {
          'destination': descriptor.destination.toJson(),
          'quality': descriptor.quality,
          'writeJson': descriptor.writeJson,
        },
      );
      final next = prepared.withValues({
        'id': descriptor.id,
        'filename': needsDetail ? prepared.filename : descriptor.filename,
        if (!refreshed) 'url': descriptor.url,
        'sourceKey': descriptor.sourceKey,
      });
      final current = await store.task(task.id);
      if (current?.attemptId != task.attemptId ||
          !const [DownloadState.prepared, DownloadState.transferring].contains(current?.state)) {
        return null;
      }
      await store.updateAttempt(task, {
        'payload': jsonEncode(next.toJson()),
        if (refreshed) 'validator': null,
        if (refreshed) 'stage': '',
      });
      return store.task(task.id);
    });
  }

  bool _canRefresh(PreparedTransfer transfer) {
    final source = configuration.source(transfer.sourceName);
    return source != null && BooruHandlerFactory().getBooruHandler([source], 100).booruHandler.hasLoadItemSupport;
  }

  Future<void> _reconcileNative() async {
    final fenceIds = <String>[];
    for (final raw in await downloadPlatform.invokeListMethod<dynamic>('fences') ?? []) {
      final fence = downloadMap(raw);
      final id = fence['id'] as String;
      final isTask = id.startsWith('fence:task:');
      final target = id.substring(isTask ? 'fence:task:'.length : 'fence:batch:'.length);
      final generation = isTask
          ? (await store.task(target))?.generation
          : (await store.batch(target))?['generation'] as int?;
      if (generation != null && generation < (fence['generation'] as int)) {
        await store.command(
          fence['state'] == 'cancelled' ? 'cancel' : 'pause',
          taskId: isTask ? target : null,
          batchId: isTask ? null : target,
        );
      }
      fenceIds.add(id);
    }
    if (fenceIds.isNotEmpty) await downloadPlatform.invokeMethod<void>('acknowledgeFences', fenceIds);
    for (final raw in await downloadPlatform.invokeListMethod<dynamic>('progress') ?? []) {
      final progress = downloadMap(raw);
      await store.db.update(
        'tasks',
        {
          'received': progress['received'],
          'total': progress['total'],
          'error': progress['error'] == '' ? null : progress['error'],
          'nextEligible': ((progress['due'] as num?)?.toDouble() ?? 0) * 1000,
          if (const ['publishing', 'staged'].contains(progress['state'])) 'stage': 'publishing',
        },
        where: "id = ? AND attemptId = ? AND state = 'prepared'",
        whereArgs: [progress['taskId'], progress['attemptId']],
      );
    }
    final batches = await store.batches(offset: _nativeBatchOffset);
    _nativeBatchOffset = batches.length == 100 ? _nativeBatchOffset + 100 : 0;
    for (final batch in batches) {
      final spec = DownloadBatchSpec.fromJson(downloadMap(batch['spec']));
      await downloadPlatform.invokeMethod<void>('syncBatch', {
        'id': batch['id'],
        'expected': batch['total'],
        'done': batch['discoveryDone'] == 1,
        'notifications': spec.policy['notifications'] != false,
      });
    }
    final receipts = await downloadPlatform.invokeListMethod<dynamic>('receipts') ?? [];
    final ids = <String>[];
    for (final raw in receipts) {
      final receipt = TransferReceipt.fromJson(downloadMap(raw));
      await store.applyReceipt(receipt);
      final task = await store.task(receipt.taskId);
      if (task?.state == DownloadState.needsAction &&
          task!.attempts < 5 &&
          const ['http403', 'http404', 'http410'].contains(receipt.error) &&
          _canRefresh(task.transfer)) {
        final used = await store.db.query(
          'metadata',
          where: 'key = ?',
          whereArgs: ['urlRefresh:${task.id}:${task.generation}'],
        );
        if (used.isEmpty) {
          await store.db.insert('metadata', {
            'key': 'refreshPending:${task.id}',
            'value': '1',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await store.setState(task.id, DownloadState.queued);
        }
      }
      ids.add(receipt.id);
    }
    if (ids.isNotEmpty) await downloadPlatform.invokeMethod<void>('acknowledge', ids);
    // Replay prepared intents in bounded pages after a crash between Dart commit
    // and native submission. Native deduplication prevents duplicate transfers.
    final pending = await store.db.query(
      'tasks',
      where: "state = 'prepared' AND updated <= ?",
      whereArgs: [DateTime.now().millisecondsSinceEpoch - 10000],
      limit: 100,
    );
    for (final row in pending) {
      await downloadPlatform.invokeMethod<void>('submit', DownloadTask.fromRow(row).toJson());
      await store.db.update(
        'tasks',
        {'updated': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> dispose() async {
    await quiesce();
  }
}

Future<void> runDownloadWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _runDownloadWorker();
  } catch (_) {
    await downloadPlatform.invokeMethod<void>('workerUnavailable');
  }
}

Future<void> _runDownloadWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await DownloadPaths.open();
  final store = await DownloadStore.open(paths.database);
  final configuration = await DownloadConfiguration.load();
  if (configuration == null) {
    await downloadPlatform.invokeMethod<void>('workerUnavailable');
    return;
  }
  final runtime = DownloadRuntime(
    store,
    paths,
    configuration,
    await configuration.backgroundSettings(),
    headless: true,
  );
  await configuration.attachCookies(store.db);
  Future<void> commands = Future<void>.value();
  downloadWorkerPlatform.setMethodCallHandler((call) {
    final result = commands.then((_) async {
      switch (call.method) {
        case 'resume':
          await runtime.reload();
        case 'wake':
          // A new batch does not cancel already running transfers.
          break;
        case 'suspend':
          await runtime.suspend();
        case 'quiesce':
          await runtime.quiesce();
          return true;
        case 'command':
          final arguments = downloadMap(call.arguments);
          await store.command(
            arguments['command'] as String,
            taskId: arguments['taskId'] as String?,
            batchId: arguments['batchId'] as String?,
          );
      }
      await runtime.pump();
      return true;
    });
    commands = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  });
  final enabled = await downloadPlatform.invokeMethod<bool>('workerReady') ?? false;
  await runtime.start(enabled: enabled);
}
