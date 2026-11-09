import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_id_parser.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

abstract class ServerFavoriteAdapter {
  ServerFavoriteAdapter(this.booru);

  final Booru booru;

  String? get serviceIdentity => booru.baseURL?.replaceFirst(RegExp(r'/+$'), '').toLowerCase();

  // Credentials are fingerprinted, never included in request keys or logs as plaintext.
  String get requestIdentity => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            booru.type?.name,
            serviceIdentity,
            booru.userID,
            booru.authLogin,
            booru.apiKey,
            booru.authPassword,
          ]),
        ),
      )
      .toString();

  String requestKey(String serverId) => '$requestIdentity::$serverId';

  Future<String> exportSessionIdentity() async {
    if (capabilities.canEnumerateAll) return requestIdentity;
    final cookies = await storedCookieHeader();
    return _cookieAccountIdentity(cookies) ?? requestIdentity;
  }

  String? _cookieAccountIdentity(String cookies) {
    final cookieUser = RegExp(r'(^|;)\s*user_id=([^;]+)').firstMatch(cookies)?.group(2)?.trim();
    if (cookieUser == null || cookieUser.isEmpty) return null;
    return sha256.convert(utf8.encode('$requestIdentity::$cookieUser')).toString();
  }

  ServerFavoriteCapabilities get capabilities;

  String get displayName =>
      booru.name?.isNotEmpty == true ? booru.name! : booru.baseURL ?? booru.type?.alias ?? 'Booru';

  String get host {
    final uri = Uri.tryParse(booru.baseURL ?? '');
    return uri?.host.isNotEmpty == true ? uri!.host : (booru.baseURL ?? '').replaceFirst(RegExp('https?://'), '');
  }

  List<String> get localHosts => [host];

  bool ownsPostUrl(String url) {
    final uri = Uri.tryParse(url);
    final base = Uri.tryParse(booru.baseURL ?? '');
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    if (base == null || !base.hasAuthority) return false;
    String normalize(String value) => value.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    int? nonDefaultPort(Uri value) =>
        (value.scheme == 'https' && value.port == 443) || (value.scheme == 'http' && value.port == 80)
        ? null
        : value.port;
    if (nonDefaultPort(base) != nonDefaultPort(uri)) return false;
    if (normalize(base.host) == normalize(uri.host)) {
      final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
      return basePath.isEmpty || uri.path == basePath || uri.path.startsWith('$basePath/');
    }
    // Explicit historical/API aliases are allowed only on standard ports.
    return nonDefaultPort(base) == null && localHosts.any((host) => normalize(host) == normalize(uri.host));
  }

  String favoriteQuery();

  String? unavailableModeReason(ServerFavoriteSyncMode mode) {
    if (capabilities.supportsMode(mode)) return null;
    if (capabilities.unsupportedReason != null) return capabilities.unsupportedReason;
    if (!capabilities.canEnumerateAll && (mode.isDestructive || mode == ServerFavoriteSyncMode.twoWayMerge)) {
      return loc.serverFavouritesSync.completeListRequired;
    }
    return loc.serverFavouritesSync.selectedModeNotSupported;
  }

  ({BooruHandler booruHandler, int startingPage}) createFavoriteReader() =>
      BooruHandlerFactory().getBooruHandler([booru], 100);

  int get favoritePageLimit => 100000;
  bool get allowsPartialPageLimit => false;

  Future<bool> checkFavorite(String serverId) async {
    if (!capabilities.canCheckSingle || !canMutateServerId(serverId)) {
      throw StateError('Checking a single server favourite is unsupported');
    }
    final entries = await fetchFavorites(serverId: serverId);
    return entries.any((entry) => entry.serverId == serverId);
  }

  String? serverIdFromItem(BooruItem item) =>
      item.serverId?.isNotEmpty == true ? item.serverId : serverIdFromUrl(item.postURL);

  String? serverIdFromUrl(String url);

  Future<List<ServerFavoriteEntry>> fetchFavorites({
    ValueChanged<String>? onStatus,
    bool Function()? shouldCancel,
    bool requireComplete = true,
    String? serverId,
    Future<bool> Function(List<ServerFavoriteEntry>)? onPage,
  }) async {
    if (!capabilities.canFetch) throw StateError('This source cannot list server favourites');
    if (requireComplete && serverId == null && !capabilities.canEnumerateAll) {
      throw StateError('This source cannot provide a complete favourite list');
    }
    if (serverId != null && (!capabilities.canCheckSingle || !canMutateServerId(serverId))) {
      throw StateError('Checking a single server favourite is unsupported');
    }

    final handlerResult = createFavoriteReader();
    final handler = handlerResult.booruHandler;
    handler.cacheParsedTagTypes = false;
    final itemTagTypes = <String, TagType>{};
    handler.onParsedTagTypes = (tags, type) {
      for (final tag in tags) {
        if (type != TagType.none || !itemTagTypes.containsKey(tag)) itemTagTypes[tag] = type;
      }
    };
    final entries = <ServerFavoriteEntry>[];
    final seenIds = <String>{};
    final seenPages = <String>{};
    final query = handler.validateTags('${favoriteQuery()}${serverId == null ? '' : ' id:$serverId'}'.trim());
    // The factory returns the page before the first request, as used by gallery search.
    int page = handlerResult.startingPage + 1;

    void checkCancelled() {
      if (shouldCancel?.call() == true) throw StateError('Cancelled before applying this action');
      DioNetwork.throwIfCancelled();
    }

    for (int i = 0; i < favoritePageLimit; i++) {
      checkCancelled();
      onStatus?.call('$displayName: fetching page $page');
      handler.pageNum = page;
      if (!await handler.searchSetup()) {
        throw StateError('Could not prepare the favourites search');
      }
      if (handler.hasSignInSupport && !await handler.isSignedIn()) {
        throw StateError('Sign-in failed');
      }
      checkCancelled();
      final url = Uri.tryParse(handler.makeURL(query));
      if (url == null || !url.hasAuthority) throw StateError('Invalid favourites search URL');
      final response = await handler.fetchSearch(url, query);
      checkCancelled();
      if (response.statusCode != 200 || looksCloudflareBlocked(response)) {
        throw StateError('Could not fetch favourites (HTTP ${response.statusCode})');
      }
      if (response.data is String) {
        final body = (response.data as String).toLowerCase();
        final responseUrl = response.realUri;
        if (body.contains('post-premium-browsing_error') ||
            body.contains('missing authentication') ||
            body.contains('access denied') ||
            RegExp(r'/(login|sign_in|signin)(/|$)').hasMatch(responseUrl.path) ||
            responseUrl.queryParameters['s'] == 'login') {
          throw StateError('The server restricted favourite pagination');
        }
      }

      final data = response.data;
      Object? jsonData = data;
      if (data is String && (data.trimLeft().startsWith('[') || data.trimLeft().startsWith('{'))) {
        jsonData = jsonDecode(data);
      }
      if (jsonData is Map) {
        final success = jsonData['success'];
        final status = jsonData['status']?.toString().toLowerCase();
        if (jsonData['post'] is! List ||
            success == false ||
            success == 'false' ||
            success == 0 ||
            jsonData['error'] != null ||
            jsonData['errors'] != null ||
            status == 'error' ||
            status == 'failed') {
          throw StateError('The server returned an invalid favourite response');
        }
      } else if (jsonData is! List && jsonData is! String) {
        throw StateError('The server returned an invalid favourite response');
      }

      // Gallery search suppresses individual parsing failures and may stop on an
      // entirely hidden page. Destructive sync needs a complete snapshot instead.
      final posts = await handler.parseListFromResponse(response);
      checkCancelled();
      if (posts.isEmpty) {
        final jsonPosts = jsonData is Map ? jsonData['post'] : jsonData;
        if (jsonPosts is List) {
          if (jsonPosts.isNotEmpty) {
            throw StateError('The server did not return a complete, readable favourite list');
          }
        } else if (data is String) {
          final isHtmlSource = booru.type == BooruType.R34US || booru.type == BooruType.R34Hentai;
          if (!requireComplete && isHtmlSource) {
            final body = data.toLowerCase();
            if (!body.contains('<html') || !body.contains('</html>')) {
              throw StateError('The server returned an invalid favourite response');
            }
            return entries;
          }
          // HTML login/challenge/error pages also produce zero posts in the
          // permissive gallery parsers. Only an empty API list is authoritative.
          final document = XmlDocument.parse(data);
          final root = document.rootElement;
          if (root.name.local != 'posts' ||
              root.getAttribute('success') == 'false' ||
              root.getAttribute('error') != null ||
              root.childElements.isNotEmpty ||
              root.innerText.trim().isNotEmpty) {
            throw StateError('The server did not return a complete, readable favourite list');
          }
        }
        return entries;
      }
      final pageDigest = sha256.convert(utf8.encode(response.data.toString())).toString();
      if (!seenPages.add(pageDigest)) {
        throw StateError('Favourite pagination stopped making progress at page $page');
      }
      final before = seenIds.length;
      final pageEntries = onPage == null ? entries : <ServerFavoriteEntry>[];
      int skippedItems = 0;
      for (int index = 0; index < posts.length; index++) {
        checkCancelled();
        itemTagTypes.clear();
        BooruItem? item;
        try {
          item = await handler.parseItemFromResponse(posts[index], index);
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) rethrow;
          if (requireComplete) rethrow;
          checkCancelled();
        }
        if (item == null) {
          if (requireComplete) {
            throw StateError('A favourite on page $page could not be loaded');
          }
          skippedItems++;
          onStatus?.call('Skipping an unavailable favourite on page $page');
          continue;
        }

        final id = serverIdFromItem(item);
        if (id == null || id.isEmpty || id == 'null') {
          if (requireComplete) {
            throw StateError('A favourite on page $page has no server ID');
          }
          skippedItems++;
          onStatus?.call('Skipping a favourite without a server ID on page $page');
          continue;
        }
        if (!seenIds.add(id)) continue;
        for (final tag in item.tagsList) {
          tag.tagType = itemTagTypes[tag.fullString] ?? tag.tagType;
        }
        item.serverId = id;
        item.isFavourite.value = true;
        pageEntries.add(ServerFavoriteEntry(serverId: id, item: item));
      }
      checkCancelled();
      if (seenIds.length == before && skippedItems == 0) {
        throw StateError('Favourite pagination stopped making progress at page $page');
      }
      if (onPage != null && !await onPage(pageEntries)) return entries;

      page++;
    }

    if (!requireComplete && allowsPartialPageLimit) return entries;
    throw StateError('Favourite pagination limit reached before completion');
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
    return ServerFavoriteMutationResult.failure('Unsupported server ID for this action: $serverId');
  }

  bool _isSuccessStatus(int? statusCode) => statusCode != null && statusCode >= 200 && statusCode < 300;

  ServerFavoriteMutationResult _httpResult(
    Response response, {
    String successMessage = 'OK',
    bool Function(Response response)? isSuccess,
    String Function(Response response)? failureMessage,
    String? accountIdentity,
  }) {
    final success = isSuccess?.call(response) ?? _isSuccessStatus(response.statusCode);
    if (success) {
      return ServerFavoriteMutationResult.success(
        message: successMessage,
        statusCode: response.statusCode,
        accountIdentity:
            accountIdentity ??
            (capabilities.canEnumerateAll
                ? null
                : _cookieAccountIdentity(response.requestOptions.headers['Cookie']?.toString() ?? '')),
      );
    }

    return ServerFavoriteMutationResult.failure(
      failureMessage?.call(response) ?? 'HTTP ${response.statusCode}: ${response.statusMessage ?? 'request failed'}',
      statusCode: response.statusCode,
    );
  }

  ServerFavoriteMutationResult _exceptionResult(Object error) {
    if (error is DioException) {
      if (error.error case final _FavoriteLoginRequired loginError) {
        return ServerFavoriteMutationResult.failure(loginError.message, canRetryAfterWebview: true);
      }
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
    return loc.serverFavouritesSync.cloudflareHelp(site: siteName);
  }

  String loginCookiesRequiredMessage(String siteName) {
    return loc.serverFavouritesSync.cookiesRequired(site: siteName);
  }

  Future<String> storedCookieHeader() async {
    if (booru.baseURL?.isNotEmpty != true) return '';
    return Tools.getCookies(booru.baseURL!);
  }

  bool hasCookieNames(String cookieHeader, Iterable<String> names) {
    final lower = cookieHeader.toLowerCase();
    return names.every((name) => RegExp('(^|;)\\s*${RegExp.escape(name.toLowerCase())}=[^;\\s]+').hasMatch(lower));
  }

  bool hasAccountCookies(String cookies) {
    if (!hasCookieNames(cookies, const ['user_id', 'pass_hash'])) return false;
    final expectedUser = booru.userID?.trim() ?? '';
    if (!RegExp(r'^\d+$').hasMatch(expectedUser)) return false;
    final cookieUser = RegExp(r'(^|;)\s*user_id=([^;]+)').firstMatch(cookies)?.group(2)?.trim();
    return cookieUser == expectedUser;
  }

  Dio favoriteCookieInterceptor(Dio client) {
    client = DioNetwork.captchaInterceptor(DioNetwork.cookieInterceptor(client));
    client.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cookies = options.headers['Cookie']?.toString() ?? '';
          final cookieUser = RegExp(r'(^|;)\s*user_id=([^;]+)').firstMatch(cookies)?.group(2)?.trim();
          final expectedUser = booru.userID?.trim() ?? '';
          final hasExpectedUser = RegExp(r'^\d+$').hasMatch(expectedUser);
          if (!hasCookieNames(cookies, const ['user_id', 'pass_hash']) ||
              (hasExpectedUser && cookieUser != expectedUser)) {
            return handler.reject(
              DioException(
                requestOptions: options,
                error: _FavoriteLoginRequired(loc.serverFavouritesSync.cookiesRequired(site: displayName)),
                message: loc.serverFavouritesSync.cookiesRequired(site: displayName),
              ),
            );
          }
          handler.next(options);
        },
      ),
    );
    return client;
  }

  bool looksCloudflareBlocked(Response response) {
    final body = response.data.toString().toLowerCase();
    return response.statusCode == 403 ||
        body.contains('cf-challenge') ||
        body.contains('cf_clearance') ||
        body.contains('just a moment') ||
        body.contains('checking your browser');
  }

  bool isFavoritesViewRedirect(Response response) {
    if (response.statusCode != 302 && response.statusCode != 303) return false;
    final location = response.headers.value('location');
    if (location == null) return false;
    final target = response.requestOptions.uri.resolve(location);
    return ownsPostUrl(target.toString()) &&
        target.path.endsWith('/index.php') &&
        target.queryParameters['page'] == 'favorites' &&
        target.queryParameters['s'] == 'view';
  }

  Future<void> tryGelbooruStyleLogin({
    required String login,
    required String password,
    String? baseUrl,
  }) async {
    final loginBaseUrl = baseUrl ?? booru.baseURL;
    if (loginBaseUrl?.isNotEmpty != true || login.isEmpty || password.isEmpty) return;

    try {
      await DioNetwork.post(
        '$loginBaseUrl/index.php',
        queryParameters: {
          'page': 'account',
          's': 'login',
          'code': '00',
        },
        data: {
          'user': login,
          'pass': password,
          'submit': 'Log in',
        },
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (_) => true,
        ),
        customInterceptor: (dio) => DioNetwork.captchaInterceptor(DioNetwork.cookieInterceptor(dio)),
      );
    } catch (_) {
      // Best effort only. Manual webview cookies may still be valid.
    }
  }
}

