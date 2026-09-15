import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/services/image_region_decoder.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

/// Owns the downloaded file until both the viewer and in-flight native reads finish.
class RegionImageSource {
  RegionImageSource(this.download, this.size);

  final DownloadedImageFile download;
  final Size size;
  int _readers = 0;
  bool _closed = false;
  bool _cleanupStarted = false;
  int _cleanupAttempts = 0;
  int _bytesPerPixel = 4;

  Future<_RegionTile> _load(
    Rect region,
    int sample,
    CancelToken token, {
    required bool Function() isForeground,
    bool withGutter = false,
    bool Function()? isSourceVisible,
  }) async {
    if (_closed || token.isCancelled) throw StateError('Image region was cancelled');
    _readers++;
    ImageMemoryLease? lease;
    try {
      // Keep one decoded neighbor pixel around internal edges for filtering.
      // The logical tile is smaller so the padded decode still fits 1024².
      final decodedRegion = withGutter ? region.inflate(sample.toDouble()).intersect(Offset.zero & size) : region;
      final decoded = await ImageRegionDecoder.instance.load(
        download.file,
        left: decodedRegion.left.toInt(),
        top: decodedRegion.top.toInt(),
        right: decodedRegion.right.toInt(),
        bottom: decodedRegion.bottom.toInt(),
        sampleSize: sample,
        cancelToken: token,
        isForeground: isForeground,
        isSourceVisible: isSourceVisible,
      );
      lease = decoded.lease;
      final image = decoded.image;
      _bytesPerPixel = math.max(_bytesPerPixel, lease.bytes ~/ (image.width * image.height));
      if (_closed || token.isCancelled) {
        image.dispose();
        if (token.isCancelled) throw token.cancelError!;
        throw StateError('Image region was closed');
      }
      return _RegionTile(region, decodedRegion, sample, image, lease);
    } catch (_) {
      lease?.release();
      rethrow;
    } finally {
      _readers--;
      _tryCleanup();
    }
  }

  void dispose() {
    _closed = true;
    _tryCleanup();
  }

  Future<void> releaseDecoder() => ImageRegionDecoder.instance.release(download.file.path);

  void _tryCleanup() {
    if (!_closed || _readers != 0 || _cleanupStarted) return;
    _cleanupStarted = true;
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    try {
      await releaseDecoder();
      await download.dispose();
    } catch (error, stack) {
      // A failed native close still owns the source. Keep its file available
      // and retry without leaking an unhandled asynchronous error.
      _cleanupStarted = false;
      _cleanupAttempts++;
      if (_cleanupAttempts < 3) {
        Timer(Duration(milliseconds: 250 * _cleanupAttempts), _tryCleanup);
      }
      developer.log('Unable to release image regions', name: 'ImageRegions', error: error, stackTrace: stack);
    }
  }
}

typedef _TileKey = ({int sample, int x, int y});

class _RegionTile {
  _RegionTile(this.region, this.decodedRegion, this.sample, this.image, this.lease);

  final Rect region;
  final Rect decodedRegion;
  final int sample;
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
    required this.isViewed,
    required this.onReady,
    required this.onError,
    super.key,
  });

  final RegionImageSource source;
  final PhotoViewController controller;
  final Size viewport;
  final bool isViewed;
  final VoidCallback onReady;
  final void Function(Object) onError;

  @override
  State<RegionImageView> createState() => _RegionImageViewState();
}

class _RegionImageViewState extends State<RegionImageView> {
  static const _maxDecodedSide = 1024;
  static const _tileSide = _maxDecodedSide - 2; // One decoded gutter pixel on each side.
  static const _maxTiles = 8;
  static const _tileBytes = _maxDecodedSide * _maxDecodedSide * 4;
  final Map<_TileKey, _RegionTile> _tiles = {};
  final CancelToken _lifetime = CancelToken();
  StreamSubscription<PhotoViewControllerValue>? _subscription;
  _RegionTile? _overview;
  List<_TileKey> _wanted = [];
  CancelToken? _tileRequest;
  _TileKey? _inFlight;
  _TileKey? _prefetch;
  Rect _visible = Rect.zero;
  int? _sample;
  bool _loading = false;
  bool _scheduled = false;
  bool _ready = false;
  int _cacheHits = 0;
  int _decodedTiles = 0;
  int _cancelledTiles = 0;
  developer.TimelineTask? _coverageTrace;

