// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:dio/dio.dart';
import 'package:flutter_avif/flutter_avif.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/services/image_download_request.dart';
import 'package:lolisnatcher/src/services/image_metadata.dart';
import 'package:lolisnatcher/src/services/bounded_image_codec.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/abstract_custom_network_image.dart' as custom_network_image;

class DownloadedImageFile {
  DownloadedImageFile(File file, {bool ownsFile = false, Directory? temporaryDirectory})
    : _state = _DownloadedFileState(file, ownsFile, temporaryDirectory);

  DownloadedImageFile._retained(this._state);

  final _DownloadedFileState _state;
  bool _released = false;

  File get file => _state.file;
  bool get ownsFile => _state.ownsFile;
  Directory? get temporaryDirectory => _state.temporaryDirectory;

  /// Each owner releases its own handle. A prepared viewer source can be
  /// released while an image codec still owns the file's native mapping.
  DownloadedImageFile retain() {
    if (_released) throw StateError('Cannot retain a released image file handle');
    _state.references++;
    return DownloadedImageFile._retained(_state);
  }

  Future<void> dispose() {
    if (!_released) {
      _released = true;
      _state.references--;
    }
    // A repeated dispose can retry cleanup if a transient Windows file lock
    // outlived the earlier attempts; releasing a handle is always idempotent.
    return _state.cleanup();
  }
}

class _DownloadedFileState {
  _DownloadedFileState(this.file, this.ownsFile, this.temporaryDirectory);

  final File file;
  final bool ownsFile;
  final Directory? temporaryDirectory;
  int references = 1;
  bool _cleanupComplete = false;
  Future<void>? _cleanupFuture;

  Future<void> cleanup() {
    if (references != 0 || _cleanupComplete) return Future<void>.value();
    return _cleanupFuture ??= _deleteOwnedFile().whenComplete(() => _cleanupFuture = null);
  }

  Future<void> _deleteOwnedFile() async {
    if (!ownsFile) {
      _cleanupComplete = true;
      return;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await file.exists()) await file.delete();
        // Never recursively delete: this directory belongs to one download.
        if (temporaryDirectory != null && await temporaryDirectory!.exists()) {
          await temporaryDirectory!.delete();
        }
        _cleanupComplete = true;
        return;
      } on FileSystemException {
        // A released native mapping may take a short time to unlock on
        // Windows. Failed cleanup remains retryable, rather than completed.
        if (attempt < 4) await Future<void>.delayed(Duration(milliseconds: 50 << attempt));
      }
    }
  }
}

final Object _safeResizeZone = Object();
final Object _decodeSessionZone = Object();

/// Keeps ResizeImage's key and resize policy, but bounds its target dimensions.
/// Flutter's ResizeImage cannot compose a provider-supplied getTargetSize. The
/// scoped marker lets our provider pass its callback to the bounded decoder.
class SafeResizeImage extends ResizeImage {
  const SafeResizeImage(
    super.imageProvider, {
    super.width,
    super.height,
    super.policy,
    super.allowUpscaling,
  });

  @override
  ImageStream createStream(ImageConfiguration configuration) => _ConsumerImageStream(
    imageProvider is CustomNetworkImage ? (imageProvider as CustomNetworkImage).cancelToken : null,
  );

  @override
  ImageStreamCompleter loadImage(ResizeImageKey key, ImageDecoderCallback decode) {
    if (imageProvider is! CustomNetworkImage) return super.loadImage(key, decode);
    final completer = runZoned(
      () => super.loadImage(key, _decodeBounded),
      zoneValues: {_safeResizeZone: true},
    );
    if (completer is _MemoryImageCompleter) completer.cacheKey = key;
    return completer;
  }
}

