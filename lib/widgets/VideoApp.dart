import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:LoliSnatcher/ImageWriter.dart';
import 'package:LoliSnatcher/Tools.dart';
import 'package:LoliSnatcher/libBooru/BooruItem.dart';

class VideoApp extends StatefulWidget {
  final BooruItem booruItem;
  final int index;
  final int viewedIndex;
  SettingsHandler settingsHandler;
  VideoApp(this.booruItem, this.index, this.viewedIndex, this.settingsHandler);
  @override
  _VideoAppState createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  VideoPlayerController _videoController;
  ChewieController _chewieController;
  TapDownDetails doubleTapInfo;

  // VideoPlayerValue _latestValue;

  String cacheMode;
  final ImageWriter imageWriter = ImageWriter();
  int _total = 0, _received = 0;
  bool isFromCache = false;
  StreamedResponse _response;
  File _video;
  List<int> _bytes = [];
  StreamSubscription _subscription;

  Future<void> _downloadImage() async {
    final String filePath =
        await imageWriter.getCachePath(widget.booruItem.fileURL, 'media');

    // If file is in cache - load
    print(filePath);
    if (filePath != null) {
      final File file = File(filePath);
      await file.readAsBytes();
      setState(() {
        _video = file;
        isFromCache = true;
      });

      // Start video if already cached
      initPlayer();
      return;
    }

    // Start video if not cached and we use both methods of loading
    if (cacheMode == 'Stream+Cache') {
      initPlayer();
    }

    // Otherwise start loading and subscribe to progress
    _response = await Client()
        .send(Request('GET', Uri.parse(widget.booruItem.fileURL)));
    _total = _response.contentLength;

    _subscription = _response.stream.listen((value) {
      //Restate only when just Caching or video is not initialized from network yet
      if (cacheMode == 'Cache' || !(_videoController.value != null && _videoController.value.initialized)) {
        setState(() {
          _bytes.addAll(value);
          _received += value.length;
        });
      } else {
        _bytes.addAll(value);
        _received += value.length;
      }
    });
    _subscription.onDone(() async {
      if (_received > (_total * 0.95)) {
        // Sometimes stream ends before fully loading, so we require at least 95% loaded to write to cache
        final File cacheFile = await imageWriter.writeCacheFromBytes(
            widget.booruItem.fileURL, _bytes, 'media');
        if (cacheFile != null) {
          //Restate only when just Caching
          if (cacheMode == 'Cache') {
            setState(() {
              _video = cacheFile;
            });
          } else {
            _video = cacheFile;
          }
        }

        // Start video after caching
        if (cacheMode == 'Cache') {
          initPlayer();
        }
      } else {
        print('Image load incomplete'); // Throw an error, allow to retry?
      }
    });
  }

