import 'dart:io';
import 'dart:typed_data';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';

class BackupImportCompatService {
  BackupImportCompatService({BackupPackageService? packageService, BackupEntryRegistry? registry})
    : packageService = packageService ?? BackupPackageService(registry: registry),
      registry = registry ?? BackupEntryRegistry.instance;
  final BackupPackageService packageService;
  final BackupEntryRegistry registry;

  BackupEntryId legacyEntryId(String fileName) {
    final name = fileName.replaceAll(r'\', '/').split('/').last.toLowerCase();
    final entry = registry.entries.where((entry) => entry.fileName.toLowerCase() == name).firstOrNull;
    if (entry == null) throw FormatException(loc.settings.backupAndTransfer.unsupportedBackupFile(fileName: fileName));
    return entry.id;
  }

  Future<List<BackupEntryId>> inspectNamedFile(String name, File file) async =>
      BackupFileNaming.isPackageFileName(name) ? packageService.inspectPackageFile(file) : [legacyEntryId(name)];

  Future<BackupPreview> inspectNamedPreview(String name, File file) async => BackupFileNaming.isPackageFileName(name)
      ? packageService.inspectPackagePreview(file)
      : (entries: [legacyEntryId(name)], createdAt: null);

  Future<List<BackupEntryId>> importNamedBytes(
    String fileName,
    Uint8List bytes, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    if (BackupFileNaming.isPackageFileName(fileName)) return packageService.importPackage(bytes, options: options);
    final id = legacyEntryId(fileName);
    await registry.ensureImportAllowed(id, options);
    await registry.validateEntry(id, bytes: bytes, onProgress: options.onProgress);
    final applyOptions = _applyOptions(options);
    return registry.runImport(
      () async {
        options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.importing, entryId: id));
        await registry.byId(id).importEntry(bytes, applyOptions);
        options.onProgress?.call(const BackupImportProgress(phase: BackupImportPhase.refreshing));
        await registry.refreshAfterImport({id}, options: applyOptions);
        return [id];
      },
      onProgress: options.onProgress,
    );
  }

  Future<List<BackupEntryId>> importNamedFile(
    String fileName,
    File file, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    if (BackupFileNaming.isPackageFileName(fileName)) return packageService.importPackageFile(file, options: options);
    final id = legacyEntryId(fileName);
    await registry.ensureImportAllowed(id, options);
    await registry.validateEntry(id, file: file, onProgress: options.onProgress);
    final applyOptions = _applyOptions(options);
    return registry.runImport(() async {
      options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.importing, entryId: id));
      final definition = registry.byId(id);
      if (definition.importFile != null) {
        await definition.importFile!(file, applyOptions);
      } else {
        await definition.importEntry(await file.readAsBytes(), applyOptions);
      }
      options.onProgress?.call(const BackupImportProgress(phase: BackupImportPhase.refreshing));
      await registry.refreshAfterImport({id}, options: applyOptions);
      return [id];
    }, onProgress: options.onProgress);
  }

  BackupImportOptions _applyOptions(BackupImportOptions options) => BackupImportOptions(
    tabsMode: options.tabsMode,
    tagsMode: options.tagsMode,
    allowedEntryIds: options.allowedEntryIds,
    rejectUnexpectedEntries: options.rejectUnexpectedEntries,
    booruNameRemap: {},
    onProgress: options.onProgress,
  );
}
