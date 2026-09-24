import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/thumbnail_loading.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/preview/shimmer_builder.dart';

class Thumbnail extends StatefulWidget {
  const Thumbnail({
    required this.item,
    this.booru,
    this.isStandalone = false,
    this.useHero = true,
    super.key,
  });

  final BooruItem item;
  final Booru? booru;

  /// set to true when used in a list
  final bool isStandalone;
  final bool useHero;

  @override
  State<Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<Thumbnail> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  final ValueNotifier<int> total = ValueNotifier(0), received = ValueNotifier(0), startedAt = ValueNotifier(0);
  int restartedCount = 0;
  final ValueNotifier<bool?> isFromCache = ValueNotifier(null);
  final ValueNotifier<bool> isFirstBuild = ValueNotifier(true);
  final ValueNotifier<bool> isFailed = ValueNotifier(false);
  final ValueNotifier<bool> isLoaded = ValueNotifier(false);
  final ValueNotifier<bool> isLoadedExtra = ValueNotifier(false);
  final ValueNotifier<bool> useExtra = ValueNotifier(false);
  final ValueNotifier<bool> failedRendering = ValueNotifier(false);
  final ValueNotifier<String?> errorCode = ValueNotifier(null);
  CancelToken? mainCancelToken, extraCancelToken, loadItemCancelToken;

  late String currentUrl;

  Timer? debounceLoading;

  bool? isThumbQuality;
  late String thumbURL;
  late String thumbFolder;
  double? thumbWidth, thumbHeight;

  final ValueNotifier<ImageProvider?> mainProvider = ValueNotifier(null), extraProvider = ValueNotifier(null);
  ImageStreamListener? mainImageListener, extraImageListener;
  ImageStream? mainImageStream, extraImageStream;
  int _loadGeneration = 0;

  bool isBlurred = true;
  bool _useSafeThumbnail = false;
  late bool _firstFrameOnly;
  bool _playbackUpdateScheduled = false;
  int? _rendererErrorGeneration;

  // Hidden thumbnails also use a tiny pixelated image on low-end devices.
  // Neither blur nor pixelation needs an active animation codec.
  bool get _isObscured => isBlurred && (settingsHandler.blurImages || widget.item.isHidden);

  bool get _shouldShowFirstFrame =>
      _isObscured ||
      !settingsHandler.gifsAsThumbnails ||
      ImageMemoryManager.instance.hasAnimationViewer ||
      ImageMemoryManager.instance.underPressure.value;

  @override
  void initState() {
    super.initState();

    currentUrl = widget.item.thumbnailURL;
    _firstFrameOnly = _shouldShowFirstFrame;
    ImageMemoryManager.instance.animationViewerActive.addListener(_updatePlaybackPolicy);
    ImageMemoryManager.instance.underPressure.addListener(_updatePlaybackPolicy);
  }