@immutable
class CustomNetworkImage extends ImageProvider<custom_network_image.CustomNetworkImage>
    implements custom_network_image.CustomNetworkImage {
  const CustomNetworkImage(
    this.url, {
    this.scale = 1,
    this.headers,
    this.cancelToken,
    this.withCache = false,
    this.cacheFolder,
    this.fileNameExtras = '',
    this.onCacheDetected,
    this.onError,
    this.sendTimeout,
    this.receiveTimeout,
    this.withCaptchaCheck = false,
    this.localFilePath,
    this.preparedSource,
  }) : assert(!withCache || cacheFolder != null, 'cacheFolder must be set when withCache is true');

  @override
  final String url;
  @override
  final double scale;
  @override
  final Map<String, String>? headers;
  final CancelToken? cancelToken;
  final bool withCache;
  final String? cacheFolder;
  final String fileNameExtras;
  final void Function(bool)? onCacheDetected;
  final void Function(Object)? onError;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;
  final bool withCaptchaCheck;

  /// A prepared source whose lifetime belongs to the caller. URL/configuration
  /// remain the cache key so preparing a file does not defeat image reuse.
  final String? localFilePath;

  /// Prefer this over a bare path for owned temporary files. Retained only when
  /// an actual load begins; a Flutter image-cache hit creates no extra owner.
  final DownloadedImageFile? preparedSource;
  bool get _isAvif => false;

  @override
  Future<CustomNetworkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStream createStream(ImageConfiguration configuration) => _ConsumerImageStream(cancelToken);

  @override
  ImageStreamCompleter loadImage(custom_network_image.CustomNetworkImage key, ImageDecoderCallback decode) {
    final chunks = StreamController<ImageChunkEvent>();
    // A cached completer may already serve several widgets. Its work belongs
    // to that shared lifetime, not to the first widget's cancellation token.
    // Viewer-owned preflight/download work still uses its caller's token.
    final session = _DecodeSession(isAvif: _isAvif);
    final selectedDecode = Zone.current[_safeResizeZone] == true ? decode : _decodeBounded;
    final codec = runZoned(
      () => _loadAsync(key, chunks, selectedDecode, session),
      zoneValues: {_decodeSessionZone: session},
    );
    return _MemoryImageCompleter(
      session: session,
      codec: codec,
      chunkEvents: chunks.stream,
      scale: key.scale,
      cacheKey: key,
    );
  }

  Future<bool> deleteCacheFile() async {
    await NetworkImageLoader.deleteCache(url, cacheFolder, fileNameExtras);
    return true;
  }

  Future<ui.Codec> _loadAsync(
    custom_network_image.CustomNetworkImage key,
    StreamController<ImageChunkEvent> chunks,
    ImageDecoderCallback decode,
    _DecodeSession session,
  ) async {
    DownloadedImageFile? source;
    ui.Codec? pendingCodec;
    var sourceTransferred = false;
    try {
      // Retain synchronously before the first await, so viewer disposal cannot
      // delete a prepared file while this decode is queued or still reading it.
      source = preparedSource?.retain();
      source ??= localFilePath != null
          ? DownloadedImageFile(File(localFilePath!))
          : await NetworkImageLoader.downloadFile(
              ImageDownloadRequest(
                url: url,
                cacheFolder: cacheFolder,
                fileNameExtras: fileNameExtras,
                withCache: withCache,
                headers: headers,
                sendTimeout: sendTimeout,
                receiveTimeout: receiveTimeout,
                withCaptchaCheck: withCaptchaCheck,
              ),
              cancelToken: session.cancelToken,
              chunkEvents: chunks,
              onCacheDetected: onCacheDetected,
            );
      session.file = source.file;
      session.encodedBytes = await source.file.length();
      NetworkImageLoader._checkLength(session.encodedBytes);
      if (session.encodedBytes == 0) throw const FormatException('Empty image');
      // File mapping, metadata parsing and codec construction share one slot,
      // preventing queued jobs from each retaining another encoded buffer.
      pendingCodec = await ImageMemoryManager.instance.runDecode(
        ImageMemoryManager.maxTransientBytes,
        () async {
          session.checkCancelled();
          ui.ImmutableBuffer? buffer;
          try {
            buffer = await ui.ImmutableBuffer.fromFilePath(source!.file.path);
            session.checkCancelled();
            final ownedBuffer = buffer;
            buffer = null; // The bounded decoder owns disposal from here.
            final codec = await decode(ownedBuffer);
            if (session.disposed || session.cancelToken.isCancelled) {
              codec.dispose();
              session.checkCancelled();
            }
            return codec;
          } finally {
            buffer?.dispose();
          }
        },
        cancelToken: session.cancelToken,
      );
      session.checkCancelled();
      session.source = source;
      sourceTransferred = true;
      final result = pendingCodec!;
      pendingCodec = null;
      return result;
    } catch (error) {
      pendingCodec?.dispose();
      session.releaseReservations();
      if (!session.abandoned) {
        onError?.call(error);
        scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key, includeLive: false));
      }
      rethrow;
    } finally {
      if (!sourceTransferred) await source?.dispose();
      // Closing must not wait for a chunk listener after a disposed completer.
      unawaited(chunks.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CustomNetworkImage &&
      other.url == url &&
      other.scale == scale &&
      other.headers == headers &&
      other.withCache == withCache &&
      other.cacheFolder == cacheFolder &&
      other.fileNameExtras == fileNameExtras &&
      other.sendTimeout == sendTimeout &&
      other.receiveTimeout == receiveTimeout &&
      other.withCaptchaCheck == withCaptchaCheck;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    url,
    scale,
    headers,
    withCache,
    cacheFolder,
    fileNameExtras,
    sendTimeout,
    receiveTimeout,
    withCaptchaCheck,
  );

  @override
  String toString() => '${objectRuntimeType(this, 'CustomNetworkImage')}(scale: $scale)';
}

