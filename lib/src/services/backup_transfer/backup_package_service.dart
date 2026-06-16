import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';

class BackupPackageService {
  BackupPackageService({
    BackupEntryRegistry? registry,
  }) : registry = registry ?? BackupEntryRegistry.instance;

  final BackupEntryRegistry registry;

  static const extension = BackupFileNaming.extension;
  static const manifestFileName = 'manifest.json';
  static const formatVersion = 1;

  Future<Uint8List> exportPackage({
    required List<BackupEntryId> entryIds,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    final files = <Map<String, Object>>[];
    final entries = <Map<String, dynamic>>[];

    for (final id in entryIds) {
      final definition = registry.byId(id);
      if (!await definition.isAvailable()) continue;
      final payload = await definition.exportEntry(entryOptions[id] ?? options);
      final path = payload.fileName;
      files.add({
        'path': path,
        'bytes': payload.bytes,
      });
      entries.add({
        'id': id.name,
        'title': definition.title(),
        'path': path,
        'mimeType': payload.mimeType,
        'metadata': payload.metadata,
      });
    }

    final manifest = {
      'format': BackupFileNaming.currentFormatId,
      'formatVersion': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'entries': entries,
    };

    return compute(_encodeBackupPackage, {
      'files': files,
      'manifest': manifest,
    });
  }

  Future<File> exportPackageFile({
    required List<BackupEntryId> entryIds,
    required File outputFile,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    final tempDir = Directory('${outputFile.path}.parts');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);
    final files = <Map<String, String>>[];
    final entries = <Map<String, dynamic>>[];

    try {
      for (final id in entryIds) {
        final definition = registry.byId(id);
        if (!await definition.isAvailable()) continue;
        final path = definition.fileName;
        final exportFile = definition.exportFile;
        File sourceFile;
        if (exportFile != null) {
          sourceFile = await exportFile(entryOptions[id] ?? options);
        } else {
          final payload = await definition.exportEntry(entryOptions[id] ?? options);
          sourceFile = File('${tempDir.path}${Platform.pathSeparator}${payload.fileName}');
          await sourceFile.writeAsBytes(payload.bytes, flush: true);
        }
        files.add({
          'sourcePath': sourceFile.path,
          'archivePath': path,
        });
        entries.add({
          'id': id.name,
          'title': definition.title(),
          'path': path,
          'mimeType': 'application/octet-stream',
          'metadata': <String, dynamic>{},
        });
      }

      final manifest = {
        'format': BackupFileNaming.currentFormatId,
        'formatVersion': formatVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'entries': entries,
      };
      final manifestFile = File('${tempDir.path}${Platform.pathSeparator}$manifestFileName');
      await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest), flush: true);
      files.add({
        'sourcePath': manifestFile.path,
        'archivePath': manifestFileName,
      });

      await compute(_encodeBackupPackageFile, {
        'outputPath': outputFile.path,
        'files': files,
      });
      return outputFile;
    } finally {
      unawaited(tempDir.delete(recursive: true).catchError((_) => tempDir));
    }
  }

  Future<List<BackupEntryId>> importPackage(
    Uint8List bytes, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final decoded = await compute(_decodeBackupPackage, bytes);
    return _importDecodedPackage(decoded, options);
  }

  Future<List<BackupEntryId>> importPackageFile(
    File file, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final extractDir = Directory('${file.parent.path}${Platform.pathSeparator}${file.uri.pathSegments.last}.entries');
    try {
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      final decoded = await compute(_extractBackupPackageFile, {
        'packagePath': file.path,
        'extractDir': extractDir.path,
      });
      return await _importDecodedPackage(decoded, options);
    } finally {
      unawaited(extractDir.delete(recursive: true).catchError((_) => extractDir));
    }
  }

  Future<List<BackupEntryId>> _importDecodedPackage(
    Map<String, Object?> decoded,
    BackupImportOptions options,
  ) async {
    final manifest = decoded['manifest'];
    if (manifest is! Map || !BackupFileNaming.isSupportedFormatId(manifest['format'])) {
      throw FormatException(loc.settings.backupAndTransfer.unsupportedBackupFormat);
    }
    final files = decoded['files'];
    if (files is! Map) return [];

    final imported = <BackupEntryId>[];
    final rawEntries = manifest['entries'];
    if (rawEntries is! List) return imported;

    final sortedEntries = rawEntries.whereType<Map>().toList()
      ..sort((a, b) {
        final aIsDatabase = a['id'] == BackupEntryId.database.name;
        final bIsDatabase = b['id'] == BackupEntryId.database.name;
        if (aIsDatabase == bIsDatabase) return 0;
        return aIsDatabase ? 1 : -1;
      });

    for (final raw in sortedEntries) {
      final id = BackupEntryId.values.firstWhere(
        (entryId) => entryId.name == raw['id'],
        orElse: () => BackupEntryId.settings,
      );
      if (id.name != raw['id']) continue;
      final path = raw['path']?.toString();
      if (path == null) continue;
      final content = files[path];
      final definition = registry.byId(id);
      if (content is Uint8List) {
        await definition.importEntry(content, options);
      } else if (content is String) {
        final entryFile = File(content);
        if (!entryFile.existsSync()) {
          throw PathNotFoundException(entryFile.path, const OSError('Backup package entry was not extracted'));
        }
        final importFile = definition.importFile;
        if (importFile != null) {
          await importFile(entryFile, options);
        } else {
          await definition.importEntry(await entryFile.readAsBytes(), options);
        }
      } else {
        continue;
      }
      imported.add(id);
    }
    return imported;
  }

  Future<String?> savePackageWithPicker(Uint8List bytes) async {
    final fileName = BackupFileNaming.packageFileName(DateTime.now());
    final path = await FilePicker.saveFile(
      dialogTitle: loc.settings.backupAndTransfer.exportBackupDialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  Future<String?> exportPackageFileWithPicker({
    required List<BackupEntryId> entryIds,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    final fileName = BackupFileNaming.packageFileName(DateTime.now());
    if (Platform.isAndroid) {
      final savePath = await ServiceHandler.getSAFDirectoryAccess();
      if (savePath.isEmpty) return null;
      final tempFile = await _createTempPackageFile(fileName);
      try {
        await exportPackageFile(
          entryIds: entryIds,
          outputFile: tempFile,
          options: options,
          entryOptions: entryOptions,
        );
        final copied = await ServiceHandler.copyFileToSafDir(
          tempFile.parent.path,
          fileName,
          savePath,
          'application/zip',
        );
        if (!copied) throw FileSystemException('Failed to save backup package', savePath);
        return savePath;
      } finally {
        unawaited(tempFile.parent.delete(recursive: true).catchError((_) => tempFile.parent));
      }
    }

    final path = await FilePicker.saveFile(
      dialogTitle: loc.settings.backupAndTransfer.exportBackupDialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List(0),
    );
    if (path == null) return null;
    await exportPackageFile(
      entryIds: entryIds,
      outputFile: File(path),
      options: options,
      entryOptions: entryOptions,
    );
    return path;
  }

  Future<File> _createTempPackageFile(String fileName) async {
    final dir = Directory(
      '${await ServiceHandler.getCacheDir()}backup_transfer${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  Future<({String name, Uint8List bytes})?> pickBackupFile() async {
    final file = await FilePicker.pickFile(
      dialogTitle: loc.settings.backupAndTransfer.importBackupDialogTitle,
      type: FileType.custom,
      allowedExtensions: [extension, 'json', 'db'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return (name: file.name, bytes: bytes);
  }
}

Uint8List _encodeBackupPackage(Map<String, Object?> data) {
  final archive = Archive();
  final rawFiles = data['files'];
  if (rawFiles is List) {
    for (final raw in rawFiles) {
      if (raw is! Map) continue;
      final path = raw['path']?.toString();
      final bytes = raw['bytes'];
      if (path == null || bytes is! Uint8List) continue;
      final file = ArchiveFile(path, bytes.length, bytes)..compression = CompressionType.none;
      archive.addFile(file);
    }
  }

  final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data['manifest']));
  archive.addFile(
    ArchiveFile(BackupPackageService.manifestFileName, manifestBytes.length, manifestBytes)
      ..compression = CompressionType.none,
  );

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _encodeBackupPackageFile(Map<String, Object?> data) {
  final outputPath = data['outputPath']?.toString();
  final rawFiles = data['files'];
  if (outputPath == null || rawFiles is! List) {
    throw const FormatException('Missing package file export data');
  }
  final encoder = ZipFileEncoder()..create(outputPath, level: ZipFileEncoder.store);
  try {
    for (final raw in rawFiles) {
      if (raw is! Map) continue;
      final sourcePath = raw['sourcePath']?.toString();
      final archivePath = raw['archivePath']?.toString();
      if (sourcePath == null || archivePath == null) continue;
      encoder.addFileSync(File(sourcePath), archivePath, ZipFileEncoder.store);
    }
  } finally {
    encoder.closeSync();
  }
}

Map<String, Object?> _decodeBackupPackage(Uint8List bytes) {
  return _decodeArchive(ZipDecoder().decodeBytes(bytes));
}

Map<String, Object?> _decodeArchive(Archive archive) {
  final manifestFile = archive.files.firstWhere(
    (file) => file.name == BackupPackageService.manifestFileName,
    orElse: () => throw const FormatException('Backup manifest not found'),
  );
  final manifest = jsonDecode(utf8.decode(_archiveFileBytes(manifestFile)));
  final files = <String, Uint8List>{};
  for (final file in archive.files) {
    if (file.name == BackupPackageService.manifestFileName || !file.isFile) continue;
    files[file.name] = _archiveFileBytes(file);
  }
  return {
    'manifest': manifest,
    'files': files,
  };
}

Map<String, Object?> _extractBackupPackageFile(Map<String, String> data) {
  final packagePath = data['packagePath'];
  final extractDir = data['extractDir'];
  if (packagePath == null || extractDir == null) {
    throw const FormatException('Missing package extraction paths');
  }

  final input = InputFileStream(packagePath);
  final archive = ZipDecoder().decodeStream(input);
  try {
    final fileNames = archive.files
        .where((file) => file.isFile && file.name != BackupPackageService.manifestFileName)
        .map((file) => file.name)
        .toList();
    if (!archive.files.any((file) => file.name == BackupPackageService.manifestFileName && file.isFile)) {
      throw const FormatException('Backup manifest not found');
    }

    final extractedFiles = _extractArchiveEntriesToDisk(archive, extractDir);
    final manifestPath = extractedFiles[BackupPackageService.manifestFileName];
    if (manifestPath == null) {
      throw const FormatException('Backup manifest not found');
    }
    final manifest = jsonDecode(File(manifestPath).readAsStringSync());
    final files = <String, String>{};
    for (final name in fileNames) {
      final path = extractedFiles[name];
      if (path == null) continue;
      files[name] = path;
    }
    return {
      'manifest': manifest,
      'files': files,
    };
  } finally {
    archive.clear();
    input.closeSync();
  }
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  return file.content;
}

String _extractedArchivePath(String extractDir, String archivePath) {
  final safeName = _normalizedArchivePath(archivePath).replaceAll('/', '_');
  return '$extractDir${Platform.pathSeparator}$safeName';
}

Map<String, String> _extractArchiveEntriesToDisk(Archive archive, String extractDir) {
  Directory(extractDir).createSync(recursive: true);
  final extracted = <String, String>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final outPath = _extractedArchivePath(extractDir, file.name);
    File(outPath).parent.createSync(recursive: true);
    final output = OutputFileStream(outPath, bufferSize: 64 * 1024);
    try {
      file.writeContent(output);
    } finally {
      output.closeSync();
    }
    if (!File(outPath).existsSync()) {
      throw PathNotFoundException(outPath, const OSError('Archive entry was not extracted'));
    }
    extracted[file.name] = outPath;
    extracted[_normalizedArchivePath(file.name)] = outPath;
  }
  return extracted;
}

String _normalizedArchivePath(String archivePath) {
  return Uri.decodeFull(archivePath).replaceAll(r'\', '/').split('/').where((part) => part.isNotEmpty).join('/');
}
