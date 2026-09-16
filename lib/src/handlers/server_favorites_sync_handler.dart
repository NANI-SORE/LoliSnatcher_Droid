import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/server_favorite_adapter.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/server_favorite_feedback.dart';

class ServerFavoritesSyncHandler {
  ServerFavoritesSyncHandler({
    required this.adapter,
    SettingsHandler? settingsHandler,
    SearchHandler? searchHandler,
  }) : settingsHandler = settingsHandler ?? SettingsHandler.instance,
       searchHandler = searchHandler ?? SearchHandler.instance;

  final ServerFavoriteAdapter adapter;
  final SettingsHandler settingsHandler;
  final SearchHandler searchHandler;

  void _checkMode(ServerFavoriteSyncMode mode) {
    if (!adapter.capabilities.supportsMode(mode)) {
      throw StateError(adapter.capabilities.unsupportedReason ?? loc.serverFavouritesSync.selectedModeNotSupported);
    }
  }

  void _checkCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() == true) throw StateError('Server favourites sync cancelled');
  }

  Future<ServerFavoritesSyncPreview> preview(
    ServerFavoriteSyncMode mode, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    _checkMode(mode);
    // Write-only adapters can export additions, but cannot supply a mirror snapshot.
    final diff = mode == ServerFavoriteSyncMode.exportLocal && !adapter.capabilities.canFetch
        ? ServerFavoritesDiff(
            localById: await _localFavoritesById(shouldCancel: shouldCancel),
            serverById: const {},
          )
        : await loadDiff(onStatus: onStatus, shouldCancel: shouldCancel, requireComplete: mode.isDestructive);
    _checkCancelled(shouldCancel);
    return ServerFavoritesSyncPreview(diff: diff, mode: mode);
  }

  Future<ServerFavoritesDiff> loadDiff({
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
    bool requireComplete = true,
  }) async {
    if (!adapter.capabilities.canFetch) {
      throw StateError(adapter.capabilities.unsupportedReason ?? 'Server favourites cannot be fetched');
    }
    final local = await _localFavoritesById(shouldCancel: shouldCancel);
    _checkCancelled(shouldCancel);
    final serverEntries = await adapter.fetchFavorites(
      onStatus: onStatus,
      shouldCancel: shouldCancel,
      requireComplete: requireComplete,
    );

    _checkCancelled(shouldCancel);
    final server = <String, BooruItem>{};
    for (final entry in serverEntries) {
      if (!adapter.ownsPostUrl(entry.item.postURL)) {
        throw StateError('The server returned a favourite from a different source');
      }
      server[entry.serverId] = entry.item;
    }

    return ServerFavoritesDiff(localById: local, serverById: server);
  }

  Future<ServerFavoritesSyncResult> apply(
    ServerFavoritesSyncPreview preview, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    _checkMode(preview.mode);
    final result = ServerFavoritesSyncResult(preview: preview);

    if (preview.addLocal > 0) {
      await _addLocal(
        preview.diff.serverOnlyItems(),
        result,
        onStatus: onStatus,
        shouldCancel: shouldCancel,
      );
    }

    if (preview.addServer > 0) {
      await _addServer(
        preview.diff.localOnlyIds.toList(),
        result,
        onStatus: onStatus,
        shouldCancel: shouldCancel,
      );
    }

    if (preview.removeLocal > 0) {
      await _removeLocal(
        preview.diff.localOnlyItems(),
        result,
        onStatus: onStatus,
        shouldCancel: shouldCancel,
      );
    }

    if (preview.removeServer > 0) {
      await _removeServer(
        preview.diff.serverOnlyIds.toList(),
        result,
        onStatus: onStatus,
        shouldCancel: shouldCancel,
      );
    }

    if (shouldCancel?.call() == true) result.cancelled = true;
    await _refreshAfterSync(result);
    return result;
  }

  Future<ServerFavoritesSyncResult> retryFailures(
    ServerFavoritesSyncResult previousResult, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    _checkMode(previousResult.preview.mode);
    final result = ServerFavoritesSyncResult(preview: previousResult.preview)
      ..addedLocal = previousResult.addedLocal
      ..addedServer = previousResult.addedServer
      ..removedLocal = previousResult.removedLocal
      ..removedServer = previousResult.removedServer;
    final failures = previousResult.failures;

    await _addLocal(
      failures
          .where((failure) => failure.operation == ServerFavoritesSyncFailureOperation.addLocal)
          .map((failure) => failure.item)
          .whereType<BooruItem>()
          .toList(),
      result,
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );
    await _addServer(
      failures
          .where((failure) => failure.operation == ServerFavoritesSyncFailureOperation.addServer)
          .map((failure) => failure.serverId)
          .whereType<String>()
          .toList(),
      result,
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );
    await _removeLocal(
      failures
          .where((failure) => failure.operation == ServerFavoritesSyncFailureOperation.removeLocal)
          .map((failure) => failure.item)
          .whereType<BooruItem>()
          .toList(),
      result,
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );
    await _removeServer(
      failures
          .where((failure) => failure.operation == ServerFavoritesSyncFailureOperation.removeServer)
          .map((failure) => failure.serverId)
          .whereType<String>()
          .toList(),
      result,
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );

    if (shouldCancel?.call() == true) result.cancelled = true;
    await _refreshAfterSync(result);
    return result;
  }

  Future<Map<String, BooruItem>> _localFavoritesById({bool Function()? shouldCancel}) async {
    final database = settingsHandler.dbHandler.db;
    if (database == null || !database.isOpen) throw StateError('The favourites database is not open');
    final itemsByPostUrl = <String, BooruItem>{};
    const int pageSize = 500;
    for (final host in adapter.localHosts) {
      for (int offset = 0; ; offset += pageSize) {
        _checkCancelled(shouldCancel);
        final items = await settingsHandler.dbHandler.getFavouriteItemsForHost(
          host,
          limit: pageSize,
          offset: offset,
        );
        if (items.isEmpty) break;
        for (final item in items) {
          // SQL only finds candidates; shared CDNs and URL substrings are not ownership proof.
          if (adapter.ownsPostUrl(item.postURL)) itemsByPostUrl[item.postURL] = item;
        }
        if (items.length < pageSize) break;
      }
    }
    _checkCancelled(shouldCancel);
    final byId = <String, BooruItem>{};
    for (final item in itemsByPostUrl.values) {
      final id = adapter.serverIdFromItem(item);
      if (id == null || id.isEmpty) continue;
      item.serverId = id;
      byId[id] = item;
    }
    return byId;
  }

  Future<void> _addLocal(
    List<BooruItem> items,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    for (final item in items) {
      if (_deferAction(result, ServerFavoritesSyncFailureOperation.addLocal, item: item, shouldCancel: shouldCancel)) {
        continue;
      }
      onStatus?.call('${adapter.displayName}: adding local ${item.serverId ?? item.postURL}');
      final previousFavourite = item.isFavourite.value;
      try {
        if (!adapter.ownsPostUrl(item.postURL)) throw StateError('Favourite belongs to a different source');
        item.isFavourite.value = true;
        await settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.favourite);
        result.addedLocal++;
      } catch (e) {
        item.isFavourite.value = previousFavourite;
        result.failed++;
        final message = 'Local add failed: ${item.postURL} - $e';
        result.errors.add(message);
        result.failures.add(
          ServerFavoritesSyncFailure(
            operation: ServerFavoritesSyncFailureOperation.addLocal,
            item: item,
            message: message,
          ),
        );
      }
    }
  }

  Future<void> _addServer(
    List<String> ids,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    for (final id in ids) {
      if (_deferAction(
        result,
        ServerFavoritesSyncFailureOperation.addServer,
        serverId: id,
        shouldCancel: shouldCancel,
      )) {
        continue;
      }
      onStatus?.call('${adapter.displayName}: adding server $id');
      final mutation = await _mutateServer(id, remove: false);
      if (mutation.success) {
        result.addedServer++;
      } else {
        result.failed++;
        final message = 'Server add failed: $id - ${mutation.message}';
        result.errors.add(message);
        result.failures.add(
          ServerFavoritesSyncFailure(
            operation: ServerFavoritesSyncFailureOperation.addServer,
            serverId: id,
            message: message,
          ),
        );
      }
    }
  }

  Future<void> _removeLocal(
    List<BooruItem> items,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    final deferRemovals = result.preview.mode.isDestructive && result.failed > 0;
    for (final item in items) {
      if (_deferAction(
        result,
        ServerFavoritesSyncFailureOperation.removeLocal,
        item: item,
        shouldCancel: shouldCancel,
        deferRemoval: deferRemovals,
      )) {
        continue;
      }
      onStatus?.call('${adapter.displayName}: removing local ${item.serverId ?? item.postURL}');
      final previousFavourite = item.isFavourite.value;
      try {
        if (!adapter.ownsPostUrl(item.postURL)) throw StateError('Favourite belongs to a different source');
        item.isFavourite.value = false;
        await settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.favourite);
        result.removedLocal++;
      } catch (e) {
        item.isFavourite.value = previousFavourite;
        result.failed++;
        final message = 'Local remove failed: ${item.postURL} - $e';
        result.errors.add(message);
        result.failures.add(
          ServerFavoritesSyncFailure(
            operation: ServerFavoritesSyncFailureOperation.removeLocal,
            item: item,
            message: message,
          ),
        );
      }
    }
  }

  Future<void> _removeServer(
    List<String> ids,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    final deferRemovals = result.preview.mode.isDestructive && result.failed > 0;
    for (final id in ids) {
      if (_deferAction(
        result,
        ServerFavoritesSyncFailureOperation.removeServer,
        serverId: id,
        shouldCancel: shouldCancel,
        deferRemoval: deferRemovals,
      )) {
        continue;
      }
      onStatus?.call('${adapter.displayName}: removing server $id');
      final mutation = await _mutateServer(id, remove: true);
      if (mutation.success) {
        result.removedServer++;
      } else {
        result.failed++;
        final message = 'Server remove failed: $id - ${mutation.message}';
        result.errors.add(message);
        result.failures.add(
          ServerFavoritesSyncFailure(
            operation: ServerFavoritesSyncFailureOperation.removeServer,
            serverId: id,
            message: message,
          ),
        );
      }
    }
  }

  bool _deferAction(
    ServerFavoritesSyncResult result,
    ServerFavoritesSyncFailureOperation operation, {
    BooruItem? item,
    String? serverId,
    bool Function()? shouldCancel,
    bool deferRemoval = false,
  }) {
    if (shouldCancel?.call() == true) result.cancelled = true;
    if (!result.cancelled && !deferRemoval) return false;
    final failure = ServerFavoritesSyncFailure(
      operation: operation,
      item: item,
      serverId: serverId,
      message: result.cancelled ? 'Cancelled before applying this action' : 'Removal deferred because additions failed',
    );
    result.failed++;
    result.failures.add(failure);
    result.errors.add(failure.logLine);
    return true;
  }

  Future<ServerFavoriteMutationResult> _mutateServer(String id, {required bool remove}) async {
    final caps = adapter.capabilities;
    if (remove ? !caps.canRemove : !caps.canAdd) {
      return ServerFavoriteMutationResult.failure(
        caps.unsupportedReason ?? loc.serverFavouritesSync.serverWriteUnsupported,
      );
    }
    final key = ServerFavoriteFeedback.requestKey(booruName: adapter.displayName, serverId: id);
    if (!ServerFavoriteFeedback.tryStartRequest(key)) {
      return ServerFavoriteMutationResult.failure('A favourite request is already running');
    }
    try {
      return remove ? await adapter.removeFavoriteResult(id) : await adapter.addFavoriteResult(id);
    } catch (error) {
      return ServerFavoriteMutationResult.failure(error.toString());
    } finally {
      ServerFavoriteFeedback.finishRequest(key);
    }
  }

  Future<void> _refreshAfterSync(ServerFavoritesSyncResult result) async {
    if (result.addedLocal == 0 && result.removedLocal == 0) return;
    try {
      await _refreshOpenTabs();
    } catch (error) {
      result.failed++;
      result.errors.add('Could not refresh open tabs: $error');
    }
  }

  Future<void> _refreshOpenTabs() async {
    final localById = await _localFavoritesById();
    for (final tab in searchHandler.tabs) {
      var changed = false;
      for (final item in tab.booruHandler.fetched) {
        if (!adapter.ownsPostUrl(item.postURL)) continue;
        final id = adapter.serverIdFromItem(item);
        if (id == null) continue;
        item.isFavourite.value = localById.containsKey(id);
        changed = true;
      }
      if (changed) tab.booruHandler.filterFetched();
    }
  }
}