class CustomNetworkAvifImage extends CustomNetworkImage {
  const CustomNetworkAvifImage(
    super.url, {
    super.scale,
    super.headers,
    super.cancelToken,
    super.withCache,
    super.cacheFolder,
    super.fileNameExtras,
    super.onCacheDetected,
    super.onError,
    super.sendTimeout,
    super.receiveTimeout,
    super.withCaptchaCheck,
    super.localFilePath,
    super.preparedSource,
  });

  @override
  bool get _isAvif => true;
}

class _DecodeSession {
  _DecodeSession({required this.isAvif});

  final CancelToken cancelToken = CancelToken();
  final bool isAvif;
  late File file;
  DownloadedImageFile? source;
  bool isGif = false;
  int encodedBytes = 0;
  int transientBytes = 0;
  ImageMemoryLease? outputLease;
  ImageMemoryLease? codecLease;
  ui.Image? pendingFrame;
  bool hasEmittedFrame = false;
  bool disposed = false;
  bool abandoned = false;

  void checkCancelled() {
    cancelToken.throwIfCancellationRequested();
    if (disposed) throw StateError('Image stream has been disposed');
  }

  void releaseReservations() {
    outputLease?.release();
    codecLease?.release();
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    cancelToken.cancel();
    pendingFrame?.dispose();
    pendingFrame = null;
    releaseReservations();
    // Retry earlier cleanup after cached static images release their completer.
    // An active codec must retain its handle until its native mapping closes.
    final releasedSource = source;
    if (releasedSource != null && releasedSource._released) unawaited(releasedSource.dispose());
  }
}

/// Tracks widget subscriptions, excluding ImageCache's internal pending listener.
/// The same completer can serve several streams and several listeners per stream.
class _ConsumerImageStream extends ImageStream {
  _ConsumerImageStream(this._cancelToken);

  final CancelToken? _cancelToken;
  final List<ImageStreamListener> _consumers = [];
  _MemoryImageCompleter? _owner;
  bool _registered = false;
  bool _hasListened = false;

  void _syncOwner() {
    if (_owner == null) return;
    // A caller token covers temporary listener removal (for example, pausing
    // Image in TickerMode) until that widget actually abandons its request.
    final active = _cancelToken == null ? _consumers.isNotEmpty : _hasListened && !_cancelToken.isCancelled;
    if (active == _registered) return;
    _registered = active;
    _owner!.changeConsumers(active ? 1 : -1);
  }

  @override
  void setCompleter(ImageStreamCompleter value) {
    if (value is _MemoryImageCompleter) {
      _owner = value;
      value.registerCacheOwner();
      _syncOwner();
      value.changeConsumers(0);
    }
    super.setCompleter(value);
  }

  @override
  void addListener(ImageStreamListener listener) {
    _consumers.add(listener);
    if (!_hasListened) {
      _hasListened = true;
      if (_cancelToken != null) {
        // Keep this ownership registration until its token releases it, even
        // if the widget removes its final listener before canceling the token.
        unawaited(_cancelToken.whenCancel.then((_) => _syncOwner()));
      }
    }
    _syncOwner();
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    if (!_consumers.remove(listener)) return;
    super.removeListener(listener);
    _syncOwner();
  }
}

