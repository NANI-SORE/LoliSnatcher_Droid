import 'package:flutter/foundation.dart';

/// Stable transport and disk-cache configuration shared by image load paths.
/// Cancellation and progress belong to each operation and are passed separately.
@immutable
class ImageDownloadRequest {
  const ImageDownloadRequest({
    required this.url,
    this.cacheFolder,
    this.fileNameExtras = '',
    this.withCache = false,
    this.headers,
    this.sendTimeout,
    this.receiveTimeout,
    this.withCaptchaCheck = false,
  });

  final String url;
  final String? cacheFolder;
  final String fileNameExtras;
  final bool withCache;
  final Map<String, String>? headers;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;
  final bool withCaptchaCheck;
}
