import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

enum ServerFavoriteSyncMode {
  importServer,
  exportLocal,
  twoWayMerge,
  mirrorServerToLocal,
  mirrorLocalToServer,
}

extension ServerFavoriteSyncModeExt on ServerFavoriteSyncMode {
  String get title {
    switch (this) {
      case ServerFavoriteSyncMode.importServer:
        return 'Import server to local'.temploc;
      case ServerFavoriteSyncMode.exportLocal:
        return 'Export local to server'.temploc;
      case ServerFavoriteSyncMode.twoWayMerge:
        return 'Two-way add/merge'.temploc;
      case ServerFavoriteSyncMode.mirrorServerToLocal:
        return 'Mirror server to local'.temploc;
      case ServerFavoriteSyncMode.mirrorLocalToServer:
        return 'Mirror local to server'.temploc;
    }
  }

  bool get isDestructive =>
      this == ServerFavoriteSyncMode.mirrorServerToLocal || this == ServerFavoriteSyncMode.mirrorLocalToServer;
}

class ServerFavoriteCapabilities {
  const ServerFavoriteCapabilities({
    required this.canFetch,
    required this.canAdd,
    required this.canRemove,
    required this.requiresAuth,
    required this.isDestructiveMirrorAllowed,
    this.unsupportedReason,
  });

  final bool canFetch;
  final bool canAdd;
  final bool canRemove;
  final bool requiresAuth;
  final bool isDestructiveMirrorAllowed;
  final String? unsupportedReason;

  bool get hasAnySupport => canFetch || canAdd || canRemove;
  bool get isReadOnly => canFetch && !canAdd && !canRemove;
}

class ServerFavoriteEntry {
  const ServerFavoriteEntry({
    required this.serverId,
    required this.item,
  });

  final String serverId;
  final BooruItem item;
}

class ServerFavoritesDiff {
  const ServerFavoritesDiff({
    required this.localById,
    required this.serverById,
  });

  final Map<String, BooruItem> localById;
  final Map<String, BooruItem> serverById;

  Set<String> get localIds => localById.keys.toSet();
  Set<String> get serverIds => serverById.keys.toSet();
  Set<String> get matchedIds => localIds.intersection(serverIds);
  Set<String> get localOnlyIds => localIds.difference(serverIds);
  Set<String> get serverOnlyIds => serverIds.difference(localIds);

  List<BooruItem> localOnlyItems() => localOnlyIds.map((id) => localById[id]).whereType<BooruItem>().toList();
  List<BooruItem> serverOnlyItems() => serverOnlyIds.map((id) => serverById[id]).whereType<BooruItem>().toList();
}

class ServerFavoritesSyncPreview {
  const ServerFavoritesSyncPreview({
    required this.diff,
    required this.mode,
  });

  final ServerFavoritesDiff diff;
  final ServerFavoriteSyncMode mode;

  int get matched => diff.matchedIds.length;
  int get localOnly => diff.localOnlyIds.length;
  int get serverOnly => diff.serverOnlyIds.length;

  int get addLocal {
    switch (mode) {
      case ServerFavoriteSyncMode.importServer:
      case ServerFavoriteSyncMode.twoWayMerge:
      case ServerFavoriteSyncMode.mirrorServerToLocal:
        return serverOnly;
      case ServerFavoriteSyncMode.exportLocal:
      case ServerFavoriteSyncMode.mirrorLocalToServer:
        return 0;
    }
  }

  int get addServer {
    switch (mode) {
      case ServerFavoriteSyncMode.exportLocal:
      case ServerFavoriteSyncMode.twoWayMerge:
      case ServerFavoriteSyncMode.mirrorLocalToServer:
        return localOnly;
      case ServerFavoriteSyncMode.importServer:
      case ServerFavoriteSyncMode.mirrorServerToLocal:
        return 0;
    }
  }

  int get removeLocal => mode == ServerFavoriteSyncMode.mirrorServerToLocal ? localOnly : 0;
  int get removeServer => mode == ServerFavoriteSyncMode.mirrorLocalToServer ? serverOnly : 0;
}

class ServerFavoritesSyncResult {
  ServerFavoritesSyncResult({required this.preview});

  final ServerFavoritesSyncPreview preview;
  int addedLocal = 0;
  int addedServer = 0;
  int removedLocal = 0;
  int removedServer = 0;
  int failed = 0;
  final List<String> errors = [];
}