class _MemoryImageCompleter extends MultiFrameImageStreamCompleter {
  _MemoryImageCompleter({
    required this.session,
    required Future<ui.Codec> codec,
    required this.cacheKey,
    required super.scale,
    super.chunkEvents,
  }) : super(
         codec: codec.then((value) {
           if (session.disposed) {
             value.dispose();
             session.checkCancelled();
           }
           return value;
         }),
       );

  final _DecodeSession session;
  static final Map<Object, WeakReference<_MemoryImageCompleter>> _pendingOwners = {};
  Object cacheKey;

  void registerCacheOwner() {
    // Resolution has now finished assigning the effective key, including a
    // ResizeImage wrapper. Never temporarily register a resized load under
    // its raw provider key: an independent raw load may already own that key.
    if (!session.hasEmittedFrame && !session.disposed && !session.abandoned) {
      _pendingOwners[cacheKey] = WeakReference(this);
    }
  }

  void _forgetPendingOwner() {
    if (identical(_pendingOwners[cacheKey]?.target, this)) _pendingOwners.remove(cacheKey);
  }

  int _consumers = 0;
  bool _abandonCheckScheduled = false;

  void changeConsumers(int delta) {
    _consumers += delta;
    assert(_consumers >= 0, 'Image consumer count cannot be negative');
    if (_consumers != 0 || session.hasEmittedFrame || session.disposed || _abandonCheckScheduled) return;
    _abandonCheckScheduled = true;
    // Let widgets replace subscriptions or attach to a newly resolved stream
    // in this frame before deciding the pending image has no remaining users.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _abandonCheckScheduled = false;
      if (_consumers != 0 || session.hasEmittedFrame || session.disposed || session.abandoned) return;
      session.abandoned = true;
      // A manual restart may have replaced the cache entry before this frame
      // callback runs. Cancel our work without evicting the newer completer.
      if (identical(_pendingOwners[cacheKey]?.target, this)) {
        _forgetPendingOwner();
        PaintingBinding.instance.imageCache.evict(cacheKey);
      }
      session.cancelToken.cancel('Image no longer has consumers');
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void reportError({
    required Object exception,
    DiagnosticsNode? context,
    StackTrace? stack,
    InformationCollector? informationCollector,
    bool silent = false,
  }) {
    // An abandoned stream has already been evicted. Reporting its delayed
    // cancellation would run ResizeImage's error eviction against a new load
    // with the same key, or deliver an obsolete error to a departed widget.
    if (session.abandoned) return;
    _forgetPendingOwner();
    super.reportError(
      context: context,
      exception: exception,
      stack: stack,
      informationCollector: informationCollector,
      silent: silent,
    );
  }

  @override
  void setImage(ImageInfo image) {
    // The superclass disposes the native frame immediately after emitting its
    // clone. A pending, un-emitted frame instead belongs to onDisposed below.
    session.pendingFrame = null;
    session.hasEmittedFrame = true;
    _forgetPendingOwner();
    super.setImage(image);
  }

  @override
  void onDisposed() {
    _forgetPendingOwner();
    session.dispose();
    super.onDisposed();
  }
}

({int width, int height}) _targetSize(int width, int height, ui.TargetImageSizeCallback? callback) {
  final requested = callback?.call(width, height);
  var ratio = 1.0;
  if (requested?.width != null) ratio = math.min(ratio, requested!.width! / width);
  if (requested?.height != null) ratio = math.min(ratio, requested!.height! / height);
  ratio = math.min(ratio, ImageMemoryManager.maxTextureDimension / math.max(width, height));
  ratio = math.min(ratio, math.sqrt(ImageMemoryManager.maxOutputPixels / (width * height)));
  return (width: math.max(1, (width * ratio).floor()), height: math.max(1, (height * ratio).floor()));
}

Future<ui.Codec> _decodeBounded(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) async {
  final session = Zone.current[_decodeSessionZone] as _DecodeSession;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    session.checkCancelled();
    if (session.isAvif) return await _decodeAvif(session, getTargetSize);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    session.checkCancelled();
    final width = descriptor.width;
    final height = descriptor.height;
    ImageMetadata.checkDimensions(width, height);
    final animation = await ImageMetadata.inspectAnimation(session.file, session.cancelToken);
    session.isGif = animation.isGif;
    if (animation.animated) {
      ImageMetadata.checkDimensions(width, height, pixelLimit: ImageMemoryManager.maxAnimatedSourcePixels);
    }
    final target = _targetSize(width, height, getTargetSize);
    final pixels = target.width * target.height;
    session.transientBytes = session.encodedBytes + width * height * 4 + pixels * 4;
    if (session.transientBytes > ImageMemoryManager.maxTransientBytes) {
      throw const ImageMemoryException('Decode exceeds the transient memory budget');
    }
    session.outputLease = ImageMemoryManager.instance.reserveImage(pixels * 4);
    session.codecLease = ImageMemoryManager.instance.reserveImage(session.encodedBytes);
    codec = await descriptor.instantiateCodec(targetWidth: target.width, targetHeight: target.height);
    session.checkCancelled();
    if (codec.frameCount > 1) {
      ImageMetadata.checkDimensions(width, height, pixelLimit: ImageMemoryManager.maxAnimatedSourcePixels);
      if (width > ImageMemoryManager.maxTextureDimension || height > ImageMemoryManager.maxTextureDimension) {
        throw const ImageMemoryException('Animated source exceeds the native texture limit');
      }
      final sourceBytes = width * height * 4;
      final targetBytes = pixels * 4;
      // The engine ignores target dimensions for multi-frame codecs. It keeps
      // a source-sized backdrop; APNG also caches decoded frame pixels (and
      // may have a separate default image). Allow 8-byte cached PNG pixels.
      final frameCacheBytes = animation.isApng ? (codec.frameCount + 1) * sourceBytes * 2 : 0;
      session.transientBytes = session.encodedBytes + frameCacheBytes + sourceBytes * 6 + targetBytes * 8;
      if (session.transientBytes > ImageMemoryManager.maxTransientBytes) {
        throw const ImageMemoryException('Animated frame work exceeds the transient memory budget');
      }
      session.outputLease!.release();
      // Native and Picture.toImage textures may have mipmaps. Up to twice the
      // base RGBA bytes covers a complete mip chain, including narrow images.
      session.outputLease = ImageMemoryManager.instance.reserveImage(targetBytes * 2);
      session.codecLease!.release();
      session.codecLease = ImageMemoryManager.instance.reserveImage(
        session.encodedBytes + frameCacheBytes + sourceBytes + targetBytes * 2,
      );
      codec = BoundedImageCodec(
        codec,
        expectedSourceWidth: width,
        expectedSourceHeight: height,
        targetWidth: target.width,
        targetHeight: target.height,
      );
    }
    // The pinned engine's SingleFrameCodec keeps this descriptor until its
    // first frame is decoded. dispose() clears the generator even when the
    // native codec still references it, so transfer ownership to the codec.
    final wrapped = _ManagedCodec(codec, session, descriptor);
    codec = null;
    descriptor = null;
    return wrapped;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Keeps frame allocation serialized, including animations. Codec lifetime and
/// output lifetime are separate: Flutter disposes static codecs after frame 1.
class _ManagedCodec implements ui.Codec {
  _ManagedCodec(this._codec, this._session, [this._descriptor])
    : frameCount = _codec.frameCount,
      repetitionCount = _codec.repetitionCount;

  final ui.Codec _codec;
  final _DecodeSession _session;
  final ui.ImageDescriptor? _descriptor;
  bool _disposed = false;
  bool _inFrame = false;
  bool _released = false;

  @override
  final int frameCount;
  @override
  final int repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    // MultiFrameImageStreamCompleter disposes any previous pending frame before
    // requesting the next one, including after reattaching to a cached stream.
    _session.pendingFrame = null;
    try {
      return await ImageMemoryManager.instance.runDecode(
        _session.transientBytes,
        () async {
          _session.checkCancelled();
          if (_disposed) throw StateError('Codec has been disposed');
          _inFrame = true;
          try {
            final frame = await _codec.getNextFrame();
            if (_disposed || _session.cancelToken.isCancelled || _session.disposed) {
              frame.image.dispose();
              _session.checkCancelled();
              throw StateError('Codec has been disposed');
            }
            _session.pendingFrame = frame.image;
            if (_session.isGif && frame.duration < const Duration(milliseconds: 100)) {
              return _FrameInfo(frame.image, const Duration(milliseconds: 100));
            }
            return frame;
          } finally {
            _inFrame = false;
            if (_disposed) _releaseCodec();
          }
        },
        cancelToken: _session.cancelToken,
      );
    } catch (_) {
      // Flutter reports frame errors without disposing its codec. End native
      // work here, including failures/cancellation while queued for a slot.
      dispose();
      // A previously emitted image still belongs to the completer/cache. Its
      // output lease must survive a later animation failure until onDisposed.
      if (!_session.hasEmittedFrame && _session.pendingFrame == null) {
        _session.outputLease?.release();
      }
      rethrow;
    }
  }

  void _releaseCodec() {
    if (_released) return;
    _released = true;
    try {
      _codec.dispose();
    } finally {
      _descriptor?.dispose();
      _session.codecLease?.release();
      unawaited(_session.source?.dispose());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_inFrame) _releaseCodec();
  }
}

Future<T> _guardAvif<T>(Future<T> Function() operation) {
  final result = Completer<T>();
  runZonedGuarded(
    () {
      unawaited(operation().then(result.complete, onError: result.completeError));
    },
    (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future;
}

Future<ui.Codec> _decodeAvif(_DecodeSession session, ui.TargetImageSizeCallback? callback) async {
  // libavif allocates full-size RGBA before Flutter sees the result. Inspect
  // bounded container metadata first, including all declared image properties.
  final dimensions = await ImageMetadata.inspectAvif(session.file, session.cancelToken);
  ImageMetadata.checkDimensions(
    dimensions.width,
    dimensions.height,
    pixelLimit: ImageMemoryManager.maxAvifSourcePixels,
  );
  if (dimensions.width > ImageMemoryManager.maxTextureDimension ||
      dimensions.height > ImageMemoryManager.maxTextureDimension) {
    throw const ImageMemoryException('AVIF dimensions exceed the native frame limit');
  }
  final target = _targetSize(dimensions.width, dimensions.height, callback);
  final pixels = target.width * target.height;
  session.transientBytes = session.encodedBytes * 2 + dimensions.width * dimensions.height * 16 + pixels * 8;
  if (session.transientBytes > ImageMemoryManager.maxTransientBytes) {
    throw const ImageMemoryException('AVIF exceeds the transient memory budget');
  }
  session.outputLease = ImageMemoryManager.instance.reserveImage(pixels * 4);
  session.codecLease = ImageMemoryManager.instance.reserveImage(
    session.encodedBytes + dimensions.width * dimensions.height * 4 + pixels * 4,
  );
  session.checkCancelled();
  final bytes = await session.file.readAsBytes();
  session.checkCancelled();
  NetworkImageLoader._checkLength(bytes.length);
  final type = isAvifFile(bytes.sublist(0, math.min(16, bytes.length)));
  if (type == AvifFileType.unknown) throw const FormatException('Invalid AVIF header');
  AvifCodec? avif;
  try {
    await _guardAvif(() async {
      avif = type == AvifFileType.avif
          ? SingleFrameAvifCodec(bytes: bytes)
          : MultiFrameAvifCodec(key: identityHashCode(session), avifBytes: bytes, overrideDurationMs: -1);
      await avif!.ready();
    });
    session.checkCancelled();
    return _ManagedCodec(_AvifCodecAdapter(avif!, target.width, target.height), session);
  } catch (_) {
    avif?.dispose();
    rethrow;
  }
}

class _AvifCodecAdapter implements ui.Codec {
  _AvifCodecAdapter(this.codec, this.width, this.height);

  final AvifCodec codec;
  final int width;
  final int height;

  @override
  int get frameCount => codec.frameCount;
  @override
  int get repetitionCount => -1;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = await _guardAvif(codec.getNextFrame);
    if (frame.image.width == width && frame.image.height == height) return _FrameInfo(frame.image, frame.duration);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      frame.image,
      ui.Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return _FrameInfo(await picture.toImage(width, height), frame.duration);
    } finally {
      picture.dispose();
      frame.image.dispose();
    }
  }

  @override
  void dispose() => codec.dispose();
}

class _FrameInfo implements ui.FrameInfo {
  const _FrameInfo(this.image, this.duration);

