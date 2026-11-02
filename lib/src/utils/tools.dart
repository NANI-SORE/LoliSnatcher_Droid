import 'dart:async';
import 'dart:io';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/cloudflare_refresh.dart';
import 'package:lolisnatcher/src/services/webview_cookies.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/dialogs/timed_leave_dialog.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class Tools {
  // code taken from: https://gist.github.com/zzpmaster/ec51afdbbfa5b2bf6ced13374ff891d9
  static String formatBytes(
    int bytes,
    int decimals, {
    bool withSpace = true,
    bool withTrailingZeroes = true,
  }) {
    if (bytes <= 0) {
      return '0 B';
    }
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (log(bytes) / log(1024)).floor();

    final num = bytes / pow(1024, i);
    return '${num.toStringAsFixed(withTrailingZeroes ? decimals : (num.truncateToDouble() == num ? 0 : decimals))}${withSpace ? ' ' : ''}${suffixes[i]}';
  }

  static int parseFormattedBytes(String bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

    if (bytes.isEmpty) {
      return 0;
    }
    // parse bytes (string of format: 1.1GB)
    String suffixStr = bytes.substring(bytes.length - 2);
    if (!suffixes.contains(suffixStr)) {
      suffixStr = bytes.substring(bytes.length - 1);
    }
    if (!suffixes.contains(suffixStr)) {
      return 0;
    }

    final String bytesStr = bytes.substring(0, bytes.length - suffixStr.length);
    final int suffixIndex = suffixes.indexOf(suffixStr);

    return ((double.tryParse(bytesStr) ?? 0) * pow(1024, suffixIndex)).round();
  }

  static int gibibytesToBytes(num value) => (value * pow(1024, 3)).round();

  static int boolToInt(bool boolean) {
    return boolean ? 1 : 0;
  }

  static bool intToBool(int boolean) {
    return boolean != 0;
  }

  static bool stringToBool(String boolean) {
    return boolean == 'true';
  }

  static String getFileExt(String fileURL) {
    if (fileURL.contains('paheal') && fileURL.contains('file_ext')) {
      return Uri.parse(fileURL).queryParameters['file_ext'] ?? 'png';
    }

    final int queryLastIndex = fileURL.lastIndexOf('?'); // if has GET query parameters
    final int lastIndex = queryLastIndex != -1 ? queryLastIndex : fileURL.length;
    final String fileURLWithQueryParameters = fileURL.substring(0, lastIndex);
    final String fileExt = fileURLWithQueryParameters.substring(
      fileURLWithQueryParameters.lastIndexOf('.') + 1,
      lastIndex,
    );
    return fileExt;
  }

  static String getFileName(String fileURL) {
    final int queryLastIndex = fileURL.lastIndexOf('?'); // if has GET query parameters
    final int lastIndex = queryLastIndex != -1 ? queryLastIndex : fileURL.length;
    final String fileExt = fileURL.substring(fileURL.lastIndexOf('/') + 1, lastIndex);
    return fileExt;
  }

  static String sanitize(String str, {String replacement = ''}) {
    final RegExp illegalRe = RegExp(r'[\/\?<>\\:\*\|"]');
    final RegExp controlRe = RegExp(r'[\x00-\x1f\x80-\x9f]');
    final RegExp reservedRe = RegExp(r'^\.+$');
    final RegExp windowsReservedRe = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);
    final RegExp windowsTrailingRe = RegExp(r'[\. ]+$');

    // TODO truncate to 255 symbols for windows?
    return str
        .replaceAll(illegalRe, replacement)
        .replaceAll(controlRe, replacement)
        .replaceAll(reservedRe, replacement)
        .replaceAll(windowsReservedRe, replacement)
        .replaceAll(windowsTrailingRe, replacement)
        .replaceAll('%20', '_');
  }

  // unified http headers list generator for dio in thumb/media/video loaders
  static Future<Map<String, String>> getFileCustomHeaders(
    Booru? booru, {
    BooruItem? item,
    bool checkForReferer = false,
  }) async {
    final uri = Uri.parse((booru?.baseURL?.isNotEmpty == true ? booru?.baseURL : item?.postURL) ?? '');
    if (uri.host.isEmpty) {
      return {};
    }

    // a few boorus don't work without a browser useragent
    final Map<String, String> headers = {
      'User-Agent': browserUserAgentForBooru(booru?.name),
    };
    if (uri.host.contains('danbooru.donmai.us')) {
      headers['User-Agent'] = appUserAgent;
    } else if (IdolSankakuHandler.knownUrls.contains(uri.host)) {
      headers['User-Agent'] = Constants.sankakuIdolAppUserAgent;
    } else if ([
      ...SankakuHandler.knownUrls,
      'sankakuapi.com',
    ].any(uri.host.contains)) {
      headers['User-Agent'] = Constants.sankakuAppUserAgent;
    } else if (uri.host.contains('rule34.us')) {
      headers['LS-IGNORE-REDIRECT'] = '1';
    }

    if (!isTestMode) {
      try {
        final cookiesStr = await getCookies(uri.toString());
        if (cookiesStr.isNotEmpty) {
          headers['Cookie'] = cookiesStr;
        }
      } catch (e) {
        print('Error getting cookies: $e');
      }
    }

    // some boorus require referer header
    if (checkForReferer) {
      if (uri.host.contains('rule34.xyz')) {
        headers['Referer'] = 'https://rule34xyz.b-cdn.net';
      } else if (uri.host.contains('rule34.world')) {
        headers['Referer'] = 'https://rule34storage.b-cdn.net';
      } else if (uri.host.contains('gelbooru.com')) {
        headers['Referer'] = 'https://gelbooru.com';
      } else if (uri.host.contains('rule34.us')) {
        headers['Referer'] = 'https://rule34.us';
      } else if (uri.host.contains('realbooru.com')) {
        headers['Referer'] = 'https://realbooru.com';
      }
    }

    return headers;
  }

  static IconData? getFileIcon(MediaType? mediaType) {
    switch (mediaType) {
      case MediaType.image:
        return null; // Icons.photo;
      case MediaType.video:
        return CupertinoIcons.videocam_fill;
      case MediaType.animation:
        return CupertinoIcons.play_fill;
      case MediaType.notSupportedAnimation:
        return Icons.play_disabled;
      default:
        return CupertinoIcons.question;
    }
  }

  static void forceClearMemoryCache({bool withLive = false}) {
    // clears memory image cache on timer or when changing tabs
    PaintingBinding.instance.imageCache.clear();
    if (withLive) {
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  static bool isGoodStatusCode(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  static bool isGoodResponse(Response response) {
    if (!isGoodStatusCode(response.statusCode)) {
      return false;
    }

    final isSankaku = response.realUri.toString().contains('sankakucomplex.com');
    final isImageOrVideo =
        response.headers['content-type']?.any((t) => t.contains('image') || t.contains('video')) == true;
    if (isSankaku && isImageOrVideo) {
      final int? contentLength = int.tryParse(response.headers['content-length']?.firstOrNull ?? '');
      if (contentLength != null) {
        // TODO investigate better ways/possibility of this number changing
        // Image with "Expired link - please reload site" text
        const int expiredLinkFileSize = 14802;
        return contentLength != expiredLinkFileSize;
      }
    }

    // TODO add more checks
    return true;
  }

  static final String appUserAgent = 'LoliSnatcher_Droid/${Constants.updateInfo.versionName}';
  static String get browserUserAgent {
    return (isTestMode || SX.customUserAgent.value.isEmpty) ? appUserAgent : SX.customUserAgent.value;
  }

  /// Resolves a request's source without using the foreground tab's override.
  static String browserUserAgentForBooru(String? booruName) {
    if (isTestMode && SettingsRegistry.instance.isEmpty) return appUserAgent;
    final configured = SX.customUserAgent.valueForBooru(booruName);
    return configured.isEmpty ? appUserAgent : configured;
  }

  static bool get isTestMode => Platform.environment.containsKey('FLUTTER_TEST');

  static const String captchaCheckHeader = 'LSCaptchaCheck';
  static Completer<bool>? _captchaClosed;
  static String? _captchaOrigin;

  static bool hasCaptchaStrings(String host, String content) {
    final Map<String, List<String>> knownCaptchaStrings = {
      // TODO add multiple strings for each, then try to find as much as possible and decide if it's a captcha based on the ratio of found/total
      'booru.allthefallen.moe': ['processChallenge'],
      'derpibooru.org': ['derpi-challenge'],
    };

    final List<String>? stringsToFind = knownCaptchaStrings.entries
        .firstWhereOrNull((e) => host.contains(e.key))
        ?.value;

    if (stringsToFind == null) return false;
    return stringsToFind.any((t) => content.contains(t));
  }

  static Future<bool> checkForCaptcha(
    Response? response,
    Uri uri, {
    String? customUserAgent,
    CancelToken? cancelToken,
    void Function()? onSilentRefresh,
  }) async {
    bool isCancelled() => cancelToken?.isCancelled == true;
    if (isCancelled()) return false;
    final retryStage = response?.requestOptions.headers[captchaCheckHeader];
    if (isTestMode || retryStage == 'done') {
      return false;
    }
    bool allowSilentRefresh = retryStage != 'silent';

    Future<bool?> waitForScreen() async {
      while (captchaScreenActive) {
        if (_captchaOrigin != uri.origin || _captchaClosed == null) return false;
        final completed = await Future.any([
          _captchaClosed!.future,
          if (cancelToken != null) cancelToken.whenCancel.then((_) => false),
        ]);
        if (isCancelled()) return false;
        if (completed) return true;
        // The owner may have cancelled while this request is still active.
        // Join another waiter's replacement screen, or open one below.
      }
      return null;
    }

    final String host = uri.host;

    final bool hasCaptchaContent = hasCaptchaStrings(host, response?.data.toString() ?? '');

    if (PlatformExt.hasWebviewSupport &&
        ContentPolicy.canOpenWebview &&
        (CloudflareRefresh.isChallenge(response) ||
            response?.statusCode == HttpStatus.forbidden ||
            response?.statusCode == HttpStatus.serviceUnavailable ||
            hasCaptchaContent)) {
      while (captchaScreenActive) {
        final completed = await waitForScreen();
        if (completed != null) return completed;
        allowSilentRefresh = false;
      }

      if (allowSilentRefresh && CloudflareRefresh.isChallenge(response)) {
        final method = response?.requestOptions.method.toUpperCase();
        final refreshed = await CloudflareRefresh.refresh(
          method == 'GET' || method == 'HEAD' ? uri : Uri.parse(uri.origin),
          customUserAgent ?? browserUserAgent,
          cancelToken: cancelToken,
        );
        if (isCancelled()) return false;
        if (refreshed) {
          onSilentRefresh?.call();
          return true;
        }
        // Another request can have opened the screen while this one refreshed.
        while (captchaScreenActive) {
          final completed = await waitForScreen();
          if (completed != null) return completed;
        }
      }

      captchaScreenActive = true;
      _captchaOrigin = uri.origin;
      final closedSignal = _captchaClosed = Completer<bool>();
      bool completed = false;
      try {
        // Let the site renew clearance if needed. A failed request alone
        // does not establish that the stored cookie should be deleted.
        if (isCancelled()) return false;

        bool userDecidedToStay = false;
        final navigator = Navigator.of(NavigationHandler.instance.navContext);
        final route = MaterialPageRoute<void>(
          builder: (context) => InAppWebviewView(
            initialUrl: uri.origin,
            userAgent: customUserAgent,
            title: context.loc.webview.captcha,
            subtitle: context.loc.webview.captchaCheckDescription,
            onLoadStop: (context, controller, url) async {
              // close cloudflare captcha automatically
              if (url == null || isCancelled()) return;

              await Future.delayed(const Duration(milliseconds: 500));
              if (!context.mounted || isCancelled()) return;

              final List<Cookie> cookies = await WebviewCookies.read(url, controller: controller);
              if (!context.mounted || isCancelled()) return;
              final bool hasClearanceCookie = cookies.any((c) => c.name == 'cf_clearance');

              final String? htmlContent = await controller.evaluateJavascript(
                source: 'window.document.documentElement.outerHTML;',
              );

              if (htmlContent == null || !context.mounted || isCancelled()) return;

              final bool isCloudflareChallengeActive = CloudflareRefresh.hasChallenge(htmlContent);
              final bool isKnownCaptchaRunning = hasCaptchaStrings(url.host, htmlContent);
              if (context.mounted &&
                  hasClearanceCookie &&
                  !isCloudflareChallengeActive &&
                  !isKnownCaptchaRunning &&
                  !userDecidedToStay) {
                // allow user to stay in webview through a dialog, in case of false positives, otherwise leave after a few seconds
                final bool res = await showTimedLeaveDialog(
                  context,
                  title: context.loc.webview.captchaCompleted,
                  icon: const Icon(Icons.thumb_up_alt_rounded),
                  duration: const Duration(seconds: 4),
                );
                if (!context.mounted || isCancelled()) return;

                if (res) {
                  Navigator.of(context).pop();
                } else {
                  userDecidedToStay = true;
                }
              }
            },
          ),
        );
        final closed = navigator.push(route);
        if (cancelToken != null) {
          unawaited(
            cancelToken.whenCancel.then((_) {
              if (route.isActive) navigator.removeRoute(route);
            }),
          );
        }
        await closed;
        completed = !isCancelled();
        return !isCancelled();
      } finally {
        captchaScreenActive = false;
        _captchaOrigin = null;
        _captchaClosed = null;
        closedSignal.complete(completed);
      }
    }
    return false;
  }

  static Future<String> getCookies(String uri) async {
    String cookieString = '';
    if (PlatformExt.hasWebviewSupport) {
      try {
        List<Cookie> cookies = [];
        if (Platform.isWindows) {
          cookies.addAll(WebviewCookies.cachedForRequest(Uri.parse(uri)));
        } else {
          cookies = await WebviewCookies.read(Uri.parse(uri));
        }
        for (final Cookie cookie in cookies) {
          cookieString += '${cookie.name}=${cookie.value}; ';
        }
      } catch (e, s) {
        Logger.Inst().log(
          e.toString(),
          'Tools',
          'getCookies',
          LogTypes.exception,
          s: s,
        );
      }
    }

    return cookieString.trim();
  }

  static Future<bool> saveCookies(String uri, List<String> cookies) async {
    if (cookies.isEmpty) return true;

    if (PlatformExt.hasWebviewSupport) {
      try {
        final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
        final url = Uri.parse(uri);
        for (final value in cookies) {
          final io.Cookie cookie;
          try {
            cookie = io.Cookie.fromSetCookieValue(value);
          } on FormatException {
            continue;
          } on io.HttpException {
            continue;
          }
          final defaultPath = url.path.lastIndexOf('/') > 0 ? url.path.substring(0, url.path.lastIndexOf('/')) : '/';
          final path = cookie.path?.startsWith('/') == true ? cookie.path! : defaultPath;
          await cookieManager.setCookie(
            url: WebUri(uri),
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: path,
            expiresDate: cookie.expires?.millisecondsSinceEpoch,
            maxAge: cookie.maxAge,
            isSecure: cookie.secure,
            isHttpOnly: cookie.httpOnly,
          );
        }
        if (Platform.isWindows) await WebviewCookies.read(url);
        return true;
      } catch (e, s) {
        Logger.Inst().log(
          e.toString(),
          'Tools',
          'saveCookies',
          LogTypes.exception,
          s: s,
        );
      }
    }

    return false;
  }

  static String? urlJoin(String? base, String? segment) {
    if (base == null) return segment;
    if (segment == null) return base;

    final baseUri = Uri.parse(base), segUri = Uri.parse(segment);
    final schemeRegex = RegExp(r'^[a-zA-Z][a-zA-Z\d+\-.]*:');
    if (schemeRegex.hasMatch(segment)) return segment;
    if (segment.startsWith('//')) return '${baseUri.scheme}:$segment';
    if (segment.startsWith('?')) return baseUri.replace(query: segUri.query, fragment: segUri.fragment).toString();
    if (segment.startsWith('#')) return baseUri.replace(fragment: segUri.fragment).toString();

    var path = baseUri.path.endsWith('/') ? baseUri.path : baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
    if (segment.startsWith('/')) {
      path = segment.substring(1);
    } else {
      path += segUri.path;
    }

    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: path,
      query: segUri.query.isEmpty ? null : segUri.query,
      fragment: segUri.fragment.isEmpty ? null : segUri.fragment,
    ).toString();
  }
}

bool captchaScreenActive = false;
