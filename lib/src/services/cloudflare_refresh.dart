import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/services/webview_cookies.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class _Refresh {
  final stop = Completer<void>();
  late final Future<bool> result;
  int waiters = 0;
}

class CloudflareRefresh {
  static final Map<String, _Refresh> _pending = {};
  static final Map<String, DateTime> _lastAttempt = {};
  static final Set<String> _recentSuccess = {};

  static bool hasChallenge(String content) =>
      content.contains('id="cf-challenge-') ||
      content.contains("id='cf-challenge-") ||
      content.contains('cf-browser-verification') ||
      content.contains('_cf_chl_opt');

  static bool isChallenge(Response? response) =>
      response?.headers['cf-mitigated']?.contains('challenge') == true || hasChallenge(response?.data.toString() ?? '');

  static Future<bool> refresh(
    Uri uri,
    String userAgent, {
    CancelToken? cancelToken,
    bool requireNewClearance = true,
    bool useCooldown = true,
  }) async {
    if (cancelToken?.isCancelled == true) return false;
    final key = '${uri.origin}\n$userAgent\n$requireNewClearance';
    var pending = _pending[key];
    if (pending == null) {
      final now = DateTime.now();
      _lastAttempt.removeWhere((_, time) => now.difference(time) >= const Duration(seconds: 30));
      _recentSuccess.removeWhere((key) => !_lastAttempt.containsKey(key));
      if (useCooldown && _lastAttempt.containsKey(key)) return _recentSuccess.contains(key);
      _lastAttempt[key] = now;
      pending = _Refresh();
      final refresh = pending;
      _pending[key] = refresh;
      refresh.result = _run(uri, userAgent, refresh.stop.future, requireNewClearance: requireNewClearance)
          .then((success) {
            if (success) _recentSuccess.add(key);
            return success;
          })
          .whenComplete(() => _pending.remove(key));
    }
    final refresh = pending;
    refresh.waiters++;
    try {
      return await Future.any([
        refresh.result,
        if (cancelToken != null) cancelToken.whenCancel.then((_) => false),
      ]);
    } finally {
      refresh.waiters--;
      if (refresh.waiters == 0 && !refresh.stop.isCompleted) refresh.stop.complete();
    }
  }

  static Future<bool> _run(
    Uri uri,
    String userAgent,
    Future<void> cancelled, {
    required bool requireNewClearance,
  }) async {
    final result = Completer<bool>();
    void finish(bool success) {
      if (!result.isCompleted) result.complete(success);
    }

    final deadline = Timer(const Duration(seconds: 8), () => finish(false));
    unawaited(cancelled.then((_) => finish(false)));
    HeadlessInAppWebView? webview;
    Timer? poll;
    bool checking = false;
    bool pageLoaded = false;
    bool mainFrameFailed = false;
    Future<void>? startup;
    try {
      final oldCookies = await Future.any([
        WebviewCookies.read(uri),
        result.future.then((_) => <Cookie>[]),
      ]);
      if (result.isCompleted) return false;
      final oldClearance = oldCookies.where((cookie) => cookie.name == 'cf_clearance').map((c) => c.value).toSet();
      Future<void> check(InAppWebViewController controller) async {
        if (checking || result.isCompleted || !pageLoaded || mainFrameFailed) return;
        checking = true;
        try {
          final url = await controller.getUrl();
          if (url == null || url.host != uri.host || result.isCompleted) return;
          final html = await controller.getHtml();
          if (html == null || html.isEmpty || hasChallenge(html) || result.isCompleted) return;
          final cookies = await WebviewCookies.read(uri, controller: controller);
          if (result.isCompleted) return;
          if (!requireNewClearance ||
              cookies.any((c) => c.name == 'cf_clearance' && c.value.isNotEmpty && !oldClearance.contains(c.value))) {
            finish(true);
          }
        } catch (e, s) {
          if (!result.isCompleted) {
            Logger.Inst().log(e.toString(), 'CloudflareRefresh', 'check', LogTypes.exception, s: s);
            finish(false);
          }
        } finally {
          checking = false;
        }
      }

      webview = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri.uri(uri)),
        initialSettings: InAppWebViewSettings(
          userAgent: userAgent,
          javaScriptEnabled: true,
          cacheEnabled: false,
          thirdPartyCookiesEnabled: true,
          mediaPlaybackRequiresUserGesture: true,
          javaScriptCanOpenWindowsAutomatically: false,
        ),
        onWebViewCreated: (controller) {
          if (result.isCompleted) return;
          poll = Timer.periodic(const Duration(milliseconds: 300), (_) => unawaited(check(controller)));
        },
        onLoadStart: (_, _) {
          pageLoaded = false;
          mainFrameFailed = false;
        },
        onLoadStop: (controller, _) {
          pageLoaded = true;
          unawaited(check(controller));
        },
        onReceivedHttpError: (_, request, response) {
          if (request.isForMainFrame == true && (response.statusCode ?? 0) >= 400) mainFrameFailed = true;
        },
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true) finish(false);
        },
      );
      startup = webview.run();
      unawaited(
        startup.then(
          (_) {},
          onError: (Object e, StackTrace s) {
            Logger.Inst().log(e.toString(), 'CloudflareRefresh', 'run', LogTypes.exception, s: s);
            finish(false);
          },
        ),
      );
      return await result.future;
    } catch (e, s) {
      Logger.Inst().log(e.toString(), 'CloudflareRefresh', 'refresh', LogTypes.exception, s: s);
      return false;
    } finally {
      finish(false);
      deadline.cancel();
      poll?.cancel();
      final instance = webview;
      if (instance != null) {
        // Startup can finish after timeout/cancellation. Dispose once it has
        // settled as well, so a late native creation cannot leak a WebView.
        Future<void> dispose() async {
          try {
            await instance.dispose();
          } catch (e, s) {
            Logger.Inst().log(e.toString(), 'CloudflareRefresh', 'dispose', LogTypes.exception, s: s);
          }
        }

        await dispose().timeout(const Duration(seconds: 1), onTimeout: () {});
        if (startup != null) unawaited(startup.then((_) => dispose(), onError: (Object _) {}));
      }
    }
  }
}
