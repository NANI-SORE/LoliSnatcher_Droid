import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';

import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';
import 'package:lolisnatcher/src/utils/http_overrides.dart';
import 'package:lolisnatcher/src/services/local_network_permission.dart';

class DownloadBlocked implements Exception {
  const DownloadBlocked(this.code);
  final String code;
  @override
  String toString() => code;
}

class DownloadRateGate {
  DownloadRateGate(this.store);
  final DownloadStore store;
  final Set<String> _held = {};
  int _active = 0;
  Future<void> _admission = Future<void>.value();

  Future<void Function()> acquire(String site, String host, int delay, CancelToken? token) async {
    final scopes = ['site:$site', 'host:$host'];
    while (true) {
      if (token?.isCancelled == true) throw token!.cancelError!;
      final previous = _admission;
      final complete = Completer<void>();
      _admission = complete.future;
      await previous;
      var granted = false;
      var waitMs = 100;
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final deadline = await store.deadline(scopes);
        waitMs = max(100, min(1000, deadline - now));
        if (_active < 3 && !scopes.any(_held.contains) && deadline <= now) {
          if (Platform.isIOS) {
            granted =
                await downloadPlatform.invokeMethod<bool>('acquireSite', {
                  'site': site,
                  'host': host,
                  'delayMs': delay,
                }) ??
                false;
          } else {
            granted = true;
          }
          if (granted) {
            await store.defer(scopes, now + delay);
            _active++;
            _held.addAll(scopes);
          }
        }
      } finally {
        complete.complete();
      }
      if (granted) {
        var released = false;
        return () {
          if (released) return;
          released = true;
          _active--;
          _held.removeAll(scopes);
          if (Platform.isIOS) {
            unawaited(downloadPlatform.invokeMethod<void>('releaseSite', {'site': site, 'host': host}));
          }
        };
      }
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  }
}

class DownloadNetwork {
  DownloadNetwork({
    required this.configuration,
    required this.gate,
    required this.site,
    this.cooldown = 1000,
    this.sourceName = '',
  });
  final DownloadConfiguration configuration;
  final DownloadRateGate gate;
  final String site;
  final String sourceName;
  final int cooldown;
  static const _leaseKey = 'downloadLease';

