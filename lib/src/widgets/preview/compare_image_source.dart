import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/media_loading.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';

/// Owns image loading for standalone views without registering with ViewerHandler.
class CompareImageSource extends ChangeNotifier {
  CompareImageSource(this.item, this.booru, {required this.widthLimit})
    : fullQuality = SX.galleryMode.value.isFullRes ? !item.toggleQuality.value : item.toggleQuality.value,
      originalResolution = item.isNoScale.value;

  final BooruItem item;
  final Booru booru;
  final int widthLimit;
  final total = ValueNotifier(0);
  final received = ValueNotifier(0);
  final startedAt = ValueNotifier(0);
  bool fullQuality;
  bool originalResolution;
  bool loaded = false;
  bool fromCache = false;
  bool allowHidden = false;
  bool _ignoreLimits = false;
  bool _disposed = false;
  int _generation = 0;
  ViewerStopReason? stopReason;
  String? stopDetails;
  ImageProvider? provider;
  Future<ImageProvider>? providerFuture;
  Size? imageSize;
  CancelToken? _cancelToken;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
  }

  void _cancel() {
    _generation++;
    _detach();
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  void stop(ViewerStopReason reason, [String? details]) {
    if (_disposed) return;
    _cancel();
    loaded = false;
    stopReason = reason;
    stopDetails = details;
    notifyListeners();
  }

  void restart() {
    if (stopReason == ViewerStopReason.hidden) allowHidden = true;
    if (stopReason == ViewerStopReason.tooBig) _ignoreLimits = true;
    load();
  }

  void toggleQuality() {
    fullQuality = !fullQuality;
    _ignoreLimits = false;
    load();
  }

  void toggleResolution() {
    originalResolution = !originalResolution;
    load();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  bool _checkSize(int? bytes) {
    if (bytes == 0) {
      stop(ViewerStopReason.error);
      return false;
    }
    final limit = SX.preloadSizeLimit.value == 0 ? null : Tools.gibibytesToBytes(SX.preloadSizeLimit.value);
    if (!_ignoreLimits && limit != null && bytes != null && bytes > limit) {
      stop(ViewerStopReason.tooBig, '${Tools.formatBytes(bytes, 2)} / ${Tools.formatBytes(limit, 2)}');
      return false;
    }
    return true;
  }

  Future<void> load() async {
    if (_disposed) return;
    final previousProvider = provider;
    _cancel();
    final generation = _generation;
    loaded = false;
    fromCache = false;
    provider = null;
    providerFuture = null;
    stopReason = null;
    stopDetails = null;
    total.value = 0;
    received.value = 0;
    startedAt.value = DateTime.now().millisecondsSinceEpoch;
    if (item.isHidden && !allowHidden) {
      stop(
        ViewerStopReason.hidden,
        SettingsHandler.instance.parseTagsList(item.tagsList, isCapped: true).hiddenTags.join('\n'),
      );
      return;
    }
    final useSample = !fullQuality && item.sampleURL.isNotEmpty;
    final url = useSample ? item.sampleURL : (item.fileURL.isNotEmpty ? item.fileURL : item.sampleURL);
    final height = useSample ? item.sampleHeight : item.fileHeight;
    if (!_ignoreLimits && SX.preloadHeight.value > 0 && height != null && height > SX.preloadHeight.value) {
      stop(ViewerStopReason.tooBig, '${height.round()}px / ${SX.preloadHeight.value}px');
      return;
    }
    if (!useSample && (item.fileSize ?? 0) > 0 && !_checkSize(item.fileSize)) return;
    notifyListeners();
    final cancelToken = _cancelToken = CancelToken();
    try {
      if (previousProvider != null) await previousProvider.evict();
      if (!_current(generation)) return;
      if (url.isEmpty) throw StateError('No image URL found for selected item');
      final headers = await Tools.getFileCustomHeaders(booru, item: item, checkForReferer: true);
      if (!_current(generation)) return;
      void onCache(bool value) {
        if (_current(generation) && fromCache != value) {
          fromCache = value;
          notifyListeners();
        }
      }

      ImageProvider imageProvider = url.toLowerCase().contains('.avif')
          ? CustomNetworkAvifImage(
              url,
              headers: headers,
              cancelToken: cancelToken,
              withCache: SX.mediaCache.value,
              cacheFolder: useSample ? 'samples' : 'media',
              fileNameExtras: item.fileNameExtras,
              withCaptchaCheck: true,
              onCacheDetected: onCache,
            )
          : CustomNetworkImage(
              url,
              headers: headers,
              cancelToken: cancelToken,
              withCache: SX.mediaCache.value,
              cacheFolder: useSample ? 'samples' : 'media',
              fileNameExtras: item.fileNameExtras,
              withCaptchaCheck: true,
              onCacheDetected: onCache,
            );
      if (!item.mediaType.value.isAnimation && !SX.disableImageScaling.value && !originalResolution) {
        imageProvider = ResizeImage(
          imageProvider,
          width: widthLimit,
          height: 8192,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        );
      }
      provider = imageProvider;
      _stream = imageProvider.resolve(ImageConfiguration.empty);
      _listener = ImageStreamListener(
        (info, _) {
          try {
            if (!_current(generation)) return;
            loaded = true;
            imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
            providerFuture = Future.value(imageProvider);
            _detach();
            notifyListeners();
          } finally {
            info.dispose();
          }
        },
        onChunk: (event) {
          if (!_current(generation)) return;
          final knownBytes = event.expectedTotalBytes ?? event.cumulativeBytesLoaded;
          if (knownBytes > 0 && !_checkSize(knownBytes)) return;
          received.value = event.cumulativeBytesLoaded;
          total.value = event.expectedTotalBytes ?? 0;
        },
        onError: (Object error, StackTrace? stack) {
          if (_current(generation)) stop(ViewerStopReason.error, error.toString());
        },
      );
      _stream!.addListener(_listener!);
    } catch (error) {
      if (_current(generation)) stop(ViewerStopReason.error, error.toString());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    total.dispose();
    received.dispose();
    startedAt.dispose();
    super.dispose();
  }
}

class CompareImageLoading extends StatelessWidget {
  const CompareImageLoading({required this.source, super.key});
  final CompareImageSource source;

  @override
  Widget build(BuildContext context) {
    final loading = MediaLoading(
      item: source.item,
      hasProgress: true,
      isFromCache: source.fromCache,
      isDone: source.loaded,
      isStopped: source.stopReason != null,
      isViewed: true,
      isTooBig: source.stopReason == ViewerStopReason.tooBig,
      stopReason: source.stopReason,
      stopDetails: source.stopDetails,
      total: source.total,
      received: source.received,
      startedAt: source.startedAt,
      onRestart: source.restart,
      onStop: () => source.stop(ViewerStopReason.user),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // MediaLoading contains a full-height Row with vertical progress bars.
        // Give it finite space inside the scroll view, including long filter
        // explanations, so buttons remain reachable in short split panes.
        final details = TextPainter(
          text: TextSpan(text: source.stopDetails ?? '', style: const TextStyle(fontSize: 20)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: math.max(1, constraints.maxWidth - 40));
        final height = math.max(constraints.maxHeight, 360 + details.height);
        details.dispose();
        return SingleChildScrollView(
          child: SizedBox(height: height, child: loading),
        );
      },
    );
  }
}

class CompareImageOptions extends StatelessWidget {
  const CompareImageOptions({required this.source, required this.label, super.key});
  final CompareImageSource source;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '$label: ${context.loc.galleryButtons.toggleQuality}',
      onSelected: (action) => action == 0 ? source.toggleQuality() : source.toggleResolution(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 0,
          child: Text(
            source.fullQuality
                ? context.loc.viewer.appBar.loadSampleQuality
                : context.loc.viewer.appBar.loadHighQuality,
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: Text(
            source.originalResolution
                ? context.loc.viewer.appBar.reloadWithScaling
                : context.loc.galleryButtons.reloadNoScale,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label), const SizedBox(width: 4), const Icon(Icons.image_outlined)],
        ),
      ),
    );
  }
}
