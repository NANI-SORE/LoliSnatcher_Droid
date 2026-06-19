import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_id_parser.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

abstract class ServerFavoriteAdapter {
  ServerFavoriteAdapter(this.booru);

  final Booru booru;

  ServerFavoriteCapabilities get capabilities;

  String get displayName =>
      booru.name?.isNotEmpty == true ? booru.name! : booru.baseURL ?? booru.type?.alias ?? 'Booru';

  String get host {
    final uri = Uri.tryParse(booru.baseURL ?? '');
    return uri?.host.isNotEmpty == true ? uri!.host : (booru.baseURL ?? '').replaceFirst(RegExp('https?://'), '');
  }

  List<String> get localHosts => [host];

  String favoriteQuery();

  String? serverIdFromItem(BooruItem item) =>
      item.serverId?.isNotEmpty == true ? item.serverId : serverIdFromUrl(item.postURL);

  String? serverIdFromUrl(String url);

  Future<List<ServerFavoriteEntry>> fetchFavorites({
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
  }) async {
    if (!capabilities.canFetch) return [];

    final handlerResult = BooruHandlerFactory().getBooruHandler([booru], 100);
    final handler = handlerResult.booruHandler;
    final entries = <ServerFavoriteEntry>[];
    final seenIds = <String>{};
    final query = favoriteQuery();
    int page = handlerResult.startingPage;
    int emptyPages = 0;

    for (int i = 0; i < 100000; i++) {
      if (shouldCancel?.call() == true) break;
      onStatus?.call('$displayName: fetching page $page');
      final before = handler.fetched.length;
      await handler.search(query, page, withCaptchaCheck: true);
      if (handler.errorString.isNotEmpty) {
        throw Exception(handler.errorString);
      }
      final newItems = handler.fetched.skip(before).toList();
      if (newItems.isEmpty) {
        emptyPages++;
        if (handler.locked || emptyPages >= 2) break;
      } else {
        emptyPages = 0;
      }

      for (final item in newItems) {
        final id = serverIdFromItem(item);
        if (id == null || id.isEmpty || !seenIds.add(id)) continue;
        item.serverId = id;
        item.isFavourite.value = true;
        entries.add(ServerFavoriteEntry(serverId: id, item: item));
      }

      page++;
      handler.fetched.clear();
      handler.filteredFetched.clear();
      if (handler.locked) break;
    }

    return entries;
  }

  Future<bool> addFavorite(String serverId) async => false;

  Future<bool> removeFavorite(String serverId) async => false;
}

typedef ValueChanged<T> = void Function(T value);

class DanbooruServerFavoriteAdapter extends ServerFavoriteAdapter {
  DanbooruServerFavoriteAdapter(super.booru);

  bool get _hasAuth => booru.userID?.isNotEmpty == true && booru.apiKey?.isNotEmpty == true;

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasAuth,
    canAdd: _hasAuth,
    canRemove: _hasAuth,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _hasAuth,
    unsupportedReason: _hasAuth ? null : 'Missing login/API key'.temploc,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  Map<String, dynamic> get _authQuery => {
    'login': booru.userID,
    'api_key': booru.apiKey,
  };

