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
    this.canEnumerateAll = false,
    this.canCheckSingle = false,
    this.listingHint,
    this.unsupportedReason,
  });

  final bool canFetch;
  final bool canEnumerateAll;
  final bool canAdd;
  final bool canRemove;
  final bool requiresAuth;
  final bool isDestructiveMirrorAllowed;
  final bool canCheckSingle;
  final String? unsupportedReason;
  final String? listingHint;

  bool get hasAnySupport => canFetch || canAdd || canRemove;
  bool get isReadOnly => canFetch && !canAdd && !canRemove;

  bool supportsMode(ServerFavoriteSyncMode mode) => switch (mode) {
    ServerFavoriteSyncMode.importServer => canFetch,
    ServerFavoriteSyncMode.exportLocal => canAdd,
    ServerFavoriteSyncMode.twoWayMerge => canFetch && canEnumerateAll && canAdd,
    ServerFavoriteSyncMode.mirrorServerToLocal => canFetch && canEnumerateAll && isDestructiveMirrorAllowed,
    ServerFavoriteSyncMode.mirrorLocalToServer =>
      canFetch && canEnumerateAll && canAdd && canRemove && isDestructiveMirrorAllowed,
  };

  bool usesServerSnapshot(ServerFavoriteSyncMode mode) =>
      canFetch && (mode != ServerFavoriteSyncMode.exportLocal || canEnumerateAll);
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
    this.accountIdentity,
  });

  factory ServerFavoriteMutationResult.success({
    String message = 'OK',
    int? statusCode,
    String? accountIdentity,
  }) {
    return ServerFavoriteMutationResult(
      success: true,
      message: message,
      statusCode: statusCode,
      accountIdentity: accountIdentity,
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
  final String? accountIdentity;

  static ServerFavoriteMutationResult get unsupported => ServerFavoriteMutationResult(
    success: false,
    message: loc.serverFavouritesSync.serverWriteUnsupported,
  );
}

class ServerFavoritesDiff {
  ServerFavoritesDiff({required this.localUrlsById, required this.serverIds});

  final Map<String, Set<String>> localUrlsById;
  final Set<String> serverIds;

  // Snapshot membership never changes. Compute differences once, not on every rebuild.
  late final Set<String> localIds = localUrlsById.keys.toSet();
  late final Set<String> localOnlyIds = localIds.difference(serverIds);
  late final Set<String> serverOnlyIds = serverIds.difference(localIds);
  int get matched => localIds.length - localOnlyIds.length;
}

class ServerFavoritesSyncPreview {
  ServerFavoritesSyncPreview({
    required this.diff,
    required this.mode,
    required this.sourceIdentity,
    this.acknowledgedExports = const {},
    this.exportAccountIdentity,
  });

  final ServerFavoritesDiff diff;
  final ServerFavoriteSyncMode mode;
  final String sourceIdentity;
  final Set<String> acknowledgedExports;
  final String? exportAccountIdentity;
  late final Set<String> serverAddIds = diff.localOnlyIds.difference(acknowledgedExports);

  bool sameSnapshot(ServerFavoritesSyncPreview other) {
    bool sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
    return mode == other.mode &&
        sourceIdentity == other.sourceIdentity &&
        sameSet(diff.localIds, other.diff.localIds) &&
        sameSet(diff.serverIds, other.diff.serverIds) &&
        sameSet(
          diff.localUrlsById.values.expand((urls) => urls).toSet(),
          other.diff.localUrlsById.values.expand((urls) => urls).toSet(),
        );
  }

  bool get hasChanges => addLocal + addServer + removeLocal + removeServer > 0;

  int get matched => diff.matched;
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
        return serverAddIds.length;
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
  bool cancelled = false;
  final Set<String> confirmedServerAdds = {};
  String? exportAccountIdentity;
  int get remaining =>
      preview.addLocal +
      preview.addServer +
      preview.removeLocal +
      preview.removeServer -
      addedLocal -
      addedServer -
      removedLocal -
      removedServer;

  final List<String> errors = [];
}
