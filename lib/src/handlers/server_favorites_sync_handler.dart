import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/server_favorite_adapter.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/server_favorite_coordinator.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

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
      throw StateError(adapter.unavailableModeReason(mode) ?? 'Selected mode is not supported');
    }
  }

  void _checkCancelled(bool Function()? shouldCancel) {
    if (shouldCancel?.call() == true) throw StateError('Cancelled before applying this action');
    DioNetwork.throwIfCancelled();
  }

  Future<ServerFavoritesSyncPreview> preview(
    ServerFavoriteSyncMode mode, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
    Set<String> acknowledgedExports = const {},
    String? exportAccountIdentity,
  }) async {
    _checkMode(mode);
    onStatus?.call('${adapter.displayName}: reading local favourite identities');
    final local = await _localFavoritesById(shouldCancel: shouldCancel);
    final server = <String>{};
    if (adapter.capabilities.usesServerSnapshot(mode)) {
      await adapter.fetchFavorites(
        onStatus: onStatus,
        shouldCancel: shouldCancel,
        requireComplete: mode.isDestructive || mode == ServerFavoriteSyncMode.twoWayMerge,
        onPage: (entries) async {
          for (final entry in entries) {
            if (!adapter.ownsPostUrl(entry.item.postURL)) {
              throw StateError('The favourite belongs to a different source');
            }
            server.add(entry.serverId);
          }
          onStatus?.call('${adapter.displayName}: ${server.length} server favourites read');
          return true;
        },
      );
    }
    _checkCancelled(shouldCancel);
    return ServerFavoritesSyncPreview(
      diff: ServerFavoritesDiff(localUrlsById: local, serverIds: server),
      mode: mode,
      sourceIdentity: adapter.requestIdentity,
      exportAccountIdentity: acknowledgedExports.isEmpty ? null : exportAccountIdentity,
      acknowledgedExports: adapter.capabilities.usesServerSnapshot(mode)
          ? const {}
          : acknowledgedExports.intersection(local.keys.toSet()),
    );
  }

  Future<ServerFavoritesSyncResult> apply(
    ServerFavoritesSyncPreview preview, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    _checkMode(preview.mode);
    if (preview.sourceIdentity != adapter.requestIdentity) {
      throw StateError('Account settings changed. Review a fresh preview before running again.');
    }
    final result = ServerFavoritesSyncResult(preview: preview);
    try {
      _checkCancelled(shouldCancel);
      if (preview.addLocal > 0 || preview.removeLocal > 0) {
        onStatus?.call('${adapter.displayName}: preparing local favourite lookups');
        await settingsHandler.dbHandler.prepareFavouriteSync();
        _checkCancelled(shouldCancel);
      }
      if (preview.addLocal > 0) {
        await _addLocal(result, onStatus: onStatus, shouldCancel: shouldCancel);
      }
      if (preview.addServer > 0) {
        await _writeServer(
          preview.serverAddIds,
          result,
          remove: false,
          onStatus: onStatus,
          shouldCancel: shouldCancel,
        );
      }
      if (preview.removeLocal > 0) {
        final ids = preview.diff.localOnlyIds.toList();
        for (var offset = 0; offset < ids.length; offset += 100) {
          _checkCancelled(shouldCancel);
          final batch = ids.skip(offset).take(100).toList();
          final urls = batch.expand((id) => preview.diff.localUrlsById[id]!).toList();
          if (urls.any((url) => !adapter.ownsPostUrl(url))) {
            throw StateError('The favourite belongs to a different source');
          }
          await settingsHandler.dbHandler.clearFavouriteUrls(urls);
          result.removedLocal += batch.length;
          onStatus?.call('${adapter.displayName}: removed locally ${result.removedLocal}/${preview.removeLocal}');
        }
      }

      if (preview.removeServer > 0) {
        await _writeServer(
          preview.diff.serverOnlyIds,
          result,
          remove: true,
          onStatus: onStatus,
          shouldCancel: shouldCancel,
        );
      }
    } catch (error) {
      if (shouldCancel?.call() == true) {
        result.cancelled = true;
      } else {
        // Stop on the first failed action. In mirror modes this also prevents
        // removals after a failed addition, without walking all deferred IDs.
        result.failed++;
        if (result.errors.length < 100) result.errors.add(error.toString());
      }
    }
    if (shouldCancel?.call() == true) result.cancelled = true;
    if (result.addedLocal > 0 || result.removedLocal > 0) {
      try {
        // Cancellation stops server work; completed local changes still reach open tabs.
        await _refreshOpenTabs();
      } catch (error) {
        result.failed++;
        result.errors.add('Could not refresh open tabs: $error');
      }
    }
    return result;
  }

  Future<Map<String, Set<String>>> _localFavoritesById({bool Function()? shouldCancel}) async {
    final byId = <String, Set<String>>{};
    int? beforeId;
    while (true) {
      // This also runs after cancellation to refresh tabs, so only use the explicit check.
      if (shouldCancel?.call() == true) throw StateError('Cancelled while reading local favourites');
      final rows = await settingsHandler.dbHandler.getFavouriteIdentities(beforeId: beforeId);
      if (rows.isEmpty) break;
      for (final row in rows) {
        final url = row['postURL']! as String;
        if (!adapter.ownsPostUrl(url)) continue;
        final storedId = row['serverId']?.toString();
        final id = storedId != null && storedId.isNotEmpty && storedId != 'null'
            ? storedId
            : adapter.serverIdFromUrl(url);
        if (id == null || id.isEmpty) continue;
        (byId[id] ??= {}).add(url);
      }
      beforeId = rows.last['id']! as int;
      if (rows.length < 500) break;
    }
    return byId;
  }

  Future<void> _addLocal(
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    final pending = result.preview.diff.serverOnlyIds.toSet();
    await adapter.fetchFavorites(
      onStatus: onStatus,
      shouldCancel: shouldCancel,
      requireComplete: result.preview.mode.isDestructive || result.preview.mode == ServerFavoriteSyncMode.twoWayMerge,
      onPage: (entries) async {
        final planned = entries.where((entry) => pending.contains(entry.serverId)).toList();
        for (var offset = 0; offset < planned.length; offset += 100) {
          _checkCancelled(shouldCancel);
          final batch = planned.skip(offset).take(100).toList();
          if (batch.any((entry) => !adapter.ownsPostUrl(entry.item.postURL))) {
            throw StateError('The favourite belongs to a different source');
          }
          await settingsHandler.dbHandler.setFavouriteBatch(batch.map((entry) => entry.item).toList());
          for (final entry in batch) {
            pending.remove(entry.serverId);
          }
          result.addedLocal += batch.length;
          final tags = {
            for (final entry in batch)
              for (final tag in entry.item.tagsList) tag.fullString: tag,
          };
          for (final tag in tags.values) {
            final tagHandler = TagHandler.instance;
            if (!tagHandler.hasTag(tag.fullString) || tagHandler.getTag(tag.fullString).tagType.isNone) {
              await tagHandler.putTag(tag, dbEnabled: true, useDB: false, preferTypeIfNone: true);
            }
          }
          onStatus?.call('${adapter.displayName}: added locally ${result.addedLocal}/${result.preview.addLocal}');
        }
        return pending.isNotEmpty;
      },
    );
    if (pending.isNotEmpty) {
      throw StateError('${pending.length} planned imports were no longer available. Refresh the preview.');
    }
  }

  Future<void> _writeServer(
    Set<String> ids,
    ServerFavoritesSyncResult result, {
    required bool remove,
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    var done = 0;
    String? exportAccount = result.preview.exportAccountIdentity;
    for (final id in ids) {
      _checkCancelled(shouldCancel);
      onStatus?.call('${adapter.displayName}: ${remove ? 'removing' : 'adding'} on server ${done + 1}/${ids.length}');
      if (exportAccount != null && await adapter.exportSessionIdentity() != exportAccount) {
        throw StateError('The website account changed. Start a new preview before continuing.');
      }
      final mutation = await _mutateServer(id, remove: remove);
      if (!mutation.success) {
        _checkCancelled(shouldCancel);
        throw StateError('Server ${remove ? 'removal' : 'addition'} failed for $id: ${mutation.message}');
      }
      if (remove) {
        result.removedServer++;
      } else {
        if (!adapter.capabilities.canEnumerateAll) {
          final currentAccount = mutation.accountIdentity;
          if (exportAccount != null && currentAccount != exportAccount) {
            throw StateError('The website account changed during the request. Refresh the preview.');
          }
          if (currentAccount != null) {
            exportAccount = currentAccount;
            result.exportAccountIdentity = currentAccount;
            result.confirmedServerAdds.add(id);
          }
        }
        result.addedServer++;
      }
      done++;
    }
  }

  Future<ServerFavoriteMutationResult> _mutateServer(String id, {required bool remove}) async {
    final caps = adapter.capabilities;
    if (remove ? !caps.canRemove : !caps.canAdd) {
      return ServerFavoriteMutationResult.failure(caps.unsupportedReason ?? 'Server favourite write is unsupported');
    }
    final key = adapter.requestKey(id);
    if (!ServerFavoriteCoordinator.tryStart(key)) {
      return ServerFavoriteMutationResult.failure('A favourite request is already running');
    }
    try {
      return remove ? await adapter.removeFavoriteResult(id) : await adapter.addFavoriteResult(id);
    } catch (error) {
      return ServerFavoriteMutationResult.failure(error.toString());
    } finally {
      ServerFavoriteCoordinator.finish(key);
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