  int get _tileLimit => math.min(_maxTiles, (_maxTiles * 4) ~/ widget.source._bytesPerPixel);
  int get _maxTileBytes => _maxDecodedSide * _maxDecodedSide * widget.source._bytesPerPixel;

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
    if (oldWidget.viewport != widget.viewport || oldWidget.isViewed != widget.isViewed) _schedule();
    if (oldWidget.isViewed && !widget.isViewed) {
      unawaited(
        widget.source.releaseDecoder().catchError((Object error, StackTrace stack) {
          developer.log('Unable to release idle image decoder', name: 'ImageRegions', error: error, stackTrace: stack);
        }),
      );
    }
  }

  Future<void> _loadOverview() async {
    int sample = 1;
    while (widget.source.size.longestSide / sample > _maxDecodedSide) {
      sample *= 2;
    }
    try {
      final tile = await widget.source._load(
        Offset.zero & widget.source.size,
        sample,
        _lifetime,
        isForeground: () => mounted && widget.isViewed,
      );
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
    if (!widget.isViewed) {
      _wanted = [];
      _prefetch = null;
      _tileRequest?.cancel();
      _finishCoverage();
      if (_trimTiles()) setState(() {});
      return;
    }
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
    final movement = _visible.isEmpty ? Offset.zero : visible.center - _visible.center;
    _visible = visible;

    final pixelScale = scale * MediaQuery.devicePixelRatioOf(context);
    int sample = 1;
    while (sample < 262144 && sample * 2 * pixelScale <= 1) {
      sample *= 2;
    }
    // Keep a small dead band around level boundaries during pinch gestures.
    // Capacity/pressure checks below can still force a coarser level.
    final previousSample = _sample;
    if (previousSample != null &&
        ((sample == previousSample * 2 && previousSample * pixelScale >= 0.4) ||
            (sample * 2 == previousSample && previousSample * pixelScale <= 1.1))) {
      sample = previousSample;
    }
    final pressure = ImageMemoryManager.instance.underPressure.value;
    final limit = pressure ? 2 : _tileLimit;
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
    _sample = sample;
    // Nearest tiles first. A missing high-resolution tile still has the overview beneath it.
    wanted.sort((a, b) {
      double distance(_TileKey key) =>
          (Offset((key.x + 0.5) * _tileSide * sample, (key.y + 0.5) * _tileSide * sample) - visible.center)
              .distanceSquared;
      return distance(a).compareTo(distance(b));
    });
    final wantedChanged = wanted.length != _wanted.length || !wanted.every(_wanted.contains);
    if (wantedChanged) {
      _cacheHits += wanted.where((key) => !_wanted.contains(key) && _tiles.containsKey(key)).length;
      _finishCoverage();
    }
    _wanted = wanted;
    // One adjacent tile in the direction of travel, only after visible work.
    if (movement.distanceSquared > 1) {
      final side = _tileSide * sample;
      final vertical = movement.dy.abs() >= movement.dx.abs();
      final x = vertical
          ? (visible.center.dx / side).floor()
          : (movement.dx > 0 ? (visible.right / side).ceil() : (visible.left / side).floor() - 1);
      final y = !vertical
          ? (visible.center.dy / side).floor()
          : (movement.dy > 0 ? (visible.bottom / side).ceil() : (visible.top / side).floor() - 1);
      _prefetch = x >= 0 && y >= 0 && x * side < sourceSize.width && y * side < sourceSize.height
          ? (sample: sample, x: x, y: y)
          : null;
    } else if (_prefetch?.sample != sample) {
      _prefetch = null;
    }
    if (pressure) _prefetch = null;
    if (_inFlight != null &&
        !_wanted.contains(_inFlight) &&
        _inFlight != _prefetch &&
        _tileRequest?.isCancelled == false) {
      _cancelledTiles++;
      _tileRequest?.cancel();
    }
    // Touch visible entries for LRU eviction without changing paint precedence.
    for (final key in wanted.reversed) {
      final tile = _tiles.remove(key);
      if (tile != null) _tiles[key] = tile;
    }
    if (_trimTiles()) setState(() {});
    _trackCoverage();
    unawaited(_loadTiles());
  }

  void _finishCoverage({bool complete = false}) {
    _coverageTrace?.finish(arguments: {'complete': complete});
    _coverageTrace = null;
  }

  void _trackCoverage() {
    if (kReleaseMode) return;
    final missing = _wanted.where((key) => !_tiles.containsKey(key)).length;
    if (missing == 0) {
      _finishCoverage(complete: true);
    } else {
      _coverageTrace ??= developer.TimelineTask()..start('Image visible tile coverage');
    }
    developer.Timeline.instantSync(
      'Image tile working set',
      arguments: {
        'cached': _tiles.length,
        'missing': missing,
        'reused': _cacheHits,
        'decoded': _decodedTiles,
        'cancelled': _cancelledTiles,
      },
    );
  }

  /// Include the next decode in the eight-tile envelope. Optional retained
  /// coverage must never prevent a visible replacement from being admitted.
  bool _trimTiles({int incomingBytes = 0, int incomingCount = 0}) {
    final memory = ImageMemoryManager.instance;
    final pressure = memory.underPressure.value;
    final limit = !widget.isViewed ? 0 : (pressure ? 2 : _tileLimit);
    var changed = false;
    int bytes() => _tiles.values.fold(0, (sum, tile) => sum + tile.lease.bytes);
    void remove(_TileKey key) {
      _tiles.remove(key)!.dispose();
      changed = true;
    }

    if (pressure || !widget.isViewed) {
      for (final key in _tiles.keys.where((key) => !_wanted.contains(key)).toList()) {
        remove(key);
      }
    }
    while (_tiles.length + incomingCount > limit ||
        bytes() + incomingBytes > math.min(_maxTiles * _tileBytes, limit * _maxTileBytes) ||
        (incomingBytes > 0 && memory.retainedBytes + incomingBytes > ImageMemoryManager.maxRetainedBytes)) {
      final optional = _tiles.keys.where((key) => !_wanted.contains(key));
      final victim =
          optional.where((key) => !_tiles[key]!.region.overlaps(_visible)).firstOrNull ?? optional.firstOrNull;
      if (victim == null) break;
      remove(victim);
    }
    return changed;
  }

  Future<void> _loadTiles() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      while (mounted && widget.isViewed) {
        final missing = _wanted.where((key) => !_tiles.containsKey(key));
        final memory = ImageMemoryManager.instance;
        final prefetch = _prefetch;
        final canPrefetch =
            !memory.underPressure.value &&
            prefetch != null &&
            !_tiles.containsKey(prefetch) &&
            _tiles.length < _tileLimit &&
            memory.retainedBytes + _maxTileBytes <= ImageMemoryManager.maxRetainedBytes;
        final key = missing.firstOrNull ?? (canPrefetch ? prefetch : null);
        if (key == null) break;
        final side = _tileSide * key.sample;
        final region = Rect.fromLTRB(
          (key.x * side).toDouble(),
          (key.y * side).toDouble(),
          math.min(((key.x + 1) * side).toDouble(), widget.source.size.width),
          math.min(((key.y + 1) * side).toDouble(), widget.source.size.height),
        );
        final token = CancelToken();
        _inFlight = key;
        _tileRequest = token;
        final padded = region.inflate(key.sample.toDouble()).intersect(Offset.zero & widget.source.size);
        final incomingBytes =
            (padded.width / key.sample).ceil() * (padded.height / key.sample).ceil() * widget.source._bytesPerPixel;
        if (_trimTiles(incomingBytes: incomingBytes, incomingCount: 1)) setState(() {});
        try {
          final tile = await widget.source._load(
            region,
            key.sample,
            token,
            withGutter: true,
            isForeground: () => mounted && widget.isViewed && _wanted.contains(key),
            isSourceVisible: () => mounted && widget.isViewed,
          );
          if (!mounted || !widget.isViewed || token.isCancelled || (!_wanted.contains(key) && key != _prefetch)) {
            tile.dispose();
          } else {
            setState(() {
              _tiles[key] = tile;
              _trimTiles();
            });
            _decodedTiles++;
            _markReady();
            _trackCoverage();
            // A wide-gamut fallback may increase the per-tile reservation.
            // Recompute the sample before admitting more detail at that level.
            if (_wanted.length > _tileLimit) {
              _schedule();
              break;
            }
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
      _inFlight = null;
    }
  }

  @override
  void dispose() {
    _lifetime.cancel();
    _tileRequest?.cancel();
    _subscription?.cancel();
    _finishCoverage();
    ImageMemoryManager.instance.underPressure.removeListener(_schedule);
    _overview?.dispose();
    for (final tile in _tiles.values) {
      tile.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Coarse coverage is replaced by finer pixels regardless of cache recency.
    final tiles = _tiles.values.toList()
      ..sort((a, b) {
        final level = b.sample.compareTo(a.sample);
        if (level != 0) return level;
        final row = a.region.top.compareTo(b.region.top);
        return row != 0 ? row : a.region.left.compareTo(b.region.left);
      });
    return CustomPaint(
      size: widget.source.size,
      painter: _RegionPainter([?_overview, ...tiles]),
    );
  }
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
  bool shouldRepaint(_RegionPainter oldDelegate) => !listEquals(tiles, oldDelegate.tiles);
}
