import 'dart:typed_data';

import 'package:dio/dio.dart';

enum CacheMode { disabled, memory, disk }

class CronetEngine {
  const CronetEngine._();

  static CronetEngine build({
    CacheMode? cacheMode,
    int? cacheMaxSize,
    bool? enableBrotli,
    bool? enableHttp2,
    bool? enableQuic,
    String? userAgent,
  }) {
    return const CronetEngine._();
  }
}

class CronetAdapter implements HttpClientAdapter {
  CronetAdapter(CronetEngine? engine, {bool closeEngine = true})
    : _isConfigured = engine != null || closeEngine;

  final bool _isConfigured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    throw UnsupportedError('Cronet is not available in no-cronet builds');
  }

  @override
  void close({bool force = false}) {
    if (_isConfigured) return;
  }
}
