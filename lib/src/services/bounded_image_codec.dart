import 'dart:ui' as ui;

import 'package:lolisnatcher/src/services/image_memory_manager.dart';

/// Resizes decoded frames after the caller reserves their full native cost.
///
/// Native animation codecs decode at source size, even when an image descriptor
/// is given smaller target dimensions. The target must preserve the source's
/// aspect ratio, apart from integer rounding, and be checked by the caller.
class BoundedImageCodec implements ui.Codec {
  BoundedImageCodec(
    this._codec, {
    required this.expectedSourceWidth,
    required this.expectedSourceHeight,
    required this.targetWidth,
    required this.targetHeight,
  });

  final ui.Codec _codec;
  final int expectedSourceWidth;
  final int expectedSourceHeight;
  final int targetWidth;
  final int targetHeight;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = await _codec.getNextFrame();
    final source = frame.image;
    var sourceTransferred = false;
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    try {
      if (source.width != expectedSourceWidth || source.height != expectedSourceHeight) {
        throw const ImageMemoryException('Decoded frame dimensions differ from the reserved source dimensions');
      }
      if (source.width == targetWidth && source.height == targetHeight) {
        sourceTransferred = true;
        return frame;
      }

      recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      picture = recorder.endRecording();
      final resized = await picture.toImage(targetWidth, targetHeight);
      return _BoundedFrameInfo(resized, frame.duration);
    } finally {
      try {
        // Even a failure while recording must release the recorded image refs.
        if (recorder?.isRecording ?? false) {
          recorder!.endRecording().dispose();
        }
        picture?.dispose();
      } finally {
        if (!sourceTransferred) source.dispose();
      }
    }
  }

  @override
  void dispose() => _codec.dispose();
}

class _BoundedFrameInfo implements ui.FrameInfo {
  const _BoundedFrameInfo(this.image, this.duration);

  @override
  final ui.Image image;

  @override
  final Duration duration;
}