  @override
  Future<bool> addFavorite(String serverId) async {
    try {
      final response = await DioNetwork.post(
        '${booru.baseURL}/favorites.json',
        queryParameters: {
          ..._authQuery,
          'post_id': serverId,
        },
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeFavorite(String serverId) async {
    final client = DioNetwork.getClient();
    try {
      final response = await client.delete(
        '${booru.baseURL}/favorites/$serverId.json',
        queryParameters: _authQuery,
        options: DioNetwork.defaultOptions,
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

class GelbooruServerFavoriteAdapter extends ServerFavoriteAdapter {
  GelbooruServerFavoriteAdapter(super.booru);

  bool get _hasUserId => booru.userID?.isNotEmpty == true;
  bool get _hasPassHash => booru.apiKey?.isNotEmpty == true && booru.apiKey?.contains('api_key') != true;
  bool get _isOfficialGelbooru => booru.baseURL?.contains('gelbooru.com') == true;
  bool get _canWrite => _isOfficialGelbooru && _hasUserId && _hasPassHash;

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasUserId,
    canAdd: _canWrite,
    canRemove: _canWrite,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _canWrite,
    unsupportedReason: _hasUserId
        ? (_canWrite ? null : 'Read-only: favorite writes need Gelbooru user_id/pass_hash cookies'.temploc)
        : 'Missing user ID'.temploc,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  Map<String, dynamic> get _cookieHeaders => {
    'Cookie': 'user_id=${booru.userID}; pass_hash=${booru.apiKey}',
  };

  @override
  Future<bool> addFavorite(String serverId) async {
    try {
      final response = await DioNetwork.get(
        '${booru.baseURL}/public/addfav.php',
        queryParameters: {'id': serverId},
        headers: _cookieHeaders,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data.toString() == '1' || response.data.toString() == '3';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeFavorite(String serverId) async {
    try {
      final response = await DioNetwork.get(
        '${booru.baseURL}/index.php',
        queryParameters: {
          'page': 'favorites',
          's': 'delete',
          'id': serverId,
        },
        headers: _cookieHeaders,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status == 200 || status == 302,
        ),
      );
      return response.statusCode == 200 || response.statusCode == 302;
    } catch (_) {
      return false;
    }
  }
}

class SankakuServerFavoriteAdapter extends ServerFavoriteAdapter {
  SankakuServerFavoriteAdapter(super.booru);

  bool get _isIdol => booru.type?.isIdolSankaku == true;
  bool get _hasAuth => booru.userID?.isNotEmpty == true && booru.apiKey?.isNotEmpty == true;

  @override
  List<String> get localHosts => _isIdol
      ? [host, 'idol.sankakucomplex.com', 'idolcomplex.com']
      : [host, 'chan.sankakucomplex.com', 'sankakucomplex.com', 'sankakuapi.com'];

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasAuth,
    canAdd: _hasAuth && !_isIdol,
    canRemove: _hasAuth && !_isIdol,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _hasAuth && !_isIdol,
    unsupportedReason: !_hasAuth
        ? 'Missing login/password'.temploc
        : (_isIdol ? 'Idol Sankaku server favorite writes are not supported'.temploc : null),
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  Future<SankakuHandler?> _signedInHandler() async {
    final handler = SankakuHandler(booru, 100);
    if (!await handler.signIn()) return null;
    return handler;
  }

  @override
  Future<bool> addFavorite(String serverId) async {
    try {
      final handler = await _signedInHandler();
      if (handler == null) return false;
      final response = await DioNetwork.post(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        headers: handler.getHeaders(),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> removeFavorite(String serverId) async {
    final handler = await _signedInHandler();
    if (handler == null) return false;
    final client = DioNetwork.getClient();
    try {
      final response = await client.delete(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        options: DioNetwork.defaultOptions.copyWith(headers: handler.getHeaders()),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}

class ReadOnlyFavQueryServerFavoriteAdapter extends ServerFavoriteAdapter {
  ReadOnlyFavQueryServerFavoriteAdapter(super.booru);

  bool get _hasUserId => booru.userID?.isNotEmpty == true;

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasUserId,
    canAdd: false,
    canRemove: false,
    requiresAuth: true,
    isDestructiveMirrorAllowed: false,
    unsupportedReason: _hasUserId
        ? 'Read-only: write endpoint is not verified for this site'.temploc
        : 'Missing user ID'.temploc,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);
}

class ServerFavoriteAdapterFactory {
  const ServerFavoriteAdapterFactory();

  ServerFavoriteAdapter? adapterFor(Booru booru) {
    switch (booru.type) {
      case BooruType.Danbooru:
        return DanbooruServerFavoriteAdapter(booru);
      case BooruType.Gelbooru:
      case BooruType.GelbooruAlike:
        if (booru.baseURL?.contains('gelbooru.com') == true) {
          return GelbooruServerFavoriteAdapter(booru);
        }
        return ReadOnlyFavQueryServerFavoriteAdapter(booru);
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
        return SankakuServerFavoriteAdapter(booru);
      case BooruType.R34US:
      case BooruType.R34Hentai:
        return ReadOnlyFavQueryServerFavoriteAdapter(booru);
      default:
        return null;
    }
  }

  List<ServerFavoriteAdapter> adaptersFor(Iterable<Booru> boorus) {
    return boorus
        .map(adapterFor)
        .whereType<ServerFavoriteAdapter>()
        .where((adapter) => adapter.capabilities.hasAnySupport)
        .toList();
  }
}
