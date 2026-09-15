import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';

/// All session mutations run inside the global decode queue, including closes.
/// The caller owns both the returned image and its retained-memory lease.
class ImageRegionDecoder {
  ImageRegionDecoder._() {
    _memory.underPressure.addListener(_onPressure);
  }

  static final ImageRegionDecoder instance = ImageRegionDecoder._();
  final ImageMemoryManager _memory = ImageMemoryManager.instance;
  _RegionDecoderSession? _session;

  // Input storage plus a conservative allowance for decoder metadata/state.
  static const _nativeOverhead = 8 * 1024 * 1024;
  // Includes a 16 MiB bitmap cap, bounded PNG staging + copy, channel
  // copies, Dart/engine buffers, and the final tile while they overlap.
  static const _tileTransientBytes = 128 * 1024 * 1024;

  Future<DecodedImageRegion> load(
    File file, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    required int sampleSize,
    required CancelToken cancelToken,
    required bool Function() isForeground,
    bool Function()? isSourceVisible,
  }) {
    if (left < 0 ||
        top < 0 ||
        right <= left ||
        bottom <= top ||
        sampleSize < 1 ||
        sampleSize > 262144 ||
        (sampleSize & (sampleSize - 1)) != 0) {
      return Future.error(ArgumentError('Invalid image region'));
    }
    final expectedWidth = (right - left + sampleSize - 1) ~/ sampleSize;
    final expectedHeight = (bottom - top + sampleSize - 1) ~/ sampleSize;
    if (expectedWidth > 1024 || expectedHeight > 1024) {
      return Future.error(const ImageMemoryException('Image region exceeds the tile limit'));
    }
    final visible = isSourceVisible ?? isForeground;
    final timeline = TimelineTask()..start('ImageRegionDecoder.load');
    return _memory
        .runDecode(
          ImageMemoryManager.maxEncodedBytes + _nativeOverhead + _tileTransientBytes,
          () async {
            timeline.instant('admitted');
            try {
              cancelToken.throwIfCancellationRequested();
              if (_session != null && (_memory.underPressure.value || (visible() && _session!.path != file.path))) {
                await _close(_session!);
              }
              cancelToken.throwIfCancellationRequested();
              if (_session == null && visible() && !_memory.underPressure.value) {
                final length = await file.length();
                cancelToken.throwIfCancellationRequested();
                if (length <= 0 || length > ImageMemoryManager.maxEncodedBytes) {
                  throw const ImageMemoryException('Image source exceeds the encoded limit');
                }
                final reservation = length + _nativeOverhead;
                // Optional caching must never provoke pressure or evict visible tiles.
                // The check and reservation are synchronous on this isolate.
                if (visible() &&
                    !_memory.underPressure.value &&
                    _memory.retainedBytes + reservation + expectedWidth * expectedHeight * 8 <=
                        ImageMemoryManager.maxRetainedBytes) {
                  _session = _RegionDecoderSession(file.path, _memory.reserveImage(reservation));
                }
              }
              cancelToken.throwIfCancellationRequested();
              final session = _session?.path == file.path ? _session : null;
              Map<String, dynamic> response;
              try {
                response = await ServiceHandler.decodeImageRegion(
                  file.path,
                  left: left,
                  top: top,
                  right: right,
                  bottom: bottom,
                  sampleSize: sampleSize,
                  retainDecoder: session != null,
                );
              } catch (_) {
                // Native may have retained the source before failing the tile.
                if (session != null) await _close(session);
                rethrow;
              }
              if (session != null && (_memory.underPressure.value || !visible())) {
                await _close(session);
              }
              cancelToken.throwIfCancellationRequested();
              return await _createImage(response, expectedWidth, expectedHeight, cancelToken);
            } on PlatformException catch (error) {
              if (error.code == 'IMAGE_MEMORY_LIMIT') {
                _memory.handleMemoryPressure();
                throw const ImageMemoryException('Native image region exceeded available memory');
              }
              rethrow;
            }
          },
          cancelToken: cancelToken,
          isForeground: isForeground,
        )
        .whenComplete(timeline.finish);
  }

  Future<DecodedImageRegion> _createImage(
    Map<String, dynamic> response,
    int expectedWidth,
    int expectedHeight,
    CancelToken token,
  ) async {
    final width = response['width'];
    final height = response['height'];
    final bytes = response['bytes'];
    if (width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > expectedWidth ||
        height > expectedHeight ||
        bytes is! Uint8List) {
      throw StateError('Invalid image region response');
    }
    final format = response['format'];
    final rowBytes = response['rowBytes'];
    if (format == 'rgba8888') {
      if (rowBytes is! int ||
          rowBytes < width * 4 ||
          rowBytes % 4 != 0 ||
          rowBytes * height != bytes.length ||
          bytes.length > 8 * 1024 * 1024) {
        throw StateError('Invalid raw image region stride');
      }
    } else if (format != 'png' || bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw StateError('Invalid encoded image region');
    }
    // Encoded wide-gamut fallback may produce F16 pixels in Flutter.
    final outputBytes = width * height * (format == 'rgba8888' ? 4 : 8);
    if (_session != null && _memory.retainedBytes + outputBytes > ImageMemoryManager.maxRetainedBytes) {
      await _close(_session!);
    }
    token.throwIfCancellationRequested();
    final lease = _memory.reserveImage(outputBytes);
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    final timeline = TimelineTask()..start('ImageRegionDecoder.createImage', arguments: {'format': format});
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      token.throwIfCancellationRequested();
      descriptor = format == 'rgba8888'
          ? ui.ImageDescriptor.raw(
              buffer,
              width: width,
              height: height,
              rowBytes: rowBytes as int,
              pixelFormat: ui.PixelFormat.rgba8888,
            )
          : await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width != width || descriptor.height != height) {
        throw StateError('Image region dimensions do not match payload');
      }
      token.throwIfCancellationRequested();
      codec = await descriptor.instantiateCodec();
      token.throwIfCancellationRequested();
      final frame = await codec.getNextFrame();
      if (token.isCancelled) {
        frame.image.dispose();
        token.throwIfCancellationRequested();
      }
      return DecodedImageRegion(frame.image, lease);
    } catch (_) {
      lease.release();
      rethrow;
    } finally {
      // Raw descriptors/buffers must survive until getNextFrame completes.
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      timeline.finish();
    }
  }

  /// Call after cancelling/draining this source's readers, before file deletion.
  /// Capturing identity prevents a late close from affecting a replacement.
  Future<void> release(String path) {
    final session = _session;
    if (session == null || session.path != path) return Future.value();
    return _memory.runDecode(0, () => _close(session));
  }

  Future<void> _close(_RegionDecoderSession session) async {
    if (!identical(_session, session)) return;
    await ServiceHandler.releaseImageRegionDecoder(session.path);
    // A failed channel close keeps both identity and lease for a later retry.
    _session = null;
    session.lease.release();
  }

  void _onPressure() {
    if (!_memory.underPressure.value) return;
    final session = _session;
    if (session == null) return;
    unawaited(
      release(session.path).catchError((Object error, StackTrace stack) {
        ServiceHandler.log(error, s: stack);
      }),
    );
  }
}

class DecodedImageRegion {
  DecodedImageRegion(this.image, this.lease);

  final ui.Image image;
  final ImageMemoryLease lease;
}

class _RegionDecoderSession {
  _RegionDecoderSession(this.path, this.lease);

  final String path;
  final ImageMemoryLease lease;
}
