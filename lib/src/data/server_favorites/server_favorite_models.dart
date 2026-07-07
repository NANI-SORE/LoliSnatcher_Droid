import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';

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
        return loc.serverFavouritesSync.importServerToLocal;
      case ServerFavoriteSyncMode.exportLocal:
        return loc.serverFavouritesSync.exportLocalToServer;
      case ServerFavoriteSyncMode.twoWayMerge:
        return loc.serverFavouritesSync.twoWayAddMerge;
      case ServerFavoriteSyncMode.mirrorServerToLocal:
        return loc.serverFavouritesSync.mirrorServerToLocal;
      case ServerFavoriteSyncMode.mirrorLocalToServer:
        return loc.serverFavouritesSync.mirrorLocalToServer;
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

class ServerFavoriteMutationResult {
  const ServerFavoriteMutationResult({
    required this.success,
    required this.message,
    this.statusCode,
    this.canRetryAfterWebview = false,
  });

  factory ServerFavoriteMutationResult.success({
    String message = 'OK',
    int? statusCode,
  }) {
    return ServerFavoriteMutationResult(
      success: true,
      message: message,
      statusCode: statusCode,
    );
  }

  factory ServerFavoriteMutationResult.failure(
    String message, {
    int? statusCode,
    bool canRetryAfterWebview = false,
  }) {
    return ServerFavoriteMutationResult(
      success: false,
      message: message,
      statusCode: statusCode,
      canRetryAfterWebview: canRetryAfterWebview,
    );
  }

  final bool success;
  final String message;
  final int? statusCode;
  final bool canRetryAfterWebview;

  static ServerFavoriteMutationResult get unsupported => ServerFavoriteMutationResult(
    success: false,
    message: loc.serverFavouritesSync.serverWriteUnsupported,
  );
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
  final List<ServerFavoritesSyncFailure> failures = [];
}

enum ServerFavoritesSyncFailureOperation {
  addLocal,
  addServer,
  removeLocal,
  removeServer,
}

class ServerFavoritesSyncFailure {
  const ServerFavoritesSyncFailure({
    required this.operation,
    required this.message,
    this.item,
    this.serverId,
  });

  final ServerFavoritesSyncFailureOperation operation;
  final String message;
  final BooruItem? item;
  final String? serverId;

  String get target => serverId ?? item?.serverId ?? item?.postURL ?? '?';

  String get logLine => '${operation.name}: $target - $message';
}
