import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/offline_media_resolver.dart';

class OfflineThumbnailService {
  OfflineThumbnailService._();
  static final OfflineThumbnailService instance = OfflineThumbnailService._();

  final ImageWriter _imageWriter = ImageWriter();
  final Map<String, Future<File?>> _inProgress = {};
  final Map<String, Future<File?>> _pendingExistingCacheGenerations = {};
  final Queue<Completer<bool>> _generationQueue = Queue();
  int _activeGenerations = 0;

  int get _maxConcurrentGenerations {
    final value = SX.offlineThumbnailConcurrentGenerations.value;
    return value < 1 ? 1 : (value > 8 ? 8 : value);
  }

  bool get _isGenerationEnabled => SX.offlineThumbnailGeneration.value;

  Future<File?> getOrGenerate(
    BooruItem item,
    Booru booru, {
    OfflineMediaResolution? resolution,
  }) async {
    final storageIdentity = OfflineMediaResolver.instance.storageIdentity;
    final suppliedResolution = resolution?.storageIdentity == storageIdentity ? resolution : null;
    final sourceBooru =
        suppliedResolution?.sourceBooru ?? OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = suppliedResolution?.fileName ?? (fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null);
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName, storageIdentity);
    if (await _isUsableFile(target)) {
      return _storageMatches(storageIdentity) ? target : null;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() async {
        if (!_storageMatches(storageIdentity)) return null;
        final mediaResolution = suppliedResolution?.isAvailable == true
            ? suppliedResolution!
            : await OfflineMediaResolver.instance.resolve(
                item,
                sourceBooru,
                allowUntrackedItem: true,
              );

        if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
        if (mediaResolution.isAvailable && mediaResolution.storageIdentity == storageIdentity) {
          final generated = await _generateFromMedia(item, mediaResolution.file!, target, storageIdentity);
          if (generated != null) {
            return generated;
          }
        }

        return _copyExistingNetworkCache(item, target, storageIdentity);
      });
    });
  }

  Future<OfflineThumbnailLookup> getExistingOrQueue(
    BooruItem item,
    Booru booru, {
    bool allowGeneration = true,
  }) async {
    final storageIdentity = OfflineMediaResolver.instance.storageIdentity;
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return const OfflineThumbnailLookup();
    }

    final fileNames = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    for (final fileName in fileNames) {
      final target = await _thumbnailFile(sourceBooru, fileName, storageIdentity);
      if (await _isUsableFile(target)) {
        return OfflineThumbnailLookup(file: _storageMatches(storageIdentity) ? target : null);
      }
    }

    if (fileNames.isEmpty) {
      return const OfflineThumbnailLookup();
    }

    if (!allowGeneration || !_isGenerationEnabled || !_storageMatches(storageIdentity)) {
      return const OfflineThumbnailLookup();
    }

    final target = await _thumbnailFile(sourceBooru, fileNames.first, storageIdentity);
    if (!_storageMatches(storageIdentity)) return const OfflineThumbnailLookup();
    final existingGeneration = _pendingExistingCacheGenerations[target.path];
    if (existingGeneration != null) {
      return OfflineThumbnailLookup(generation: existingGeneration);
    }

    final generation = generateRuntimeThumbnail(item, booru).catchError((_) => null);
    _pendingExistingCacheGenerations[target.path] = generation;
    unawaited(
      generation.whenComplete(() {
        _pendingExistingCacheGenerations.remove(target.path);
      }),
    );
    return OfflineThumbnailLookup(generation: generation);
  }

  Future<void> generateAfterSave(BooruItem item, Booru booru) async {
    if (!_isGenerationEnabled) {
      return;
    }

    final future = Platform.isAndroid && SX.extPathOverride.value.isNotEmpty
        ? generateFromExistingCache(item, booru)
        : getOrGenerate(item, booru);
    unawaited(future.catchError((_) => null));
  }

  Future<File?> generateFromExistingCache(BooruItem item, Booru booru) async {
    final storageIdentity = OfflineMediaResolver.instance.storageIdentity;
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null;
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName, storageIdentity);
    if (await _isUsableFile(target)) {
      return _storageMatches(storageIdentity) ? target : null;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() => _copyExistingNetworkCache(item, target, storageIdentity));
    });
  }

  Future<File?> generateRuntimeThumbnail(BooruItem item, Booru booru) async {
    final storageIdentity = OfflineMediaResolver.instance.storageIdentity;
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null;
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName, storageIdentity);
    if (await _isUsableFile(target)) {
      return _storageMatches(storageIdentity) ? target : null;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() async {
        if (!_storageMatches(storageIdentity)) return null;
        final cached = await _copyExistingNetworkCache(item, target, storageIdentity);
        if (cached != null) {
          return cached;
        }

        if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
        final mediaResolution = await OfflineMediaResolver.instance.resolve(
          item,
          sourceBooru,
          allowSafCopy: true,
          allowUntrackedItem: true,
        );
        if (!mediaResolution.isAvailable || mediaResolution.storageIdentity != storageIdentity) {
          return null;
        }

        return _generateFromMedia(item, mediaResolution.file!, target, storageIdentity);
      });
    });
  }

  Future<File?> _generateFromMedia(
    BooruItem item,
    File mediaFile,
    File target,
    String storageIdentity,
  ) async {
    if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
    if (item.mediaType.value.isVideo) {
      final bytes = await ServiceHandler.makeVidThumb(mediaFile.path);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final thumbnailBytes = await _encodeOfflineThumbnail(bytes: bytes);
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        return null;
      }
      return _publishThumbnail(target, storageIdentity, (file) => file.writeAsBytes(thumbnailBytes, flush: true));
    }

    if (!item.mediaType.value.isImageOrAnimation) {
      return null;
    }

    final thumbnailBytes = await _encodeOfflineThumbnail(file: mediaFile);
    if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
      return null;
    }
    return _publishThumbnail(target, storageIdentity, (file) => file.writeAsBytes(thumbnailBytes, flush: true));
  }

  Future<File?> _copyExistingNetworkCache(BooruItem item, File target, String storageIdentity) async {
    if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
    final canCopyThumbnail = item.thumbnailURL.isNotEmpty && !item.thumbnailURL.toLowerCase().contains('.avif');
    final thumbnailPath = canCopyThumbnail
        ? await _imageWriter.getCachePath(
            Uri.base.resolve(item.thumbnailURL).toString(),
            'thumbnails',
            clearName: true,
            fileNameExtras: item.fileNameExtras,
          )
        : null;
    if (thumbnailPath != null) {
      final source = File(thumbnailPath);
      if (await _isUsableFile(source)) {
        try {
          // Decode before publishing so a corrupt network cache cannot mask a
          // usable saved original or become a permanent offline thumbnail.
          final bytes = await _encodeOfflineThumbnail(file: source);
          if (bytes != null && bytes.isNotEmpty) {
            final generated = await _publishThumbnail(
              target,
              storageIdentity,
              (file) => file.writeAsBytes(bytes, flush: true),
            );
            if (generated != null) return generated;
          }
        } catch (_) {}
      }
    }

    final samplePath = item.sampleURL.isNotEmpty
        ? await _imageWriter.getCachePath(
            Uri.base.resolve(item.sampleURL).toString(),
            'samples',
            clearName: true,
            fileNameExtras: item.fileNameExtras,
          )
        : null;
    if (samplePath != null) {
      final source = File(samplePath);
      if (!await _isUsableFile(source)) {
        return null;
      }

      if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
      final thumbnailBytes = await _encodeOfflineThumbnail(file: source);
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        return null;
      }

      return _publishThumbnail(target, storageIdentity, (file) => file.writeAsBytes(thumbnailBytes, flush: true));
    }

    return null;
  }

  Future<File?> _withInProgress(File target, Future<File?> Function() action) async {
    final existing = _inProgress[target.path];
    if (existing != null) return existing;

    final generation = Future<File?>.sync(action);
    _inProgress[target.path] = generation;
    try {
      return await generation;
    } finally {
      unawaited(_inProgress.remove(target.path));
    }
  }

  Future<File?> _withGenerationSlot(Future<File?> Function() action) async {
    if (!await _acquireGenerationSlot()) return null;
    try {
      if (!_isGenerationEnabled) return null;
      return await action();
    } finally {
      _releaseGenerationSlot();
    }
  }

  Future<bool> _acquireGenerationSlot() {
    final completer = Completer<bool>();
    _generationQueue.add(completer);
    _drainGenerationQueue();
    return completer.future;
  }

  void _releaseGenerationSlot() {
    _activeGenerations--;
    _drainGenerationQueue();
  }

  void _drainGenerationQueue() {
    if (!_isGenerationEnabled) {
      while (_generationQueue.isNotEmpty) {
        _generationQueue.removeFirst().complete(false);
      }
      return;
    }
    while (_generationQueue.isNotEmpty && _activeGenerations < _maxConcurrentGenerations) {
      _activeGenerations++;
      _generationQueue.removeFirst().complete(true);
    }
  }

  bool _storageMatches(String identity) => OfflineMediaResolver.instance.storageIdentity == identity;

  Future<File?> _publishThumbnail(
    File target,
    String storageIdentity,
    Future<File> Function(File temporaryFile) write,
  ) async {
    if (!_isGenerationEnabled || !_storageMatches(storageIdentity)) return null;
    final temporaryDirectory = await target.parent.createTemp('.thumbnail-');
    final temporaryFile = File('${temporaryDirectory.path}/thumbnail');
    try {
      await write(temporaryFile);
      if (!_isGenerationEnabled || !_storageMatches(storageIdentity) || !await _isUsableFile(temporaryFile)) {
        return null;
      }
      final published = await temporaryFile.rename(target.path);
      return _storageMatches(storageIdentity) ? published : null;
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
        await temporaryDirectory.delete();
      } catch (_) {}
    }
  }

  Future<File> _thumbnailFile(Booru sourceBooru, String mediaFileName, String storageIdentity) async {
    final cachePath = '${await ServiceHandler.getCacheDir()}offline_thumbnails/';
    await Directory(cachePath).create(recursive: true);
    final fileName = OfflineMediaResolver.instance.cacheKey(
      sourceBooru,
      mediaFileName,
      storageIdentity: storageIdentity,
    );
    return File('$cachePath$fileName.jpg');
  }

  Future<bool> _isUsableFile(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }
}