  @override
  final ui.Image image;
  @override
  final Duration duration;
}

class NetworkImageLoader {
  static const Duration _defaultReceiveTimeout = Duration(seconds: 30);

  /// Inspects bounded AVIF container metadata without invoking its decoder.
  static Future<ui.Size> inspectAvifSize(File file, {CancelToken? cancelToken}) =>
      inspectImageSize(file, cancelToken: cancelToken, isAvif: true);

  /// Metadata is serialized with native decode work so simultaneous viewer
  /// preflights cannot retain a separate large encoded mapping per image.
  /// Source dimensions are returned without a whole-image decode. The provider
  /// still applies its own source/output limits before constructing a codec.
  static Future<ui.Size> inspectImageSize(File file, {CancelToken? cancelToken, bool isAvif = false}) async {
    final token = cancelToken ?? CancelToken();
    token.throwIfCancellationRequested();
    final length = await file.length();
    _checkLength(length);
    return ImageMemoryManager.instance.runDecode(
      length + 1024 * 1024,
      () async {
        token.throwIfCancellationRequested();
        _checkLength(await file.length());
        if (isAvif) {
          final dimensions = await ImageMetadata.inspectAvif(file, token);
          token.throwIfCancellationRequested();
          return ui.Size(dimensions.width.toDouble(), dimensions.height.toDouble());
        }
        ui.ImmutableBuffer? buffer;
        ui.ImageDescriptor? descriptor;
        try {
          buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
          token.throwIfCancellationRequested();
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          token.throwIfCancellationRequested();
          return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
        } finally {
          descriptor?.dispose();
          buffer?.dispose();
        }
      },
      cancelToken: token,
    );
  }

