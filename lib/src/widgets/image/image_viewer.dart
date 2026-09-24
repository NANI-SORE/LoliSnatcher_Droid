import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/services/image_download_request.dart';
import 'package:lolisnatcher/src/widgets/image/region_image_view.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/media_loading.dart';
import 'package:lolisnatcher/src/widgets/common/preserve_media_animations.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

enum ViewerStopReason {
  user,
  error,
  tooBig,
  hidden,
  videoError,
  reset,
  ;

  bool get isUser => this == user;
  bool get isError => this == error;
  bool get isTooBig => this == tooBig;
  bool get isHidden => this == hidden;
  bool get isVideoError => this == videoError;
  bool get isReset => this == reset;
}

enum PreloadBlockState {
  tooBig,
  ignore,
  initial,
  ;

  bool get isTooBig => this == tooBig;
  bool get isIgnore => this == ignore;
  bool get isInitial => this == initial;
}

class ImageViewer extends StatefulWidget {
  const ImageViewer(
    this.booruItem, {
    required this.booru,
    required this.isViewed,
    this.isRevealed,
    this.onReveal,
    super.key,
  });

  final BooruItem booruItem;
  final Booru booru;
  final bool isViewed;

  /// Gallery-owned reveal choice, retained even when this viewer is recreated.
  final bool Function()? isRevealed;
  final VoidCallback? onReveal;

  @override
  State<ImageViewer> createState() => ImageViewerState();
}

class ImageViewerState extends State<ImageViewer> {
  final settingsHandler = SettingsHandler.instance;
  final viewerHandler = ViewerHandler.instance;

  PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  PhotoViewController viewController = PhotoViewController();

  final ValueNotifier<int> total = ValueNotifier(0), received = ValueNotifier(0), startedAt = ValueNotifier(0);
  final ValueNotifier<bool> isFirstBuild = ValueNotifier(true);
  final ValueNotifier<bool> isLoaded = ValueNotifier(false);
  final ValueNotifier<bool> isViewed = ValueNotifier(false);
  final ValueNotifier<bool> isFromCache = ValueNotifier(false);
  final ValueNotifier<bool> isZoomed = ValueNotifier(false);
  final ValueNotifier<bool> isStopped = ValueNotifier(false);
  final ValueNotifier<bool> showLoading = ValueNotifier(true);

  PreloadBlockState blockPreloadState = .initial;
  final ValueNotifier<ViewerStopReason?> stopReason = ValueNotifier(null);
  final ValueNotifier<String?> stopDetails = ValueNotifier(null);

  final ValueNotifier<ImageProvider?> mainProvider = ValueNotifier(null);
  ImageStreamListener? imageListener;
  ImageStream? imageStream;
  StreamSubscription<PhotoViewControllerValue>? viewStateSubscription;
  StreamSubscription<PhotoViewScaleState>? scaleStateSubscription;
  int _loadGeneration = 0;

  String imageFolder = 'media';
  int? widthLimit;
  CancelToken? cancelToken;
  CancelToken? loadItemCancelToken;

  DownloadedImageFile? _download;
  RegionImageSource? _regionSource;
  String? _fallbackUrl;
  String? _activeUrl;
  final Set<String> _attemptedUrls = {};
  int _animationRetries = 0;
  bool _ignoreTagsForLoad = false;
  bool _captchaForLoad = false;
  bool isTiled = false;
  final ValueNotifier<bool?> isTilingProcessing = ValueNotifier(null);
  Size? tiledSize;

  bool get isProviderLoaded {
    if (isTilingProcessing.value != false) {
      return false;
    }

    if (isTiled && _regionSource != null) {
      return true;
    } else {
      return mainProvider.value != null;
    }
  }

