import 'package:lolisnatcher/src/downloads/download_localizations.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_runtime.dart';
import 'package:lolisnatcher/src/downloads/download_notices.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';
import 'package:lolisnatcher/src/downloads/transfer_preparation.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/inner_drawer.dart';

/// Foreground compatibility adapter. Execution and recovery live in downloads/.
class SnatchHandler with WidgetsBindingObserver {
  static SnatchHandler get instance => GetIt.instance<SnatchHandler>();
  static SnatchHandler register() {
    if (!GetIt.instance.isRegistered<SnatchHandler>()) {
      GetIt.instance.registerSingleton(SnatchHandler(), dispose: (value) => value.dispose());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SnatchHandler>();
  final active = false.obs;
  final status = ''.obs;
  final queueProgress = 0.obs;
  final current = Rx<SnatchItem?>(null);
  final currentItemKeys = <Key>{}.obs;
  final activeItem = Rxn<BooruItem>();
  final received = 0.obs;
  final total = 0.obs;
  final revision = 0.obs;
  final attention = 0.obs;
  final summary = <String, dynamic>{}.obs;
  final focusedBatch = RxnString();
  // Compatibility views stay bounded; persistent history is queried in pages.
  final queuedList = <SnatchItem>[].obs;
  final existsItems = <({BooruItem item, Booru booru})>[].obs;
  final failedItems = <({BooruItem item, Booru booru})>[].obs;
  final cancelledItems = <({BooruItem item, Booru booru})>[].obs;
  DownloadStore? _store;
  DownloadNotices? _notices;
  DownloadRuntime? _runtime;
  Timer? _poller;
  Timer? _configurationTimer;
  Future<void>? _initialization;
  bool _polling = false, _foreground = true, _continued = false, _restoring = false;
  bool _launchFailed = false;
  String? _activeTaskId;
  Future<void> _operations = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> Function(PreparedTransfer, TransferReceipt)? onCompleted;
  double get currentProgress => total.value <= 0 ? 0 : (received.value / total.value).clamp(0, 1);
  bool isActiveItem(BooruItem item) => activeItem.value?.postURL == item.postURL;
  Future<DownloadStore> get store async {
    await initialize();
    return _store!;
  }

  Future<void> initialize() => _initialization ??= _initialize().catchError((Object error, StackTrace stack) async {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    await _runtime?.dispose();
    _runtime = null;
    await _store?.close();
    _store = null;
    _initialization = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _initialize() async {
    final paths = await DownloadPaths.open();
    _store = await DownloadStore.open(paths.database);
    _notices = DownloadNotices(_store!);
    final configuration = await DownloadConfiguration.capture();
    await configuration.attachCookies(_store!.db, seed: true);
    await configuration.save();
    await _configureNative(configuration);
    if (!Platform.isAndroid) {
      _runtime = DownloadRuntime(_store!, paths, configuration, SettingsHandler.instance);
      await _runtime!.start();
    }
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isIOS) {
      downloadPlatform.setMethodCallHandler((call) async {
        if (call.method == 'discoveryContinued') _continued = true;
        if (call.method == 'discoveryExpired') _continued = false;
        _runtime?.foreground = _foreground || _continued;
        if (call.method == 'openDownloads') focusedBatch.value = downloadMap(call.arguments)['batchId'] as String?;
      });
    }
    final presetFile = File(p.join(await ServiceHandler.getConfigDir(), 'download_presets.json'));
    if (await presetFile.exists()) {
      for (final raw in jsonDecode(await presetFile.readAsString()) as List) {
        final preset = downloadMap(raw);
        await _store!.putPreset(preset['id'] as String, preset['name'] as String, downloadMap(preset['payload']));
      }
    }
    _poller = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(refresh()));
    SettingsHandler.instance.onDownloadConfigurationChanged = _configurationChanged;
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _runtime?.foreground = _foreground || _continued;
    if (_foreground) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_polling || _store == null || _restoring) return;
    _polling = true;
    try {
      final data = await _store!.summary();
      summary.value = data;
      attention.value =
          (data['failed'] as int? ?? 0) +
          (data['needsAction'] as int? ?? 0) +
          (data['discoveryAttention'] as int? ?? 0);
      final candidates = data['activeTasks'] as List? ?? [];
      final first = candidates.isEmpty ? null : DownloadTask.fromRow(downloadMap(candidates.first));
      _activeTaskId = first?.id;
      activeItem.value = first == null ? null : BooruItem.fromMap(first.transfer.item);
      received.value = first?.received ?? 0;
      total.value = first?.total ?? 0;
      active.value =
          (data['queued'] as int? ?? 0) +
              (data['waitingNetwork'] as int? ?? 0) +
              (data['waitingRate'] as int? ?? 0) +
              (data['transferring'] as int? ?? 0) +
              (data['prepared'] as int? ?? 0) +
              (data['finalizing'] as int? ?? 0) +
              (data['discovery'] as int? ?? 0) >
          0;
      if (first != null) {
        final source = SettingsHandler.instance.booruList.where((s) => s.name == first.transfer.sourceName).firstOrNull;
        current.value = source == null
            ? null
            : SnatchItem([activeItem.value!], first.transfer.cooldownMs, source, first.transfer.overwrite);
      } else {
        current.value = null;
      }
      queueProgress.value = 0;
      // Recompute transient errors on every successful read on every platform.
      status.value = active.value ? 'running' : 'idle';
      if (Platform.isAndroid || Platform.isIOS) {
        status.value = await downloadPlatform.invokeMethod<String>('executionState') ?? '';
        if (Platform.isAndroid && active.value && status.value == 'idle') status.value = 'resumeRequired';
        if (_launchFailed && status.value != 'running') status.value = 'resumeRequired';
        if (status.value == 'resumeRequired') attention.value++;
        if (_foreground &&
            LocalAuthHandler.instance.isAuthenticated.value == true &&
            SearchHandler.instance.mainDrawerKey.currentState is InnerDrawerState) {
          final opened = await downloadPlatform.invokeMapMethod<String, dynamic>('consumeOpen');
          if (opened != null) {
            final id = opened['batchId'] as String?;
            focusedBatch.value = id?.isEmpty == true ? null : id;
            (SearchHandler.instance.mainDrawerKey.currentState! as InnerDrawerState).open(
              direction: SX.handSide.value.isRight ? InnerDrawerDirection.start : InnerDrawerDirection.end,
            );
          }
        }
      }
      if (data['runtimeError'] != null && active.value) {
        status.value = 'executionError';
        attention.value++;
      }
      await _completionEvents();
      await _notices?.check();
      revision.value++;
    } catch (_) {
      status.value = 'storage';
      attention.value = max(1, attention.value);
    } finally {
      _polling = false;
    }
  }

  Future<void> _completionEvents() async {
    if (!_foreground) return;
    final settings = SettingsHandler.instance;
    final acknowledged = <String>[];
    for (final event in await _store!.completionEvents()) {
      final value = downloadMap(event['payload']);
      final transfer = PreparedTransfer.fromJson(downloadMap(value['transfer']));
      final receipt = TransferReceipt.fromJson(downloadMap(value['receipt']));
      final item = BooruItem.fromMap(transfer.item)..isSnatched.value = true;
      if (SX.dbEnabled.value && settings.dbHandler.db != null) {
        final tracked = await settings.dbHandler.getTrackedValues(item);
        item.isFavourite.value = tracked[1];
        await settings.dbHandler.updateBooruItem(item, BooruUpdateMode.local);
      }
      for (final tab in SearchHandler.instance.tabs) {
        for (final shown in tab.booruHandler.fetched.where((e) => e.postURL == item.postURL)) {
          shown.isSnatched.value = true;
        }
      }
      SAFFileCache.instance.onFileCreated(receipt.filename ?? transfer.filename);
      await onCompleted?.call(transfer, receipt);
      acknowledged.add(event['id'] as String);
    }
    await _store!.acknowledgeEvents(acknowledged);
  }

  Future<DownloadConfiguration> _capture({Iterable<String> urls = const []}) async {
    final configuration = await DownloadConfiguration.capture(mediaUrls: urls);
    await configuration.attachCookies(_store!.db, seed: true);
    await configuration.save();
    await _configureNative(configuration);
    if (_runtime != null) _runtime!.configuration = configuration;
    if (Platform.isAndroid) await downloadPlatform.invokeMethod<void>('refresh');
    return configuration;
  }

  Future<void> _configureNative(DownloadConfiguration configuration) async {
    if (!Platform.isIOS) return;
    await downloadPlatform.invokeMethod<void>('configure', {
      'profiles': {
        for (final source in configuration.sources) sourceIdentity(source): configuration.profile(source.name ?? ''),
      },
      'cookies': configuration.data['cookies'],
      'cookieHosts': configuration.data['cookieHosts'],
      'generation': configuration.data['version'],
    });
  }

  void _configurationChanged() {
    _configurationTimer?.cancel();
    _configurationTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(
        _serialize(() async {
          if (_restoring || _store == null) return;
          try {
            await _capture();
          } catch (_) {
            status.value = 'storage';
            attention.value = max(1, attention.value);
          }
        }),
      );
    });
  }

  Future<void> _start({bool discovery = false}) async {
    try {
      _launchFailed = false;
      if (Platform.isAndroid) {
        await Permission.notification.request();
        status.value = await downloadPlatform.invokeMethod<String>('start') ?? 'resumeRequired';
      } else if (Platform.isIOS) {
        await downloadPlatform.invokeMethod<void>('requestPermissions');
        if (discovery) await downloadPlatform.invokeMethod<void>('beginDiscovery');
        await downloadPlatform.invokeMethod<void>('start');
        await _runtime?.reload();
      } else {
        await _runtime?.reload();
      }
    } catch (_) {
      // Enqueue has already committed. A host launch failure must never make
      // callers retry the enqueue and accidentally create another batch.
      _launchFailed = true;
      status.value = 'resumeRequired';
    }
    await refresh();
  }

  Future<bool> queue(
    List<BooruItem> booruItems,
    Booru booru,
    int cooldown,
    bool ignoreExists, {
    Booru Function(BooruItem)? sourceFor,
    bool useSourceCooldown = false,
  }) {
    final snapshot = [...booruItems];
    final provenance = Map<BooruItem, Booru>.identity();
    for (final item in snapshot) {
      provenance[item] = sourceFor?.call(item) ?? booru;
    }
    return _serialize(
      () => _queue(
        snapshot,
        booru,
        cooldown,
        ignoreExists,
        sourceFor: (item) => provenance[item]!,
        useSourceCooldown: useSourceCooldown,
      ),
    );
  }

  Future<bool> _queue(
    List<BooruItem> booruItems,
    Booru booru,
    int cooldown,
    bool ignoreExists, {
    Booru Function(BooruItem)? sourceFor,
    bool useSourceCooldown = false,
  }) async {
    if (booruItems.isEmpty) return false;
    try {
      await initialize();
      final configuration = await _capture(urls: booruItems.take(100).map((e) => e.fileURL));
      final id = const Uuid().v4();
      final spec = DownloadBatchSpec(
        id: id,
        title: booru.name ?? '',
        requestedCount: booruItems.length,
        policy: {'notifications': SX.downloadNotifications.value},
      );
      await _store!.enqueueAtomic(spec, (offset, executor) async {
        Future<String> cookies(String url) => configuration.cookies(url, executor: executor);
        final scope = RequestScope(client: dio.Dio.new, cookies: cookies, saveCookies: configuration.saveCookies);
        return scope.run(() async {
          final page = <PreparedTransfer>[];
          for (final item in booruItems.skip(offset).take(100)) {
            final source = sourceFor?.call(item) ?? booru;
            page.add(
              await prepareTransfer(
                source: source,
                item: item,
                batchId: id,
                configuration: configuration,
                cookiesOverride: cookies,
                overwrite: ignoreExists,
                cooldownMs: useSourceCooldown ? SX.snatchCooldown.valueForBooru(source.name) : cooldown,
              ),
            );
          }
          return page;
        });
      });
      await _start();
      _message(downloadText('added', {'count': booruItems.length}));
      return true;
    } catch (_) {
      _message(downloadText('enqueueError'), error: true);
      return false;
    }
  }

  Future<String> searchSnatch(
    String tags,
    String amount,
    int cooldown,
    Booru booru, {
    int startPage = 1,
    String? quality,
    bool overwrite = false,
    List<Booru>? sources,
  }) => _serialize(
    () => _searchSnatch(
      tags,
      amount,
      cooldown,
      booru,
      startPage: startPage,
      quality: quality,
      overwrite: overwrite,
      sources: sources,
    ),
  );

  Future<String> _searchSnatch(
    String tags,
    String amount,
    int cooldown,
    Booru booru, {
    int startPage = 1,
    String? quality,
    bool overwrite = false,
    List<Booru>? sources,
  }) async {
    final count = int.tryParse(amount);
    if (count == null || count < 1 || startPage < 1) throw ArgumentError('Enter a positive amount and starting page.');
    await initialize();
    final configuration = await _capture();
    final selected = sources ?? [booru];
    final policies = <String, dynamic>{};
    for (final source in selected) {
      policies[source.name ?? ''] = {...configuration.policy(source.name ?? ''), 'quality': ?quality};
    }
    final id = const Uuid().v4();
    await _store!.createBatch(
      DownloadBatchSpec(
        id: id,
        title: selected.map((s) => s.name).join(', '),
        requestedCount: count,
        query: tags,
        startPage: startPage,
        sourceNames: selected.map((s) => s.name ?? '').toList(),
        policy: {
          'sources': policies,
          'overwrite': overwrite,
          'delayMs': cooldown,
          'notifications': SX.downloadNotifications.value,
        },
      ),
    );
    await _start(discovery: true);
    focusedBatch.value = id;
    return id;
  }

  Future<void> command(String command, {String? taskId, String? batchId}) =>
      _serialize(() => _command(command, taskId: taskId, batchId: batchId));

  Future<void> _command(String command, {String? taskId, String? batchId}) async {
    await initialize();
    if (command == 'clear' && Platform.isIOS) {
      while (true) {
        final batches = await _store!.clearableBatches(batchId: batchId);
        if (batches.isEmpty) break;
        for (final batch in batches) {
          await downloadPlatform.invokeMethod<void>('forgetBatch', {'batchId': batch['id']});
          await _store!.command('clear', batchId: batch['id'] as String);
        }
      }
      await refresh();
      return;
    }
    if (const ['resume', 'retry', 'redownload'].contains(command)) await _capture();
    if (Platform.isIOS) {
      final fences = <String, int>{};
      if (command == 'pause' || command == 'cancel') {
        if (taskId != null) {
          final task = await _store!.task(taskId);
          if (task != null) fences['task:$taskId'] = task.generation + 1;
        } else {
          var offset = 0;
          while (true) {
            final rows = await _store!.db.query(
              'batches',
              columns: ['id', 'generation'],
              where: batchId == null ? null : 'id = ?',
              whereArgs: batchId == null ? null : [batchId],
              orderBy: 'id',
              limit: 100,
              offset: offset,
            );
            for (final row in rows) {
              fences['batch:${row['id']}'] = (row['generation']! as int) + 1;
            }
            if (rows.length < 100) break;
            await downloadPlatform.invokeMethod<void>('fence', {...fences, 'command': command});
            fences.clear();
            offset += 100;
          }
        }
        await downloadPlatform.invokeMethod<void>('fence', {...fences, 'command': command});
      }
      await downloadPlatform.invokeMethod<void>('command', {'command': command, 'taskId': taskId, 'batchId': batchId});
    }
    await _store!.command(command, taskId: taskId, batchId: batchId);
    if (const ['resume', 'retry', 'redownload'].contains(command)) await _start(discovery: true);
    await refresh();
  }

  Future<void> savePreset(String id, String name, Map<String, dynamic> payload) async {
    await (await store).putPreset(id, name, payload);
    await _persistPresets();
  }

  Future<void> deletePreset(String id) async {
    await (await store).deletePreset(id);
    await _persistPresets();
  }

  Future<void> _persistPresets() async {
    final file = File(p.join(await ServiceHandler.getConfigDir(), 'download_presets.json'));
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(await _store!.presets()), flush: true);
    await temporary.rename(file.path);
  }

  Future<List<Map<String, dynamic>>> portablePresets() async => (await (await store).presets())
      .map(
        (row) => {
          'id': row['id'],
          'name': row['name'],
          'payload': downloadMap(row['payload']),
        },
      )
      .toList();
  Future<void> importPresets(Object? value) async {
    if (value is! List) return;
    for (final raw in value) {
      final row = downloadMap(raw);
      if (row['id'] is! String || row['name'] is! String) continue;
      final payload = downloadMap(row['payload']);
      // Deliberately allow only portable form inputs, never paths or receipts.
      final safe = {
        for (final key in ['query', 'amount', 'delay', 'startPage', 'sourceNames', 'quality', 'overwrite'])
          if (payload.containsKey(key)) key: payload[key],
      };
      await (await store).putPreset(row['id'] as String, row['name'] as String, safe);
    }
    await _persistPresets();
  }

  Future<void> suspendForRestore() async {
    _restoring = true;
    while (_polling) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await command('pause');
    if (Platform.isAndroid) await downloadPlatform.invokeMethod<void>('quiesce');
    await _runtime?.quiesce();
  }

  Future<void> finishRestore() async {
    _restoring = false;
    await _capture();
    await refresh();
  }

  Future<void> retryPhotos(String taskId) async {
    final journal = File((await DownloadPaths.open()).journal(taskId));
    final saved = await journal.exists() ? downloadMap(await journal.readAsString()) : <String, dynamic>{};
    await downloadPlatform.invokeMethod<void>('retryPhotos', {'taskId': taskId, 'digest': saved['sha256']});
    await command('retry', taskId: taskId);
  }

  void _message(String message, {bool error = false}) {
    FlashElements.showSnackbar(
      context: NavigationHandler.instance.navContext,
      title: Text(message),
      leadingIcon: error ? Icons.error_outline : Icons.download_done,
      sideColor: error ? Colors.red : Colors.green,
      duration: const Duration(seconds: 3),
    );
  }

  void onCancel() => unawaited(command('cancel', taskId: _activeTaskId));
  void onRetryCurrent() => unawaited(command('retry', taskId: _activeTaskId));
  void trySnatch() => unawaited(command('resume'));
  void onClearRetryableItems() => unawaited(command('clear'));
  void onRemoveRetryItem(({BooruItem item, Booru booru}) record) {}
  Future<void> onRetryAll({required int cooldown, bool ignoreExists = false}) =>
      command(ignoreExists ? 'redownload' : 'retry');
  void onRetryItem(({BooruItem item, Booru booru}) record, {required int cooldown, bool ignoreExists = false}) =>
      unawaited(queue([record.item], record.booru, cooldown, ignoreExists));
  void dispose() {
    SettingsHandler.instance.onDownloadConfigurationChanged = null;
    _configurationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    unawaited(_runtime?.dispose() ?? Future<void>.value());
  }
}

class SnatchItem {
  SnatchItem(this.booruItems, this.cooldown, this.booru, this.ignoreExists);
  final List<BooruItem> booruItems;
  final int cooldown;
  final Booru booru;
  final bool ignoreExists;
}