  static void _checkLength(int length) {
    if (length > ImageMemoryManager.maxEncodedBytes) {
      throw const ImageMemoryException('Encoded image exceeds 64 MiB');
    }
  }

  static Future<void> _commitCacheFile(File temporary, String destination) async {
    final existing = File(destination);
    // Preserve a valid winner if another download has already committed.
    if (await existing.exists() && await existing.length() >= 10) {
      await temporary.delete();
      return;
    }
    try {
      await temporary.rename(destination);
    } on FileSystemException {
      if (await existing.exists() && await existing.length() >= 10) {
        await temporary.delete();
      } else {
        rethrow;
      }
    }
  }

  static Future<DownloadedImageFile> downloadFile(
    ImageDownloadRequest request, {
    CancelToken? cancelToken,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function(bool)? onCacheDetected,
    void Function(int, int?)? onReceiveProgress,
  }) => ImageMemoryManager.instance.runDownload(
    () => _downloadFile(
      request,
      cancelToken: cancelToken,
      chunkEvents: chunkEvents,
      onCacheDetected: onCacheDetected,
      onReceiveProgress: onReceiveProgress,
    ),
    cancelToken: cancelToken,
  );

  static Future<DownloadedImageFile> _downloadFile(
    ImageDownloadRequest request, {
    CancelToken? cancelToken,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function(bool)? onCacheDetected,
    void Function(int, int?)? onReceiveProgress,
  }) async {
    cancelToken?.throwIfCancellationRequested();
    final resolved = Uri.base.resolve(request.url);
    final cachePath = await ImageWriter().getCachePathString(
      resolved.toString(),
      request.cacheFolder ?? 'media',
      clearName: request.cacheFolder != 'favicons',
      fileNameExtras: request.fileNameExtras,
    );

    void progress(int received, int? total) {
      if (chunkEvents?.isClosed == false) {
        chunkEvents!.add(ImageChunkEvent(cumulativeBytesLoaded: received, expectedTotalBytes: total));
      }
      onReceiveProgress?.call(received, total);
    }

    if (request.withCache) {
      final cached = File(cachePath);
      if (await cached.exists()) {
        final length = await cached.length();
        _checkLength(length); // A valid, oversized original must not be deleted.
        if (length >= 10) {
          cancelToken?.throwIfCancellationRequested();
          onCacheDetected?.call(true);
          progress(length, length);
          return DownloadedImageFile(cached);
        }
        await cached.delete();
      }
    }
    onCacheDetected?.call(false);
    cancelToken?.throwIfCancellationRequested();
    final parent = request.withCache ? File(cachePath).parent : Directory.systemTemp;
    await parent.create(recursive: true);
    final directory = await parent.createTemp('image-download-');
    final temporary = DownloadedImageFile(
      File('${directory.path}${Platform.pathSeparator}image'),
      ownsFile: true,
      temporaryDirectory: directory,
    );
    final client = DioNetwork.getClient(skipLogging: !SettingsHandler.instance.useImageLogging.value);
    // Captcha retries inherit streaming and timeouts from the client defaults.
    client.options.responseType = ResponseType.stream;
    client.options.receiveTimeout = request.receiveTimeout ?? _defaultReceiveTimeout;
    client.options.sendTimeout = request.sendTimeout;
    if (request.withCaptchaCheck) DioNetwork.captchaInterceptor(client, customUserAgent: Tools.appUserAgent);
    RandomAccessFile? output;
    var returnedTemporary = false;
    try {
      final response = await client.getUri<ResponseBody>(
        resolved,
        options: Options(
          headers: request.headers,
          responseType: ResponseType.stream,
          followRedirects: request.headers?.containsKey('LS-IGNORE-REDIRECT') != true,
        ),
        cancelToken: cancelToken,
      );
      cancelToken?.throwIfCancellationRequested();
      if (!Tools.isGoodResponse(response) || response.data == null) {
        throw NetworkImageLoadException(statusCode: response.statusCode ?? 0, uri: resolved);
      }
      final declared = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
      if (declared != null) _checkLength(declared);
      output = await temporary.file.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.data!.stream.timeout(request.receiveTimeout ?? _defaultReceiveTimeout)) {
        cancelToken?.throwIfCancellationRequested();
        received += chunk.length;
        _checkLength(received); // Also bounds chunked and incorrectly declared bodies.
        await output.writeFrom(chunk); // Backpressure: no accumulating IOSink queue.
        progress(received, declared != null && declared > 0 ? declared : null);
      }
      await output.close();
      output = null;
      cancelToken?.throwIfCancellationRequested();
      if (received == 0) throw const FormatException('Empty image');
      // Content-Length describes compressed transport bytes when auto-unzipped.
      final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
      if (declared != null && declared > 0 && (encoding == null || encoding == 'identity') && received != declared) {
        throw const FormatException('Incomplete image download');
      }
      if (request.withCache) {
        await _commitCacheFile(temporary.file, cachePath);
        final result = File(cachePath);
        _checkLength(await result.length());
        cancelToken?.throwIfCancellationRequested();
        return DownloadedImageFile(result);
      }
      returnedTemporary = true;
      return temporary;
    } finally {
      client.close(force: true);
      await output?.close();
      if (!returnedTemporary) await temporary.dispose();
    }
  }

