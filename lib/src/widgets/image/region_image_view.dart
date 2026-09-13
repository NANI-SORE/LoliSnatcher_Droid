import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// Owns the downloaded file until both the viewer and in-flight native reads finish.
class RegionImageSource {
  RegionImageSource(this.download, this.size);

  final DownloadedImageFile download;
  final Size size;
  int _readers = 0;
  bool _closed = false;

  Future<_RegionTile> _load(Rect region, int sample, CancelToken token, {bool withGutter = false}) async {
    if (_closed || token.isCancelled) throw StateError('Image region was cancelled');
    _readers++;
    ImageMemoryLease? lease;
    try {
      // Keep one decoded neighbor pixel around internal edges for filtering.
      // The logical tile is smaller so the padded decode still fits 1024².
      final decodedRegion = withGutter ? region.inflate(sample.toDouble()).intersect(Offset.zero & size) : region;
      final width = (decodedRegion.width / sample).ceil();
      final height = (decodedRegion.height / sample).ceil();
      lease = ImageMemoryManager.instance.reserveImage(width * height * 4);
      final image = await ImageMemoryManager.instance.runDecode(
        // The region decoder may also retain the encoded source while reading.
        ImageMemoryManager.maxEncodedBytes + 16 * 1024 * 1024,
        () async {
          final bytes = await ServiceHandler.decodeImageRegion(
            download.file.path,
            left: decodedRegion.left.toInt(),
            top: decodedRegion.top.toInt(),
            right: decodedRegion.right.toInt(),
            bottom: decodedRegion.bottom.toInt(),
            sampleSize: sample,
          );
          if (token.isCancelled) throw token.cancelError!;
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            final frame = await codec.getNextFrame();
            if (token.isCancelled || _closed) {
              frame.image.dispose();
              if (token.isCancelled) throw token.cancelError!;
              throw StateError('Image region was closed');
            }
            return frame.image;
          } finally {
            codec.dispose();
          }
        },
        cancelToken: token,
      );
      return _RegionTile(region, decodedRegion, image, lease);
    } catch (_) {
      lease?.release();
      rethrow;
    } finally {
      _readers--;
      if (_closed && _readers == 0) unawaited(download.dispose());
    }
  }

  void dispose() {
    _closed = true;
    if (_readers == 0) unawaited(download.dispose());
  }
}

typedef _TileKey = ({int sample, int x, int y});

class _RegionTile {
  _RegionTile(this.region, this.decodedRegion, this.image, this.lease);

  final Rect region;
  final Rect decodedRegion;
  final ui.Image image;
  final ImageMemoryLease lease;

  void dispose() {
    image.dispose();
    lease.release();
  }
}

/// Paints a small overview and only the regions needed at the current zoom.
/// PhotoView remains responsible for all gestures, transforms and zoom bounds.
class RegionImageView extends StatefulWidget {
  const RegionImageView({
    required this.source,
    required this.controller,
    required this.viewport,
    required this.onReady,
    required this.onError,
    super.key,
  });

  final RegionImageSource source;
  final PhotoViewController controller;
  final Size viewport;
  final VoidCallback onReady;
  final void Function(Object) onError;

  @override
  State<RegionImageView> createState() => _RegionImageViewState();
}