  void onSize(int? size) {
    // TODO find a way to stop loading based on size when caching is enabled
    final int? maxSize = settingsHandler.preloadSizeLimit == 0
        ? null
        : (1024 * 1024 * settingsHandler.preloadSizeLimit * 1000).round();
    if (size != null && size > 0) {
      widget.booruItem.fileSize = size;
    }

    if (size == null) {
      //
    } else if (size == 0) {
      stopLoading(
        reason: .error,
        title: context.loc.media.loading.fileIsZeroBytes,
      );
      return;
    } else if (maxSize != null && (size > maxSize) && !blockPreloadState.isIgnore) {
      stopLoading(
        reason: .tooBig,
        details:
            '${context.loc.media.loading.fileSize(size: Tools.formatBytes(size, 2))}\n'
            '${context.loc.media.loading.sizeLimit(limit: Tools.formatBytes(maxSize, 2, withTrailingZeroes: false))}',
      );
      return;
    }

    if (_fallbackUrl == null &&
        settingsHandler.preloadHeight != 0 &&
        widget.booruItem.fileHeight != null &&
        widget.booruItem.fileHeight! > settingsHandler.preloadHeight &&
        !blockPreloadState.isIgnore) {
      stopLoading(
        reason: .tooBig,
        details:
            '${context.loc.media.loading.fileSize(size: '${widget.booruItem.fileWidth?.toFormattedString()}x${widget.booruItem.fileHeight?.toFormattedString()}')}\n'
            '${context.loc.media.loading.sizeLimit(limit: '...x${settingsHandler.preloadHeight.toFormattedString()}')}',
      );
      return;
    }
  }

  void onBytesAdded(int receivedNew, int? totalNew) {
    received.value = receivedNew;
    if (totalNew != null) {
      total.value = totalNew;
    }
    onSize(totalNew ?? receivedNew);
  }

  void onError(Object error) {
    showLoading.value = true;
    final animation = widget.booruItem.mediaType.value.isAnimation;
    final cancelled = error is DioException && CancelToken.isCancel(error);
    if (animation && (cancelled || (error is ImageMemoryException && error.isTransient)) && _animationRetries < 2) {
      _animationRetries++;
      disposables();
      isLoaded.value = false;
      final generation = _loadGeneration;
      unawaited(_retryAnimation(generation));
      return;
    }
    if (error is ImageMemoryException) {
      if (animation) {
        // A static sample/thumbnail cannot satisfy a request for playback.
        // Keep genuine refusal visible instead of declaring a still image loaded.
        stopLoading(reason: error.isTransient ? .error : .tooBig, details: error.reason);
        return;
      }
      final fallback = [
        widget.booruItem.sampleURL,
        widget.booruItem.thumbnailURL,
      ].where((url) => url.isNotEmpty && url != _activeUrl && !_attemptedUrls.contains(url)).firstOrNull;
      if (fallback != null) {
        disposables();
        _fallbackUrl = fallback;
        isLoaded.value = false;
        unawaited(initViewer(false));
        return;
      }
      stopLoading(reason: .tooBig);
      return;
    }
    if (cancelled) {
      stopLoading(reason: .error, details: error.toString());
    } else {
      if (error is DioException) {
        stopLoading(
          reason: .error,
          title: error.type.name,
          details: (error.response?.statusCode != null)
              ? '${error.response?.statusCode} - ${error.response?.statusMessage ?? DioNetwork.badResponseExceptionMessage(error.response?.statusCode)}'
              : null,
        );
      } else {
        stopLoading(
          reason: .error,
          details: error.toString(),
        );
      }
    }
  }

  Future<void> _retryAnimation(int generation) async {
    // Let thumbnail policy changes rebuild and remove their codec owners.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!_isCurrentLoad(generation)) return;
    PaintingBinding.instance.imageCache.clear();
    await initViewer(_ignoreTagsForLoad, withCaptchaCheck: _captchaForLoad);
  }

  void _updateAnimationFocus() {
    ImageMemoryManager.instance.setAnimationViewerActive(
      this,
      widget.isViewed && widget.booruItem.mediaType.value.isAnimation && !isStopped.value,
    );
  }