  /// Compatibility for callers that explicitly need bytes; providers use files.
  static Future<Uint8List> downloadAndCache(
    ImageDownloadRequest request, {
    CancelToken? cancelToken,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function(bool)? onCacheDetected,
    void Function(int, int?)? onReceiveProgress,
  }) async {
    final downloaded = await downloadFile(
      request,
      cancelToken: cancelToken,
      chunkEvents: chunkEvents,
      onCacheDetected: onCacheDetected,
      onReceiveProgress: onReceiveProgress,
    );
    try {
      cancelToken?.throwIfCancellationRequested();
      _checkLength(await downloaded.file.length());
      final bytes = await downloaded.file.readAsBytes();
      cancelToken?.throwIfCancellationRequested();
      _checkLength(bytes.length);
      return bytes;
    } finally {
      await downloaded.dispose();
    }
  }

  static Future<Uint8List> tryFixGifSpeed(String url, Uint8List image) async {
    if (!url.toLowerCase().contains('.gif')) return image;
    for (var i = 0; i < image.length - 6; i++) {
      if (image[i] == 0x21 && image[i + 1] == 0xf9 && image[i + 2] == 4) {
        final delay = image[i + 4] | (image[i + 5] << 8);
        if (delay < 10) image[i + 4] = 10;
        i += 5;
      }
    }
    return image;
  }

  static Future<void> deleteCache(String url, String? cacheFolder, String fileNameExtras) async {
    final cachePath = await ImageWriter().getCachePathString(
      Uri.base.resolve(url).toString(),
      cacheFolder ?? 'media',
      clearName: cacheFolder != 'favicons',
      fileNameExtras: fileNameExtras,
    );
    try {
      final file = File(cachePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cache removal is best effort.
    }
  }
}
