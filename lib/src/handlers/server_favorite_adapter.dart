import 'package:dio/dio.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_id_parser.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';

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

  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    return ServerFavoriteMutationResult.unsupported;
  }

  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    return ServerFavoriteMutationResult.unsupported;
  }

  bool canMutateServerId(String serverId) => RegExp(r'^[0-9]+$').hasMatch(serverId);

  ServerFavoriteMutationResult invalidServerIdResult(String serverId) {
    return ServerFavoriteMutationResult.failure('Unsafe or unsupported server ID for write: $serverId');
  }

  bool _isSuccessStatus(int? statusCode) => statusCode != null && statusCode >= 200 && statusCode < 300;

  ServerFavoriteMutationResult _httpResult(
    Response response, {
    String successMessage = 'OK',
    bool Function(Response response)? isSuccess,
    String Function(Response response)? failureMessage,
  }) {
    final success = isSuccess?.call(response) ?? _isSuccessStatus(response.statusCode);
    if (success) {
      return ServerFavoriteMutationResult.success(
        message: successMessage,
        statusCode: response.statusCode,
      );
    }

    return ServerFavoriteMutationResult.failure(
      failureMessage?.call(response) ?? 'HTTP ${response.statusCode}: ${response.statusMessage ?? 'request failed'}',
      statusCode: response.statusCode,
    );
  }

  ServerFavoriteMutationResult _exceptionResult(Object error) {
    if (error is DioException) {
      return ServerFavoriteMutationResult.failure(
        error.response == null
            ? (error.message ?? error.type.name)
            : 'HTTP ${error.response?.statusCode}: ${error.response?.statusMessage ?? error.message ?? error.type.name}',
        statusCode: error.response?.statusCode,
      );
    }
    return ServerFavoriteMutationResult.failure(error.toString());
  }

  String cloudflareBlockedMessage(String action, String siteName) {
    return '$siteName $action may be blocked by Cloudflare. Open $siteName in the in-app webview, log in, complete any captcha, then retry.';
  }

  bool looksCloudflareBlocked(Response response) {
    final body = response.data.toString().toLowerCase();
    return response.statusCode == 403 ||
        body.contains('cf-challenge') ||
        body.contains('cf_clearance') ||
        body.contains('just a moment') ||
        body.contains('checking your browser');
  }
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
    unsupportedReason: _hasAuth ? null : loc.serverFavouritesSync.missingLoginApiKey,
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
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final response = await DioNetwork.post(
        '${booru.baseURL}/favorites.json',
        queryParameters: {
          ..._authQuery,
          'post_id': serverId,
        },
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      return _httpResult(response, successMessage: 'Danbooru favourite added');
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    final client = DioNetwork.getClient();
    try {
      final response = await client.delete(
        '${booru.baseURL}/favorites/${Uri.encodeComponent(serverId)}.json',
        queryParameters: _authQuery,
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      return _httpResult(response, successMessage: 'Danbooru favourite removed');
    } catch (e) {
      return _exceptionResult(e);
    } finally {
      client.close();
    }
  }
}

class GelbooruServerFavoriteAdapter extends ServerFavoriteAdapter {
  GelbooruServerFavoriteAdapter(super.booru);

  bool get _hasUserId => booru.userID?.isNotEmpty == true;
  bool get _hasApiKey => booru.apiKey?.isNotEmpty == true;
  bool get _isOfficialGelbooru {
    final host = Uri.tryParse(booru.baseURL ?? '')?.host.toLowerCase();
    return host == 'gelbooru.com' || host == 'www.gelbooru.com';
  }

  bool get _canWrite => _isOfficialGelbooru && _hasUserId && _hasApiKey;

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasUserId,
    canAdd: _canWrite,
    canRemove: _canWrite,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _canWrite,
    unsupportedReason: _hasUserId
        ? (_canWrite ? null : loc.serverFavouritesSync.gelbooruNeedsUserIdApiKey)
        : loc.serverFavouritesSync.missingUserId,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  Map<String, dynamic> get _authQuery => {
    'user_id': booru.userID,
    'api_key': booru.apiKey,
  };

