import 'dart:io';

import 'package:collection/collection.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

enum OfflineMediaResolutionType {
  unavailable,
  file,
  ;

  bool get isUnavailable => this == unavailable;
  bool get isFile => this == file;
}

class OfflineMediaResolution {
  const OfflineMediaResolution._({
    required this.type,
    this.file,
    this.sourceBooru,
    this.fileName,
    this.copiedFromSaf = false,
  });

  const OfflineMediaResolution.unavailable()
    : this._(
        type: .unavailable,
      );

  const OfflineMediaResolution.file(
    File file, {
    required Booru sourceBooru,
    required String fileName,
    bool copiedFromSaf = false,
  }) : this._(
         type: .file,
         file: file,
         sourceBooru: sourceBooru,
         fileName: fileName,
         copiedFromSaf: copiedFromSaf,
       );

  final OfflineMediaResolutionType type;
  final File? file;
  final Booru? sourceBooru;
  final String? fileName;
  final bool copiedFromSaf;

  bool get isAvailable => type.isFile && file != null;
}

class OfflineMediaResolver {
  OfflineMediaResolver._();
  static final OfflineMediaResolver instance = OfflineMediaResolver._();

  final ImageWriter _imageWriter = ImageWriter();

  Future<OfflineMediaResolution> resolve(
    BooruItem item,
    Booru booru, {
    bool allowSafCopy = true,
    bool allowUntrackedItem = false,
  }) async {
    if (!allowUntrackedItem && item.isSnatched.value != true) {
      return const OfflineMediaResolution.unavailable();
    }

    final sourceBooru = resolveSourceBooru(item, fallback: booru);
    if (sourceBooru == null || sourceBooru.type?.isFavouritesOrDownloads == true) {
      return const OfflineMediaResolution.unavailable();
    }

    final fileNames = filenameCandidates(item, sourceBooru);
    if (fileNames.isEmpty) {
      return const OfflineMediaResolution.unavailable();
    }
    await _imageWriter.setPaths();

    if (Platform.isAndroid && SX.extPathOverride.value.isNotEmpty) {
      return _resolveSaf(
        sourceBooru,
        fileNames,
        allowCopy: allowSafCopy,
      );
    }

    for (final fileName in fileNames) {
      final file = File('${_imageWriter.path}$fileName');
      if (await _isUsableFile(file)) {
        return OfflineMediaResolution.file(
          file,
          sourceBooru: sourceBooru,
          fileName: fileName,
        );
      }
    }

    return const OfflineMediaResolution.unavailable();
  }

  Future<OfflineMediaResolution> _resolveSaf(
    Booru sourceBooru,
    List<String> fileNames, {
    required bool allowCopy,
  }) async {
    for (final fileName in fileNames) {
      final cachedFile = await _safCacheFile(sourceBooru, fileName);
      if (await _isUsableFile(cachedFile)) {
        return OfflineMediaResolution.file(
          cachedFile,
          sourceBooru: sourceBooru,
          fileName: fileName,
          copiedFromSaf: true,
        );
      }
    }

    if (!allowCopy) {
      return const OfflineMediaResolution.unavailable();
    }

    final safUri = SX.extPathOverride.value;
    if (safUri.isEmpty) {
      return const OfflineMediaResolution.unavailable();
    }

    String? existingFileName;
    for (final fileName in fileNames) {
      final exists = await SAFFileCache.instance.existsFile(safUri, fileName);
      if (exists) {
        existingFileName = fileName;
        break;
      }
    }
    if (existingFileName == null) return const OfflineMediaResolution.unavailable();

    final cacheDirPath = '${await ServiceHandler.getCacheDir()}offline_media/';
    final targetFile = await _safCacheFile(sourceBooru, existingFileName);
    if (await _isUsableFile(targetFile)) {
      return OfflineMediaResolution.file(
        targetFile,
        sourceBooru: sourceBooru,
        fileName: existingFileName,
        copiedFromSaf: true,
      );
    }

    final copied = await ServiceHandler.copySafFileToDir(safUri, existingFileName, cacheDirPath);
    if (!copied) {
      return const OfflineMediaResolution.unavailable();
    }

    final copiedFile = File('$cacheDirPath$existingFileName');
    if (await _isUsableFile(copiedFile)) {
      if (copiedFile.path != targetFile.path) {
        try {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await copiedFile.rename(targetFile.path);
        } catch (_) {
          return OfflineMediaResolution.file(
            copiedFile,
            sourceBooru: sourceBooru,
            fileName: existingFileName,
            copiedFromSaf: true,
          );
        }
      }

      return OfflineMediaResolution.file(
        targetFile,
        sourceBooru: sourceBooru,
        fileName: existingFileName,
        copiedFromSaf: true,
      );
    }

    return const OfflineMediaResolution.unavailable();
  }

  Booru? resolveSourceBooru(BooruItem item, {Booru? fallback}) {
    if (fallback != null && fallback.type?.isFavouritesOrDownloads != true && fallback.baseURL?.isNotEmpty == true) {
      return fallback;
    }

    final settingsHandler = SettingsHandler.instance;
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;

    return settingsHandler.booruList.firstWhereOrNull((booru) {
      if (booru.type?.isFavouritesOrDownloads == true) {
        return false;
      }

      final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
      if (booruHost?.isNotEmpty != true) {
        return false;
      }

      return (itemPostHost?.isNotEmpty == true &&
              (itemPostHost == booruHost ||
                  switch (booru.type) {
                    BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                    BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                    _ => false,
                  })) ||
          (itemFileHost?.isNotEmpty == true && itemFileHost == booruHost);
    });
  }

  List<String> filenameCandidates(BooruItem item, Booru sourceBooru) {
    final candidates = <String>[];

    void add(String? value) {
      if (value == null || value.isEmpty || value.startsWith('.')) {
        return;
      }
      if (!candidates.contains(value)) {
        candidates.add(value);
      }
    }

    add(item.savedFileName);

    try {
      add(_imageWriter.getFilename(item, sourceBooru));
    } catch (_) {}

    final int queryLastIndex = item.fileURL.lastIndexOf('?');
    final int lastIndex = queryLastIndex != -1 ? queryLastIndex : item.fileURL.length;
    final int slashIndex = item.fileURL.lastIndexOf('/');
    if (slashIndex != -1 && slashIndex + 1 < lastIndex) {
      final urlFileName = item.fileURL.substring(slashIndex + 1, lastIndex);
      add('${sourceBooru.name}_$urlFileName');
    }

    return candidates;
  }

  String cacheKey(Booru sourceBooru, String fileName) {
    return _cacheFileName(sourceBooru, fileName);
  }

  String _cacheFileName(Booru sourceBooru, String fileName) {
    final booruName = sourceBooru.name ?? sourceBooru.baseURL ?? 'unknown';
    return Tools.sanitize('${booruName}_$fileName');
  }

  Future<File> _safCacheFile(Booru sourceBooru, String fileName) async {
    final cacheDirPath = '${await ServiceHandler.getCacheDir()}offline_media/';
    await Directory(cacheDirPath).create(recursive: true);
    return File('$cacheDirPath${_cacheFileName(sourceBooru, fileName)}');
  }

  Future<bool> _isUsableFile(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }
}
