import 'dart:async';
import 'dart:collection';
import 'dart:io';

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
  final Set<String> _inProgress = {};
  final Map<String, Future<File?>> _pendingExistingCacheGenerations = {};
  final Queue<Completer<void>> _generationQueue = Queue();
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
    final sourceBooru =
        resolution?.sourceBooru ?? OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = resolution?.fileName ?? (fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null);
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName);
    if (await _isUsableFile(target)) {
      return target;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() async {
        final mediaResolution = resolution?.isAvailable == true
            ? resolution!
            : await OfflineMediaResolver.instance.resolve(
                item,
                sourceBooru,
                allowUntrackedItem: true,
              );

        if (mediaResolution.isAvailable) {
          final generated = await _generateFromMedia(item, mediaResolution.file!, target);
          if (generated != null) {
            return generated;
          }
        }

        return _copyExistingNetworkCache(item, target);
      });
    });
  }

  Future<OfflineThumbnailLookup> getExistingOrQueue(
    BooruItem item,
    Booru booru, {
    bool allowGeneration = true,
  }) async {
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return const OfflineThumbnailLookup();
    }

    final fileNames = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    for (final fileName in fileNames) {
      final target = await _thumbnailFile(sourceBooru, fileName);
      if (await _isUsableFile(target)) {
        return OfflineThumbnailLookup(file: target);
      }
    }

    if (fileNames.isEmpty) {
      return const OfflineThumbnailLookup();
    }

    if (!allowGeneration || !_isGenerationEnabled) {
      return const OfflineThumbnailLookup();
    }

    final target = await _thumbnailFile(sourceBooru, fileNames.first);
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
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null;
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName);
    if (await _isUsableFile(target)) {
      return target;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() => _copyExistingNetworkCache(item, target));
    });
  }

  Future<File?> generateRuntimeThumbnail(BooruItem item, Booru booru) async {
    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return null;
    }

    final fileNameCandidates = OfflineMediaResolver.instance.filenameCandidates(item, sourceBooru);
    final fileName = fileNameCandidates.isNotEmpty ? fileNameCandidates.first : null;
    if (fileName == null) {
      return null;
    }
    final target = await _thumbnailFile(sourceBooru, fileName);
    if (await _isUsableFile(target)) {
      return target;
    }
    if (!_isGenerationEnabled) {
      return null;
    }

    return _withInProgress(target, () {
      return _withGenerationSlot(() async {
        final cached = await _copyExistingNetworkCache(item, target);
        if (cached != null) {
          return cached;
        }

        final mediaResolution = await OfflineMediaResolver.instance.resolve(
          item,
          sourceBooru,
          allowSafCopy: true,
          allowUntrackedItem: true,
        );
        if (!mediaResolution.isAvailable) {
          return null;
        }

        return _generateFromMedia(item, mediaResolution.file!, target);
      });
    });
  }

  Future<File?> _generateFromMedia(
    BooruItem item,
    File mediaFile,
    File target,
  ) async {
    if (item.mediaType.value.isVideo) {
      final bytes = await ServiceHandler.makeVidThumb(mediaFile.path);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final thumbnailBytes = await compute(_encodeOfflineThumbnail, bytes);
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        return null;
      }
      await target.writeAsBytes(thumbnailBytes);
      return target;
    }

    if (!item.mediaType.value.isImageOrAnimation) {
      return null;
    }

    final thumbnailBytes = await compute(_encodeOfflineThumbnail, await mediaFile.readAsBytes());
    if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
      return null;
    }
    await target.writeAsBytes(thumbnailBytes);
    return target;
  }

  Future<File?> _copyExistingNetworkCache(BooruItem item, File target) async {
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
          await source.copy(target.path);
          if (await _isUsableFile(target)) {
            return target;
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

      final thumbnailBytes = await compute(_encodeOfflineThumbnail, await source.readAsBytes());
      if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
        return null;
      }

      await target.writeAsBytes(thumbnailBytes);
      if (await _isUsableFile(target)) {
        return target;
      }
    }

    return null;
  }

  Future<File?> _withInProgress(File target, Future<File?> Function() action) async {
    if (_inProgress.contains(target.path)) {
      return null;
    }

    _inProgress.add(target.path);
    try {
      return await action();
    } finally {
      _inProgress.remove(target.path);
    }
  }

  Future<T> _withGenerationSlot<T>(Future<T> Function() action) async {
    await _acquireGenerationSlot();
    try {
      return await action();
    } finally {
      _releaseGenerationSlot();
    }
  }

  Future<void> _acquireGenerationSlot() {
    if (_activeGenerations < _maxConcurrentGenerations) {
      _activeGenerations++;
      return Future.value();
    }

    final completer = Completer<void>();
    _generationQueue.add(completer);
    return completer.future;
  }

  void _releaseGenerationSlot() {
    if (_generationQueue.isNotEmpty) {
      _generationQueue.removeFirst().complete();
    } else {
      _activeGenerations--;
    }
  }

  Future<File> _thumbnailFile(Booru sourceBooru, String mediaFileName) async {
    final cachePath = '${await ServiceHandler.getCacheDir()}offline_thumbnails/';
    await Directory(cachePath).create(recursive: true);
    final fileName = OfflineMediaResolver.instance.cacheKey(sourceBooru, mediaFileName);
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

Uint8List? _encodeOfflineThumbnail(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    return null;
  }

  final thumb = img.copyResize(
    image,
    width: image.width >= image.height ? 480 : null,
    height: image.height > image.width ? 480 : null,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(thumb, quality: 86));
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