  @override
  void initState() {
    super.initState();

    isViewed.value = widget.isViewed;
    _updateAnimationFocus();

    viewerHandler.addViewed(widget.key);

    // debug output
    viewStateSubscription = viewController.outputStateStream.listen(onViewStateChanged);
    scaleStateSubscription = scaleController.outputScaleStateStream.listen(onScaleStateChanged);

    calcWidthLimit(MediaQuery.sizeOf(NavigationHandler.instance.navContext).width);

    if (isFirstBuild.value) {
      isFirstBuild.value = false;
      initViewer(false);
    }
  }

  @override
  void didUpdateWidget(ImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // force redraw on item data change
    if (oldWidget.booruItem != widget.booruItem) {
      _animationRetries = 0;
      _ignoreTagsForLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        stopLoading(reason: .reset);
        initViewer(false);
      });
    }

    if (oldWidget.isViewed != widget.isViewed) {
      isViewed.value = widget.isViewed;
      if (widget.booruItem.mediaType.value.isAnimation) {
        if (widget.isViewed && oldWidget.booruItem == widget.booruItem) {
          _animationRetries = 0;
          unawaited(initViewer(false));
        } else if (!widget.isViewed) {
          disposables();
          isLoaded.value = false;
        }
      }
      _updateAnimationFocus();
      if (!isViewed.value) {
        // reset zoom if not viewed
        resetZoom();
      }
    }
  }

  bool get useFullImage => settingsHandler.galleryMode.isFullRes
      ? !widget.booruItem.toggleQuality.value
      : widget.booruItem.toggleQuality.value;

  Future<void> initViewer(
    bool ignoreTagsCheck, {
    bool withCaptchaCheck = false,
  }) async {
    // An offscreen GIF needs only its thumbnail. Its native animation codec
    // must not reserve the memory needed by the currently viewed GIF.
    if (widget.booruItem.mediaType.value.isAnimation && !widget.isViewed) return;
    _ignoreTagsForLoad = ignoreTagsCheck || _ignoreTagsForLoad || (widget.isRevealed?.call() ?? false);
    _captchaForLoad = withCaptchaCheck;
    final int loadGeneration = ++_loadGeneration;
    widget.booruItem.isNoScale.addListener(noScaleListener);

    widget.booruItem.toggleQuality.addListener(toggleQualityListener);

    if (widget.booruItem.isHidden && !_ignoreTagsForLoad) {
      if (widget.booruItem.isHidden) {
        stopLoading(
          reason: .hidden,
          details: settingsHandler
              .parseTagsList(
                widget.booruItem.tagsList,
                isCapped: true,
              )
              .hiddenTags
              .join('\n'),
        );
        return;
      }
    }

    isStopped.value = false;
    _updateAnimationFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentLoad(loadGeneration)) return;

      viewerHandler.setStopped(widget.key, false);
    });

    startedAt.value = DateTime.now().millisecondsSinceEpoch;

    final mQuery = MediaQuery.of(NavigationHandler.instance.navContext);
    widthLimit = settingsHandler.disableImageScaling ? null : (mQuery.size.width * mQuery.devicePixelRatio * 2).round();

    ImageProvider? newProvider;
    try {
      if (widget.booruItem.mediaType.value.isAnimation) {
        await WidgetsBinding.instance.endOfFrame;
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentLoad(loadGeneration)) return;
        PaintingBinding.instance.imageCache.clear();
      }
      newProvider = await getImageProvider(
        loadGeneration: loadGeneration,
        withCaptchaCheck: withCaptchaCheck,
      );
    } catch (error) {
      if (_isCurrentLoad(loadGeneration)) onError(error);
      return;
    }

    if (!_isCurrentLoad(loadGeneration)) {
      return;
    }

    isTilingProcessing.value = false;
    if (isTiled) return;
    if (newProvider == null) return;
    mainProvider.value = newProvider;
    _removeImageStreamListener();
    imageStream = mainProvider.value!.resolve(ImageConfiguration.empty);
    imageListener = ImageStreamListener(
      (imageInfo, syncCall) {
        // Release this bookkeeping listener's clone, preserving cache/render handles.
        imageInfo.dispose();
        if (!_isCurrentLoad(loadGeneration)) return;

        final prevIsLoaded = isLoaded.value;
        isLoaded.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isCurrentLoad(loadGeneration)) return;

          // without this check gifs will keep resetting zoom on every frame change
          // because every frame is considered as new image
          if (prevIsLoaded == false) {
            resetZoom();
          }
          viewerHandler.setLoaded(widget.key, true);
        });
      },
      onChunk: (event) {
        if (!_isCurrentLoad(loadGeneration)) return;

        onBytesAdded(event.cumulativeBytesLoaded, event.expectedTotalBytes);
      },
      onError: (e, stack) {
        if (_isCurrentLoad(loadGeneration)) {
          onError(e);
        }
      },
    );
    imageStream!.addListener(imageListener!);
  }

  void forceLoad() {
    if (isStopped.value) {
      onManualRestart();
    }
  }

  void noScaleListener() {
    _animationRetries = 0;
    stopLoading(reason: .reset);
    _fallbackUrl = null;
    _attemptedUrls.clear();
    initViewer(false);
  }

  void toggleQualityListener() {
    _animationRetries = 0;
    stopLoading(reason: .reset);
    _fallbackUrl = null;
    _attemptedUrls.clear();
    initViewer(false);
  }

  void calcWidthLimit(double maxWidth) {
    if (!mounted) {
      return;
    }

    widthLimit = settingsHandler.disableImageScaling
        ? null
        : (maxWidth * MediaQuery.devicePixelRatioOf(NavigationHandler.instance.navContext) * 2).round();
  }

  Future<ImageProvider?> getImageProvider({
    required int loadGeneration,
    bool withCaptchaCheck = false,
  }) async {
    final url = _fallbackUrl ?? (useFullImage ? widget.booruItem.fileURL : widget.booruItem.sampleURL);
    _activeUrl = url;
    _attemptedUrls.add(url);
    imageFolder = url == widget.booruItem.thumbnailURL
        ? 'thumbnails'
        : (url == widget.booruItem.sampleURL && !useFullImage || _fallbackUrl != null)
        ? 'samples'
        : 'media';
    cancelToken?.cancel();
    final token = CancelToken();
    cancelToken = token;
    final headers = await Tools.getFileCustomHeaders(widget.booru, item: widget.booruItem, checkForReferer: true);
    if (!_isCurrentLoad(loadGeneration)) return null;
    final downloadTrace = kReleaseMode ? null : (developer.TimelineTask()..start('Image viewer download'));
    final download = await NetworkImageLoader.downloadFile(
      ImageDownloadRequest(
        url: url,
        cacheFolder: imageFolder,
        fileNameExtras: widget.booruItem.fileNameExtras,
        withCache: settingsHandler.mediaCache,
        headers: headers,
        withCaptchaCheck: withCaptchaCheck,
      ),
      cancelToken: token,
      onCacheDetected: (detected) {
        if (_isCurrentLoad(loadGeneration)) isFromCache.value = detected;
      },
      onReceiveProgress: (count, total) {
        if (_isCurrentLoad(loadGeneration)) onBytesAdded(count, total);
      },
    ).whenComplete(() => downloadTrace?.finish());
    if (!_isCurrentLoad(loadGeneration)) {
      await download.dispose();
      return null;
    }
    _download = download;
    // Disposal can race with asynchronous metadata reads or the region copy.
    final preparationSource = download.retain();
    final preparationTrace = kReleaseMode ? null : (developer.TimelineTask()..start('Image viewer preparation'));
    try {
      final isAvif = url.toLowerCase().contains('.avif');
      Size? sourceSize;
      final canTryRegions = Platform.isAndroid && !widget.booruItem.mediaType.value.isAnimation && !isAvif;
      if (canTryRegions) {
        sourceSize = await ImageMemoryManager.instance.runDecode(
          ImageMemoryManager.maxEncodedBytes + 16 * 1024 * 1024,
          () => ServiceHandler.getImageRegionInfo(download.file.path),
          cancelToken: token,
          isForeground: () => mounted && isViewed.value,
        );
      }
      if (!_isCurrentLoad(loadGeneration)) return null;
      final regionSize = sourceSize;
      sourceSize ??= await NetworkImageLoader.inspectImageSize(download.file, cancelToken: token, isAvif: isAvif);
      preparationTrace?.instant('metadataReady');
      if (!_isCurrentLoad(loadGeneration)) return null;
      final heightLimit = settingsHandler.preloadHeight;
      if (heightLimit != 0 && sourceSize.height >= heightLimit && !blockPreloadState.isIgnore) {
        stopLoading(
          reason: .tooBig,
          details:
              '${context.loc.media.loading.fileSize(size: '${sourceSize.width.toInt()}x${sourceSize.height.toInt()}')}\n'
              '${context.loc.media.loading.sizeLimit(limit: '...x${heightLimit.toFormattedString()}')}',
        );
        return null;
      }
      if (regionSize != null && regionSize.height >= 4096 && regionSize.height > regionSize.width * 2) {
        // Owned temporary downloads already have the required lifetime. Cache
        // files still need a private copy to survive cache maintenance.
        Directory? directory;
        DownloadedImageFile? retained;
        try {
          if (download.ownsFile) {
            retained = preparationSource.retain();
          } else {
            directory = await Directory.systemTemp.createTemp('image-regions-');
            final copyTrace = kReleaseMode ? null : (developer.TimelineTask()..start('Image region source copy'));
            final file = await download.file
                .copy('${directory.path}${Platform.pathSeparator}image')
                .whenComplete(() => copyTrace?.finish());
            retained = DownloadedImageFile(file, ownsFile: true, temporaryDirectory: directory);
          }
          if (!_isCurrentLoad(loadGeneration)) {
            await retained.dispose();
            return null;
          }
          _regionSource = RegionImageSource(retained, regionSize);
        } catch (_) {
          if (retained != null) {
            await retained.dispose();
          } else if (directory != null) {
            try {
              await File('${directory.path}${Platform.pathSeparator}image').delete();
            } on FileSystemException catch (_) {}
            try {
              await directory.delete();
            } on FileSystemException catch (_) {}
          }
          rethrow;
        }
        _download = null;
        await download.dispose();
        if (!_isCurrentLoad(loadGeneration)) return null;
        tiledSize = regionSize;
        isTiled = true;
        return null;
      }

      // A viewer opens a fresh playback session, even when a thumbnail has
      // already played a finite animation to its final frame.
      final playbackKey = widget.booruItem.mediaType.value.isAnimation ? Object() : null;
      ImageProvider provider = isAvif
          ? CustomNetworkAvifImage(
              url,
              playbackKey: playbackKey,
              isForeground: () => mounted && isViewed.value,
              localFilePath: download.file.path,
              preparedSource: download,
              cancelToken: token,
              headers: headers,
              withCache: settingsHandler.mediaCache,
              cacheFolder: imageFolder,
              fileNameExtras: widget.booruItem.fileNameExtras,
            )
          : CustomNetworkImage(
              url,
              playbackKey: playbackKey,
              isForeground: () => mounted && isViewed.value,
              localFilePath: download.file.path,
              preparedSource: download,
              cancelToken: token,
              headers: headers,
              withCache: settingsHandler.mediaCache,
              cacheFolder: imageFolder,
              fileNameExtras: widget.booruItem.fileNameExtras,
            );
      // Keep the user's width/quality preference. Provider-level pixel and memory
      // limits still apply to desktop, animation and explicitly unscaled images.
      if (!settingsHandler.disableImageScaling && !widget.booruItem.isNoScale.value && (widthLimit ?? 0) > 0) {
        provider = SafeResizeImage(provider, width: widthLimit, policy: ResizeImagePolicy.fit, allowUpscaling: false);
      }
      return provider;
    } finally {
      preparationTrace?.finish();
      await preparationSource.dispose();
    }
  }

  void stopLoading({
    required ViewerStopReason reason,
    String? title,
    String? details,
  }) {
    disposables();

    total.value = 0;
    received.value = 0;

    startedAt.value = 0;

    isLoaded.value = false;
    isFromCache.value = false;
    isStopped.value = true;
    _updateAnimationFocus();
    stopReason.value = reason;
    stopDetails.value = '${title != null ? '$title\n' : ''}${details ?? ''}';

    if (reason.isTooBig) {
      blockPreloadState = .tooBig;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      viewerHandler.setStopped(widget.key, true);
      viewerHandler.setLoaded(widget.key, false);
    });
  }

  @override
  void dispose() {
    ImageMemoryManager.instance.setAnimationViewerActive(this, false);
    disposables();

    viewStateSubscription?.cancel();
    scaleStateSubscription?.cancel();
    scaleController.dispose();
    viewController.dispose();
    disposeNotifiers();

    viewerHandler.removeViewed(widget.key);
    super.dispose();
  }

  void disposables() {
    _loadGeneration++;
    _removeImageStreamListener();

    if (!(cancelToken?.isCancelled ?? true)) {
      cancelToken?.cancel();
    }
    cancelToken = null;

    if (!(loadItemCancelToken?.isCancelled ?? true)) {
      loadItemCancelToken?.cancel();
    }
    loadItemCancelToken = null;

    _regionSource?.dispose();
    _regionSource = null;
    final download = _download;
    _download = null;
    if (download != null) unawaited(download.dispose());
    isTiled = false;
    isTilingProcessing.value = null;
    tiledSize = null;

    // Viewer providers have their own playback identity; no thumbnail relies
    // on keeping a completed viewer animation in the cache.
    unawaited(mainProvider.value?.evict());

    mainProvider.value = null;

    widget.booruItem.isNoScale.removeListener(noScaleListener);
    widget.booruItem.toggleQuality.removeListener(toggleQualityListener);
  }

  bool _isCurrentLoad(int loadGeneration) {
    return mounted && loadGeneration == _loadGeneration;
  }

  void _removeImageStreamListener() {
    final ImageStreamListener? listener = imageListener;
    if (listener != null) {
      imageStream?.removeListener(listener);
    }
    imageStream = null;
    imageListener = null;
  }

  void disposeNotifiers() {
    total.dispose();
    received.dispose();
    startedAt.dispose();
    isFirstBuild.dispose();
    isLoaded.dispose();
    isViewed.dispose();
    isFromCache.dispose();
    isZoomed.dispose();
    isStopped.dispose();
    showLoading.dispose();
    stopReason.dispose();
    stopDetails.dispose();
    mainProvider.dispose();
    isTilingProcessing.dispose();
  }

  // debug functions
  void onScaleStateChanged(PhotoViewScaleState scaleState) {
    // print(scaleState);

    // manual zoom || double tap || double tap AFTER double tap
    isZoomed.value =
        scaleState == PhotoViewScaleState.zoomedIn ||
        scaleState == PhotoViewScaleState.covering ||
        scaleState == PhotoViewScaleState.originalSize;

    viewerHandler.setZoomed(widget.key, isZoomed.value);
  }

  void onViewStateChanged(PhotoViewControllerValue viewState) {
    // print(viewState);
    viewerHandler.setViewValue(widget.key, viewState);
  }

  void resetZoom() {
    scaleController.scaleState = PhotoViewScaleState.initial;
    viewerHandler.setZoomed(widget.key, false);
  }

  void scrollZoomImage(double value) {
    final double upperLimit = min(8, (viewController.scale ?? 1) + (value / 200));
    // zoom on which image fits to container can be less than limit
    // therefore don't clump the value to lower limit if we are zooming in to avoid unnecessary zoom jumps
    final double lowerLimit = value > 0 ? upperLimit : max(0.75, upperLimit);

    // if zooming out and zoom is smaller than limit - reset to container size
    // TODO minimal scale to fit can be different from limit
    if (lowerLimit == 0.75 && value < 0) {
      scaleController.scaleState = PhotoViewScaleState.initial;
    } else {
      viewController.scale = lowerLimit;
    }
  }

  void doubleTapZoom() {
    if (!isLoaded.value) return;
    scaleController.scaleState = PhotoViewScaleState.covering;
  }

  Future<void> onManualRestart() async {
    _ignoreTagsForLoad = true;
    widget.onReveal?.call();
    _animationRetries = 0;
    _fallbackUrl = null;
    _attemptedUrls.clear();
    final int loadGeneration = ++_loadGeneration;
    if (blockPreloadState.isTooBig) {
      blockPreloadState = .ignore;
    }

    isStopped.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentLoad(loadGeneration)) return;

      viewerHandler.setStopped(widget.key, false);
    });

    startedAt.value = DateTime.now().millisecondsSinceEpoch;

    final bool shouldUpdate = switch (stopReason.value) {
      .error => true,
      _ => false,
    };
    bool shouldDoCaptchaCheck = false;
    if (shouldUpdate) {
      loadItemCancelToken = CancelToken();
      final CancelToken itemLoadCancelToken = loadItemCancelToken!;
      final updateRes = await tryToLoadAndUpdateItem(
        widget.booruItem,
        itemLoadCancelToken,
      );

      if (!_isCurrentLoad(loadGeneration) ||
          itemLoadCancelToken.isCancelled ||
          !identical(loadItemCancelToken, itemLoadCancelToken)) {
        return;
      }

      shouldDoCaptchaCheck = updateRes != true;

      if (updateRes != true && widget.booru.baseURL?.isNotEmpty == true) {
        await DioNetwork.get(
          widget.booru.baseURL ?? '',
          headers: await Tools.getFileCustomHeaders(
            widget.booru,
            item: widget.booruItem,
            checkForReferer: true,
          ),
          customInterceptor: (dio) => DioNetwork.captchaInterceptor(
            dio,
            customUserAgent: Tools.appUserAgent,
          ),
        );
        if (!_isCurrentLoad(loadGeneration)) return;
      }
    }

    await initViewer(
      true,
      withCaptchaCheck: shouldDoCaptchaCheck,
    );
  }

  Future<void> onManualStop() async {
    stopLoading(reason: .user);
  }

  @override
  Widget build(BuildContext context) {
    return PreserveMediaAnimations(
      child: Material(
        // without this every text element will have broken styles on first frames
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([isTilingProcessing, isLoaded, isViewed]),
              builder: (context, child) {
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: (isLoaded.value && isProviderLoaded) ? 0 : 1,
                  child: Hero(
                    tag: 'imageHero${isViewed.value ? '' : '-ignore-'}${widget.booruItem.hashCode}',
                    child: child!,
                  ),
                );
              },
              child: Thumbnail(
                item: widget.booruItem,
                booru: widget.booru,
                isStandalone: false,
                useHero: false,
              ),
            ),
            //
            ValueListenableBuilder(
              valueListenable: showLoading,
              builder: (context, showLoadingVal, child) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: showLoadingVal ? child : const SizedBox.shrink(),
                );
              },
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  isTilingProcessing,
                  isLoaded,
                  isViewed,
                  isStopped,
                  isFromCache,
                  stopReason,
                  stopDetails,
                ]),
                builder: (context, _) {
                  return MediaLoading(
                    item: widget.booruItem,
                    hasProgress: true,
                    isFromCache: isFromCache.value,
                    isDone: isLoaded.value && isProviderLoaded,
                    isTooBig: blockPreloadState.isTooBig,
                    isStopped: isStopped.value,
                    stopReason: stopReason.value,
                    stopDetails: stopDetails.value,
                    isViewed: isViewed.value,
                    total: total,
                    received: received,
                    startedAt: startedAt,
                    onRestart: onManualRestart,
                    onStop: onManualStop,
                  );
                },
              ),
            ),
            //
            Listener(
              onPointerSignal: (pointerSignal) {
                if (!isProviderLoaded || !PlatformExt.isDesktop) {
                  return;
                }
                if (pointerSignal is PointerScrollEvent) {
                  scrollZoomImage(pointerSignal.scrollDelta.dy);
                }
              },
              child: ImageFiltered(
                enabled: settingsHandler.blurImages,
                imageFilter: ImageFilter.blur(
                  sigmaX: 40,
                  sigmaY: 40,
                  tileMode: TileMode.decal,
                ),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    isLoaded,
                    isTilingProcessing,
                    mainProvider,
                    isViewed,
                  ]),
                  builder: (context, _) {
                    final loadGeneration = _loadGeneration;
                    return AnimatedOpacity(
                      opacity: (settingsHandler.shitDevice || isLoaded.value) ? 1 : 0,
                      duration: Duration(
                        milliseconds: (settingsHandler.appMode.value.isDesktop || isViewed.value) ? 50 : 300,
                      ),
                      child: AnimatedSwitcher(
                        // Outgoing GIF listeners must release their codec now,
                        // not after a fade that can outlast the next GIF's retry.
                        key: widget.booruItem.mediaType.value.isAnimation
                            ? ValueKey((isViewed.value, mainProvider.value))
                            : null,
                        duration: Duration(
                          milliseconds: (settingsHandler.appMode.value.isDesktop || isViewed.value) ? 50 : 300,
                        ),
                        child: !isProviderLoaded
                            ? const SizedBox.shrink()
                            : ((isTiled && _regionSource != null)
                                  ? PhotoView.customChild(
                                      childSize: tiledSize,
                                      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                                      customSize: MediaQuery.sizeOf(context),
                                      minScale: PhotoViewComputedScale.contained,
                                      maxScale: PhotoViewComputedScale.covered * 8,
                                      initialScale: PhotoViewComputedScale.contained,
                                      enableRotation: settingsHandler.allowRotation,
                                      basePosition: Alignment.center,
                                      controller: viewController,
                                      scaleStateController: scaleController,
                                      child: RegionImageView(
                                        key: ObjectKey(_regionSource),
                                        source: _regionSource!,
                                        controller: viewController,
                                        viewport: MediaQuery.sizeOf(context),
                                        isViewed: isViewed.value,
                                        onReady: () {
                                          if (!_isCurrentLoad(loadGeneration) || _regionSource == null) return;
                                          if (!isLoaded.value) resetZoom();
                                          isLoaded.value = true;
                                          viewerHandler.setLoaded(widget.key, true);
                                        },
                                        onError: (error) {
                                          if (_isCurrentLoad(loadGeneration)) {
                                            onError(
                                              error is ImageMemoryException
                                                  ? error
                                                  : const ImageMemoryException(
                                                      'Unable to decode bounded image regions',
                                                    ),
                                            );
                                          }
                                        },
                                      ),
                                    )
                                  : PhotoView(
                                      imageProvider: mainProvider.value,
                                      gaplessPlayback: true,
                                      loadingBuilder: (context, event) {
                                        return const SizedBox.shrink();
                                      },
                                      errorBuilder: (_, error, _) {
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (_isCurrentLoad(loadGeneration)) {
                                            onError(error);
                                          }
                                        });
                                        return const SizedBox.shrink();
                                      },
                                      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                                      // to avoid flickering during hero transition
                                      // TODO will cause scaling issues on desktop, fix when we'll get back to it
                                      customSize: MediaQuery.sizeOf(context),
                                      // TODO FilterQuality.high somehow leads to a worse looking image on desktop
                                      filterQuality: FilterQuality.medium,
                                      minScale: PhotoViewComputedScale.contained,
                                      maxScale: PhotoViewComputedScale.covered * 8,
                                      initialScale: PhotoViewComputedScale.contained,
                                      enableRotation: settingsHandler.allowRotation,
                                      basePosition: Alignment.center,
                                      controller: viewController,
                                      scaleStateController: scaleController,
                                    )),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
