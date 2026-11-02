import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class _WindowsCookie extends Cookie {
  _WindowsCookie(Map<dynamic, dynamic> data)
    : partitionKey = data['partitionKey'],
      partitionKeyOpaque = data['partitionKeyOpaque'] == true,
      super(
        name: data['name'] as String,
        value: data['value'] as String,
        domain: data['domain'] as String?,
        path: data['path'] as String?,
        isSecure: data['secure'] as bool?,
        isHttpOnly: data['httpOnly'] as bool?,
        expiresDate: (data['expires'] as num?) != null && (data['expires'] as num) > 0
            ? ((data['expires'] as num) * 1000).round()
            : null,
      );

  // Preserve the protocol value, including older WebView2 string keys.
  // The plugin's Cookie model does not expose partition information.
  final dynamic partitionKey;
  final bool partitionKeyOpaque;

  String get partitionIdentity {
    final key = partitionKey;
    if (key is Map) return '${key['topLevelSite']}\n${key['hasCrossSiteAncestor']}';
    return '$key\n$partitionKeyOpaque';
  }
}

class WebviewCookies {
  static CookieManager get _manager => CookieManager.instance(webViewEnvironment: webViewEnvironment);
  static int _revision = 0;
  static final Map<String, Set<String>> _knownPaths = {};

  static void remember(Uri uri) {
    if (!io.Platform.isAndroid) return;
    final paths = _knownPaths.putIfAbsent(uri.host, () => {});
    final path = uri.path.isEmpty ? '/' : uri.path;
    paths.remove(path);
    paths.add(path);
    if (paths.length > 64) paths.remove(paths.first);
  }

  static bool _domainMatches(String host, String domain) {
    final normalized = domain.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    return host == normalized || host.endsWith('.$normalized');
  }

  static String _identity(Cookie cookie) =>
      '${cookie.name}\n${cookie.domain}\n${cookie.path}\n'
      '${cookie is _WindowsCookie ? cookie.partitionIdentity : 'null\nfalse'}';

  static bool _partitionApplies(_WindowsCookie cookie, Uri uri) {
    if (cookie.partitionKeyOpaque) return false;
    final key = cookie.partitionKey;
    if (key == null) return true;
    final String? topLevelSite;
    if (key is Map) {
      if (key['hasCrossSiteAncestor'] == true) return false;
      topLevelSite = key['topLevelSite'] as String?;
    } else {
      topLevelSite = key is String ? key : null;
    }
    final site = topLevelSite == null ? null : Uri.tryParse(topLevelSite);
    // Chromium supplies the schemeful registrable site, so subdomains share
    // this partition. Never include cookies partitioned under another site.
    return site != null && site.host.isNotEmpty && site.scheme == uri.scheme && _domainMatches(uri.host, site.host);
  }

  static bool _applies(Cookie cookie, Uri uri) {
    final domain = cookie.domain;
    if (domain != null &&
        !(domain.startsWith('.') ? _domainMatches(uri.host, domain) : uri.host == domain.toLowerCase())) {
      return false;
    }
    if (cookie.isSecure == true && uri.scheme != 'https') return false;
    final path = cookie.path ?? '/';
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == path || requestPath.startsWith(path.endsWith('/') ? path : '$path/');
  }

  static List<Cookie> cachedForRequest(Uri uri) =>
      (globalWindowsCookies[uri.host] ?? [])
          .where(
            (cookie) =>
                _applies(cookie, uri) &&
                (cookie.expiresDate == null || cookie.expiresDate! > DateTime.now().millisecondsSinceEpoch),
          )
          .toList()
        ..sort((a, b) => (b.path?.length ?? 1).compareTo(a.path?.length ?? 1));

  static Future<List<Cookie>> read(Uri uri, {InAppWebViewController? controller}) async {
    remember(uri);
    final revision = _revision;
    final cookies = io.Platform.isWindows
        ? await _windowsCookies(controller, url: uri)
        : await _manager.getCookies(url: WebUri.uri(uri), webViewController: controller);
    if (io.Platform.isWindows && revision == _revision) {
      final cached = globalWindowsCookies.putIfAbsent(uri.host, () => []);
      cached.removeWhere((cookie) => _applies(cookie, uri));
      cached.addAll(cookies);
    }
    return cookies;
  }