Future<Uint8List?> _encodeOfflineThumbnail({File? file, Uint8List? bytes}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = file != null
        ? await ui.ImmutableBuffer.fromFilePath(file.path)
        : await ui.ImmutableBuffer.fromUint8List(bytes!);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) return null;
    final scale = width >= height ? (width > 480 ? 480 / width : 1.0) : (height > 480 ? 480 / height : 1.0);
    codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round().clamp(1, 480),
      targetHeight: (height * scale).round().clamp(1, 480),
    );
    // Decode only the first animation frame, and pass only thumbnail-sized
    // pixels to the Dart JPEG encoder. Some codecs still allocate source pixels
    // internally; target dimensions cannot guarantee their peak native memory.
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (pixels == null) return null;
    return await compute(_encodeThumbnailPixels, (
      width: image.width,
      height: image.height,
      bytes: pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
    ));
  } catch (_) {
    // Let the caller try a cached thumbnail/sample when the engine cannot decode
    // the original. Avoid an unbounded full-resolution Dart decoder fallback.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Uint8List _encodeThumbnailPixels(({int width, int height, Uint8List bytes}) pixels) {
  final image = img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.bytes.buffer,
    bytesOffset: pixels.bytes.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 86));
}

class OfflineThumbnailLookup {
  const OfflineThumbnailLookup({
    this.file,
    this.generation,
  });

  final File? file;
  final Future<File?>? generation;

  bool get isGenerating => generation != null;
}