  Future<ServerFavoriteMutationResult?> _preflightHost(String action) async {
    try {
      final response = await DioNetwork.get(
        booru.baseURL!,
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
        customInterceptor: DioNetwork.captchaInterceptor,
      );
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage(action, 'Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      if (!_isSuccessStatus(response.statusCode)) {
        return ServerFavoriteMutationResult.failure(
          'Rule34.xxx host preflight returned HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
      return null;
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final preflight = await _preflightHost('add favourite');
      if (preflight != null) return preflight;

      final response = await DioNetwork.get(
        '${booru.baseURL}/public/addfav.php',
        queryParameters: {
          ..._authQuery,
          'id': serverId,
        },
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
      );
      final code = response.data.toString().trim();
      return _httpResult(
        response,
        successMessage: code == '3' ? 'Gelbooru favourite was already present' : 'Gelbooru favourite added',
        isSuccess: (_) => code == '1' || code == '3',
        failureMessage: (_) => 'Gelbooru add favourite returned $code',
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final preflight = await _preflightHost('remove favourite');
      if (preflight != null) return preflight;

      final response = await DioNetwork.get(
        '${booru.baseURL}/index.php',
        queryParameters: {
          'page': 'favorites',
          's': 'delete',
          'id': serverId,
          ..._authQuery,
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      final body = response.data.toString().toLowerCase();
      final looksAuthFailed =
          body.contains('login') ||
          body.contains('sign in') ||
          body.contains('access denied') ||
          body.contains('not authorized');
      return _httpResult(
        response,
        successMessage: 'Gelbooru favourite removed',
        isSuccess: (response) => (response.statusCode == 200 || response.statusCode == 302) && !looksAuthFailed,
        failureMessage: (response) => looksAuthFailed
            ? 'Gelbooru remove favourite looks unauthenticated'
            : 'Gelbooru remove favourite returned HTTP ${response.statusCode}',
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }
}

class Rule34XxxServerFavoriteAdapter extends ServerFavoriteAdapter {
  Rule34XxxServerFavoriteAdapter(super.booru);

  bool get _hasAuth => booru.userID?.isNotEmpty == true && booru.apiKey?.isNotEmpty == true;

  @override
  List<String> get localHosts => [host, 'rule34.xxx', 'api.rule34.xxx'];

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _hasAuth,
    canAdd: _hasAuth,
    canRemove: _hasAuth,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _hasAuth,
    unsupportedReason: _hasAuth ? null : loc.serverFavouritesSync.missingUserIdPassHash,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  Map<String, dynamic> get _authQuery => {
    'user_id': booru.userID,
    'api_key': booru.apiKey,
  };

  Map<String, dynamic> get _authCookieHeaders => {
    'Cookie': 'user_id=${booru.userID}; pass_hash=${booru.apiKey}',
  };

  @override
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final response = await DioNetwork.get(
        '${booru.baseURL}/public/addfav.php',
        queryParameters: {'id': serverId},
        headers: _authCookieHeaders,
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
        customInterceptor: DioNetwork.captchaInterceptor,
      );
      final body = response.data.toString().trim();
      if (!(response.statusCode == 200 && (body == '1' || body == '3')) && looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('add favourite', 'Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: body == '3' ? 'Rule34.xxx favourite was already present' : 'Rule34.xxx favourite added',
        isSuccess: (_) => response.statusCode == 200 && (body == '1' || body == '3'),
        failureMessage: (_) => 'Rule34.xxx add favourite returned HTTP ${response.statusCode}: $body',
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final response = await DioNetwork.get(
        '${booru.baseURL}/index.php',
        queryParameters: {
          ..._authQuery,
          'page': 'favorites',
          's': 'delete',
          'id': serverId,
          'return_pid': '0',
        },
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
        customInterceptor: DioNetwork.captchaInterceptor,
      );
      final body = response.data.toString().toLowerCase();
      final looksAuthFailed =
          body.contains('login') ||
          body.contains('sign in') ||
          body.contains('access denied') ||
          body.contains('not authorized');
      if (!(response.statusCode == 200 && !looksAuthFailed) && looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('remove favourite', 'Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: 'Rule34.xxx favourite removed',
        isSuccess: (response) => response.statusCode == 200 && !looksAuthFailed,
        failureMessage: (response) {
          return looksAuthFailed
              ? 'Rule34.xxx remove favourite looks unauthenticated'
              : 'Rule34.xxx remove favourite returned HTTP ${response.statusCode}';
        },
      );
    } catch (e) {
      return _exceptionResult(e);
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
        ? loc.serverFavouritesSync.missingLoginPassword
        : (_isIdol ? loc.serverFavouritesSync.idolSankakuWriteUnsupported : null),
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  @override
  bool canMutateServerId(String serverId) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(serverId);

  Future<SankakuHandler?> _signedInHandler() async {
    final handler = SankakuHandler(booru, 100);
    if (!await handler.signIn()) return null;
    return handler;
  }

  @override
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final handler = await _signedInHandler();
      if (handler == null) return ServerFavoriteMutationResult.failure('Sankaku sign-in failed');
      final response = await DioNetwork.post(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        headers: handler.getHeaders(),
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      return _httpResult(response, successMessage: 'Sankaku favourite added');
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    final handler = await _signedInHandler();
    if (handler == null) return ServerFavoriteMutationResult.failure('Sankaku sign-in failed');
    final client = DioNetwork.getClient();
    try {
      final response = await client.delete(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        options: DioNetwork.defaultOptions.copyWith(headers: handler.getHeaders(), validateStatus: (_) => true),
      );
      return _httpResult(response, successMessage: 'Sankaku favourite removed');
    } catch (e) {
      return _exceptionResult(e);
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
        ? loc.serverFavouritesSync.writeEndpointNotVerified
        : loc.serverFavouritesSync.missingUserId,
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
        final host = Uri.tryParse(booru.baseURL ?? '')?.host.toLowerCase();
        if (host == 'rule34.xxx' || host == 'api.rule34.xxx') {
          return Rule34XxxServerFavoriteAdapter(booru);
        }
        if (host == 'gelbooru.com' || host == 'www.gelbooru.com') {
          return GelbooruServerFavoriteAdapter(booru);
        }
        return ReadOnlyFavQueryServerFavoriteAdapter(booru);
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
        return SankakuServerFavoriteAdapter(booru);
      case BooruType.R34US:
        final host = Uri.tryParse(booru.baseURL ?? '')?.host.toLowerCase();
        if (host == 'rule34.xxx' || host == 'api.rule34.xxx') {
          return Rule34XxxServerFavoriteAdapter(booru);
        }
        return ReadOnlyFavQueryServerFavoriteAdapter(booru);
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
