import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:dio/dio.dart';

import 'package:lolisnatcher/src/services/image_memory_manager.dart';

@immutable
class ImageDimensions {
  const ImageDimensions(this.width, this.height);

  final int width;
  final int height;
}

/// Bounded metadata inspection and dimension checks before image decoding.
class ImageMetadata {
  /// Reads ISO BMFF box headers using small, bounded file reads. Neither image
  /// data nor untrusted box lengths are materialized as a Dart byte array.
  static Future<ImageDimensions> inspectAvif(File file, CancelToken cancelToken) async {
    final input = await file.open();
    var maxWidth = 0;
    var maxHeight = 0;
    var boxCount = 0;
    var foundBrand = false;
    var animated = false;
    var sampleEntries = 0;
    var imageProperties = 0;
    try {
      final length = await input.length();
      Future<Uint8List> readAt(int offset, int count) async {
        cancelToken.throwIfCancellationRequested();
        if (offset < 0 || count < 0 || offset + count > length) throw const FormatException('Truncated AVIF box');
        await input.setPosition(offset);
        final bytes = await input.read(count);
        if (bytes.length != count) throw const FormatException('Truncated AVIF box');
        return bytes;
      }

      void recordSize(int width, int height) {
        checkDimensions(width, height, pixelLimit: ImageMemoryManager.maxAvifSourcePixels);
        maxWidth = math.max(maxWidth, width);
        maxHeight = math.max(maxHeight, height);
      }

      Future<void> boxes(int start, int end, int depth) async {
        if (depth > 12) throw const ImageMemoryException('AVIF metadata nesting exceeds the safe limit');
        var offset = start;
        while (offset < end) {
          if (++boxCount > 4096) throw const ImageMemoryException('AVIF metadata exceeds the safe limit');
          if (end - offset < 8) throw const FormatException('Invalid AVIF box boundary');
          final header = await readAt(offset, 8);
          final data = ByteData.sublistView(header);
          var size = data.getUint32(0);
          final type = String.fromCharCodes(header.sublist(4));
          var headerSize = 8;
          if (size == 1) {
            if (end - offset < 16) throw const FormatException('Invalid AVIF extended box');
            size = ByteData.sublistView(await readAt(offset + 8, 8)).getUint64(0);
            headerSize = 16;
          } else if (size == 0) {
            size = end - offset;
          }
          if (size < headerSize || size > end - offset) throw const FormatException('Invalid AVIF box size');
          final payload = offset + headerSize;
          final payloadSize = size - headerSize;
          switch (type) {
            case 'ftyp':
              if (payloadSize < 8 || payloadSize > 1024) throw const FormatException('Invalid AVIF file type');
              final brands = await readAt(payload, payloadSize);
              for (var i = 0; i + 4 <= brands.length; i += 4) {
                if (i == 4) continue;
                final brand = String.fromCharCodes(brands.sublist(i, i + 4));
                foundBrand |= brand == 'avif' || brand == 'avis';
                animated |= brand == 'avis';
              }
              break;
            case 'ispe':
              if (payloadSize < 12) throw const FormatException('Invalid AVIF image dimensions');
              final fields = ByteData.sublistView(await readAt(payload, 12));
              recordSize(fields.getUint32(4), fields.getUint32(8));
              imageProperties++;
              break;
            case 'av01':
              if (payloadSize < 78) throw const FormatException('Invalid AVIF sample description');
              final fields = ByteData.sublistView(await readAt(payload + 24, 4));
              recordSize(fields.getUint16(0), fields.getUint16(2));
              sampleEntries++;
              await boxes(payload + 78, offset + size, depth + 1);
              break;
            case 'meta':
            case 'stsd':
              final skip = type == 'meta' ? 4 : 8;
              if (payloadSize < skip) throw const FormatException('Invalid AVIF metadata box');
              await boxes(payload + skip, offset + size, depth + 1);
              break;
            case 'iprp':
            case 'ipco':
            case 'moov':
            case 'trak':
            case 'mdia':
            case 'minf':
            case 'stbl':
              await boxes(payload, offset + size, depth + 1);
              break;
          }
          offset += size;
        }
      }

      await boxes(0, length, 0);
      if (!foundBrand || (animated ? sampleEntries == 0 : imageProperties == 0)) {
        throw const ImageMemoryException('AVIF dimensions could not be verified before decoding');
      }
      checkDimensions(maxWidth, maxHeight, pixelLimit: ImageMemoryManager.maxAvifSourcePixels);
      return ImageDimensions(maxWidth, maxHeight);
    } finally {
      await input.close();
    }
  }

  static Future<({bool isGif, bool animated, bool isApng})> inspectAnimation(File file, CancelToken cancelToken) async {
    final input = await file.open();
    try {
      final header = await input.read(32);
      if (header.length >= 6 && String.fromCharCodes(header.sublist(0, 3)) == 'GIF') {
        return (isGif: true, animated: true, isApng: false);
      }
      if (header.length >= 21 && String.fromCharCodes(header.sublist(8, 12)) == 'WEBP') {
        final extended = String.fromCharCodes(header.sublist(12, 16)) == 'VP8X';
        return (isGif: false, animated: extended && header[20] & 2 != 0, isApng: false);
      }
      if (header.length >= 8 && header[0] == 137 && String.fromCharCodes(header.sublist(1, 4)) == 'PNG') {
        final length = await input.length();
        var offset = 8;
        for (var chunks = 0; offset + 8 <= length && chunks < 4096; chunks++) {
          cancelToken.throwIfCancellationRequested();
          await input.setPosition(offset);
          final chunk = await input.read(8);
          if (chunk.length != 8) throw const FormatException('Truncated PNG header');
          final type = String.fromCharCodes(chunk.sublist(4));
          if (type == 'acTL') return (isGif: false, animated: true, isApng: true);
          if (type == 'IDAT' || type == 'IEND') return (isGif: false, animated: false, isApng: false);
          offset += ByteData.sublistView(chunk).getUint32(0) + 12;
        }
        throw const ImageMemoryException('PNG animation metadata could not be verified');
      }
      return (isGif: false, animated: false, isApng: false);
    } finally {
      await input.close();
    }
  }

  static void checkDimensions(int width, int height, {int pixelLimit = ImageMemoryManager.maxSourcePixels}) {
    if (width <= 0 ||
        height <= 0 ||
        width > ImageMemoryManager.maxSourceDimension ||
        height > ImageMemoryManager.maxSourceDimension ||
        width * height > pixelLimit) {
      throw const ImageMemoryException('Source dimensions exceed the safe whole-image decode limit');
    }
  }
}
