import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/services/server_favorites_request_gate.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';

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
  ServerFavoriteAdapter? selectedAdapter;
  ServerFavoritesSyncPreview? preview;
  bool previewFailed = false;
  ServerFavoritesSyncResult? result;
  Timer? statusTimer;
  final acknowledgedExports = <String>{};
  String? exportAccountIdentity;
  final logLines = <String>[];
  ServerFavoriteSyncMode mode = ServerFavoriteSyncMode.importServer;
  bool isWorking = false;
  bool cancelRequested = false;

  bool isUpdatingSankakuUrls = false;
  int updatingFailed = 0, updatingDone = 0;
  String? get sankakuName => selectedAdapter?.displayName;
  CancelToken? cancelToken;
  List<BooruItem> updatingItems = [], failedItems = [];

  @override
  void initState() {
    super.initState();
    adapters = adapterFactory.adaptersFor(settingsHandler.booruList);

    if (adapters.isNotEmpty) _selectAdapter(adapters.first);
  }

  @override
  void dispose() {
    cancelRequested = true;
    statusTimer?.cancel();
    scrollController.dispose();
    sankakuSearchController.dispose();
    cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    if (isBusy) {
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
    if (!mounted) return;
    logLines.insert(0, value);
    if (logLines.length > 80) {
      logLines.removeRange(80, logLines.length);
    }
    statusTimer ??= Timer(const Duration(milliseconds: 250), () {
      statusTimer = null;
      if (mounted) setState(() {});
    });
  }

  bool get isBusy => isWorking || isUpdatingSankakuUrls;

  bool _modeSupported(ServerFavoriteAdapter adapter) => adapter.capabilities.supportsMode(mode);

  bool get canPreviewSelected => !isBusy && selectedAdapter != null && _modeSupported(selectedAdapter!);
  bool get canRunSelected => canPreviewSelected && preview?.hasChanges == true;

  void _selectAdapter(ServerFavoriteAdapter adapter) {
    if (selectedAdapter != adapter) {
      acknowledgedExports.clear();
      exportAccountIdentity = null;
    }
    selectedAdapter = adapter;
    if (!_modeSupported(adapter)) {
      mode = ServerFavoriteSyncMode.values.firstWhere(
        adapter.capabilities.supportsMode,
        orElse: () => ServerFavoriteSyncMode.importServer,
      );
    }
    preview = null;
    previewFailed = false;
    result = null;
    logLines.clear();
    failedItems.clear();
    updatingItems.clear();
  }

  Future<T> _runSync<T>(CancelToken token, Future<T> Function() action) {
    return ServerFavoritesRequestGate(token, onStatus: _setStatus).run(
      () => DioNetwork.runWithCancellation(token, action),
    );
  }

  Future<bool> _confirmDestructive(
    BuildContext context,
    ServerFavoriteSyncMode selectedMode,
    ServerFavoriteAdapter adapter,
    ServerFavoritesSyncPreview selectedPreview,
  ) async {
    if (!selectedMode.isDestructive) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsDialog(
        title: Text(context.loc.serverFavouritesSync.confirmDestructiveSync),
        contentItems: [
          Text(context.loc.serverFavouritesSync.destructiveSyncWarning(mode: selectedMode.title)),
          Text(
            context.loc.serverFavouritesSync.confirmRemovalSummary(
              booru: adapter.displayName,
              local: selectedPreview.removeLocal,
              server: selectedPreview.removeServer,
            ),
          ),
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
    if (!canPreviewSelected) return;
    final adapter = selectedAdapter!;
    final selectedMode = mode;
    final token = CancelToken();
    setState(() {
      isWorking = true;
      cancelRequested = false;
      cancelToken = token;
      preview = null;
      previewFailed = false;
      result = null;
      logLines.clear();
    });
    try {
      if (selectedMode == ServerFavoriteSyncMode.exportLocal &&
          !adapter.capabilities.canEnumerateAll &&
          await adapter.exportSessionIdentity() != exportAccountIdentity) {
        acknowledgedExports.clear();
        exportAccountIdentity = null;
      }
      final fresh = await _runSync(
        token,
        () => ServerFavoritesSyncHandler(adapter: adapter).preview(
          selectedMode,
          onStatus: _setStatus,
          shouldCancel: () => cancelRequested,
          acknowledgedExports: acknowledgedExports,
          exportAccountIdentity: exportAccountIdentity,
        ),
      );
      if (!cancelRequested) {
        preview = fresh;
        _setStatus('${adapter.displayName}: preview ready');
      }
    } catch (error) {
      if (!cancelRequested) {
        previewFailed = true;
        _setStatus('${adapter.displayName}: preview failed — $error');
      }
    } finally {
      safeSetState(() {
        if (cancelRequested) preview = null;
        cancelToken = null;
        isWorking = false;
      });
    }
  }

  Future<void> runSelected() async {
    if (!canRunSelected) return;
    final adapter = selectedAdapter!;
    var selectedPreview = preview!;
    final token = CancelToken();
    setState(() {
      isWorking = true;
      cancelRequested = false;
      cancelToken = token;
    });
    try {
      if (mode.isDestructive) {
        final fresh = await _runSync(
          token,
          () => ServerFavoritesSyncHandler(adapter: adapter).preview(
            mode,
            onStatus: _setStatus,
            shouldCancel: () => cancelRequested,
          ),
        );
        preview = fresh;
        if (!selectedPreview.sameSnapshot(fresh)) {
          _setStatus('Favourites changed. Review the refreshed preview before running again.');
          return;
        }
        selectedPreview = fresh;
      }
      if (!mounted || cancelRequested) return;
      if (!await _confirmDestructive(context, mode, adapter, selectedPreview) || !mounted || cancelRequested) return;
      setState(() {
        preview = null;
        result = null;
      });
      result = await _runSync(
        token,
        () => ServerFavoritesSyncHandler(adapter: adapter).apply(
          selectedPreview,
          onStatus: _setStatus,
          shouldCancel: () => cancelRequested,
        ),
      );
      if (selectedPreview.mode == ServerFavoriteSyncMode.exportLocal && !adapter.capabilities.canEnumerateAll) {
        if (result!.exportAccountIdentity != null) {
          if (exportAccountIdentity != null && exportAccountIdentity != result!.exportAccountIdentity) {
            acknowledgedExports.clear();
          }
          exportAccountIdentity = result!.exportAccountIdentity;
          acknowledgedExports.addAll(result!.confirmedServerAdds);
        }
        if (result!.remaining == 0 && result!.failed == 0) {
          acknowledgedExports.clear();
          exportAccountIdentity = null;
        }
      }
      _setStatus(
        '${adapter.displayName}: ${result!.cancelled ? 'stopped' : 'finished'}, '
        '${result!.remaining} changes remaining, ${result!.failed} errors',
      );
    } catch (error) {
      if (!cancelRequested) _setStatus('${adapter.displayName}: sync failed — $error');
    } finally {
      safeSetState(() {
        if (cancelRequested) preview = null;
        cancelToken = null;
        isWorking = false;
      });
    }
  }

  void cancelWork() {
    setState(() {
      cancelRequested = true;
      preview = null;
      cancelToken?.cancel();
      _setStatus('Stopped. Completed changes are kept; an interrupted server request may already have taken effect.');
    });
  }

  List<Booru> getSankakuBoorus() {
    final sankakuBoorus = <Booru>[];

    for (final booru in [if (selectedAdapter != null) selectedAdapter!.booru]) {
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
    if (isBusy) return false;
    final sankakuBoorus = getSankakuBoorus();
    final search = sankakuSearchController.text;

    safeSetState(() {
      updatingItems = [];
      failedItems = [];
      updatingFailed = 0;
      updatingDone = 0;
      isUpdatingSankakuUrls = true;
      cancelRequested = false;
      preview = null;
      result = null;
      logLines.clear();
      cancelToken?.cancel();
    });

    try {
      for (final sankakuBooru in sankakuBoorus) {
        if (cancelRequested) break;
        final sankakuHandler = sankakuBooru.type?.isIdolSankaku == true
            ? IdolSankakuHandler(sankakuBooru, 10)
            : SankakuHandler(sankakuBooru, 10);
        updatingItems = customItems?.isNotEmpty == true
            ? customItems!
            : await settingsHandler.dbHandler.getSankakuItems(
                search: search,
                idol: sankakuBooru.type?.isIdolSankaku == true,
              );

        safeSetState(() {});

        for (BooruItem item in updatingItems) {
          if (cancelRequested) break;
          await Future.delayed(const Duration(milliseconds: 100));
          if (cancelRequested) break;
          cancelToken = CancelToken();
          final result = await _runSync(
            cancelToken!,
            () => sankakuHandler.loadItem(item: item, cancelToken: cancelToken),
          );
          if (cancelRequested) break;
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
            await settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.urlUpdate);
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
      return !cancelRequested;
    } catch (error) {
      if (!cancelRequested) {
        FlashElements.showSnackbar(
          title: Text('${sankakuName ?? ''}: sync failed — $error'),
        );
      }
      return false;
    } finally {
      safeSetState(() {
        isUpdatingSankakuUrls = false;
        cancelToken = null;
      });
    }
  }

  Future<bool> purgeFailedSankakuItems() async {
    if (isBusy || failedItems.isEmpty) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsDialog(
        title: Text(context.loc.serverFavouritesSync.purgeFailedItems(count: failedItems.length)),
        contentItems: [Text(context.loc.serverFavouritesSync.purgeWarning)],
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.loc.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || isBusy) return false;
    final failedUrls = failedItems.map((e) => e.postURL).toList();
    setState(() {
      isWorking = true;
      cancelRequested = false;
      preview = null;
    });
    try {
      final failedIDs = await settingsHandler.dbHandler.getItemIDs(failedUrls);
      if (cancelRequested) return false;
      await settingsHandler.dbHandler.deleteItem(failedIDs);
      safeSetState(() {
        failedItems = [];
      });
      return true;
    } catch (error) {
      FlashElements.showSnackbar(
        title: Text('Local removal failed:  — $error'),
      );
      return false;
    } finally {
      safeSetState(() {
        isWorking = false;
      });
    }
  }

  void safeSetState(VoidCallback fn) {
    fn();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isBusy,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(title: context.loc.serverFavouritesSync.title),
        bottomNavigationBar: isBusy
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LinearProgressIndicator(),
                      if (logLines.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(logLines.first, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      TextButton.icon(
                        onPressed: cancelRequested ? null : cancelWork,
                        icon: const Icon(Icons.cancel),
                        label: Text(context.loc.serverFavouritesSync.stop),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        body: ListView(
          controller: scrollController,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(context.loc.serverFavouritesSync.workflowHint)),
            if (adapters.isEmpty)
              SettingsButton(
                name: context.loc.serverFavouritesSync.noSupportedBoorus,
                enabled: false,
                trailingIcon: const Icon(Icons.favorite_border),
              )
            else ...[
              SettingsDropdown<ServerFavoriteAdapter>(
                value: selectedAdapter,
                items: adapters,
                title: context.loc.serverFavouritesSync.source,
                itemTitleBuilder: (adapter) => adapter?.displayName ?? '',
                itemSubtitleBuilder: (adapter) => adapter?.host ?? '',
                itemBuilder: (adapter) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BooruFavicon(adapter?.booru),
                    const SizedBox(width: 8),
                    Flexible(child: Text(adapter?.displayName ?? '', overflow: TextOverflow.ellipsis)),
                  ],
                ),
                onChanged: isBusy
                    ? null
                    : (adapter) {
                        if (adapter != null) setState(() => _selectAdapter(adapter));
                      },
              ),
              if (selectedAdapter != null) _adapterTile(selectedAdapter!),
              SettingsDropdown<ServerFavoriteSyncMode>(
                value: mode,
                items: ServerFavoriteSyncMode.values,
                title: context.loc.serverFavouritesSync.syncMode,
                itemTitleBuilder: (item) => item?.title ?? '',
                onChanged: isBusy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          mode = value;
                          preview = null;
                          previewFailed = false;
                          result = null;
                        });
                      },
              ),
              SettingsButton(
                name: context.loc.serverFavouritesSync.previewSelected,
                icon: const Icon(Icons.manage_search),
                enabled: canPreviewSelected,
                action: canPreviewSelected ? previewSelected : null,
              ),
              if (previewFailed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    context.loc.serverFavouritesSync.previewFailedHint,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (mode == ServerFavoriteSyncMode.exportLocal && acknowledgedExports.isNotEmpty)
                SettingsButton(
                  name: context.loc.serverFavouritesSync.restartExport,
                  enabled: !isBusy,
                  icon: const Icon(Icons.restart_alt),
                  action: isBusy
                      ? null
                      : () {
                          setState(() {
                            acknowledgedExports.clear();
                            exportAccountIdentity = null;
                            preview = null;
                            result = null;
                          });
                        },
                ),
              if (preview != null) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.preview, enabled: false),
                _previewTile(selectedAdapter!, preview!),
              ],
              SettingsButton(
                name: mode.isDestructive
                    ? context.loc.serverFavouritesSync.runSelectedRemoves
                    : context.loc.serverFavouritesSync.runSelected,
                subtitle: preview?.hasChanges == true
                    ? null
                    : Text(
                        preview?.hasChanges == false
                            ? (mode == ServerFavoriteSyncMode.importServer &&
                                      selectedAdapter?.capabilities.canEnumerateAll == false
                                  ? context.loc.serverFavouritesSync.partialImportNoChanges
                                  : context.loc.serverFavouritesSync.noChanges)
                            : context.loc.serverFavouritesSync.previewRequiredBeforeRun,
                      ),
                icon: Icon(mode.isDestructive ? Icons.warning_amber : Icons.sync),
                enabled: canRunSelected,
                action: canRunSelected ? runSelected : null,
              ),
              if (result != null) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.result, enabled: false),
                ..._resultSection(selectedAdapter!, result!),
              ],
              if (logLines.isNotEmpty) ...[
                SettingsButton(name: context.loc.serverFavouritesSync.log, enabled: false),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(logLines.take(12).join('\n')),
                ),
              ],
            ],
            if (getSankakuBoorus().isNotEmpty) ..._sankakuMaintenance(),
          ],
        ),
      ),
    );
  }

  Widget _adapterTile(ServerFavoriteAdapter adapter) {
    final supported = _modeSupported(adapter);
    return ListTile(
      title: Text(adapter.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(adapter.host),
          if (adapter.capabilities.listingHint != null) Text(adapter.capabilities.listingHint!),
          if (mode == ServerFavoriteSyncMode.exportLocal &&
              adapter.capabilities.canAdd &&
              !adapter.capabilities.canEnumerateAll)
            Text(context.loc.serverFavouritesSync.writeOnlyHint),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (adapter.capabilities.canFetch) Chip(label: Text(context.loc.serverFavouritesSync.capabilityImport)),
              if (adapter.capabilities.canAdd) Chip(label: Text(context.loc.serverFavouritesSync.capabilityExport)),
              if (adapter.capabilities.canRemove) Chip(label: Text(context.loc.serverFavouritesSync.capabilityRemove)),
              if (adapter.capabilities.requiresAuth) Chip(label: Text(context.loc.serverFavouritesSync.capabilityAuth)),
              if (adapter.capabilities.isReadOnly)
                Chip(label: Text(context.loc.serverFavouritesSync.capabilityReadOnly)),
            ],
          ),
          if (!supported)
            Text(
              adapter.unavailableModeReason(mode) ?? context.loc.serverFavouritesSync.selectedModeNotSupported,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      leading: BooruFavicon(adapter.booru, size: 24),
    );
  }

  Widget _previewTile(ServerFavoriteAdapter adapter, ServerFavoritesSyncPreview preview) {
    return SettingsButton(
      name: adapter.displayName,
      icon: BooruFavicon(adapter.booru, size: 24),
      enabled: false,
      subtitle: Text(
        !adapter.capabilities.usesServerSnapshot(preview.mode)
            ? context.loc.serverFavouritesSync.exportPreviewSummary(
                remaining: preview.addServer,
                confirmed: preview.acknowledgedExports.length,
              )
            : !adapter.capabilities.canEnumerateAll
            ? context.loc.serverFavouritesSync.partialPreviewSummary(
                matched: preview.matched,
                addLocal: preview.addLocal,
              )
            : context.loc.serverFavouritesSync.previewSummary(
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
      icon: BooruFavicon(adapter.booru, size: 24),
      enabled: false,
      subtitle: Text(
        '${context.loc.serverFavouritesSync.resultSummary(
          addedLocal: result.addedLocal,
          addedServer: result.addedServer,
          removedLocal: result.removedLocal,
          removedServer: result.removedServer,
          failed: result.failed,
        )}${result.remaining > 0 ? '\n${context.loc.serverFavouritesSync.remainingChanges(count: result.remaining)}' : ''}${result.errors.isEmpty ? '' : '\n${result.errors.take(4).join('\n')}'}',
      ),
      trailingIcon: Icon(
        result.cancelled
            ? Icons.cancel
            : (result.failed == 0 && result.remaining == 0 ? Icons.check : Icons.warning_amber),
      ),
    );
  }

  List<Widget> _resultSection(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult result) {
    return [
      _resultTile(adapter, result),
      if (result.failed > 0 || result.remaining > 0 || result.cancelled) ...[
        SettingsButton(
          name: context.loc.serverFavouritesSync.copyFailureLog,
          icon: const Icon(Icons.copy),
          dense: true,
          action: () => _copyFailureLog(adapter, result),
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.refreshPreview,
          icon: const Icon(Icons.refresh),
          dense: true,
          enabled: !isBusy,
          action: isBusy ? null : previewSelected,
        ),
      ],
    ];
  }

  void _copyFailureLog(ServerFavoriteAdapter adapter, ServerFavoritesSyncResult result) {
    final summary =
        'Added local: ${result.addedLocal}, added server: ${result.addedServer}, '
        'removed local: ${result.removedLocal}, removed server: ${result.removedServer}, failed: ${result.failed}, remaining: ${result.remaining}';
    final buffer = StringBuffer()
      ..writeln('Server favourites sync')
      ..writeln('Booru: ${adapter.displayName}')
      ..writeln('Mode: ${result.preview.mode.name}')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln(summary);

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
            ignoring: isBusy,
            child: Column(
              children: [
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
                  enabled: !isBusy,
                  action: isBusy ? null : updateSankakuItems,
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
      ],
      if (!isUpdatingSankakuUrls && failedItems.isNotEmpty) ...[
        SettingsButton(
          name: context.loc.serverFavouritesSync.purgeFailedItems(count: failedItems.length),
          trailingIcon: const Icon(Icons.delete_forever),
          drawTopBorder: true,
          enabled: !isBusy,
          action: isBusy ? null : purgeFailedSankakuItems,
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.retryFailedItems(count: failedItems.length),
          trailingIcon: const Icon(Icons.refresh),
          drawTopBorder: true,
          enabled: !isBusy,
          action: isBusy ? null : () => updateSankakuItems(customItems: [...failedItems]),
        ),
      ],
      const SettingsButton(name: '', enabled: false),
    ];
  }
}
