import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

// Only clients created inside a sync operation use this gate. Gallery traffic
// keeps its existing behavior. Host cooldowns survive preview/run transitions.
class ServerFavoritesRequestGate {
  ServerFavoritesRequestGate(this.cancelToken, {this.onStatus});

  final CancelToken cancelToken;
  final void Function(String)? onStatus;
  static final _zoneKey = Object();
  static final _nextRequest = <String, DateTime>{};
  static final _cooldowns = <String, DateTime>{};
  static ServerFavoritesRequestGate? get current => Zone.current[_zoneKey] as ServerFavoritesRequestGate?;

  Future<T> run<T>(Future<T> Function() action) => runZoned(action, zoneValues: {_zoneKey: this});

  Future<void> _wait(String host) async {
    var announcedCooldown = false;
    while (true) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final now = DateTime.now();
      final next = _nextRequest[host] ?? now;
      final cooldown = _cooldowns[host] ?? now;
      final until = next.isAfter(cooldown) ? next : cooldown;
      if (!until.isAfter(now)) {
        _nextRequest[host] = now.add(const Duration(seconds: 1));
        return;
      }
      if (!announcedCooldown && cooldown.isAfter(now)) {
        onStatus?.call('$host: rate limited; waiting until ${cooldown.toLocal()}');
        announcedCooldown = true;
      }
      // Poll cancellation without retaining one listener per request on a long-lived token.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void _observe(Response? response) {
    if (response == null || (response.statusCode != 429 && response.statusCode != 503)) return;
    final now = DateTime.now();
    final header = response.headers['retry-after']?.firstOrNull;
    DateTime? until;
    if (header != null) {
      final seconds = int.tryParse(header.trim());
      if (seconds != null && seconds >= 0 && seconds <= 31536000) {
        until = now.add(Duration(seconds: seconds));
      } else {
        try {
          until = HttpDate.parse(header);
        } catch (_) {
          // A missing/malformed hint uses the conservative fallback below.
        }
      }
    }
    final fallback = now.add(const Duration(seconds: 60));
    if (until == null || !until.isAfter(now)) until = fallback;
    final host = response.requestOptions.uri.host.toLowerCase();
    final previous = _cooldowns[host];
    if (previous == null || until.isAfter(previous)) _cooldowns[host] = until;
    onStatus?.call(
      '$host: HTTP ${response.statusCode}; cooldown until ${until.toLocal()}. Refresh the preview to continue.',
    );
  }

  Interceptor get interceptor => InterceptorsWrapper(
    onRequest: (options, handler) async {
      try {
        await _wait(options.uri.host.toLowerCase());
        handler.next(options);
      } catch (error) {
        handler.reject(error is DioException ? error : DioException(requestOptions: options, error: error));
      }
    },
    onResponse: (response, handler) {
      _observe(response);
      handler.next(response);
    },
    onError: (error, handler) {
      _observe(error.response);
      handler.next(error);
    },
  );
}