  void _updatePlaybackPolicy() {
    if (!mounted || _playbackUpdateScheduled) return;
    _playbackUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playbackUpdateScheduled = false;
      if (!mounted) return;
      final firstFrameOnly = _shouldShowFirstFrame;
      if (_firstFrameOnly == firstFrameOnly) return;
      _firstFrameOnly = firstFrameOnly;
      if (!firstFrameOnly) _useSafeThumbnail = false;
      if (isFirstBuild.value || !widget.item.mediaType.value.isAnimation) return;
      // Remove all owners of the animated stream before requesting its poster.
      // TickerMode alone pauses painting but retains the native GIF codec.
      unawaited(mainProvider.value?.evict());
      unawaited(extraProvider.value?.evict());
      mainProvider.value = null;
      extraProvider.value = null;
      unawaited(restartLoading());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(Thumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // force redraw on tab change
    if (oldWidget.item != widget.item) {
      _useSafeThumbnail = false;
      _firstFrameOnly = _shouldShowFirstFrame;
      currentUrl = widget.item.thumbnailURL;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        await restartLoading();
      });
    }
  }

  Future<ImageProvider> getImageProvider(
    bool isMain, {
    required int loadGeneration,
    bool withCaptchaCheck = false,
  }) async {
    if (isMain) {
      mainCancelToken ??= CancelToken();
    } else {
      extraCancelToken ??= CancelToken();
    }
    final String url = isMain ? thumbURL : widget.item.thumbnailURL;
    final bool isAvif = url.contains('.avif');
    final ImageProvider provider = isAvif
        ? CustomNetworkAvifImage(
            url,
            firstFrameOnly: _firstFrameOnly,
            cancelToken: isMain ? mainCancelToken : extraCancelToken,
            headers: await Tools.getFileCustomHeaders(
              widget.booru,
              item: widget.item,
              checkForReferer: true,
            ),
            withCache: settingsHandler.thumbnailCache,
            cacheFolder: isMain ? thumbFolder : 'thumbnails',
            fileNameExtras: widget.item.fileNameExtras,
            sendTimeout: widget.isStandalone ? const Duration(seconds: 20) : null,
            receiveTimeout: widget.isStandalone ? const Duration(seconds: 20) : null,
            onError: isMain
                ? (error) {
                    if (_isCurrentLoad(loadGeneration)) {
                      onError(error);
                    }
                  }
                : null,
            onCacheDetected: (bool didDetectCache) {
              if (isMain && _isCurrentLoad(loadGeneration)) {
                isFromCache.value = didDetectCache;
              }
            },
            withCaptchaCheck: withCaptchaCheck,
          )
        : CustomNetworkImage(
            url,
            firstFrameOnly: _firstFrameOnly,
            cancelToken: isMain ? mainCancelToken : extraCancelToken,
            headers: await Tools.getFileCustomHeaders(
              widget.booru,
              item: widget.item,
              checkForReferer: true,
            ),
            withCache: settingsHandler.thumbnailCache,
            cacheFolder: isMain ? thumbFolder : 'thumbnails',
            fileNameExtras: widget.item.fileNameExtras,
            sendTimeout: widget.isStandalone ? const Duration(seconds: 20) : null,
            receiveTimeout: widget.isStandalone ? const Duration(seconds: 20) : null,
            onError: isMain
                ? (error) {
                    if (_isCurrentLoad(loadGeneration)) {
                      onError(error);
                    }
                  }
                : null,
            onCacheDetected: (bool didDetectCache) {
              if (isMain && _isCurrentLoad(loadGeneration)) {
                isFromCache.value = didDetectCache;
              }
            },
            withCaptchaCheck: withCaptchaCheck,
          );

    // on desktop devicePixelRatio is not working?
    final bool shouldResize = (thumbWidth != null || thumbHeight != null) && !PlatformExt.isDesktop;
    final bool shouldPixelate = widget.item.isHidden && settingsHandler.shitDevice;

    if (shouldResize || shouldPixelate) {
      return SafeResizeImage(
        provider,
        // when in low performance mode - resize hidden images to 10px to simulate blur effect
        width: shouldPixelate ? 10 : thumbWidth?.round(),
        height: shouldPixelate ? 10 : thumbHeight?.round(),
        policy: ResizeImagePolicy.fit,
        allowUpscaling: false,
      );
    }

    return provider;
  }

  void calcThumbWidth(BoxConstraints constraints) {
    if (!mounted) {
      return;
    }

    final double widthLimit = constraints.maxWidth * MediaQuery.devicePixelRatioOf(context);
    double thumbRatio = 1;
    final bool hasSizeData = widget.item.fileHeight != null && widget.item.fileWidth != null;

    if (!widget.isStandalone) {
      thumbWidth = widthLimit;
      return;
    }

    switch (settingsHandler.previewDisplay) {
      case .rectangle:
        thumbRatio = 16 / 9;
        thumbWidth = widthLimit;
        thumbHeight = widthLimit * thumbRatio;
        break;

      case .staggered:
        if (hasSizeData) {
          thumbRatio = widget.item.fileAspectRatio!;
          if (thumbRatio < 1) {
            // vertical image - resize to width
            thumbWidth = widthLimit;
          } else {
            // horizontal image - resize to height
            thumbHeight = widthLimit * thumbRatio;
          }
        } else {
          thumbRatio = 16 / 9;
          thumbWidth = widthLimit;
          thumbHeight = widthLimit * thumbRatio;
        }
        break;

      case .square:
        thumbWidth = widthLimit;
        thumbHeight = widthLimit;
        break;
    }
  }

  void onBytesAdded(int receivedNew, int? totalNew) {
    received.value = receivedNew;
    total.value = totalNew ?? 0;
  }

  void onError(Object error) {
    if (error is ImageMemoryException) {
      failedRendering.value = false; // A valid oversized file must stay on disk.
      if (!_useSafeThumbnail && widget.item.thumbnailURL.isNotEmpty && thumbURL != widget.item.thumbnailURL) {
        _useSafeThumbnail = true;
        unawaited(restartLoading());
      } else {
        isFailed.value = true;
        errorCode.value = null;
      }
      return;
    }
    if (error is DioException && CancelToken.isCancel(error)) {
      //
    } else {
      final int retryLimit = (kDebugMode || settingsHandler.shitDevice) ? 4 : 8;

      if (restartedCount < retryLimit) {
        // attempt to reload N times with a 1s delay
        Debounce.debounce(
          tag: 'thumbnail_reload_${widget.item.hashCode}',
          callback: () async {
            await restartLoading();
            restartedCount++;
          },
          duration: Duration(milliseconds: settingsHandler.shitDevice ? 1000 : 500),
        );
      } else {
        isFailed.value = true;
        if (error is DioException) {
          errorCode.value = error.response?.statusCode?.toString();
        } else {
          errorCode.value = null;
        }
      }
    }
  }

  void _reportLateFrameError(Object error, StackTrace? stack, int generation) {
    // Initial failures belong to the loading listener. After frame one, the
    // renderer owns animation activity and forwards terminal frame failures.
    if (!isLoaded.value || mainImageListener != null || _rendererErrorGeneration == generation) return;
    _rendererErrorGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentLoad(generation)) return;
      failedRendering.value = error is! DioException && error is! ImageMemoryException;
      Logger.Inst().log(
        'Error decoding thumbnail frame: $error',
        'Thumbnail',
        'build',
        LogTypes.imageLoadingError,
        s: stack,
      );
      onError(error);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void selectThumbProvider({
    bool withCaptchaCheck = false,
  }) {
    final int loadGeneration = ++_loadGeneration;
    startedAt.value = DateTime.now().millisecondsSinceEpoch;

    isThumbQuality =
        _useSafeThumbnail ||
        settingsHandler.previewMode.isThumbnail ||
        (widget.item.mediaType.value.isVideo ||
            widget.item.mediaType.value.isNeedToGuess ||
            widget.item.mediaType.value.isNeedToLoadItem) ||
        (!widget.isStandalone && widget.item.fileURL == widget.item.sampleURL);
    thumbURL = isThumbQuality == true ? widget.item.thumbnailURL : widget.item.sampleURL;
    thumbFolder = (isThumbQuality == true || thumbURL == widget.item.thumbnailURL) ? 'thumbnails' : 'samples';
    useExtra.value = isThumbQuality == false && !widget.item.isHidden && !settingsHandler.shitDevice;

    // delay loading a little to improve performance when scrolling fast, ignore delay if it's a standalone widget (i.e. not in a list)
    debounceLoading = Timer(
      Duration(milliseconds: widget.isStandalone ? 200 : 0),
      () => startDownloading(
        loadGeneration: loadGeneration,
        withCaptchaCheck: withCaptchaCheck,
      ),
    );
    return;
  }

  Future<void> startDownloading({
    required int loadGeneration,
    bool withCaptchaCheck = false,
  }) async {
    final ImageProvider newMainProvider = await getImageProvider(
      true,
      loadGeneration: loadGeneration,
      withCaptchaCheck: withCaptchaCheck,
    );

    if (!_isCurrentLoad(loadGeneration)) {
      return;
    }

    mainProvider.value = newMainProvider;
    _removeMainImageStreamListener();
    mainImageStream = mainProvider.value!.resolve(ImageConfiguration.empty);
    mainImageListener = ImageStreamListener(
      (imageInfo, syncCall) {
        // This listener owns a clone; cache and rendering handles remain reusable.
        imageInfo.dispose();
        if (!_isCurrentLoad(loadGeneration)) return;

        isLoaded.value = true;
        final stream = mainImageStream;
        scheduleMicrotask(() {
          if (identical(mainImageStream, stream)) _removeMainImageStreamListener();
        });
      },
      onChunk: (event) {
        if (!_isCurrentLoad(loadGeneration)) return;

        onBytesAdded(event.cumulativeBytesLoaded, event.expectedTotalBytes);
      },
      onError: (e, s) {
        if (!_isCurrentLoad(loadGeneration)) return;

        if (e is! DioException && e is! ImageMemoryException) {
          failedRendering.value = true;
        }
        Logger.Inst().log(
          'Error loading thumbnail: ${widget.item.sampleURL} ${widget.item.thumbnailURL}',
          'Thumbnail',
          'build',
          LogTypes.imageLoadingError,
          s: s,
        );
        onError(e);
      },
    );
    mainImageStream!.addListener(mainImageListener!);

    if (useExtra.value) {
      final ImageProvider newExtraProvider = await getImageProvider(
        false,
        loadGeneration: loadGeneration,
      );

      if (!_isCurrentLoad(loadGeneration)) {
        return;
      }

      extraProvider.value = newExtraProvider;
      _removeExtraImageStreamListener();
      extraImageStream = extraProvider.value!.resolve(ImageConfiguration.empty);
      extraImageListener = ImageStreamListener(
        (imageInfo, syncCall) {
          // This listener owns a clone; cache and rendering handles remain reusable.
          imageInfo.dispose();
          if (!_isCurrentLoad(loadGeneration)) return;

          isLoadedExtra.value = true;
          final stream = extraImageStream;
          scheduleMicrotask(() {
            if (identical(extraImageStream, stream)) _removeExtraImageStreamListener();
          });
        },
        onError: (e, s) {
          if (!_isCurrentLoad(loadGeneration)) return;

          if (e is! DioException && e is! ImageMemoryException) {
            failedRendering.value = true;
          }
          Logger.Inst().log(
            'Error loading extra thumbnail: ${widget.item.thumbnailURL}',
            'Thumbnail',
            'build',
            LogTypes.imageLoadingError,
            s: s,
          );
        },
      );
      extraImageStream!.addListener(extraImageListener!);
    }
  }

  Future<void> restartLoading({bool withItemLoad = false}) async {
    if (failedRendering.value) {
      failedRendering.value = false;
      unawaited(cleanProviderCache());
    }

    disposables();

    total.value = 0;
    received.value = 0;
    startedAt.value = 0;

    isLoaded.value = false;
    isLoadedExtra.value = false;
    isFromCache.value = null;
    isFailed.value = false;
    errorCode.value = null;

    bool? updateRes;
    if (withItemLoad) {
      loadItemCancelToken = CancelToken();
      final CancelToken itemLoadCancelToken = loadItemCancelToken!;
      updateRes = await tryToLoadAndUpdateItem(
        widget.item,
        itemLoadCancelToken,
      );

      if (!mounted || itemLoadCancelToken.isCancelled || !identical(loadItemCancelToken, itemLoadCancelToken)) {
        return;
      }
    }

    selectThumbProvider(
      withCaptchaCheck: withItemLoad && updateRes != true,
    );
  }

  Future<void> cleanProviderCache() async {
    for (final provider in [
      if (mainProvider.value != null && mainProvider.value is ResizeImage)
        (mainProvider.value! as ResizeImage).imageProvider
      else
        mainProvider.value,
      //
      if (extraProvider.value != null && extraProvider.value is ResizeImage)
        (extraProvider.value! as ResizeImage).imageProvider
      else
        extraProvider.value,
    ]) {
      if (provider == null) {
        continue;
      }

      switch (provider) {
        case CustomNetworkImage _:
          await provider.deleteCacheFile();
          break;
      }
    }
  }

  @override
  void dispose() {
    ImageMemoryManager.instance.animationViewerActive.removeListener(_updatePlaybackPolicy);
    ImageMemoryManager.instance.underPressure.removeListener(_updatePlaybackPolicy);
    disposables();
    disposeNotifiers();
    super.dispose();
  }

  void disposables() {
    _loadGeneration++;
    _removeMainImageStreamListener();
    _removeExtraImageStreamListener();

    if (!(mainCancelToken?.isCancelled ?? true)) {
      mainCancelToken?.cancel();
    }
    mainCancelToken = null;

    if (!(extraCancelToken?.isCancelled ?? true)) {
      extraCancelToken?.cancel();
    }
    extraCancelToken = null;

    if (!(loadItemCancelToken?.isCancelled ?? true)) {
      loadItemCancelToken?.cancel();
    }
    loadItemCancelToken = null;

    // evict from memory cache only when in grid
    if (widget.isStandalone) {
      mainProvider.value?.evict();
      mainProvider.value = null;
      extraProvider.value?.evict();
      extraProvider.value = null;
    }

    debounceLoading?.cancel();
    debounceLoading = null;
    Debounce.cancel('thumbnail_reload_${widget.item.hashCode}');
  }

  bool _isCurrentLoad(int loadGeneration) {
    return mounted && loadGeneration == _loadGeneration;
  }

  void _removeMainImageStreamListener() {
    final ImageStreamListener? listener = mainImageListener;
    if (listener != null) {
      mainImageStream?.removeListener(listener);
    }
    mainImageListener = null;
    mainImageStream = null;
  }

  void _removeExtraImageStreamListener() {
    final ImageStreamListener? listener = extraImageListener;
    if (listener != null) {
      extraImageStream?.removeListener(listener);
    }
    extraImageListener = null;
    extraImageStream = null;
  }

  void disposeNotifiers() {
    total.dispose();
    received.dispose();
    startedAt.dispose();
    isFromCache.dispose();
    isFirstBuild.dispose();
    isFailed.dispose();
    isLoaded.dispose();
    isLoadedExtra.dispose();
    useExtra.dispose();
    failedRendering.dispose();
    errorCode.dispose();
    mainProvider.dispose();
    extraProvider.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Blur/filter changes and local reveal actions rebuild this widget.
    // Refresh both thumbnail providers after the frame when their policy changes.
    if (_firstFrameOnly != _shouldShowFirstFrame) _updatePlaybackPolicy();

    Widget imageStack = LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          calcThumbWidth(constraints);
          if (isFirstBuild.value) {
            isFirstBuild.value = false;
            selectThumbProvider();
          }

          if (currentUrl != widget.item.thumbnailURL) {
            currentUrl = widget.item.thumbnailURL;
            restartLoading();
          }
        });

        // take smallest dimension for hidden icon container
        final double iconSize =
            (constraints.maxHeight < constraints.maxWidth ? constraints.maxHeight : constraints.maxWidth) * 0.75;

        final double blurAmount = (settingsHandler.blurImages && !widget.isStandalone)
            ? 40
            : max(constraints.maxWidth * (widget.isStandalone ? 0.1 : 0.06), 10);

        return Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isStandalone)
              ValueListenableBuilder(
                valueListenable: isFailed,
                builder: (context, isFailed, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    color: isFailed ? Colors.red.withValues(alpha: 0.1) : Colors.transparent,
                  );
                },
              ),
            //
            ValueListenableBuilder(
              valueListenable: useExtra,
              builder: (context, useExtra, child) {
                // fetch small low quality thumbnail while loading a sample
                return useExtra ? child! : const SizedBox.shrink();
              },
              child: ValueListenableBuilder(
                valueListenable: isLoadedExtra,
                builder: (context, isLoadedExtra, child) {
                  return AnimatedOpacity(
                    // fade in image
                    opacity: (!widget.isStandalone || isLoadedExtra) ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
                child: ImageFiltered(
                  enabled: settingsHandler.blurImages || widget.item.isHidden,
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurAmount,
                    sigmaY: blurAmount,
                    tileMode: TileMode.decal,
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: extraProvider,
                    builder: (context, extraProvider, _) {
                      Widget child = const SizedBox.shrink();

                      if (extraProvider != null) {
                        child = Image(
                          image: extraProvider,
                          fit: widget.isStandalone ? BoxFit.cover : BoxFit.contain,
                          isAntiAlias: true,
                          filterQuality: FilterQuality.medium,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                            if (widget.isStandalone) {
                              return Icon(
                                Icons.broken_image,
                                size: 30,
                                color: Colors.yellow.withValues(alpha: 0.5),
                              );
                            } else {
                              return const SizedBox.shrink();
                            }
                          },
                        );
                      }

                      return AnimatedSwitcher(
                        // Drop old animation owners immediately on policy changes.
                        key: ValueKey(_firstFrameOnly),
                        duration: Duration(milliseconds: widget.isStandalone ? 100 : 0),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            ),
            //
            ValueListenableBuilder(
              valueListenable: isLoaded,
              builder: (context, isLoaded, child) {
                return AnimatedOpacity(
                  // fade in image
                  opacity: (settingsHandler.shitDevice || !widget.isStandalone || isLoaded) ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: child,
                );
              },
              child: GestureDetector(
                // TODO reenable after filters rework (when blur/hide will be separate for each filter)
                // ignore: dead_code
                onTap: false && (widget.item.isHidden && !settingsHandler.shitDevice && widget.isStandalone)
                    // ignore: dead_code
                    ? () => setState(() => isBlurred = !isBlurred)
                    : null,
                child: ImageFiltered(
                  enabled:
                      isBlurred &&
                      (settingsHandler.blurImages || (widget.item.isHidden && !settingsHandler.shitDevice)),
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurAmount,
                    sigmaY: blurAmount,
                    tileMode: TileMode.decal,
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: mainProvider,
                    builder: (context, mainProvider, _) {
                      final generation = _loadGeneration;
                      Widget child = const SizedBox.shrink();

                      if (mainProvider != null) {
                        child = TickerMode(
                          enabled: !_shouldShowFirstFrame,
                          child: Image(
                            image: mainProvider,
                            fit: widget.isStandalone ? BoxFit.cover : BoxFit.contain,
                            isAntiAlias: true,
                            filterQuality: FilterQuality.medium,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                              _reportLateFrameError(exception, stackTrace, generation);
                              if (widget.isStandalone) {
                                return Icon(
                                  Icons.broken_image,
                                  size: 30,
                                  color: Colors.white.withValues(alpha: 0.5),
                                );
                              } else {
                                return const SizedBox.shrink();
                              }
                            },
                          ),
                        );
                      }

                      return AnimatedSwitcher(
                        key: ValueKey(_firstFrameOnly),
                        duration: Duration(milliseconds: widget.isStandalone ? 200 : 0),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
            ),
            //
            if (widget.isStandalone && !settingsHandler.shitDevice)
              ListenableBuilder(
                listenable: Listenable.merge([isLoaded, isLoadedExtra, isFailed]),
                builder: (context, _) {
                  final bool isAnyLoaded = isLoaded.value || isLoadedExtra.value;
                  final bool showShimmer = !isAnyLoaded && !isFailed.value;

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: showShimmer ? const ShimmerCard() : const SizedBox.shrink(),
                  );
                },
              ),
            //
            if (widget.isStandalone && widget.item.isHidden)
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(iconSize * 0.1),
                ),
                width: iconSize,
                height: iconSize,
                child: const Icon(
                  CupertinoIcons.eye_slash,
                  color: Colors.white,
                ),
              ),
            if (widget.isStandalone)
              ValueListenableBuilder(
                valueListenable: isLoaded,
                builder: (context, isLoadedVal, child) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isLoadedVal ? const SizedBox.shrink() : child,
                  );
                },
                child: ListenableBuilder(
                  listenable: Listenable.merge([isLoaded, isFromCache, isFailed, errorCode]),
                  builder: (context, child) {
                    if (widget.booru == null) return const SizedBox.shrink();

                    final bool isFavOrDlsOrHasLoad =
                        widget.booru?.type?.isFavouritesOrDownloads == true ||
                        BooruHandlerFactory().getBooruHandler([widget.booru!], null).booruHandler.hasLoadItemSupport;

                    return ThumbnailLoading(
                      item: widget.item,
                      hasProgress: true,
                      isFromCache: isFromCache.value,
                      // if any of the thumbnails loaded - dont consider a failure
                      isDone: isLoaded.value || (isFailed.value && isLoadedExtra.value),
                      isFailed: isFailed.value && !isLoaded.value && !isLoadedExtra.value,
                      total: total,
                      received: received,
                      startedAt: startedAt,
                      retryText: isFavOrDlsOrHasLoad ? 'Tap to update or retry' : null,
                      retryIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 4,
                        children: isFavOrDlsOrHasLoad
                            ? const [
                                Icon(Icons.download),
                                Text('/', style: TextStyle(fontSize: 20)),
                                Icon(Icons.refresh),
                              ]
                            : const [
                                Icon(Icons.refresh),
                              ],
                      ),
                      restartAction: () async {
                        restartedCount = 0;

                        await restartLoading(withItemLoad: isFavOrDlsOrHasLoad);
                      },
                      errorCode: errorCode.value,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );

    imageStack = Material(
      color: Colors.transparent,
      child: imageStack,
    );

    if (widget.isStandalone && widget.useHero) {
      return HeroMode(
        enabled: settingsHandler.enableHeroTransitions && !settingsHandler.shitDevice,
        child: Hero(
          tag: 'imageHero${widget.item.hashCode}',
          placeholderBuilder: (BuildContext context, Size heroSize, Widget child) {
            // keep building the image since the images can be visible in the
            // background of the image gallery
            return child;
          },
          child: imageStack,
        ),
      );
    } else {
      return imageStack;
    }
  }
}

/// Returns true if successful, false on error and null on skip
Future<bool?> tryToLoadAndUpdateItem(
  BooruItem item,
  CancelToken cancelToken,
) async {
  try {
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;
    final Booru? possibleBooru = SettingsHandler.instance.booruList.firstWhereOrNull((e) {
      final booruHost = Uri.tryParse(e.baseURL ?? '')?.host;

      return (itemPostHost?.isNotEmpty == true &&
              booruHost?.isNotEmpty == true &&
              (itemPostHost! == booruHost! ||
                  switch (e.type) {
                    BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                    BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                    _ => false,
                  })) ||
          (itemFileHost?.isNotEmpty == true && booruHost?.isNotEmpty == true && itemFileHost! == booruHost!);
    });

    if (possibleBooru != null) {
      final handler = BooruHandlerFactory().getBooruHandler([possibleBooru], null).booruHandler;
      if (handler.hasLoadItemSupport) {
        final result = await handler.loadItem(
          item: item,
          cancelToken: cancelToken,
          withCapcthaCheck: true,
        );

        if (!result.failed &&
            result.item != null &&
            (result.item?.isSnatched.value == true || result.item?.isFavourite.value == true)) {
          unawaited(
            SettingsHandler.instance.dbHandler.updateBooruItem(
              result.item!,
              BooruUpdateMode.urlUpdate,
            ),
          );
          return true;
        } else {
          return false;
        }
      }
    }
    return null;
  } catch (_) {}
  return null;
}
