import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
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
  static const maximumPackageBytes = 8 * 1024 * 1024 * 1024;
  static const maximumJsonBytes = 64 * 1024 * 1024;
  static const maximumManifestBytes = 1024 * 1024;

  Future<Directory> _stage() async {
    final root = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
    await root.create(recursive: true);
    return root.createTemp('package-');
  }

  Future<Uint8List> exportPackage({
    required List<BackupEntryId> entryIds,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    final stage = await _stage();
    try {
      final file = await exportPackageFile(
        entryIds: entryIds,
        outputFile: File('${stage.path}/backup.$extension'),
        options: options,
        entryOptions: entryOptions,
      );
      if (await file.length() > maximumJsonBytes) throw const FormatException('Use file export for large backups');
      return await file.readAsBytes();
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<File> exportPackageFile({
    required List<BackupEntryId> entryIds,
    required File outputFile,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    await outputFile.parent.create(recursive: true);
    final stage = await outputFile.parent.createTemp('.backup-export-');
    final owned = <File>[];
    try {
      final files = <Map<String, String>>[];
      final entries = <Map<String, Object?>>[];
      var total = 0;
      for (final id in entryIds.toSet()) {
        final definition = registry.byId(id);
        if (!await definition.isAvailable()) continue;
        final option = entryOptions[id] ?? options;
        File source;
        var mime = 'application/octet-stream';
        Map<String, dynamic> metadata = const {};
        if (definition.exportFile != null) {
          source = await definition.exportFile!(option);
          if (definition.exportFileIsTemporary) owned.add(source);
        } else {
          final payload = await definition.exportEntry(option);
          source = File('${stage.path}/${definition.fileName}');
          await source.writeAsBytes(payload.bytes, flush: true);
          mime = payload.mimeType;
          metadata = payload.metadata;
        }
        final size = await source.length();
        total += size;
        if (total > maximumPackageBytes - maximumManifestBytes) throw const FormatException('Backup exceeds 8 GiB');
        files.add({'sourcePath': source.path, 'archivePath': definition.fileName});
        entries.add({
          'id': id.name,
          'title': definition.title(),
          'path': definition.fileName,
          'mimeType': mime,
          'metadata': metadata,
          'size': size,
          'sha256': (await sha256.bind(source.openRead()).first).toString(),
        });
      }
      if (entries.isEmpty) throw const FormatException('No selected backup data is available');
      final manifest = File('${stage.path}/$manifestFileName');
      await manifest.writeAsString(
        jsonEncode({
          'format': BackupFileNaming.currentFormatId,
          'formatVersion': formatVersion,
          'createdAt': DateTime.now().toIso8601String(),
          'entries': entries,
        }),
        flush: true,
      );
      files.add({'sourcePath': manifest.path, 'archivePath': manifestFileName});
      final encoded = File('${stage.path}/encoded.$extension');
      await compute(_encodeBackupPackageFile, {'outputPath': encoded.path, 'files': files});
      if (await encoded.length() > maximumPackageBytes) throw const FormatException('Backup exceeds 8 GiB');
      // Preserve an existing destination until the entire export has succeeded.
      await encoded.rename(outputFile.path);
      return outputFile;
    } finally {
      try {
        await Future.wait(
          owned.map((file) async {
            if (await file.exists()) await file.delete();
          }),
        );
      } finally {
        await stage.delete(recursive: true);
      }
    }
  }

  Future<List<BackupEntryId>> importPackage(
    Uint8List bytes, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    if (bytes.length > maximumPackageBytes) throw const FormatException('Backup exceeds 8 GiB');
    final stage = await _stage();
    try {
      final file = File('${stage.path}/input.$extension');
      await file.writeAsBytes(bytes, flush: true);
      return await importPackageFile(file, options: options);
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>> _extract(File file, Directory stage) async {
    final size = await file.length();
    if (size <= 0 || size > maximumPackageBytes) throw const FormatException('Invalid backup package size');
    return compute(_extractBackupPackageFile, {'packagePath': file.path, 'extractDir': stage.path});
  }

  List<({BackupEntryId id, File file, Map raw})> _entries(Map<String, Object?> decoded) {
    final manifest = decoded['manifest'];
    final files = decoded['files'];
    if (manifest is! Map ||
        !BackupFileNaming.isSupportedFormatId(manifest['format']) ||
        manifest['formatVersion'] is! int ||
        manifest['formatVersion'] != formatVersion ||
        files is! Map) {
      throw FormatException(loc.settings.backupAndTransfer.unsupportedBackupFormat);
    }
    final rawEntries = manifest['entries'];
    if (rawEntries is! List || rawEntries.isEmpty || rawEntries.length > registry.entries.length) {
      throw const FormatException('Invalid backup entry list');
    }
    final ids = <BackupEntryId>{};
    final paths = <String>{};
    final result = <({BackupEntryId id, File file, Map raw})>[];
    for (final raw in rawEntries) {
      if (raw is! Map || raw['id'] is! String || raw['path'] is! String) {
        throw const FormatException('Invalid backup entry');
      }
      final definition = registry.entries.where((entry) => entry.id.name == raw['id']).firstOrNull;
      final path = raw['path'] as String;
      if (definition == null ||
          !ids.add(definition.id) ||
          !paths.add(path) ||
          path != definition.fileName ||
          files[path] is! String) {
        throw const FormatException('Unknown, duplicate or missing backup entry');
      }
      if (raw.containsKey('metadata') && raw['metadata'] is! Map) throw const FormatException('Invalid entry metadata');
      result.add((id: definition.id, file: File(files[path] as String), raw: raw));
    }
    if (files.length != paths.length || !files.keys.every(paths.contains)) {
      throw const FormatException('Unlisted backup files');
    }
    return result;
  }

  Future<List<BackupEntryId>> inspectPackageFile(File file) async {
    final stage = await _stage();
    try {
      return _entries(await _extract(file, stage)).map((entry) => entry.id).toList();
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<List<BackupEntryId>> importPackageFile(
    File file, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final stage = await _stage();
    try {
      options.onProgress?.call(const BackupImportProgress(phase: BackupImportPhase.extracting));
      final entries = _entries(await _extract(file, stage));
      if (options.rejectUnexpectedEntries &&
          options.allowedEntryIds != null &&
          !entries.map((entry) => entry.id).toSet().containsAll(options.allowedEntryIds!)) {
        throw const FormatException('The backup is missing requested data');
      }
      // Preflight every payload before any application writes.
      for (final entry in entries) {
        if (options.rejectUnexpectedEntries &&
            options.allowedEntryIds != null &&
            !options.allowedEntryIds!.contains(entry.id)) {
          throw const FormatException('Backup contains data that was not requested');
        }
        if (entry.raw.containsKey('size') &&
            (entry.raw['size'] is! int || entry.raw['size'] != await entry.file.length())) {
          throw const FormatException('Backup entry size mismatch');
        }
        if (entry.raw.containsKey('sha256')) {
          options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.verifying, entryId: entry.id));
          final expected = entry.raw['sha256'];
          if (expected is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected) ||
              (await sha256.bind(entry.file.openRead()).first).toString() != expected) {
            throw const FormatException('Backup entry checksum mismatch');
          }
        }
        options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.validating, entryId: entry.id));
        await registry.validateEntry(entry.id, file: entry.file, onProgress: options.onProgress);
      }
      final selectedIds = registry.normalizeSelection(
        entries
            .where((entry) => options.allowedEntryIds == null || options.allowedEntryIds!.contains(entry.id))
            .map((entry) => entry.id),
      );
      final selected = entries.where((entry) => selectedIds.contains(entry.id)).toList();
      if (selected.isEmpty) throw const FormatException('The backup does not contain the selected data');
      final settings = selected.where((entry) => entry.id == BackupEntryId.settings).firstOrNull;
      if (settings != null && selected.any((entry) => registry.requiresDatabase(entry.id))) {
        final values = jsonDecode((await settings.file.readAsString()).replaceFirst(RegExp(r'^\uFEFF'), '')) as Map;
        if (values['dbEnabled'] == false) {
          throw const FormatException(
            'The selected settings disable the database required by another selected category',
          );
        }
      }
      for (final entry in selected) {
        await registry.ensureImportAllowed(entry.id, options);
      }
      int priority(BackupEntryId id) => switch (id) {
        BackupEntryId.database => 0,
        BackupEntryId.settings => 1,
        BackupEntryId.booruProfiles => 2,
        _ => 3,
      };
      selected.sort((a, b) => priority(a.id).compareTo(priority(b.id)));
      final imported = <BackupEntryId>[];
      final applyOptions = BackupImportOptions(
        allowedEntryIds: options.allowedEntryIds,
        rejectUnexpectedEntries: options.rejectUnexpectedEntries,
        tabsMode: options.tabsMode,
        tagsMode: options.tagsMode,
        booruNameRemap: {},
        onProgress: options.onProgress,
      );
      for (final entry in selected) {
        options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.importing, entryId: entry.id));
        final definition = registry.byId(entry.id);
        if (definition.importFile != null) {
          await definition.importFile!(entry.file, applyOptions);
        } else {
          await definition.importEntry(await entry.file.readAsBytes(), applyOptions);
        }
        imported.add(entry.id);
      }
      options.onProgress?.call(const BackupImportProgress(phase: BackupImportPhase.refreshing));
      await registry.refreshAfterImport(imported.toSet(), options: applyOptions);
      return imported;
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<String?> savePackageWithPicker(Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: loc.settings.backupAndTransfer.exportBackupDialogTitle,
      fileName: BackupFileNaming.packageFileName(DateTime.now()),
      bytes: bytes,
      mimeType: BackupFileNaming.mimeType,
    );
    return uri?.toString();
  }

  Future<String?> exportPackageFileWithPicker({
    required List<BackupEntryId> entryIds,
    BackupExportOptions options = const BackupExportOptions(),
    Map<BackupEntryId, BackupExportOptions> entryOptions = const {},
  }) async {
    final name = BackupFileNaming.packageFileName(DateTime.now());
    final stage = await _stage();
    try {
      final file = await exportPackageFile(
        entryIds: entryIds,
        outputFile: File('${stage.path}/$name'),
        options: options,
        entryOptions: entryOptions,
      );
      if (Platform.isAndroid) {
        final destination = await ServiceHandler.getSAFDirectoryAccess();
        if (destination.isEmpty) return null;
        if (!await ServiceHandler.copyFileToSafDir(stage.path, name, destination, BackupFileNaming.mimeType)) {
          throw FileSystemException('Failed to save backup package', destination);
        }
        return destination;
      }
      if (Platform.isIOS) {
        // iOS's native save sheet requires the contents before presenting.
        if (await file.length() > maximumJsonBytes) {
          throw const FormatException('Use device transfer for iOS backups larger than 64 MiB');
        }
        return (await FilePicker.saveFile(
          fileName: name,
          bytes: await file.readAsBytes(),
          mimeType: BackupFileNaming.mimeType,
        ))?.toString();
      }
      final destination = await FilePicker.getDirectoryPath(
        dialogTitle: loc.settings.backupAndTransfer.exportBackupDialogTitle,
      );
      if (destination == null) return null;
      final copyStage = await Directory(destination).createTemp('.backup-save-');
      try {
        final staged = await file.copy('${copyStage.path}/$name');
        final output = File('$destination${Platform.pathSeparator}$name');
        await staged.rename(output.path);
        return output.path;
      } finally {
        await copyStage.delete(recursive: true);
      }
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<T?> withPickedBackup<T>(Future<T> Function(String name, File file) action) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: loc.settings.backupAndTransfer.importBackupDialogTitle,
      type: FileType.any,
    );
    if (picked == null) return null;
    final stage = await _stage();
    try {
      final file = File('${stage.path}/input');
      final output = await file.open(mode: FileMode.write);
      try {
        var size = 0;
        await for (final chunk in picked.readAsByteStream()) {
          size += chunk.length;
          if (size > maximumPackageBytes) throw const FormatException('Backup exceeds 8 GiB');
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      return await action(picked.name, file);
    } finally {
      await stage.delete(recursive: true);
    }
  }
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
      final sourceFile = File(sourcePath);
      final input = InputFileStream(sourcePath);
      try {
        final stat = sourceFile.statSync();
        final entry = ArchiveFile.stream(archivePath, input)
          // Level 0 still deflates into memory; explicitly store the file to stream it.
          ..compression = CompressionType.none
          ..lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000
          ..mode = stat.mode;
        encoder.addArchiveFile(entry);
      } finally {
        input.closeSync();
      }
    }
  } finally {
    encoder.closeSync();
  }
}

Map<String, Object?> _extractBackupPackageFile(Map<String, String> data) {
  final input = InputFileStream(data['packagePath']!);
  try {
    // ZipDecoder merges duplicate names; inspect the original headers first.
    final directory = ZipDirectory()..read(input);
    var total = 0;
    final names = <String>{};
    if (directory.fileHeaders.length > 16) throw const FormatException('Too many backup files');
    for (final header in directory.fileHeaders) {
      final file = header.file!;
      final name = file.filename;
      if (!RegExp(r'^[a-zA-Z0-9_-]+\.(json|db)$').hasMatch(name) ||
          !names.add(name.toLowerCase()) ||
          ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
        throw const FormatException('Unsafe or duplicate archive path');
      }
      final limit = name == BackupPackageService.manifestFileName
          ? BackupPackageService.maximumManifestBytes
          : (name == 'store.db' || name == 'favourites.json' || name == 'snatched.json')
          ? BackupPackageService.maximumPackageBytes
          : BackupPackageService.maximumJsonBytes;
      total += file.uncompressedSize;
      if (file.uncompressedSize < 0 ||
          file.uncompressedSize > limit ||
          total > BackupPackageService.maximumPackageBytes) {
        throw const FormatException('Backup extraction size limit exceeded');
      }
    }
    if (!names.contains(BackupPackageService.manifestFileName)) throw const FormatException('Missing backup manifest');
    // rewind() moves back one byte in archive's InputFileStream. The second
    // directory scan needs the full stream length, so reset to the beginning.
    input.reset();
    final archive = ZipDecoder().decodeStream(input);
    try {
      final files = <String, String>{};
      for (final file in archive.files) {
        if (!file.isFile || file.isSymbolicLink) throw const FormatException('Unsupported archive entry');
        final path = '${data['extractDir']}${Platform.pathSeparator}${file.name}';
        final output = _BoundedOutput(OutputFileStream(path, bufferSize: 64 * 1024), file.size);
        try {
          file.writeContent(output);
          if (output.length != file.size) throw const FormatException('Truncated archive entry');
        } finally {
          output.closeSync();
        }
        final check = File(path).openSync();
        var crc = 0;
        try {
          while (true) {
            final chunk = check.readSync(64 * 1024);
            if (chunk.isEmpty) break;
            crc = getCrc32(chunk, crc);
          }
        } finally {
          check.closeSync();
        }
        if (crc != file.crc32) throw const FormatException('Archive checksum mismatch');
        files[file.name] = path;
      }
      final manifestPath = files.remove(BackupPackageService.manifestFileName)!;
      return {'manifest': jsonDecode(File(manifestPath).readAsStringSync()), 'files': files};
    } finally {
      archive.clear();
    }
  } finally {
    input.closeSync();
  }
}

class _BoundedOutput extends OutputStream {
  _BoundedOutput(this.output, this.limit) : super(byteOrder: output.byteOrder);
  final OutputFileStream output;
  final int limit;
  @override
  int get length => output.length;
  void _check(int count) {
    if (count < 0 || length + count > limit) throw const FormatException('Archive entry exceeds declared size');
  }

  @override
  void writeByte(int value) {
    _check(1);
    output.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    output.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      writeBytes(stream.readBytes(stream.length > 65536 ? 65536 : stream.length).toUint8List());
    }
  }

  @override
  Uint8List subset(int start, [int? end]) => output.subset(start, end);
  @override
  void flush() => output.flush();
  @override
  void clear() {
    output.closeSync();
  }

  @override
  void closeSync() => output.closeSync();
}