typedef ValueChanged<T> = void Function(T value);

class _FavoriteLoginRequired implements Exception {
  const _FavoriteLoginRequired(this.message);

  final String message;
}

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
    canEnumerateAll: _hasAuth,
    canCheckSingle: _hasAuth,
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
      return _httpResult(response, successMessage: 'Server favourite added');
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final response = await DioNetwork.delete(
        '${booru.baseURL}/favorites/${Uri.encodeComponent(serverId)}.json',
        queryParameters: _authQuery,
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      return _httpResult(response, successMessage: 'Server favourite removed');
    } catch (e) {
      return _exceptionResult(e);
    }
  }
}

class GelbooruServerFavoriteAdapter extends ServerFavoriteAdapter {
  GelbooruServerFavoriteAdapter(super.booru);

  bool get _hasAuthPassword => booru.authPassword?.isNotEmpty == true;
  String? get _loginPassword => _hasAuthPassword ? booru.authPassword : null;
  bool get _isOfficialGelbooru {
    final host = Uri.tryParse(booru.baseURL ?? '')?.host.toLowerCase();
    return host == 'gelbooru.com' || host == 'www.gelbooru.com';
  }

  bool get _canWrite => _isOfficialGelbooru && booru.baseURL?.isNotEmpty == true;
  bool get _hasApiCredentials =>
      RegExp(r'^[0-9]+$').hasMatch(booru.userID?.trim() ?? '') && booru.apiKey?.trim().isNotEmpty == true;

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: _isOfficialGelbooru && _hasApiCredentials,
    canAdd: _canWrite,
    canRemove: _canWrite,
    requiresAuth: true,
    isDestructiveMirrorAllowed: false,
    canCheckSingle: false,
    unsupportedReason: _canWrite ? null : loc.serverFavouritesSync.missingLoginCookies,
    listingHint: loc.serverFavouritesSync.gelbooruImportLimit,
  );

  @override
  String? unavailableModeReason(ServerFavoriteSyncMode mode) {
    if (mode == ServerFavoriteSyncMode.importServer && !_hasApiCredentials) {
      return loc.serverFavouritesSync.missingUserIdApiKey;
    }
    return super.unavailableModeReason(mode);
  }

  @override
  ({BooruHandler booruHandler, int startingPage}) createFavoriteReader() =>
      (booruHandler: _GelbooruFavoriteReader(booru, 100), startingPage: -1);

  @override
  int get favoritePageLimit => 250;

  @override
  bool get allowsPartialPageLimit => true;

  @override
  String favoriteQuery() => 'fav:${booru.userID!.trim()}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  bool _hostPreflightComplete = false;

  Future<ServerFavoriteMutationResult?> _preflightHost(String action) async {
    if (_hostPreflightComplete) return null;
    try {
      final response = await DioNetwork.get(
        booru.baseURL!,
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
        customInterceptor: DioNetwork.captchaInterceptor,
      );
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage(action, 'Gelbooru'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      if (!_isSuccessStatus(response.statusCode)) {
        return ServerFavoriteMutationResult.failure(
          'Gelbooru: the server did not confirm the action (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      _hostPreflightComplete = true;
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
      await _tryLogin();
      final authFailure = await _validateLoginCookies();
      if (authFailure != null) return authFailure;

      final response = await DioNetwork.get(
        '${booru.baseURL}/public/addfav.php',
        queryParameters: {'id': serverId},
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true),
        customInterceptor: favoriteCookieInterceptor,
      );
      final code = response.data.toString().trim();
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('add favourite', 'Gelbooru'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      if (response.statusCode == 200 && code == '2') {
        return ServerFavoriteMutationResult.failure(
          loginCookiesRequiredMessage('Gelbooru'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: 'Server favourite added',
        isSuccess: (response) => response.statusCode == 200 && (code == '1' || code == '3'),
        failureMessage: (_) => 'Gelbooru: the server did not confirm the action (HTTP ${response.statusCode})',
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
      await _tryLogin();
      final authFailure = await _validateLoginCookies();
      if (authFailure != null) return authFailure;

      final response = await DioNetwork.get(
        '${booru.baseURL}/index.php',
        queryParameters: {
          'page': 'favorites',
          's': 'delete',
          'id': serverId,
        },
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          followRedirects: false,
        ),
        customInterceptor: favoriteCookieInterceptor,
      );
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('remove favourite', 'Gelbooru'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      final body = response.data.toString().toLowerCase();
      final looksAuthFailed =
          body.contains('login') ||
          body.contains('sign in') ||
          body.contains('access denied') ||
          body.contains('not authorized');
      if (looksAuthFailed) {
        return ServerFavoriteMutationResult.failure(
          loginCookiesRequiredMessage('Gelbooru'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: 'Server favourite removed',
        isSuccess: isFavoritesViewRedirect,
        failureMessage: (response) => looksAuthFailed
            ? loc.serverFavouritesSync.cookiesRequired(site: 'Gelbooru')
            : 'Gelbooru: the server did not confirm the action (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  Future<void> _tryLogin() async {
    if (hasAccountCookies(await storedCookieHeader())) return;
    final login = booru.authLogin?.isNotEmpty == true ? booru.authLogin : booru.userID;
    final password = _loginPassword;
    if (login?.isNotEmpty != true || password?.isNotEmpty != true) return;
    await tryGelbooruStyleLogin(login: login!, password: password!);
  }

  Future<ServerFavoriteMutationResult?> _validateLoginCookies() async {
    final cookies = await storedCookieHeader();
    if (hasCookieNames(cookies, const ['user_id', 'pass_hash'])) return null;
    return ServerFavoriteMutationResult.failure(
      loginCookiesRequiredMessage('Gelbooru'),
      canRetryAfterWebview: true,
    );
  }
}

// Favourite reads use API credentials only. Website cookies are for writes.
class _GelbooruFavoriteReader extends GelbooruHandler {
  _GelbooruFavoriteReader(super.booru, super.limit);

  @override
  bool get hasSignInSupport => false;

  @override
  String makeURL(String tags) => Uri.parse('${booru.baseURL!.replaceFirst(RegExp(r'/+$'), '')}/index.php')
      .replace(
        queryParameters: {
          'page': 'dapi',
          's': 'post',
          'q': 'index',
          'json': '1',
          'limit': '$limit',
          'pid': '$pageNum',
          'tags': Uri.decodeComponent(tags),
          'user_id': booru.userID!.trim(),
          'api_key': booru.apiKey!.trim(),
        },
      )
      .toString();

  @override
  Future<Response<dynamic>> fetchSearch(
    Uri uri,
    String input, {
    bool withCaptchaCheck = true,
    Map<String, dynamic>? queryParams,
  }) async {
    final response = await DioNetwork.get(
      uri.toString(),
      options: Options(responseType: ResponseType.json, validateStatus: (_) => true),
      skipLogging: true,
    );
    final data = response.data;
    if (data is Map && data['post'] is List && (data['post'] as List).length > limit) {
      throw StateError('The server returned more favourites than requested');
    }
    if (response.statusCode == 200 && data is Map && !data.containsKey('post')) {
      final attributes = data['@attributes'];
      if (attributes is Map && (attributes['count'] == 0 || attributes['count'] == '0')) {
        // Only the observed count-zero envelope may omit the post list.
        // Preserve other fields so the common validator still rejects errors.
        response.data = {...data, 'post': <dynamic>[]};
      }
    }
    return response;
  }
}

class Rule34XxxServerFavoriteAdapter extends ServerFavoriteAdapter {
  Rule34XxxServerFavoriteAdapter(super.booru);

  bool get _hasBaseUrl => booru.baseURL?.isNotEmpty == true;
  String? get _loginPassword => booru.authPassword?.isNotEmpty == true ? booru.authPassword : null;
  String get _siteBaseUrl {
    final uri = Uri.tryParse(booru.baseURL ?? '');
    if (uri == null || uri.host.isEmpty) return booru.baseURL ?? '';
    if (uri.host.toLowerCase() == 'api.rule34.xxx') {
      return uri.replace(host: 'rule34.xxx', path: '', query: '', fragment: '').toString();
    }
    return uri.replace(path: '', query: '', fragment: '').toString();
  }

  @override
  Future<String> storedCookieHeader() => Tools.getCookies(_siteBaseUrl);

  @override
  List<String> get localHosts => [host, 'rule34.xxx', 'api.rule34.xxx'];

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: false,
    canAdd: _hasBaseUrl,
    canRemove: _hasBaseUrl,
    requiresAuth: true,
    isDestructiveMirrorAllowed: _hasBaseUrl,
    canCheckSingle: false,
    unsupportedReason: _hasBaseUrl ? null : loc.serverFavouritesSync.missingLoginCookies,
  );

  @override
  String favoriteQuery() => 'fav:${booru.userID}';

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  @override
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      await _tryLogin();
      final authFailure = await _validateLoginCookies();
      if (authFailure != null) return authFailure;

      final response = await DioNetwork.get(
        '$_siteBaseUrl/public/addfav.php',
        queryParameters: {'id': serverId},
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true, followRedirects: false),
        customInterceptor: favoriteCookieInterceptor,
      );
      final body = response.data.toString().trim();
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('add favourite', 'Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      if (response.statusCode == 200 && body == '2') {
        return ServerFavoriteMutationResult.failure(
          loginCookiesRequiredMessage('Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: 'Server favourite added',
        isSuccess: (_) => response.statusCode == 200 && (body == '1' || body == '3'),
        failureMessage: (_) => 'Rule34.xxx: the server did not confirm the action (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      await _tryLogin();
      final authFailure = await _validateLoginCookies();
      if (authFailure != null) return authFailure;

      final response = await DioNetwork.get(
        '$_siteBaseUrl/index.php',
        queryParameters: {
          'page': 'favorites',
          's': 'delete',
          'id': serverId,
          'return_pid': '0',
        },
        options: Options(responseType: ResponseType.plain, validateStatus: (_) => true, followRedirects: false),
        customInterceptor: favoriteCookieInterceptor,
      );
      final body = response.data.toString().toLowerCase();
      final looksAuthFailed =
          body.contains('login') ||
          body.contains('sign in') ||
          body.contains('access denied') ||
          body.contains('not authorized');
      if (looksCloudflareBlocked(response)) {
        return ServerFavoriteMutationResult.failure(
          cloudflareBlockedMessage('remove favourite', 'Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      if (looksAuthFailed) {
        return ServerFavoriteMutationResult.failure(
          loginCookiesRequiredMessage('Rule34.xxx'),
          statusCode: response.statusCode,
          canRetryAfterWebview: true,
        );
      }
      return _httpResult(
        response,
        successMessage: 'Server favourite removed',
        isSuccess: isFavoritesViewRedirect,
        failureMessage: (response) {
          return looksAuthFailed
              ? loc.serverFavouritesSync.cookiesRequired(site: 'Rule34.xxx')
              : 'Rule34.xxx: the server did not confirm the action (HTTP ${response.statusCode})';
        },
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  Future<void> _tryLogin() async {
    if (hasAccountCookies(await Tools.getCookies(_siteBaseUrl))) return;
    final login = booru.authLogin;
    final password = _loginPassword;
    if (login?.isNotEmpty != true || password?.isNotEmpty != true) return;
    await tryGelbooruStyleLogin(login: login!, password: password!, baseUrl: _siteBaseUrl);
  }

  Future<ServerFavoriteMutationResult?> _validateLoginCookies() async {
    final cookies = await Tools.getCookies(_siteBaseUrl);
    if (hasCookieNames(cookies, const ['user_id', 'pass_hash'])) return null;
    return ServerFavoriteMutationResult.failure(
      loginCookiesRequiredMessage('Rule34.xxx'),
      canRetryAfterWebview: true,
    );
  }
}

class SankakuServerFavoriteAdapter extends ServerFavoriteAdapter {
  SankakuServerFavoriteAdapter(super.booru);

  SankakuHandler? _authenticatedHandler;
  String? _authenticatedIdentity;

  bool get _isIdol => booru.type?.isIdolSankaku == true;
  bool get _hasAuth => booru.userID?.isNotEmpty == true && booru.apiKey?.isNotEmpty == true;

  @override
  String? get serviceIdentity => _isIdol ? super.serviceIdentity : SankakuHandler.apiBaseUrlFor(booru.baseURL ?? '');

  @override
  Future<String> exportSessionIdentity() async => requestIdentity;

  @override
  List<String> get localHosts => _isIdol
      ? [host, 'idol.sankakucomplex.com', 'idolcomplex.com']
      : [
          host,
          ...SankakuHandler.knownUrls,
        ];

  @override
  ServerFavoriteCapabilities get capabilities => ServerFavoriteCapabilities(
    canFetch: false,
    canAdd: _hasAuth && !_isIdol,
    canRemove: _hasAuth && !_isIdol,
    requiresAuth: true,
    isDestructiveMirrorAllowed: false,
    canCheckSingle: _hasAuth && !_isIdol,
    listingHint: _isIdol ? null : loc.serverFavouritesSync.sankakuListingUnavailable,
    unsupportedReason: !_hasAuth
        ? loc.serverFavouritesSync.missingLoginPassword
        : (_isIdol
              ? loc.serverFavouritesSync.idolSankakuWriteUnsupported
              : loc.serverFavouritesSync.sankakuListingUnavailable),
  );

  @override
  String favoriteQuery() {
    final name = _authenticatedHandler?.authenticatedUserName;
    if (name == null || _authenticatedIdentity != requestIdentity) {
      throw StateError('An authenticated account name is required for favourites search');
    }
    return 'fav:$name';
  }

  @override
  String? serverIdFromUrl(String url) => ServerIdParser.fromUrl(url);

  @override
  bool canMutateServerId(String serverId) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(serverId);

  Future<SankakuHandler?> _signedInHandler() async {
    if (!_hasAuth || _isIdol) return null;
    if (_authenticatedIdentity == requestIdentity &&
        _authenticatedHandler != null &&
        await _authenticatedHandler!.isSignedIn()) {
      return _authenticatedHandler;
    }
    _authenticatedHandler = null;
    _authenticatedIdentity = null;
    final handler = SankakuHandler(booru, 100);
    if (!await handler.signIn() || handler.authenticatedUserId == null || handler.authenticatedUserName == null) {
      return null;
    }
    _authenticatedHandler = handler;
    _authenticatedIdentity = requestIdentity;
    return handler;
  }

  @override
  Future<bool> checkFavorite(String serverId) async {
    if (!capabilities.canCheckSingle || !canMutateServerId(serverId)) {
      throw StateError('Checking a single server favourite is unsupported');
    }
    final handler = await _signedInHandler();
    if (handler == null) throw StateError('Sign-in failed');
    final response = await DioNetwork.get(
      '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}',
      headers: handler.getHeaders(),
      skipLogging: true,
      options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
    );
    if (response.statusCode == 401 || response.statusCode == 403) _authenticatedHandler = null;
    final data = response.data;
    if (response.statusCode != 200 ||
        data is! Map ||
        data['id']?.toString() != serverId ||
        data['is_favorited'] is! bool ||
        (data.containsKey('success') && data['success'] != true) ||
        data['error'] != null ||
        data['errors'] != null) {
      throw StateError('Could not verify server favourite status (HTTP ${response.statusCode})');
    }
    return data['is_favorited'] as bool;
  }

  bool _confirmedMutation(Response response, String serverId) {
    final data = response.data;
    return response.statusCode == 200 &&
        data is Map &&
        data['success'] == true &&
        data['post_id']?.toString() == serverId &&
        data['error'] == null &&
        data['errors'] == null;
  }

  @override
  Future<bool> addFavorite(String serverId) async => (await addFavoriteResult(serverId)).success;

  @override
  Future<bool> removeFavorite(String serverId) async => (await removeFavoriteResult(serverId)).success;

  @override
  Future<ServerFavoriteMutationResult> addFavoriteResult(String serverId) async {
    if (!capabilities.canAdd) return ServerFavoriteMutationResult.unsupported;
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final handler = await _signedInHandler();
      if (handler == null) return ServerFavoriteMutationResult.failure('Sign-in failed');
      final response = await DioNetwork.post(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        headers: handler.getHeaders(),
        skipLogging: true,
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      if (response.statusCode == 401 || response.statusCode == 403) _authenticatedHandler = null;
      return _httpResult(
        response,
        successMessage: 'Server favourite added',
        isSuccess: (response) => _confirmedMutation(response, serverId),
        failureMessage: (_) => 'Sankaku did not confirm the favourite addition (HTTP ${response.statusCode})',
        accountIdentity: requestIdentity,
      );
    } catch (e) {
      return _exceptionResult(e);
    }
  }

  @override
  Future<ServerFavoriteMutationResult> removeFavoriteResult(String serverId) async {
    if (!capabilities.canRemove) return ServerFavoriteMutationResult.unsupported;
    if (!canMutateServerId(serverId)) return invalidServerIdResult(serverId);

    try {
      final handler = await _signedInHandler();
      if (handler == null) return ServerFavoriteMutationResult.failure('Sign-in failed');
      final response = await DioNetwork.delete(
        '${handler.baseUrl}/posts/${Uri.encodeComponent(serverId)}/favorite',
        headers: handler.getHeaders(),
        skipLogging: true,
        options: DioNetwork.defaultOptions.copyWith(validateStatus: (_) => true),
      );
      if (response.statusCode == 401 || response.statusCode == 403) _authenticatedHandler = null;
      return _httpResult(
        response,
        successMessage: 'Server favourite removed',
        isSuccess: (response) => _confirmedMutation(response, serverId),
        failureMessage: (_) => 'Sankaku did not confirm the favourite removal (HTTP ${response.statusCode})',
        accountIdentity: requestIdentity,
      );
    } catch (e) {
      return _exceptionResult(e);
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

  ServerFavoriteAdapter? adapterFor(Booru source) {
    // Keep an operation's credentials stable across asynchronous login and writes.
    final booru = Booru.fromMap(source.toJson());
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
    return boorus.map(adapterFor).whereType<ServerFavoriteAdapter>().toList();
  }
}
