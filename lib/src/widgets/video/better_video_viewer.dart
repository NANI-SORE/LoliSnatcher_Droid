import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:better_player/better_player.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/services/dio_downloader.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/media_loading.dart';
import 'package:lolisnatcher/src/widgets/common/transparent_pointer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/src/widgets/video/better_controls.dart';

// TODO custom controls
// TODO error handling
// TODO OOM crash when there are multiple videos?

class BetterVideoViewer extends StatefulWidget {
  const BetterVideoViewer(Key? key, this.booruItem, this.index, this.enableFullscreen) : super(key: key);
  final BooruItem booruItem;
  final int index;
  final bool enableFullscreen;

  @override
  State<BetterVideoViewer> createState() => BetterVideoViewerState();
}

class BetterVideoViewerState extends State<BetterVideoViewer> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  PhotoViewController viewController = PhotoViewController();

  BetterPlayerDataSource? videoSource;
  BetterPlayerController? videoController;
  GlobalKey videoKey = GlobalKey();
  BetterPlayerControlsConfiguration? videoControlsConfig;

  // VideoPlayerValue latestValue;
  final RxInt total = 0.obs, received = 0.obs, startedAt = 0.obs;
  int lastViewedIndex = -1;
  int isTooBig = 0; // 0 = not too big, 1 = too big, 2 = too big, but allow downloading
  bool isFromCache = false, isStopped = false, isViewed = false, isZoomed = false;
  List<String> stopReason = [];

  StreamSubscription? indexListener;

  CancelToken? cancelToken, sizeCancelToken;
  DioDownloader? client, sizeClient;
  File? video;

  bool get isVideoInited => videoController?.isVideoInitialized() ?? false;

  @override
  void didUpdateWidget(BetterVideoViewer oldWidget) {
    // force redraw on item data change
    if (oldWidget.booruItem != widget.booruItem) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        killLoading([]);
        initVideo(false);
        updateState();
      });
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> downloadVideo() async {
    isStopped = false;
    startedAt.value = DateTime.now().millisecondsSinceEpoch;

    if (!settingsHandler.mediaCache) {
      // Media caching disabled - don't cache videos
      unawaited(getSize());
      unawaited(initPlayer());
      return;
    }
    switch (settingsHandler.videoCacheMode) {
      case 'Cache':
        // Cache to device from custom request
        break;

      case 'Stream+Cache':
        // Load and stream from default player network request, cache to device from custom request
        // TODO: change video handler to allow viewing and caching from single network request
        // unawaited(initPlayer());

        unawaited(getSize());
        unawaited(initPlayer());
        return;

      case 'Stream':
      default:
        // Only stream, notice the return
        unawaited(getSize());
        unawaited(initPlayer());
        return;
    }

    cancelToken = CancelToken();
    client = DioDownloader(
      widget.booruItem.fileURL,
      headers: await Tools.getFileCustomHeaders(searchHandler.currentBooru, checkForReferer: true),
      cancelToken: cancelToken,
      onProgress: onBytesAdded,
      onEvent: onEvent,
      onError: onError,
      onDoneFile: (File file) async {
        video = file;
        // save video from cache, but restate only if player is not initialized yet
        if (!isVideoInited) {
          unawaited(initPlayer());
          updateState();
        }
      },
      cacheEnabled: settingsHandler.mediaCache,
      cacheFolder: 'media',
      fileNameExtras: widget.booruItem.fileNameExtras,
    );
    unawaited(client!.runRequest());
    return;
  }

  Future<void> getSize() async {
    sizeCancelToken = CancelToken();
    sizeClient = DioDownloader(
      widget.booruItem.fileURL,
      headers: await Tools.getFileCustomHeaders(searchHandler.currentBooru, checkForReferer: true),
      cancelToken: sizeCancelToken,
      onEvent: onEvent,
      fileNameExtras: widget.booruItem.fileNameExtras,
    );
    unawaited(sizeClient!.runRequestSize());
    return;
  }

  void onSize(int size) {
    // TODO find a way to stop loading based on size when caching is enabled
    const int maxSize = 1024 * 1024 * 200;
    // print('onSize: $size $maxSize ${size > maxSize}');
    if (size == 0) {
      killLoading(['File is zero bytes']);
    } else if ((size > maxSize) && isTooBig != 2) {
      // TODO add check if resolution is too big
      isTooBig = 1;
      killLoading(['File is too big', 'File size: ${Tools.formatBytes(size, 2)}', 'Limit: ${Tools.formatBytes(maxSize, 2)}']);
    }

    if (size > 0 && widget.booruItem.fileSize == null) {
      // set item file size if it wasn't received from api
      widget.booruItem.fileSize = size;
    }
  }

  void onBytesAdded(int receivedNew, int totalNew) {
    received.value = receivedNew;
    total.value = totalNew;
    onSize(totalNew);
  }

  void onEvent(String event, dynamic data) {
    switch (event) {
      case 'loaded':
        //
        break;
      case 'size':
        onSize(data as int);
        break;
      case 'isFromCache':
        isFromCache = true;
        break;
      case 'isFromNetwork':
        isFromCache = false;
        break;
      default:
    }
    updateState();
  }

  void onError(Exception error) {
    //// Error handling
    if (error is DioError && CancelToken.isCancel(error)) {
      // print('Canceled by user: $imageURL | $error');
    } else {
      if (error is DioError) {
        killLoading(['Loading Error: ${error.message}']);
      } else {
        killLoading(['Loading Error: $error']);
      }
      // print('Dio request cancelled: $error');
    }
  }

  @override
  void initState() {
    super.initState();

    viewerHandler.addViewed(widget.key);

    viewController.outputStateStream.listen(onViewStateChanged);
    scaleController.outputScaleStateStream.listen(onScaleStateChanged);

    isViewed = settingsHandler.appMode.value.isMobile
        ? searchHandler.viewedIndex.value == widget.index
        : searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL;
    indexListener = searchHandler.viewedIndex.listen((int value) {
      final bool prevViewed = isViewed;
      final bool isCurrentIndex = value == widget.index;
      final bool isCurrentItem = searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL;
      if (settingsHandler.appMode.value.isMobile ? isCurrentIndex : isCurrentItem) {
        isViewed = true;
      } else {
        isViewed = false;
      }

      if (prevViewed != isViewed) {
        if (isViewed) {
          if (settingsHandler.autoPlayEnabled) {
            videoController?.play();
          }
        } else {
          // reset zoom and pause if not viewed
          resetZoom();
          videoController?.pause();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          updateState();
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Color accentColor = Theme.of(context).colorScheme.secondary;
      Color darkenedAceentColor = Color.lerp(accentColor, Colors.black, 0.5)!;
      videoControlsConfig = BetterPlayerControlsConfiguration(
        enableFullscreen: widget.enableFullscreen,
        enableSubtitles: false,
        enableQualities: false,
        enableAudioTracks: false,
        enablePip: true,
        enableRetry: false,
        showControlsOnInitialize: viewerHandler.displayAppbar.value,
        progressBarBackgroundColor: Colors.grey,
        progressBarBufferedColor: Colors.white70,
        progressBarPlayedColor: accentColor,
        progressBarHandleColor: darkenedAceentColor,
        loadingColor: accentColor,
        controlBarColor: Colors.black26,
        playerTheme: BetterPlayerTheme.custom,
      );
      updateState();
    });

    initVideo(false);
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  void initVideo(bool ignoreTagsCheck) {
    if (widget.booruItem.isHated.value && !ignoreTagsCheck) {
      List<List<String>> hatedAndLovedTags = settingsHandler.parseTagsList(widget.booruItem.tagsList, isCapped: true);
      killLoading(['Contains Hated tags:', ...hatedAndLovedTags[0]]);
    } else {
      downloadVideo();
    }
  }

  void killLoading(List<String> reason) {
    disposables();

    total.value = 0;
    received.value = 0;
    startedAt.value = 0;

    isFromCache = false;
    isStopped = true;
    stopReason = reason;

    viewerHandler.setLoaded(widget.key, false);

    resetZoom();

    video = null;

    updateState();
  }

  @override
  void dispose() {
    disposables();

    indexListener?.cancel();
    indexListener = null;

    viewerHandler.removeViewed(widget.key);

    super.dispose();
  }

  void disposeClient() {
    client?.dispose();
    client = null;
    sizeClient?.dispose();
    sizeClient = null;
  }

  void disposables() {
    videoController?.setVolume(0);
    videoController?.pause();
    videoController?.removeEventsListener(updateVideoState);
    videoController?.dispose();
    videoController = null;
    videoSource = null;

    if (!(cancelToken != null && cancelToken!.isCancelled)) {
      cancelToken?.cancel();
    }
    if (!(sizeCancelToken != null && sizeCancelToken!.isCancelled)) {
      sizeCancelToken?.cancel();
    }

    disposeClient();
  }

  // debug functions
  void onScaleStateChanged(PhotoViewScaleState scaleState) {
    // print(scaleState);

    isZoomed = scaleState == PhotoViewScaleState.zoomedIn || scaleState == PhotoViewScaleState.covering || scaleState == PhotoViewScaleState.originalSize;
    viewerHandler.setZoomed(widget.key, isZoomed);
  }

  void onViewStateChanged(PhotoViewControllerValue viewState) {
    // print(viewState);
    viewerHandler.setViewState(widget.key, viewState);
  }

  void resetZoom() {
    if (!isVideoInited) return;
    scaleController.scaleState = PhotoViewScaleState.initial;
  }

  void scrollZoomImage(double value) {
    final double upperLimit = min(8, (viewController.scale ?? 1) + (value / 200));
    // zoom on which image fits to container can be less than limit
    // therefore don't clump the value to lower limit if we are zooming in to avoid unnecessary zoom jumps
    final double lowerLimit = value > 0 ? upperLimit : max(0.75, upperLimit);

    // print('ll $lowerLimit $value');
    // if zooming out and zoom is smaller than limit - reset to container size
    // TODO minimal scale to fit can be different from limit
    if (lowerLimit == 0.75 && value < 0) {
      scaleController.scaleState = PhotoViewScaleState.initial;
    } else {
      viewController.scale = lowerLimit;
    }
  }

  void doubleTapZoom() {
    if (!isVideoInited) return;
    // viewController.scale = 2;
    // viewController.updateMultiple(scale: 2);
    scaleController.scaleState = PhotoViewScaleState.covering;
  }

  void updateVideoState(BetterPlayerEvent event) {
    if (videoController == null) return;

    if (isVideoInited || event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      if (videoController!.getAspectRatio() != videoController!.videoPlayerController!.value.aspectRatio) {
        videoController!.setOverriddenAspectRatio(videoController!.videoPlayerController!.value.aspectRatio);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          updateState();
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        viewerHandler.setLoaded(widget.key, true);
      });

      videoController!.setMixWithOthers(true);

      if (!isViewed) {
        videoController!.pause();
      }
    }

    if (viewerHandler.isFullscreen.value != videoController!.isFullScreen) {
      // redisable sleep when changing fullscreen state
      ServiceHandler.disableSleep();

      // Reset systemui visibility
      if (!videoController!.isFullScreen) {
        ServiceHandler.setSystemUiVisibility(viewerHandler.displayAppbar.value);
      }

      // videoController!.setControlsEnabled(!videoController!.isFullScreen);

      // save fullscreen state only when it changed
      viewerHandler.isFullscreen.value = videoController!.isFullScreen;
    }

    if (searchHandler.viewedIndex.value == widget.index) {
      if (videoController!.isFullScreen || !settingsHandler.useVolumeButtonsForScroll) {
        ServiceHandler.setVolumeButtons(true); // in full screen or volumebuttons scroll setting is disabled
      } else {
        ServiceHandler.setVolumeButtons(viewerHandler.displayAppbar.value); // same as app bar value
      }
    }

    if (!isStopped && event.betterPlayerEventType == BetterPlayerEventType.exception) {
      killLoading(['Video Error:', event.betterPlayerEventType.name]);
    }
  }

  Future<void> initPlayer() async {
    if (video != null) {
      // Start from cache if was already cached or only caching is allowed
      videoSource = BetterPlayerDataSource.file(video!.path);
    } else {
      // Otherwise load from network
      videoSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.booruItem.fileURL,
        cacheConfiguration: BetterPlayerCacheConfiguration(
          useCache: settingsHandler.mediaCache,
          maxCacheSize: 1024 * 1024 * 1024,
          maxCacheFileSize: 1024 * 1024 * 1024,
          key: widget.booruItem.fileURL,
        ),
        headers: await Tools.getFileCustomHeaders(
          searchHandler.currentBooru,
          checkForReferer: true,
        ),
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2500,
          maxBufferMs: 60000,
          bufferForPlaybackMs: 1000,
          bufferForPlaybackAfterRebufferMs: 2500,
        ),
      );
    }

    videoController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: settingsHandler.autoPlayEnabled,
        autoDispose: false,
        looping: true,
        autoDetectFullscreenDeviceOrientation: true,
        autoDetectFullscreenAspectRatio: true,
        fit: BoxFit.contain,
        allowedScreenSleep: false,
        systemOverlaysAfterFullScreen: SystemUiOverlay.values,
        controlsConfiguration: const BetterPlayerControlsConfiguration(showControls: false),
        handleLifecycle: true,
        aspectRatio: widget.booruItem.fileAspectRatio,
        fullScreenAspectRatio: widget.booruItem.fileAspectRatio,
        errorBuilder: (context, errorMessage) {
          onError(Exception(errorMessage));

          return Center(
            child: Text(errorMessage ?? 'Error happened', style: const TextStyle(color: Colors.white)),
          );
        },
        routePageBuilder: fullscreenRoutePageBuilder,
      ),
      betterPlayerDataSource: videoSource,
    );
    // mixWithOthers: true, allows to not interrupt audio sources from other apps
    videoController!.setBetterPlayerGlobalKey(videoKey);
    // TODO store volume state in viewerHandler and restore it when video is changed
    await videoController!.setVolume(viewerHandler.videoAutoMute ? 0 : 1);
    videoController!.addEventsListener(updateVideoState);

    // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
    updateState();
  }

  AnimatedWidget fullscreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    BetterPlayerControllerProvider controllerProvider,
  ) {
    resetZoom();

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return child!;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: Stack(
            children: [
              controllerProvider,
              TransparentPointer(
                child: SafeArea(
                  child: CustomBetterPlayerMaterialControls(
                    playerController: controllerProvider.controller,
                    controlsConfiguration: videoControlsConfig!,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // print('!!! Build video mobile ${widget.index}!!!');

    // protects from video restart when something forces restate here while video is active (example: favoriting from appbar)
    int viewedIndex = searchHandler.viewedIndex.value;
    bool needsRestart = lastViewedIndex != viewedIndex;

    if (isVideoInited) {
      if (isViewed) {
        // Reset video time if it came into view
        if (needsRestart) {
          videoController!.seekTo(Duration.zero);
        }
        if (viewerHandler.videoAutoMute) {
          videoController!.setVolume(0);
        }
      }
    }

    if (needsRestart) {
      lastViewedIndex = viewedIndex;
    }

    double aspectRatio = videoController?.getAspectRatio() ?? 16 / 9;
    double screenRatio = MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
    Size childSize = Size(
      aspectRatio > screenRatio ? MediaQuery.of(context).size.width : MediaQuery.of(context).size.height * aspectRatio,
      aspectRatio < screenRatio ? MediaQuery.of(context).size.height : MediaQuery.of(context).size.width / aspectRatio,
    );

    return Hero(
      tag: 'imageHero${isViewed ? '' : '-ignore-'}${widget.index}#${widget.booruItem.fileURL}',
      child: Material(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isVideoInited
                  ? Container()
                  : Thumbnail(
                      item: widget.booruItem,
                      index: widget.index,
                      isStandalone: false,
                      ignoreColumnsCount: true,
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isVideoInited
                  ? Container()
                  : MediaLoading(
                      item: widget.booruItem,
                      hasProgress: settingsHandler.mediaCache && settingsHandler.videoCacheMode != 'Stream',
                      isFromCache: isFromCache,
                      isDone: isVideoInited,
                      isTooBig: isTooBig > 0,
                      isStopped: isStopped,
                      stopReasons: stopReason,
                      isViewed: isViewed,
                      total: total,
                      received: received,
                      startedAt: startedAt,
                      startAction: () {
                        if (isTooBig == 1) {
                          isTooBig = 2;
                        }
                        initVideo(true);
                        updateState();
                      },
                      stopAction: () {
                        killLoading(['Stopped by User']);
                      },
                    ),
            ),
            //
            AnimatedSwitcher(
              duration: Duration(milliseconds: settingsHandler.appMode.value.isDesktop ? 50 : 200),
              child: videoController != null
                  ? Listener(
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          scrollZoomImage(pointerSignal.scrollDelta.dy);
                        }
                      },
                      child: Stack(
                        children: [
                          PhotoView.customChild(
                            childSize: childSize,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 8,
                            initialScale: PhotoViewComputedScale.contained,
                            enableRotation: false,
                            basePosition: Alignment.center,
                            controller: viewController,
                            scaleStateController: scaleController,
                            child: BetterPlayer(controller: videoController!),
                          ),
                          if (videoControlsConfig != null)
                            TransparentPointer(
                              child: SafeArea(
                                child: CustomBetterPlayerMaterialControls(
                                  playerController: videoController!,
                                  controlsConfiguration: videoControlsConfig!,
                                  onLongTap: () {
                                    viewerHandler.displayAppbar.value = !viewerHandler.displayAppbar.value;
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Container(),
            ),
          ],
        ),
      ),
    );
  }
}