class _RegionImageViewState extends State<RegionImageView> {
  static const _maxDecodedSide = 1024;
  static const _tileSide = _maxDecodedSide - 2; // One decoded gutter pixel on each side.
  static const _maxTiles = 8;
  final Map<_TileKey, _RegionTile> _tiles = {};
  final CancelToken _lifetime = CancelToken();
  StreamSubscription<PhotoViewControllerValue>? _subscription;
  _RegionTile? _overview;
  List<_TileKey> _wanted = [];
  CancelToken? _tileRequest;
  bool _loading = false;
  bool _scheduled = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.outputStateStream.listen((_) => _schedule());
    ImageMemoryManager.instance.underPressure.addListener(_schedule);
    unawaited(_loadOverview());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(RegionImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) _schedule();
  }

  Future<void> _loadOverview() async {
    int sample = 1;
    while (widget.source.size.longestSide / sample > _maxDecodedSide) {
      sample *= 2;
    }
    try {
      final tile = await widget.source._load(Offset.zero & widget.source.size, sample, _lifetime);
      if (!mounted) {
        tile.dispose();
        return;
      }
      setState(() => _overview = tile);
      _markReady();
      _schedule();
    } catch (error) {
      if (mounted && !_lifetime.isCancelled) widget.onError(error);
    }
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    widget.onReady();
  }

  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _updateVisibleTiles();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _updateVisibleTiles() {
    final sourceSize = widget.source.size;
    final view = widget.controller.value;
    final scale =
        view.scale ?? math.min(widget.viewport.width / sourceSize.width, widget.viewport.height / sourceSize.height);
    if (!scale.isFinite || scale <= 0 || widget.viewport.isEmpty) return;
    final cosine = math.cos(view.rotation);
    final sine = math.sin(view.rotation);
    Offset toSource(Offset point) {
      final relative = point - widget.viewport.center(Offset.zero) - view.position;
      return Offset(
        (relative.dx * cosine + relative.dy * sine) / scale + sourceSize.width / 2,
        (-relative.dx * sine + relative.dy * cosine) / scale + sourceSize.height / 2,
      );
    }

    final corners = [
      Offset.zero,
      Offset(widget.viewport.width, 0),
      Offset(0, widget.viewport.height),
      widget.viewport.bottomRight(Offset.zero),
    ].map(toSource);
    final visible = Rect.fromLTRB(
      corners.map((p) => p.dx).reduce(math.min),
      corners.map((p) => p.dy).reduce(math.min),
      corners.map((p) => p.dx).reduce(math.max),
      corners.map((p) => p.dy).reduce(math.max),
    ).intersect(Offset.zero & sourceSize);
    if (visible.isEmpty) return;

    final pixelScale = scale * MediaQuery.devicePixelRatioOf(context);
    int sample = 1;
    while (sample < 262144 && sample * 2 * pixelScale <= 1) {
      sample *= 2;
    }
    final limit = ImageMemoryManager.instance.underPressure.value ? 2 : _maxTiles;
    List<_TileKey> keysFor(int sample) {
      final side = _tileSide * sample;
      return [
        for (int y = (visible.top / side).floor(); y < (visible.bottom / side).ceil(); y++)
          for (int x = (visible.left / side).floor(); x < (visible.right / side).ceil(); x++)
            (sample: sample, x: x, y: y),
      ];
    }

    var wanted = keysFor(sample);
    while (sample < 262144 && wanted.length > limit) {
      sample *= 2;
      wanted = keysFor(sample);
    }
    // Nearest tiles first. A missing high-resolution tile still has the overview beneath it.
    wanted.sort((a, b) {
      double distance(_TileKey key) =>
          (Offset((key.x + 0.5) * _tileSide * sample, (key.y + 0.5) * _tileSide * sample) - visible.center)
              .distanceSquared;
      return distance(a).compareTo(distance(b));
    });
    if (wanted.length != _wanted.length || !wanted.every(_wanted.contains)) _tileRequest?.cancel();
    _wanted = wanted;
    for (final key in _tiles.keys.where((key) => !_wanted.contains(key)).toList()) {
      _tiles.remove(key)!.dispose();
    }
    setState(() {});
    unawaited(_loadTiles());
  }

  Future<void> _loadTiles() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      while (mounted) {
        final missing = _wanted.where((key) => !_tiles.containsKey(key));
        if (missing.isEmpty) break;
        final key = missing.first;
        final side = _tileSide * key.sample;
        final region = Rect.fromLTRB(
          (key.x * side).toDouble(),
          (key.y * side).toDouble(),
          math.min(((key.x + 1) * side).toDouble(), widget.source.size.width),
          math.min(((key.y + 1) * side).toDouble(), widget.source.size.height),
        );
        final token = CancelToken();
        _tileRequest = token;
        try {
          final tile = await widget.source._load(region, key.sample, token, withGutter: true);
          if (!mounted || token.isCancelled || !_wanted.contains(key)) {
            tile.dispose();
          } else {
            setState(() => _tiles[key] = tile);
            _markReady();
          }
        } catch (error) {
          if (!mounted) break;
          if (token.isCancelled) continue;
          // Keep the overview usable when another live image consumes the budget.
          if (error is! ImageMemoryException) widget.onError(error);
          break;
        }
      }
    } finally {
      _loading = false;
      _tileRequest = null;
    }
  }

  @override
  void dispose() {
    _lifetime.cancel();
    _tileRequest?.cancel();
    _subscription?.cancel();
    ImageMemoryManager.instance.underPressure.removeListener(_schedule);
    _overview?.dispose();
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: widget.source.size,
    painter: _RegionPainter([?_overview, ..._tiles.values]),
  );
}

class _RegionPainter extends CustomPainter {
  _RegionPainter(this.tiles);

  final List<_RegionTile> tiles;

  @override
  void paint(Canvas canvas, Size size) {
    // Bilinear filtering only needs the one-pixel gutter. Independently
    // generated mipmaps would filter across wider, unrelated tile borders.
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..isAntiAlias = false;
    for (int index = 0; index < tiles.length; index++) {
      final tile = tiles[index];
      canvas.save();
      // Draw the padded texture through a hard logical boundary. Shared edges
      // must not fade independently or overlap alpha at fractional zoom/rotation.
      canvas.clipRect(tile.region, doAntiAlias: false);
      // Paint each source pixel once, preserving transparency across levels.
      for (final higher in tiles.skip(index + 1)) {
        canvas.clipRect(higher.region, clipOp: ui.ClipOp.difference, doAntiAlias: false);
      }
      canvas.drawImageRect(
        tile.image,
        Rect.fromLTWH(0, 0, tile.image.width.toDouble(), tile.image.height.toDouble()),
        tile.decodedRegion,
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) => true;
}
