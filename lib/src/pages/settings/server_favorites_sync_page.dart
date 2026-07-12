import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/server_favorite_adapter.dart';
import 'package:lolisnatcher/src/handlers/server_favorites_sync_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class ServerFavoritesSyncPage extends StatefulWidget {
  const ServerFavoritesSyncPage({super.key});

  @override
  State<ServerFavoritesSyncPage> createState() => _ServerFavoritesSyncPageState();
}

class _ServerFavoritesSyncPageState extends State<ServerFavoritesSyncPage> {
  final settingsHandler = SettingsHandler.instance;
  final scrollController = ScrollController();
  final adapterFactory = const ServerFavoriteAdapterFactory();
  final sankakuSearchController = TextEditingController();

  late List<ServerFavoriteAdapter> adapters;
  final selectedAdapters = <ServerFavoriteAdapter>{};
  final previews = <ServerFavoriteAdapter, ServerFavoritesSyncPreview>{};
  final results = <ServerFavoriteAdapter, ServerFavoritesSyncResult>{};
  final logLines = <String>[];
  ServerFavoriteSyncMode mode = ServerFavoriteSyncMode.importServer;
  bool isWorking = false;
  bool cancelRequested = false;

  bool isUpdatingSankakuUrls = false;
  int updatingFailed = 0, updatingDone = 0;
  BooruType? sankakuType;
  CancelToken? cancelToken;
  List<BooruItem> updatingItems = [], failedItems = [];

