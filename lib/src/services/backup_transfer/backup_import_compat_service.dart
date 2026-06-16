import 'dart:typed_data';
import 'dart:io';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';

class BackupImportCompatService {
  BackupImportCompatService({
    BackupPackageService? packageService,
    BackupEntryRegistry? registry,
  }) : packageService = packageService ?? BackupPackageService(),
       registry = registry ?? BackupEntryRegistry.instance;

  final BackupPackageService packageService;
  final BackupEntryRegistry registry;

  Future<List<BackupEntryId>> importNamedBytes(
    String fileName,
    Uint8List bytes, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.lsbackup')) {
      return packageService.importPackage(bytes, options: options);
    }

    final legacyId = switch (lowerName) {
      'settings.json' => BackupEntryId.settings,
      'boorus.json' => BackupEntryId.booruProfiles,
      'tags.json' => BackupEntryId.tags,
      'store.db' => BackupEntryId.database,
      'tabs.json' => BackupEntryId.tabs,
      'favourites.json' => BackupEntryId.favourites,
      'snatched.json' => BackupEntryId.snatched,
      _ => null,
    };
    if (legacyId == null) {
      throw FormatException(loc.settings.backupAndTransfer.unsupportedBackupFile(fileName: fileName));
    }
    await registry.byId(legacyId).importEntry(bytes, options);
    return [legacyId];
  }

  Future<List<BackupEntryId>> importNamedFile(
    String fileName,
    File file, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.lsbackup')) {
      return packageService.importPackageFile(file, options: options);
    }
    return importNamedBytes(fileName, await file.readAsBytes(), options: options);
  }
}
