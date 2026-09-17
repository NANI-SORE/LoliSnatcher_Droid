import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';
import 'package:lolisnatcher/src/widgets/video/video_viewer.dart';

/// Hosts the shared media viewers without gallery actions or shared gallery state.
class HiddenItemViewer extends StatefulWidget {
  const HiddenItemViewer({required this.item, required this.booru, super.key});

  final BooruItem item;
  final Booru booru;

  @override
  State<HiddenItemViewer> createState() => _HiddenItemViewerState();
}

class _HiddenItemViewerState extends State<HiddenItemViewer> with WidgetsBindingObserver {
  BooruItem? _item;
  GlobalKey<VideoViewerState> _videoKey = GlobalKey();
  bool _isForeground = true;

  bool get _isActive => _isForeground && LocalAuthHandler.instance.isAuthenticated.value != false;
  CancelToken? _request;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalAuthHandler.instance.isAuthenticated.addListener(_onAuthenticationChanged);
    unawaited(_load());
  }

  void _pauseVideo() {
    final video = _videoKey.currentState?.videoController.value;
    if (video != null && video.value.isInitialized) unawaited(video.pause());
  }

  void _onAuthenticationChanged() {
    if (!_isActive) _pauseVideo();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (!_isForeground) _pauseVideo();
    if (mounted) setState(() {});
  }

  bool _isCurrent(CancelToken request) => mounted && identical(_request, request) && !request.isCancelled;

  void _dismissUnavailable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalAuthHandler.instance.isAuthenticated.removeListener(_onAuthenticationChanged);
    _request?.cancel();
    _pauseVideo();
    super.dispose();
  }

  Future<void> _load({bool refreshMetadata = false}) async {
    _pauseVideo();
    _request?.cancel();
    final request = _request = CancelToken();
    setState(() {
      _loading = true;
      _failed = false;
      _item = null;
      _videoKey = GlobalKey();
    });
    try {
      // Metadata resolution must not alter the hidden result or its filter state.
      final original = widget.item;
      var item = BooruItem(
        fileURL: original.fileURL,
        sampleURL: original.sampleURL,
        thumbnailURL: original.thumbnailURL,
        tagsList: original.tagsList.map((tag) => Tag.fromJson(tag.toJson())).toList(),
        postURL: original.postURL,
        fileExt: original.fileExt,
        fileNameExtras: original.fileNameExtras,
        serverId: original.serverId,
        rating: original.rating,
        fileSize: original.fileSize,
        fileWidth: original.fileWidth,
        fileHeight: original.fileHeight,
        sampleWidth: original.sampleWidth,
        sampleHeight: original.sampleHeight,
        previewWidth: original.previewWidth,
        previewHeight: original.previewHeight,
      );
      item.mediaType.value = original.mediaType.value;
      if (!ContentPolicy.isItemAllowed(widget.booru, item)) {
        _dismissUnavailable();
        return;
      }
      if (item.mediaType.value.isNeedToLoadItem || refreshMetadata) {
        final handler = BooruHandlerFactory().getBooruHandler([widget.booru], null).booruHandler;
        if (!handler.hasLoadItemSupport && item.mediaType.value.isNeedToLoadItem) {
          throw StateError('Item metadata is unavailable');
        }
        if (handler.hasLoadItemSupport) {
          final result = await handler.loadItem(item: item, cancelToken: request, withCapcthaCheck: true);
          if (!_isCurrent(request)) return;
          if (result.failed || result.item == null) throw StateError('Could not load item metadata');
          item = result.item!;
          if (!ContentPolicy.isItemAllowed(widget.booru, item)) {
            _dismissUnavailable();
            return;
          }
        }
      }
      if (!item.mediaType.value.isImageOrAnimation && !item.mediaType.value.isVideo) {
        final headers = await Tools.getFileCustomHeaders(widget.booru, item: item, checkForReferer: true);
        if (!_isCurrent(request)) return;
        final response = await DioNetwork.head(item.fileURL, headers: headers, cancelToken: request);
        if (!_isCurrent(request)) return;
        final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
        if (contentType.startsWith('video/')) {
          item.mediaType.value = .video;
        } else if (contentType.startsWith('image/')) {
          item.mediaType.value = contentType.contains('gif') ? .animation : .image;
        } else {
          throw StateError('Unknown media type');
        }
      }
      if (_isCurrent(request)) {
        setState(() {
          _item = item;
          _loading = false;
        });
      }
    } catch (_) {
      if (_isCurrent(request)) {
        request.cancel();
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Widget _errorView() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            context.loc.media.loading.stopReasons.loadingError,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(context.loc.retry)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _pauseVideo(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            [widget.booru.name ?? '', widget.item.serverId ?? ''].where((text) => text.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          leading: IconButton(
            tooltip: context.loc.close,
            icon: const Icon(Icons.close),
            onPressed: () {
              _pauseVideo();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: SafeArea(
          child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(context.loc.media.loading.loading, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                )
              : _failed
              ? _errorView()
              : item == null
              ? const SizedBox.shrink()
              : HeroMode(
                  enabled: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(size: constraints.biggest),
                      child: item.mediaType.value.isVideo
                          ? VideoViewer(
                              item,
                              key: _videoKey,
                              booru: widget.booru,
                              isViewed: _isActive,
                              isStandalone: true,
                              allowHidden: true,
                              enableFullscreen: false,
                              onReloadItem: () => _load(refreshMetadata: true),
                            )
                          : ImageViewer(
                              item,
                              key: ObjectKey(item),
                              booru: widget.booru,
                              isViewed: _isActive,
                              isStandalone: true,
                              allowHidden: true,
                              fullQuality: true,
                              onReloadItem: () => _load(refreshMetadata: true),
                            ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