  @override
  void initState() {
    super.initState();
    adapters = adapterFactory.adaptersFor(settingsHandler.booruList);

    final sankakuBoorus = getSankakuBoorus();
    if (sankakuBoorus.isNotEmpty) {
      sankakuType = sankakuBoorus.first.type;
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    sankakuSearchController.dispose();
    cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    if (isWorking || isUpdatingSankakuUrls) {
      FlashElements.showSnackbar(
        title: Text(context.loc.serverFavouritesSync.pleaseWaitTitle, style: const TextStyle(fontSize: 20)),
        content: Text(context.loc.serverFavouritesSync.stillRunning, style: const TextStyle(fontSize: 16)),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
    }
  }

  void _setStatus(String value) {
    logLines.insert(0, value);
    if (logLines.length > 80) {
      logLines.removeRange(80, logLines.length);
    }
    safeSetState(() {});
  }

  bool _modeSupported(ServerFavoriteAdapter adapter) {
    final caps = adapter.capabilities;
    switch (mode) {
      case ServerFavoriteSyncMode.importServer:
        return caps.canFetch;
      case ServerFavoriteSyncMode.exportLocal:
        return caps.canAdd;
      case ServerFavoriteSyncMode.twoWayMerge:
        return caps.canFetch && caps.canAdd;
      case ServerFavoriteSyncMode.mirrorServerToLocal:
        return caps.canFetch;
      case ServerFavoriteSyncMode.mirrorLocalToServer:
        return caps.canFetch && caps.canAdd && caps.canRemove && caps.isDestructiveMirrorAllowed;
    }
  }

  List<ServerFavoriteAdapter> get selectedRunnableAdapters =>
      selectedAdapters.where(_modeSupported).toList(growable: false);

  bool get canPreviewSelected => !isWorking && selectedRunnableAdapters.isNotEmpty;

  bool get canRunSelected =>
      !isWorking && selectedRunnableAdapters.isNotEmpty && selectedRunnableAdapters.every(previews.containsKey);

  void _deselectUnsupportedAdaptersForMode() {
    selectedAdapters.removeWhere((adapter) => !_modeSupported(adapter));
    previews.removeWhere((adapter, _) => !selectedAdapters.contains(adapter) || !_modeSupported(adapter));
    results.removeWhere((adapter, _) => !selectedAdapters.contains(adapter) || !_modeSupported(adapter));
  }

  Future<bool> _confirmDestructive(BuildContext context) async {
    if (!mode.isDestructive) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsDialog(
        title: Text(context.loc.serverFavouritesSync.confirmDestructiveSync),
        contentItems: [
          Text(context.loc.serverFavouritesSync.destructiveSyncWarning(mode: mode.title)),
        ],
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.warning_amber),
            label: Text(context.loc.serverFavouritesSync.run),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> previewSelected() async {
    if (isWorking) return;

    setState(() {
      _deselectUnsupportedAdaptersForMode();
      isWorking = true;
      cancelRequested = false;
      previews.clear();
      results.clear();
      logLines.clear();
    });

    for (final adapter in selectedAdapters.toList()) {
      if (cancelRequested) break;
      if (!_modeSupported(adapter)) {
        _setStatus('${adapter.displayName}: skipped, mode is not supported');
        continue;
      }

      try {
        final preview = await ServerFavoritesSyncHandler(adapter: adapter).preview(
          mode,
          onStatus: _setStatus,
          shouldCancel: () => cancelRequested,
        );
        previews[adapter] = preview;
        _setStatus('${adapter.displayName}: preview ready');
      } catch (e) {
        _setStatus('${adapter.displayName}: preview failed - $e');
      }
    }

    safeSetState(() {
      isWorking = false;
    });
  }

  Future<void> runSelected() async {
    if (isWorking) return;
    setState(_deselectUnsupportedAdaptersForMode);
    if (!canRunSelected) {
      _setStatus(context.loc.serverFavouritesSync.previewRequiredBeforeRun);
      return;
    }
    if (!await _confirmDestructive(context)) return;

    setState(() {
      isWorking = true;
      cancelRequested = false;
      results.clear();
    });

    for (final entry in previews.entries.toList()) {
      if (cancelRequested) break;
      try {
        final result = await ServerFavoritesSyncHandler(adapter: entry.key).apply(
          entry.value,
          onStatus: _setStatus,
          shouldCancel: () => cancelRequested,
        );
        results[entry.key] = result;
        _setStatus('${entry.key.displayName}: sync complete');
      } catch (e) {
        _setStatus('${entry.key.displayName}: sync failed - $e');
      }
    }

    safeSetState(() {
      isWorking = false;
    });
  }

  void cancelWork() {
    setState(() {
      cancelRequested = true;
      isWorking = false;
      isUpdatingSankakuUrls = false;
      cancelToken?.cancel();
    });
  }

  List<Booru> getSankakuBoorus() {
    final sankakuBoorus = <Booru>[];

    for (final booru in settingsHandler.booruList) {
      if ((booru.type?.isSankaku == true || booru.type?.isIdolSankaku == true) &&
          [
            ...SankakuHandler.knownUrls,
            ...IdolSankakuHandler.knownUrls,
            'sankakuapi.com',
          ].any((e) => booru.baseURL?.contains(e) ?? false)) {
        sankakuBoorus.add(booru);
      }
    }
    return sankakuBoorus;
  }

  Future<bool> updateSankakuItems({List<BooruItem>? customItems}) async {
    if (isUpdatingSankakuUrls) return false;

    safeSetState(() {
      updatingItems = [];
      failedItems = [];
      updatingFailed = 0;
      updatingDone = 0;
      isUpdatingSankakuUrls = true;
      cancelToken?.cancel();
    });

    final sankakuBoorus = getSankakuBoorus().where((e) => e.type == sankakuType).toList();
    if (sankakuBoorus.isEmpty) {
      safeSetState(() {
        isUpdatingSankakuUrls = false;
      });
      return true;
    }

    for (final sankakuBooru in sankakuBoorus) {
      final sankakuHandler = sankakuBooru.type?.isIdolSankaku == true
          ? IdolSankakuHandler(sankakuBooru, 10)
          : SankakuHandler(sankakuBooru, 10);
      updatingItems = customItems?.isNotEmpty == true
          ? customItems!
          : await settingsHandler.dbHandler.getSankakuItems(
              search: sankakuSearchController.text,
              idol: sankakuBooru.type?.isIdolSankaku == true,
            );

      safeSetState(() {});

      for (BooruItem item in updatingItems) {
        if (!isUpdatingSankakuUrls) break;
        await Future.delayed(const Duration(milliseconds: 100));
        cancelToken = CancelToken();
        final result = await sankakuHandler.loadItem(item: item, cancelToken: cancelToken);
        if (result.failed) {
          safeSetState(() {
            updatingFailed += 1;
            failedItems.add(item);
          });
          Logger.Inst().log(
            'something went wrong updating favourites: ${result.error}',
            'ServerFavoritesSyncPage',
            'updateSankakuItems',
            LogTypes.exception,
          );
        } else if (result.item != null) {
          item = result.item!;
          unawaited(settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.urlUpdate));
          safeSetState(() {
            updatingDone += 1;
          });
        } else {
          safeSetState(() {
            updatingFailed += 1;
            failedItems.add(item);
          });
        }
      }
    }

    safeSetState(() {
      updatingFailed = 0;
      updatingDone = 0;
      isUpdatingSankakuUrls = false;
    });

    return true;
  }

  Future<bool> purgeFailedSankakuItems() async {
    final failedIDs = await settingsHandler.dbHandler.getItemIDs(
      failedItems.map((e) => e.postURL).toList(),
    );
    await settingsHandler.dbHandler.deleteItem(failedIDs);
    setState(() {
      failedItems = [];
    });
    return true;
  }

  void safeSetState(VoidCallback fn) {
    fn();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isWorking && !isUpdatingSankakuUrls,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(title: context.loc.serverFavouritesSync.title),
        body: ListView(
          controller: scrollController,
          children: [
            if (adapters.isEmpty)
              SettingsButton(
                name: context.loc.serverFavouritesSync.noSupportedBoorus,
                enabled: false,
                trailingIcon: const Icon(Icons.favorite_border),
              )
            else ...[
              SettingsDropdown<ServerFavoriteSyncMode>(
                value: mode,
                items: ServerFavoriteSyncMode.values,
                title: context.loc.serverFavouritesSync.syncMode,
                itemTitleBuilder: (item) => item?.title ?? '',
                onChanged: isWorking
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          mode = value;
                          _deselectUnsupportedAdaptersForMode();
                          previews.clear();
                          results.clear();
                        });
                      },
              ),
              SettingsButton(name: context.loc.serverFavouritesSync.boorus, enabled: false),
              ...adapters.map(_adapterTile),
              SettingsButton(
                name: context.loc.serverFavouritesSync.previewSelected,
                icon: const Icon(Icons.manage_search),
                enabled: canPreviewSelected,
                action: canPreviewSelected ? previewSelected : null,
              ),
              SettingsButton(
                name: mode.isDestructive
                    ? context.loc.serverFavouritesSync.runSelectedRemoves
                    : context.loc.serverFavouritesSync.runSelected,
                subtitle: canRunSelected ? null : Text(context.loc.serverFavouritesSync.previewRequiredBeforeRun),
                icon: Icon(mode.isDestructive ? Icons.warning_amber : Icons.sync),
                enabled: canRunSelected,
                action: canRunSelected ? runSelected : null,
              ),
              if (isWorking)
                SettingsButton(
                  name: context.loc.serverFavouritesSync.stop,
                  icon: const Icon(Icons.cancel),
                  action: cancelWork,
                ),
              if (previews.isNotEmpty) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.preview, enabled: false),
                ...previews.entries.map((entry) => _previewTile(entry.key, entry.value)),
              ],
              if (results.isNotEmpty) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.result, enabled: false),
                ...results.entries.expand((entry) => _resultSection(entry.key, entry.value)),
              ],
              if (logLines.isNotEmpty) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.log, enabled: false),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(logLines.take(12).join('\n')),
                ),
              ],
            ],
            if (sankakuType != null) ..._sankakuMaintenance(),
          ],
        ),
      ),
    );
  }

  Widget _adapterTile(ServerFavoriteAdapter adapter) {
    final selected = selectedAdapters.contains(adapter);
    final supported = _modeSupported(adapter);
    return CheckboxListTile(
      value: selected,
      onChanged: isWorking || !supported
          ? null
          : (value) {
              setState(() {
                if (value == true) {
                  selectedAdapters.add(adapter);
                } else {
                  selectedAdapters.remove(adapter);
                }
                previews.clear();
                results.clear();
              });
            },
      title: Text(adapter.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (adapter.capabilities.canFetch) const Chip(label: Text('import')),
              if (adapter.capabilities.canAdd) const Chip(label: Text('export')),
              if (adapter.capabilities.canRemove) const Chip(label: Text('remove')),
              if (adapter.capabilities.requiresAuth) const Chip(label: Text('auth')),
              if (adapter.capabilities.isReadOnly) const Chip(label: Text('read-only')),
            ],
          ),
          if (!supported)
            Text(
              adapter.capabilities.unsupportedReason ?? context.loc.serverFavouritesSync.selectedModeNotSupported,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      secondary: const Icon(Icons.favorite),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _previewTile(ServerFavoriteAdapter adapter, ServerFavoritesSyncPreview preview) {
    return SettingsButton(
      name: adapter.displayName,
      enabled: false,
      subtitle: Text(
        context.loc.serverFavouritesSync.previewSummary(
          matched: preview.matched,
          localOnly: preview.localOnly,
          serverOnly: preview.serverOnly,
          addLocal: preview.addLocal,
          addServer: preview.addServer,
          removeLocal: preview.removeLocal,
          removeServer: preview.removeServer,
        ),
      ),
      trailingIcon: const Icon(Icons.summarize),
    );
  }

  Widget _resultTile(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult result) {
    return SettingsButton(
      name: adapter.displayName,
      enabled: false,
      subtitle: Text(
        '${context.loc.serverFavouritesSync.resultSummary(
          addedLocal: result.addedLocal,
          addedServer: result.addedServer,
          removedLocal: result.removedLocal,
          removedServer: result.removedServer,
          failed: result.failed,
        )}${result.errors.isEmpty ? '' : '\n${result.errors.take(4).join('\n')}'}',
      ),
      trailingIcon: Icon(result.failed == 0 ? Icons.check : Icons.warning_amber),
    );
  }

  List<Widget> _resultSection(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult result) {
    return [
      _resultTile(adapter, result),
      if (result.failed > 0) ...[
        SettingsButton(
          name: context.loc.serverFavouritesSync.copyFailureLog,
          icon: const Icon(Icons.copy),
          dense: true,
          action: () => _copyFailureLog(adapter, result),
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.retryFailedActions,
          icon: const Icon(Icons.refresh),
          dense: true,
          enabled: !isWorking && result.failures.isNotEmpty,
          action: !isWorking && result.failures.isNotEmpty ? () => retryFailedActions(adapter, result) : null,
        ),
      ],
    ];
  }

  void _copyFailureLog(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult result) {
    final summary = context.loc.serverFavouritesSync.resultSummary(
      addedLocal: result.addedLocal,
      addedServer: result.addedServer,
      removedLocal: result.removedLocal,
      removedServer: result.removedServer,
      failed: result.failed,
    );
    final buffer = StringBuffer()
      ..writeln(context.loc.serverFavouritesSync.title)
      ..writeln('Booru: ${adapter.displayName}')
      ..writeln('Mode: ${result.preview.mode.title}')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln(summary);

    if (result.failures.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Retryable failures:');
      for (final failure in result.failures) {
        buffer.writeln(failure.logLine);
      }
    }

    if (result.errors.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Errors:');
      for (final error in result.errors) {
        buffer.writeln(error);
      }
    }

    unawaited(
      ClipboardUtils.copyTextToClipboard(
        buffer.toString().trim(),
        subtitle: context.loc.serverFavouritesSync.failureLogCopied,
      ),
    );
  }

  Future<void> retryFailedActions(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult previousResult) async {
    if (isWorking) return;
    if (previousResult.failures.isEmpty) {
      _setStatus('${adapter.displayName}: ${context.loc.serverFavouritesSync.noRetryableFailures}');
      return;
    }

    setState(() {
      isWorking = true;
      cancelRequested = false;
    });
    _setStatus(context.loc.serverFavouritesSync.retryingFailedActions(booru: adapter.displayName));

    try {
      final retryResult = await ServerFavoritesSyncHandler(adapter: adapter).retryFailures(
        previousResult,
        onStatus: _setStatus,
        shouldCancel: () => cancelRequested,
      );
      results[adapter] = retryResult;
      _setStatus(context.loc.serverFavouritesSync.retryComplete(booru: adapter.displayName));
    } catch (e) {
      _setStatus('${adapter.displayName}: sync retry failed - $e');
    }

    safeSetState(() {
      isWorking = false;
    });
  }

  List<Widget> _sankakuMaintenance() {
    return [
      const SettingsButton(name: '', enabled: false),
      SettingsButton(
        name: context.loc.serverFavouritesSync.sankakuMaintenance,
        subtitle: Text(
          context.loc.serverFavouritesSync.sankakuMaintenanceSubtitle,
        ),
        enabled: false,
      ),
      Stack(
        children: [
          IgnorePointer(
            ignoring: isUpdatingSankakuUrls,
            child: Column(
              children: [
                SettingsDropdown<BooruType?>(
                  value: sankakuType,
                  items: getSankakuBoorus().map((e) => e.type).toList(),
                  itemTitleBuilder: (item) => item?.alias ?? '',
                  onChanged: (newValue) {
                    setState(() {
                      sankakuType = newValue;
                    });
                  },
                  title: context.loc.serverFavouritesSync.sankakuTypeToUpdate,
                ),
                SettingsTextInput(
                  controller: sankakuSearchController,
                  title: context.loc.serverFavouritesSync.searchQuery,
                  hintText: context.loc.serverFavouritesSync.optional,
                  clearable: true,
                  pasteable: true,
                  enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
                ),
                SettingsButton(
                  name: context.loc.serverFavouritesSync.updateSankakuUrls,
                  trailingIcon: const Icon(Icons.image),
                  action: isUpdatingSankakuUrls ? null : updateSankakuItems,
                ),
              ],
            ),
          ),
          if (isUpdatingSankakuUrls)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      if (isUpdatingSankakuUrls) ...[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.loc.serverFavouritesSync.updating(count: updatingItems.length)),
              Text(
                context.loc.serverFavouritesSync.left(
                  count: max(updatingItems.length - updatingDone - updatingFailed, 0),
                ),
              ),
              Text(context.loc.serverFavouritesSync.done(count: updatingDone)),
              Text(context.loc.serverFavouritesSync.failedSkipped(count: updatingFailed)),
              Text(context.loc.serverFavouritesSync.sankakuRateLimitWarning),
            ],
          ),
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.skipCurrentItem,
          subtitle: Text(context.loc.serverFavouritesSync.skipCurrentItemHint),
          trailingIcon: const Icon(Icons.skip_next),
          drawTopBorder: true,
          action: () {
            cancelToken?.cancel();
          },
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.stop,
          trailingIcon: const Icon(Icons.cancel),
          drawTopBorder: true,
          action: cancelWork,
        ),
      ],
      if (!isUpdatingSankakuUrls && failedItems.isNotEmpty) ...[
        SettingsButton(
          name: context.loc.serverFavouritesSync.purgeFailedItems(count: failedItems.length),
          trailingIcon: const Icon(Icons.delete_forever),
          drawTopBorder: true,
          action: purgeFailedSankakuItems,
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.retryFailedItems(count: failedItems.length),
          trailingIcon: const Icon(Icons.refresh),
          drawTopBorder: true,
          action: () {
            updateSankakuItems(customItems: [...failedItems]);
          },
        ),
      ],
      const SettingsButton(name: '', enabled: false),
    ];
  }
}
