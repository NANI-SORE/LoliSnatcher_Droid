import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/server_favorite_adapter.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

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

  Future<ServerFavoritesSyncPreview> preview(
    ServerFavoriteSyncMode mode, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    final diff = await loadDiff(
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );
    return ServerFavoritesSyncPreview(diff: diff, mode: mode);
  }

  Future<ServerFavoritesDiff> loadDiff({
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    final local = await _localFavoritesById();
    final serverEntries = await adapter.fetchFavorites(
      onStatus: onStatus,
      shouldCancel: shouldCancel,
    );

    final server = <String, BooruItem>{};
    for (final entry in serverEntries) {
      server[entry.serverId] = entry.item;
    }

    return ServerFavoritesDiff(localById: local, serverById: server);
  }

  Future<ServerFavoritesSyncResult> apply(
    ServerFavoritesSyncPreview preview, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
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

    await _refreshOpenTabs();
    return result;
  }

  Future<Map<String, BooruItem>> _localFavoritesById() async {
    final itemsByPostUrl = <String, BooruItem>{};
    const int pageSize = 500;
    for (final host in adapter.localHosts) {
      for (int offset = 0; ; offset += pageSize) {
        final items = await settingsHandler.dbHandler.getFavouriteItemsForHost(
          host,
          limit: pageSize,
          offset: offset,
        );
        if (items.isEmpty) break;
        for (final item in items) {
          itemsByPostUrl[item.postURL] = item;
        }
        if (items.length < pageSize) break;
      }
    }
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
      if (shouldCancel?.call() == true) break;
      onStatus?.call('${adapter.displayName}: adding local ${item.serverId ?? item.postURL}');
      try {
        item.isFavourite.value = true;
        item.isSnatched.value ??= false;
        await settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.local);
        result.addedLocal++;
      } catch (e) {
        result.failed++;
        result.errors.add('Local add failed: ${item.postURL} - $e');
      }
    }
  }

  Future<void> _addServer(
    List<String> ids,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    if (!adapter.capabilities.canAdd) {
      result.failed += ids.length;
      result.errors.add(adapter.capabilities.unsupportedReason ?? 'Server add is not supported'.temploc);
      return;
    }

    for (final id in ids) {
      if (shouldCancel?.call() == true) break;
      onStatus?.call('${adapter.displayName}: adding server $id');
      if (await adapter.addFavorite(id)) {
        result.addedServer++;
      } else {
        result.failed++;
        result.errors.add('Server add failed: $id');
      }
    }
  }

  Future<void> _removeLocal(
    List<BooruItem> items,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    for (final item in items) {
      if (shouldCancel?.call() == true) break;
      onStatus?.call('${adapter.displayName}: removing local ${item.serverId ?? item.postURL}');
      try {
        item.isFavourite.value = false;
        item.isSnatched.value ??= false;
        await settingsHandler.dbHandler.updateBooruItem(item, BooruUpdateMode.local);
        result.removedLocal++;
      } catch (e) {
        result.failed++;
        result.errors.add('Local remove failed: ${item.postURL} - $e');
      }
    }
  }

  Future<void> _removeServer(
    List<String> ids,
    ServerFavoritesSyncResult result, {
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    if (!adapter.capabilities.canRemove) {
      result.failed += ids.length;
      result.errors.add(adapter.capabilities.unsupportedReason ?? 'Server remove is not supported'.temploc);
      return;
    }

    for (final id in ids) {
      if (shouldCancel?.call() == true) break;
      onStatus?.call('${adapter.displayName}: removing server $id');
      if (await adapter.removeFavorite(id)) {
        result.removedServer++;
      } else {
        result.failed++;
        result.errors.add('Server remove failed: $id');
      }
    }
  }

  Future<void> _refreshOpenTabs() async {
    final localById = await _localFavoritesById();
    for (final tab in searchHandler.tabs) {
      for (final item in tab.booruHandler.fetched) {
        final id = adapter.serverIdFromItem(item);
        if (id == null) continue;
        item.isFavourite.value = localById.containsKey(id);
      }
      tab.booruHandler.filterFetched();
    }
  }
}