  static Future<List<Cookie>> forSite(Uri uri, {InAppWebViewController? controller}) async {
    if (io.Platform.isIOS || io.Platform.isMacOS || io.Platform.isWindows) {
      final all = io.Platform.isWindows ? await _windowsCookies(controller) : await _manager.getAllCookies();
      final cookies = all
          .where(
            (cookie) =>
                cookie.domain != null &&
                (cookie.domain!.startsWith('.')
                    ? _domainMatches(uri.host, cookie.domain!)
                    : uri.host == cookie.domain!.toLowerCase()),
          )
          .toList();
      // The cleaner includes all partitions. Only read(), which selects
      // cookies applicable to the request's site and URL, fills the cache.
      return cookies;
    }
    final cookies = <String, Cookie>{};
    final urls = {
      uri,
      uri.replace(path: '/', query: '', fragment: ''),
      for (final path in _knownPaths[uri.host] ?? <String>{}) uri.replace(path: path, query: '', fragment: ''),
    };
    for (final url in urls) {
      for (final cookie in await read(url, controller: controller)) {
        cookies[_identity(cookie)] = cookie;
      }
    }
    return cookies.values.toList();
  }

  static Future<T> _withWindowsController<T>(
    InAppWebViewController? controller,
    Future<T> Function(InAppWebViewController) action,
  ) async {
    HeadlessInAppWebView? temporary;
    Future<void>? startup;
    var started = false;
    try {
      if (controller == null) {
        final created = Completer<InAppWebViewController>();
        temporary = HeadlessInAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialUrlRequest: URLRequest(url: WebUri('about:blank')),
          onWebViewCreated: created.complete,
        );
        startup = temporary.run();
        await startup.timeout(const Duration(seconds: 5));
        started = true;
        controller = await created.future.timeout(const Duration(seconds: 5));
      }
      return await action(controller).timeout(const Duration(seconds: 5));
    } finally {
      final instance = temporary;
      if (instance != null) {
        // Dispose a native WebView whose creation completed after timeout.
        if (startup != null && !started) {
          unawaited(startup.then((_) => instance.dispose()).catchError((Object _) {}));
        }
        await instance.dispose().timeout(const Duration(seconds: 1));
      }
    }
  }

  static Future<List<Cookie>> _windowsCookies(InAppWebViewController? controller, {Uri? url}) =>
      _withWindowsController(controller, (active) async {
        // Network.getCookies uses the controller's top-level partition even
        // when given explicit URLs. A temporary about:blank controller would
        // omit the site's partitioned clearance and erase it from our cache.
        final usePageContext = controller != null && url != null;
        final data = await active.callDevToolsProtocolMethod(
          methodName: usePageContext ? 'Network.getCookies' : 'Storage.getCookies',
          parameters: usePageContext
              ? {
                  'urls': [url.toString()],
                }
              : null,
        );
        if (data is! Map || data['cookies'] is! List) throw StateError('Unable to enumerate site cookies');
        final cookies = (data['cookies'] as List).map((dynamic value) => _WindowsCookie(value as Map));
        return url == null || usePageContext
            ? cookies.toList()
            : cookies.where((cookie) => _applies(cookie, url) && _partitionApplies(cookie, url)).toList();
      });

  static void _invalidate(Uri uri, Cookie cookie) {
    for (final entry in globalWindowsCookies.entries) {
      entry.value.removeWhere((cached) {
        if (cached.name != cookie.name) return false;
        if (cached is _WindowsCookie && cookie is _WindowsCookie && _identity(cached) != _identity(cookie)) {
          return false;
        }
        if (cookie.domain == null) return entry.key == uri.host;
        return _domainMatches(entry.key, cookie.domain!) &&
            (cached.domain == null || cached.domain == cookie.domain) &&
            (cached.path == null || cached.path == cookie.path);
      });
    }
  }

  static Future<void> _delete(Uri uri, Cookie cookie, InAppWebViewController? controller) async {
    if (io.Platform.isWindows) {
      if (cookie is! _WindowsCookie || cookie.partitionKeyOpaque) {
        throw StateError('Cookie partition information is unavailable');
      }
      await _withWindowsController(controller, (active) async {
        // The plugin omits partitionKey, which deletes only unpartitioned
        // cookies. Pass the exact key returned by Storage.getCookies.
        await active.callDevToolsProtocolMethod(
          methodName: 'Network.deleteCookies',
          parameters: {
            'name': cookie.name,
            'domain': cookie.domain,
            'path': cookie.path ?? '/',
            if (cookie.partitionKey != null) 'partitionKey': cookie.partitionKey,
          },
        );
      });
      _invalidate(uri, cookie);
      return;
    }
    // Older Android WebViews expose only name/value. Expire the possible
    // domain and path scopes instead of assuming a host-only root cookie.
    final domains = <String?>{if (cookie.name.startsWith('__Host-')) null else cookie.domain};
    final paths = <String>{cookie.path ?? '/'};
    if (io.Platform.isAndroid && cookie.domain == null && !cookie.name.startsWith('__Host-')) {
      final labels = uri.host.split('.');
      for (var i = 0; i < labels.length - 1; i++) {
        domains.add(labels.skip(i).join('.'));
      }
    }
    if (io.Platform.isAndroid && cookie.path == null && !cookie.name.startsWith('__Host-')) {
      for (final path in {uri.path, ...?_knownPaths[uri.host]}) {
        for (var i = 1; i <= path.length; i++) {
          if (i == path.length || path[i] == '/') {
            paths.add(path.substring(0, i));
            paths.add('${path.substring(0, i)}/');
          }
        }
      }
    }
    for (final domain in domains) {
      for (final path in paths) {
        if (io.Platform.isAndroid) {
          // The plugin's deleteCookie omits Secure, which cannot expire
          // __Secure-/__Host- cookies. Use the native set-cookie API instead.
          await _manager.setCookie(
            url: WebUri.uri(uri),
            name: cookie.name,
            value: '',
            domain: domain,
            path: path,
            maxAge: -1,
            isSecure: uri.scheme == 'https',
            isHttpOnly: true,
            webViewController: controller,
          );
        } else {
          await _manager.deleteCookie(
            url: WebUri.uri(uri),
            name: cookie.name,
            domain: domain,
            path: path,
            webViewController: controller,
          );
        }
      }
    }
    _invalidate(uri, cookie);
  }

  static Future<bool> delete(Uri uri, Cookie cookie, {InAppWebViewController? controller}) async {
    if (io.Platform.isWindows && controller == null) {
      return _withWindowsController(null, (active) => delete(uri, cookie, controller: active));
    }
    _revision++;
    try {
      await _delete(uri, cookie, controller);
      final remaining = await forSite(uri, controller: controller);
      return !remaining.any((c) => _identity(c) == _identity(cookie));
    } finally {
      _revision++;
    }
  }

  static Future<bool> clearSite(Uri uri, {String? name, InAppWebViewController? controller}) async {
    if (io.Platform.isWindows && controller == null) {
      return _withWindowsController(null, (active) => clearSite(uri, name: name, controller: active));
    }
    _revision++;
    try {
      final cookies = name == null || io.Platform.isWindows
          ? await forSite(uri, controller: controller)
          : await read(uri, controller: controller);
      for (final cookie in cookies) {
        if (name == null || cookie.name == name) await _delete(uri, cookie, controller);
      }
      if (name == null) {
        globalWindowsCookies.remove(uri.host);
      } else {
        globalWindowsCookies[uri.host]?.removeWhere((cookie) => cookie.name == name);
      }
      final remaining = name == null || io.Platform.isWindows
          ? await forSite(uri, controller: controller)
          : await read(uri, controller: controller);
      return !remaining.any((cookie) => name == null || cookie.name == name);
    } finally {
      _revision++;
    }
  }

  static Future<bool> clearAll() async {
    _revision++;
    try {
      final result = await _manager.deleteAllCookies();
      // Android's callback means "any cookies removed", so false is also
      // returned for an already-empty store after a successful operation.
      final success = result || io.Platform.isAndroid;
      if (success) globalWindowsCookies.clear();
      return success;
    } finally {
      _revision++;
    }
  }
}
