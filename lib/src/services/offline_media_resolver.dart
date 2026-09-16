import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

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
    this.storageIdentity,
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
    String? storageIdentity,
  }) : this._(
         type: .file,
         file: file,
         sourceBooru: sourceBooru,
         fileName: fileName,
         copiedFromSaf: copiedFromSaf,
         storageIdentity: storageIdentity,
       );

  final OfflineMediaResolutionType type;
  final File? file;
  final Booru? sourceBooru;
  final String? fileName;
  final bool copiedFromSaf;
  final String? storageIdentity;

  bool get isAvailable => type.isFile && file != null;
}

class OfflineMediaResolver {
  OfflineMediaResolver._();
  static final OfflineMediaResolver instance = OfflineMediaResolver._();

  final ImageWriter _imageWriter = ImageWriter();
  final Map<String, Future<OfflineMediaResolution>> _pendingCopies = {};

  String get storageIdentity {
    final override = SX.extPathOverride.value;
    final backend = Platform.isAndroid && override.isNotEmpty ? 'saf' : 'file';
    return '$backend:${override.isEmpty ? 'default' : override}';
  }

  Future<OfflineMediaResolution> resolve(
    BooruItem item,
    Booru booru, {
    bool allowSafCopy = true,
    bool allowUntrackedItem = false,
  }) async {
    try {
      return await _resolve(item, booru, allowSafCopy: allowSafCopy, allowUntrackedItem: allowUntrackedItem);
    } catch (_) {
      // Offline lookup is optional; an inaccessible folder must allow normal loading.
      return const OfflineMediaResolution.unavailable();
    }
  }

  Future<OfflineMediaResolution> _resolve(
    BooruItem item,
    Booru booru, {
    required bool allowSafCopy,
    required bool allowUntrackedItem,
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
    final selectedStorage = storageIdentity;
    final selectedPath = SX.extPathOverride.value;

    if (Platform.isAndroid && selectedPath.isNotEmpty) {
      final result = await _resolveSaf(
        sourceBooru,
        fileNames,
        selectedPath,
        selectedStorage,
        allowCopy: allowSafCopy,
      );
      return selectedStorage == storageIdentity ? result : const OfflineMediaResolution.unavailable();
    }

    final directory = selectedPath.isEmpty ? await ServiceHandler.getPicturesDir() : selectedPath;
    for (final fileName in fileNames) {
      final file = File('$directory${Platform.pathSeparator}$fileName');
      if (await _isUsableFile(file) && selectedStorage == storageIdentity) {
        return OfflineMediaResolution.file(
          file,
          sourceBooru: sourceBooru,
          fileName: fileName,
          storageIdentity: selectedStorage,
        );
      }
    }

    return const OfflineMediaResolution.unavailable();
  }

  Future<OfflineMediaResolution> _resolveSaf(
    Booru sourceBooru,
    List<String> fileNames,
    String safUri,
    String selectedStorage, {
    required bool allowCopy,
  }) async {
    for (final fileName in fileNames) {
      final cachedFile = await _safCacheFile(sourceBooru, fileName, selectedStorage);
      if (await _isUsableFile(cachedFile)) {
        return OfflineMediaResolution.file(
          cachedFile,
          sourceBooru: sourceBooru,
          fileName: fileName,
          copiedFromSaf: true,
          storageIdentity: selectedStorage,
        );
      }
    }

    if (!allowCopy) {
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

    final targetFile = await _safCacheFile(sourceBooru, existingFileName, selectedStorage);
    if (await _isUsableFile(targetFile)) {
      return OfflineMediaResolution.file(
        targetFile,
        sourceBooru: sourceBooru,
        fileName: existingFileName,
        copiedFromSaf: true,
        storageIdentity: selectedStorage,
      );
    }

    final pending = _pendingCopies[targetFile.path];
    if (pending != null) return pending;
    final copy = _copySafFile(sourceBooru, safUri, existingFileName, targetFile, selectedStorage);
    _pendingCopies[targetFile.path] = copy;
    try {
      return await copy;
    } finally {
      unawaited(_pendingCopies.remove(targetFile.path));
    }
  }

  Future<OfflineMediaResolution> _copySafFile(
    Booru sourceBooru,
    String safUri,
    String fileName,
    File target,
    String selectedStorage,
  ) async {
    Directory? staging;
    try {
      // Each copy owns its staging directory; only a completed file is published.
      staging = await target.parent.createTemp('.copy-');
      if (!await ServiceHandler.copySafFileToDir(safUri, fileName, staging.path)) {
        return const OfflineMediaResolution.unavailable();
      }
      final copiedFile = File('${staging.path}${Platform.pathSeparator}$fileName');
      if (!await _isUsableFile(copiedFile)) return const OfflineMediaResolution.unavailable();
      if (await target.exists()) await target.delete();
      await copiedFile.rename(target.path);
      return OfflineMediaResolution.file(
        target,
        sourceBooru: sourceBooru,
        fileName: fileName,
        copiedFromSaf: true,
        storageIdentity: selectedStorage,
      );
    } catch (_) {
      return const OfflineMediaResolution.unavailable();
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Booru? resolveSourceBooru(BooruItem item, {Booru? fallback}) {
    if (fallback != null &&
        fallback.type?.isFavouritesOrDownloads != true &&
        fallback.type?.isMerge != true &&
        fallback.baseURL?.isNotEmpty == true) {
      return fallback;
    }

    final settingsHandler = SettingsHandler.instance;
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;

    final sources = settingsHandler.booruList.where((booru) {
      if (booru.type?.isFavouritesOrDownloads == true || booru.type?.isMerge == true) {
        return false;
      }

      final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
      if (booruHost?.isNotEmpty != true) {
        return false;
      }

      return true;
    }).toList();

    // Prefer the post's source over a different site sharing its media host.
    return sources.firstWhereOrNull(
          (booru) => itemPostHost?.isNotEmpty == true && itemPostHost == Uri.tryParse(booru.baseURL ?? '')?.host,
        ) ??
        sources.firstWhereOrNull(
          (booru) =>
              itemPostHost?.isNotEmpty == true &&
              switch (booru.type) {
                BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                _ => false,
              },
        ) ??
        sources.firstWhereOrNull(
          (booru) => itemFileHost?.isNotEmpty == true && itemFileHost == Uri.tryParse(booru.baseURL ?? '')?.host,
        );
  }

  List<String> filenameCandidates(BooruItem item, Booru sourceBooru) {
    final candidates = <String>[];

    void add(String? value) {
      if (value == null || value.isEmpty || value.startsWith('.') || RegExp(r'[/\\\x00-\x1f:]').hasMatch(value)) {
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

  String cacheKey(Booru sourceBooru, String fileName, {String? storageIdentity}) {
    final identity = jsonEncode([
      storageIdentity ?? this.storageIdentity,
      sourceBooru.type?.name,
      sourceBooru.baseURL,
      fileName,
    ]);
    final extension = RegExp(r'\.[a-zA-Z0-9]{1,12}$').firstMatch(fileName)?.group(0) ?? '';
    return '${sha256.convert(utf8.encode(identity))}$extension';
  }

  Future<File> _safCacheFile(Booru sourceBooru, String fileName, String selectedStorage) async {
    final cacheDirPath = '${await ServiceHandler.getCacheDir()}offline_media/';
    await Directory(cacheDirPath).create(recursive: true);
    return File('$cacheDirPath${cacheKey(sourceBooru, fileName, storageIdentity: selectedStorage)}');
  }

  Future<bool> _isUsableFile(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }
}