  Dio client() {
    initializeDownloadTrust();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        followRedirects: false,
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    );
    final transport = configuration.transportFor(sourceName);
    var proxy = transport['proxyAddress'] as String? ?? '';
    final username = transport['proxyUsername'] as String? ?? '';
    if (username.isNotEmpty) proxy = '$username:${transport['proxyPassword'] ?? ''}@$proxy';
    final type = transport['proxyType'] as String? ?? 'direct';
    if (const ['http', 'socks4', 'socks5'].contains(type) && (transport['proxyAddress'] as String? ?? '').isEmpty) {
      throw const DownloadBlocked('proxyConfiguration');
    }
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = createProxyHttpClient();
        client.badCertificateCallback = (_, _, _) => transport['allowSelfSigned'] == true;
        client.findProxy = (_) => switch (type) {
          'http' when proxy.isNotEmpty => 'PROXY $proxy',
          'socks4' when proxy.isNotEmpty => 'SOCKS4 $proxy',
          'socks5' when proxy.isNotEmpty => 'SOCKS5 $proxy',
          'system' when (transport['systemProxy'] as String? ?? '').isNotEmpty => 'PROXY ${transport['systemProxy']}',
          _ => 'DIRECT',
        };
        return client;
      },
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final networkUrls = [options.uri.toString(), if (proxy.isNotEmpty) 'http://$proxy'];
            if (Platform.isAndroid && networkUrls.any(LocalNetworkPermission.isLocalUrl)) {
              if (await downloadPlatform.invokeMethod<bool>('hasLocalNetworkPermission') != true) {
                throw const DownloadBlocked('localNetworkPermission');
              }
            }
            final currentCooldown = (configuration.policy(sourceName)['cooldownMs'] as num?)?.toInt() ?? 0;
            options.extra[_leaseKey] = await gate.acquire(
              site,
              options.uri.host,
              RateLimitPolicy(cooldownMs: max(cooldown, currentCooldown)).delayMs,
              options.cancelToken,
            );
            handler.next(options);
          } catch (error) {
            release(options);
            handler.reject(DioException(requestOptions: options, error: error));
          }
        },
        onResponse: (response, handler) async {
          final options = response.requestOptions;
          try {
            await configuration.saveCookies(options.uri.toString(), response.headers['set-cookie'] ?? const []);
            if ((response.statusCode ?? 0) >= 300) {
              release(options);
              final location = response.headers.value('location');
              final hops = options.extra['downloadRedirects'] as int? ?? 0;
              if (location == null || hops >= 5 || options.headers.containsKey('LS-IGNORE-REDIRECT')) {
                throw const DownloadBlocked('redirect');
              }
              final uri = options.uri.resolve(location);
              if (!{'http', 'https'}.contains(uri.scheme) || options.uri.scheme == 'https' && uri.scheme != 'https') {
                throw const DownloadBlocked('redirect');
              }
              final headers = Map<String, dynamic>.from(options.headers);
              if (uri.host != options.uri.host) {
                headers.removeWhere(
                  (key, _) => const [
                    'authorization',
                    'cookie',
                    'proxy-authorization',
                    'hydrus-client-api-access-key',
                  ].contains(key.toLowerCase()),
                );
              }
              // Close an unfollowed streaming response before opening the next hop.
              if (response.data is ResponseBody) await (response.data as ResponseBody).stream.drain<void>();
              final redirected = await dio.request<dynamic>(
                uri.toString(),
                data: response.statusCode == 307 || response.statusCode == 308 ? options.data : null,
                options: Options(
                  method: response.statusCode == 307 || response.statusCode == 308 ? options.method : 'GET',
                  headers: headers,
                  responseType: options.responseType,
                  extra: {...options.extra..remove(_leaseKey), 'downloadRedirects': hops + 1},
                ),
                cancelToken: options.cancelToken,
              );
              handler.resolve(redirected);
              return;
            }
            if (options.responseType != ResponseType.stream) release(options);
            handler.next(response);
          } catch (error) {
            release(options);
            handler.reject(DioException(requestOptions: options, response: response, error: error));
          }
        },
        onError: (error, handler) async {
          release(error.requestOptions);
          final status = error.response?.statusCode;
          if (status == 429 || status == 503) {
            final deadline =
                RateLimitPolicy.retryAfter(error.response?.headers.value('retry-after'), DateTime.now()) ??
                DateTime.now().add(const Duration(seconds: 30));
            await gate.store.defer([
              'site:$site',
              'host:${error.requestOptions.uri.host}',
            ], deadline.millisecondsSinceEpoch);
          }
          handler.next(error);
        },
      ),
    );
    return dio;
  }

  static void release(RequestOptions options) => (options.extra.remove(_leaseKey) as void Function()?)?.call();

  static String errorCode(Object error) {
    if (error is PlatformException) {
      if (error.code == 'authentication') return 'authentication';
      if (error.code.contains('publicationAmbiguous')) return 'publicationAmbiguous';
      if (error.code.contains('photosAmbiguous')) return 'photosAmbiguous';
      if (error.code.contains('photosPermission')) return 'photosPermission';
      return 'storage';
    }
    if (error is StateError && error.message == 'authentication') return 'authentication';
    if (error is DownloadBlocked) return error.code;
    if (error is FileSystemException) return 'storage';
    if (error is DioException) {
      if (error.error is DownloadBlocked) return (error.error! as DownloadBlocked).code;
      if (error.response?.statusCode != null) return 'http${error.response!.statusCode}';
      if (error.type == DioExceptionType.connectionError || error.error is SocketException) return 'network';
      if (error.type == DioExceptionType.cancel) return 'interrupted';
      if (error.type == DioExceptionType.badCertificate) return 'certificate';
      return 'timeout';
    }
    return 'preparation';
  }
}