  @override
  void initState() {
    super.initState();
    cacheMode = widget.settingsHandler.videoCacheMode;
    if (!widget.settingsHandler.mediaCache) {
      initPlayer();
      return;
    }
    switch (cacheMode) {
      case "Stream":
        initPlayer();
        break;
      case "Cache":
      case "Stream+Cache":
        _downloadImage();
        break;
    }
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    _chewieController?.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  // void _updateState() {
  //   print(_controller.value);
  //   setState(() {
  //     _latestValue = _controller.value;
  //   });
  // }

  void doubleTapInfoWrite(TapDownDetails event) {
    doubleTapInfo = event;
  }

  // TODO: make customControls and implement this there
  void doubleTapAction() {
    if (doubleTapInfo == null ||
        _chewieController == null ||
        !_chewieController.videoPlayerController.value.initialized) return;

    // Detect on which side we tapped
    double screenWidth = MediaQuery.of(context).size.width;
    double screenMiddle = screenWidth / 2;
    double sidesLimit = screenWidth / 6;
    double tapPositionWidth = doubleTapInfo.localPosition.dx;
    int tapSide;
    if (tapPositionWidth > (screenMiddle + sidesLimit)) {
      tapSide = 1;
    } else if (tapPositionWidth < (screenMiddle - sidesLimit)) {
      tapSide = -1;
    } else {
      tapSide = 0;
    }

    // Decide how much we will skip depending on video length
    int videoDuration = _videoController.value.duration.inSeconds;
    int skipSeconds;
    if (videoDuration <= 5) {
      skipSeconds = 0;
    } else if (videoDuration <= 10) {
      skipSeconds = 1;
    } else if (videoDuration <= 60) {
      skipSeconds = 5;
    } else if (videoDuration <= 120) {
      skipSeconds = 10;
    } else {
      skipSeconds = 15;
    }

    if (tapSide != 0 && skipSeconds != 0) {
      int videoPositionMillisecs =
          _videoController.value.position.inMilliseconds;
      int videoDurationMillisecs =
          _videoController.value.duration.inMilliseconds;
      // Calculate new time with skip and limit it to range (0 to duration of video) (in milliseconds for accuracy)
      int newTime = min(
          max(0, videoPositionMillisecs + (skipSeconds * 1000 * tapSide)),
          videoDurationMillisecs);
      // print(newTime);
      // Skip set amount of seconds if we tapped on left/right third of the screen or play/pause if in the middle
      _videoController.seekTo(new Duration(milliseconds: newTime));
      if (videoDurationMillisecs == newTime) {
        Get.snackbar("", "Reached video end",
            snackStyle: SnackStyle.GROUNDED,
            snackPosition: SnackPosition.TOP,
            duration: Duration(seconds: 1),
            colorText: Colors.black,
            backgroundColor: Theme.of(context).primaryColor);
      } else if (newTime == 0) {
        Get.snackbar("", "Reached video start",
            snackStyle: SnackStyle.GROUNDED,
            snackPosition: SnackPosition.TOP,
            duration: Duration(seconds: 1),
            colorText: Colors.black,
            backgroundColor: Theme.of(context).primaryColor);
      } else {
        Get.snackbar("",
            "${tapSide == 1 ? 'Skipped' : 'Rewind'} $skipSeconds second${skipSeconds > 1 ? 's' : ''}",
            snackStyle: SnackStyle.GROUNDED,
            snackPosition: SnackPosition.TOP,
            duration: Duration(seconds: 1),
            colorText: Colors.black,
            backgroundColor: Theme.of(context).primaryColor);
      }
    } else {
      _videoController.value.isPlaying
          ? _videoController.pause()
          : _videoController.play();
    }
  }

  Future<void> initPlayer() async {
    // Start from cache if was already cached or only caching is allowed
    if (widget.settingsHandler.mediaCache && _video != null) {
      _videoController = VideoPlayerController.file(_video);
    } else {
      // Otherwise load from network
      _videoController =
          VideoPlayerController.network(widget.booruItem.fileURL);
    }
    await _videoController.initialize();
    // _videoController.addListener(_updateState);

    // Player wrapper to allow controls, looping...
    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      // autoplay is disabled here, because videos started playing randomly, but videos will still autoplay when in view (see isViewed check later)
      autoPlay: false,
      allowedScreenSleep: false,
      looping: true,
      showControls: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: Colors.blue,
        handleColor: Colors.blue,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white,
      ),
      placeholder: Container(
        color: Colors.black,
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: TextStyle(color: Colors.white),
          ),
        );
      },

      // Specify this to allow any orientation in fullscreen, otherwise it will decide for itself based on video dimensions
      // deviceOrientationsOnEnterFullScreen: [
      //     DeviceOrientation.landscapeLeft,
      //     DeviceOrientation.landscapeRight,
      //     DeviceOrientation.portraitUp,
      //     DeviceOrientation.portraitDown,
      // ],
    );

    // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
    setState(() {});
  }

  Widget loadingElementBuilder() {
    bool hasProgressData =
        widget.settingsHandler.mediaCache && _total != null && _total > 0;
    int expectedBytes = hasProgressData ? _received : null;
    int totalBytes = hasProgressData ? _total : null;

    double percentDone = hasProgressData ? (expectedBytes / totalBytes) : null;
    String loadedSize =
        hasProgressData ? Tools.formatBytes(expectedBytes, 1) : '';
    String expectedSize =
        hasProgressData ? Tools.formatBytes(totalBytes, 1) : '';

    String percentDoneText = hasProgressData
        ? ('${(percentDone * 100).toStringAsFixed(2)}%')
        : 'Loading...';
    String filesizeText =
        hasProgressData ? ('$loadedSize / $expectedSize') : '';

    String thumbnailFileURL = widget.booruItem.thumbnailURL; // sample can be a video
    // widget.settingsHandler.previewMode == "Sample"
    //     ? widget.booruItem.sampleURL
    //     : widget.booruItem.thumbnailURL;
    File preview = File(
        "${widget.settingsHandler.cachePath}thumbnails/${thumbnailFileURL.substring(thumbnailFileURL.lastIndexOf("/") + 1)}");
    // start opacity from 20%
    double opacityValue = hasProgressData
        ? 0.2 +
            0.8 * lerpDouble(0.0, 1.0, (percentDone == null ? 0 : percentDone))
        : 0.66;


    // print(widget.settingsHandler.cachePath + "thumbnails/" + thumbnailFileURL.substring(thumbnailFileURL.lastIndexOf("/") + 1));
    // print(opacityValue);

    return Container(
        decoration: new BoxDecoration(
          color: Colors.black,
          image: new DecorationImage(
              image: preview.existsSync()
                  ? FileImage(preview)
                  : NetworkImage(thumbnailFileURL),
              fit: BoxFit.contain,
              colorFilter: new ColorFilter.mode(
                  Colors.black.withOpacity(opacityValue), BlendMode.dstATop)),
        ),
        child: new BackdropFilter(
            filter: new ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
            child: Container(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 10,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: LinearProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.pink[300]),
                          value: percentDone),
                    ),
                  ),
                  Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: widget.settingsHandler.loadingGif
                          ? [
                              Container(
                                  width: MediaQuery.of(context).size.width - 30,
                                  child: Image(
                                      image: AssetImage(
                                          'assets/images/loading.gif')))
                            ]
                          : [
                              Stack(children: [
                                Text(
                                  percentDoneText,
                                  style: TextStyle(
                                    fontSize: 28,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 4
                                      ..color = Colors.black,
                                  ),
                                ),
                                Text(
                                  percentDoneText,
                                  style: TextStyle(
                                    fontSize: 28,
                                  ),
                                ),
                              ]),
                              Stack(children: [
                                Text(
                                  filesizeText,
                                  style: TextStyle(
                                    fontSize: 24,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = 4
                                      ..color = Colors.black,
                                  ),
                                ),
                                Text(
                                  filesizeText,
                                  style: TextStyle(
                                    fontSize: 24,
                                  ),
                                ),
                              ]),
                            ]),
                  SizedBox(
                    width: 10,
                    child: RotatedBox(
                      quarterTurns: percentDone != null ? -1 : 1,
                      child: LinearProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.pink[300]),
                          value: percentDone),
                    ),
                  ),
                ],
              ),
            )));
  }

  @override
  Widget build(BuildContext context) {
    bool isViewed = widget.viewedIndex == widget.index;
    bool initialized = _chewieController != null &&
        _chewieController.videoPlayerController.value.initialized;
    String vWidth = '';
    String vHeight = '';

    if (initialized) {
      // vWidth = _chewieController.videoPlayerController.value.size.width.toStringAsFixed(0);
      // vHeight = _chewieController.videoPlayerController.value.size.height.toStringAsFixed(0);
      if (isViewed) {
        // Reset video time if in view
        _videoController.seekTo(Duration());
        if (widget.settingsHandler.autoPlayEnabled) {
          // autoplay if viewed and setting is enabled
          _videoController.play();
        }
      } else {
        _videoController.pause();
      }
    }

    return Container(
      child: Scaffold(
          body: Column(
        children: <Widget>[
          // Show video dimensions on the top
          // Container(
          //   child: MediaQuery.of(context).orientation == Orientation.portrait ? Text(vWidth+'x'+vHeight) : null
          // ),
          Expanded(
            child: Center(
                child: initialized
                    ? GestureDetector(
                        onDoubleTapDown: doubleTapInfoWrite,
                        onDoubleTap: doubleTapAction,
                        child: Chewie(controller: _chewieController))
                    : loadingElementBuilder()),
          ),
        ],
      )),
    );
  }
}
