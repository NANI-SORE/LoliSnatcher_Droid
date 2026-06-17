import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';

class BackupEntryRegistry {
  BackupEntryRegistry._();

  static final BackupEntryRegistry instance = BackupEntryRegistry._();

  static const BackupEntryId databaseParentId = BackupEntryId.database;
  static const List<BackupEntryId> databaseChildIds = [
    BackupEntryId.tabs,
    BackupEntryId.favourites,
    BackupEntryId.snatched,
    BackupEntryId.tags,
    BackupEntryId.searchHistory,
    BackupEntryId.pinnedTags,
  ];

  final SettingsHandler _settingsHandler = SettingsHandler.instance;
  final SearchHandler _searchHandler = SearchHandler.instance;
  final TagHandler _tagHandler = TagHandler.instance;

  late final List<BackupEntryDefinition> entries = [
    BackupEntryDefinition(
      id: BackupEntryId.settings,
      title: () => loc.settings.backupAndTransfer.entrySettingsTitle,
      description: () => loc.settings.backupAndTransfer.entrySettingsDescription,
      fileName: 'settings.json',
      icon: Icons.settings,
      supportsClipboard: true,
      isAvailable: () async => true,
      exportEntry: _exportSettings,
      importEntry: _importSettings,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.booruProfiles,
      title: () => loc.settings.backupAndTransfer.entryBooruProfilesTitle,
      description: () => loc.settings.backupAndTransfer.entryBooruProfilesDescription,
      fileName: 'boorus.json',
      icon: Icons.image_search,
      supportsClipboard: true,
      isAvailable: () async => true,
      exportEntry: _exportBoorus,
      importEntry: _importBoorus,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.database,
      title: () => loc.settings.backupAndTransfer.entryDatabaseTitle,
      description: () => loc.settings.backupAndTransfer.entryDatabaseDescription,
      fileName: 'store.db',
      icon: Icons.storage,
      supportsClipboard: false,
      isAvailable: _databaseExists,
      exportEntry: _exportDatabase,
      importEntry: _importDatabase,
      exportFile: _exportDatabaseFile,
      importFile: _importDatabaseFile,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.tabs,
      title: () => loc.settings.backupAndTransfer.entryTabsTitle,
      description: () => loc.settings.backupAndTransfer.entryTabsDescription,
      fileName: 'tabs.json',
      icon: Icons.tab,
      supportsClipboard: true,
      isAvailable: () async => true,
      exportEntry: _exportTabs,
      importEntry: _importTabs,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.favourites,
      title: () => loc.settings.backupAndTransfer.entryFavouritesTitle,
      description: () => loc.settings.backupAndTransfer.entryFavouritesDescription,
      fileName: 'favourites.json',
      icon: Icons.favorite,
      supportsClipboard: false,
      isAvailable: () async => SX.dbEnabled.value,
      exportEntry: (options) => _exportFlaggedItems(isDownloads: false, options: options),
      importEntry: _importFlaggedItems,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.snatched,
      title: () => loc.settings.backupAndTransfer.entrySnatchedTitle,
      description: () => loc.settings.backupAndTransfer.entrySnatchedDescription,
      fileName: 'snatched.json',
      icon: Icons.file_download_outlined,
      supportsClipboard: false,
      isAvailable: () async => SX.dbEnabled.value,
      exportEntry: (options) => _exportFlaggedItems(isDownloads: true, options: options),
      importEntry: _importFlaggedItems,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.tags,
      title: () => loc.settings.backupAndTransfer.entryTagsTitle,
      description: () => loc.settings.backupAndTransfer.entryTagsDescription,
      fileName: 'tags.json',
      icon: Icons.sell,
      supportsClipboard: true,
      isAvailable: () async => true,
      exportEntry: _exportTags,
      importEntry: _importTags,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.pinnedTags,
      title: () => loc.settings.backupAndTransfer.entryPinnedTagsTitle,
      description: () => loc.settings.backupAndTransfer.entryPinnedTagsDescription,
      fileName: 'pinned_tags.json',
      icon: Icons.push_pin,
      supportsClipboard: true,
      isAvailable: () async => SX.dbEnabled.value,
      exportEntry: _exportPinnedTags,
      importEntry: _importPinnedTags,
    ),
    BackupEntryDefinition(
      id: BackupEntryId.searchHistory,
      title: () => loc.settings.backupAndTransfer.entrySearchHistoriesTitle,
      description: () => loc.settings.backupAndTransfer.entrySearchHistoriesDescription,
      fileName: 'search_history.json',
      icon: Icons.history,
      supportsClipboard: false,
      isAvailable: () async => SX.dbEnabled.value,
      exportEntry: _exportSearchHistory,
      importEntry: _importSearchHistory,
    ),
  ];

  List<BackupEntryDefinition> get defaultEntries => entries.where((entry) {
    return {
      BackupEntryId.settings,
      BackupEntryId.booruProfiles,
      BackupEntryId.database,
      BackupEntryId.favourites,
      BackupEntryId.snatched,
      BackupEntryId.tabs,
      BackupEntryId.tags,
      BackupEntryId.pinnedTags,
      BackupEntryId.searchHistory,
    }.contains(entry.id);
  }).toList();

  List<BackupEntryDefinition> get fullBackupEntries => entries.where((entry) {
    return {
      BackupEntryId.settings,
      BackupEntryId.booruProfiles,
      BackupEntryId.database,
    }.contains(entry.id);
  }).toList();

  BackupEntryDefinition byId(BackupEntryId id) => entries.firstWhere((entry) => entry.id == id);

  bool isDatabaseChild(BackupEntryId id) => databaseChildIds.contains(id);

  Future<bool> _databaseExists() async {
    final file = File('${await ServiceHandler.getConfigDir()}store.db');
    return file.exists();
  }

  Future<BackupEntryPayload> _exportSettings(BackupExportOptions options) async {
    final json = SettingsRegistry.instance.toJson();
    final beforeFilterCount = json.length;
    if (options.excludeDeviceSpecificSettings) {
      for (final state in SettingsRegistry.instance.deviceSpecific) {
        json.remove(state.def.jsonKey);
      }
    }
    for (final key in _alwaysLocalSettingKeys) {
      json.remove(key.jsonKey);
    }
    BackupTransferLogger.info(
      'Exporting settings count=${json.length} filtered=${beforeFilterCount - json.length} excludeDeviceSpecific=${options.excludeDeviceSpecificSettings}',
      'BackupEntryRegistry',
      '_exportSettings',
    );
    return _jsonPayload('settings.json', json);
  }

  Future<void> _importSettings(Uint8List bytes, BackupImportOptions options) async {
    BackupTransferLogger.info(
      'Importing settings bytes=${bytes.length}',
      'BackupEntryRegistry',
      '_importSettings',
    );
    await _settingsHandler.loadFromJSON(utf8.decode(bytes), false);
    await _settingsHandler.saveSettings(restate: true);
  }

  static const Set<SettingKey> _alwaysLocalSettingKeys = {
    // system-dependant
    .appMode,
    .proxyType,
    .proxyAddress,
    .proxyUsername,
    .proxyPassword,
    .useLockscreen,
    .autoLockTimeout,
    .incognitoKeyboard,
    .shitDevice,
    .appAlias,
    .usePredictiveBack,
    .captureLogcat,
    .useImageLogging,
    // paths
    .drawerMascotPathOverride,
    .extPathOverride,
    .backupPath,
  };

  Future<BackupEntryPayload> _exportBoorus(BackupExportOptions options) async {
    final booruList = _settingsHandler.booruList.isEmpty
        ? await _readBoorusFromFiles()
        : _settingsHandler.booruList.where((e) => BooruType.saveable.contains(e.type)).toList();
    BackupTransferLogger.info(
      'Exporting booru profiles count=${booruList.length}',
      'BackupEntryRegistry',
      '_exportBoorus',
    );
    return _jsonPayload('boorus.json', booruList.map((b) => b.toJson()).toList());
  }

  Future<List<Booru>> _readBoorusFromFiles() async {
    final path = '${await ServiceHandler.getConfigDir()}boorus/';
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final boorus = <Booru>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final booru = Booru.fromJSON(await entity.readAsString());
        if (BooruType.saveable.contains(booru.type)) {
          boorus.add(booru);
        }
      } catch (_) {}
    }
    return boorus;
  }

  Future<void> _importBoorus(Uint8List bytes, BackupImportOptions options) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) return;
    final configBoorusPath = '${await ServiceHandler.getConfigDir()}boorus/';
    final configBoorusDir = await Directory(configBoorusPath).create(recursive: true);
    var imported = 0;
    var skipped = 0;
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final booru = Booru.fromMap(Map<String, dynamic>.from(raw));
      final alreadyExists =
          _settingsHandler.booruList.indexWhere((el) => el.baseURL == booru.baseURL && el.name == booru.name) != -1;
      final isAllowed = BooruType.saveable.contains(booru.type);
      if (!alreadyExists && isAllowed && booru.name?.isNotEmpty == true) {
        final booruFile = File('${configBoorusDir.path}${booru.name}.json');
        await booruFile.writeAsString(jsonEncode(booru.toJson()));
        imported++;
      } else {
        skipped++;
      }
    }
    BackupTransferLogger.info(
      'Imported booru profiles imported=$imported skipped=$skipped',
      'BackupEntryRegistry',
      '_importBoorus',
    );
    await _settingsHandler.loadBoorus();
  }

  Future<BackupEntryPayload> _exportDatabase(BackupExportOptions options) async {
    final file = File('${await ServiceHandler.getConfigDir()}store.db');
    if (!await file.exists()) {
      throw StateError(loc.settings.backupAndTransfer.databaseFileNotFound);
    }
    BackupTransferLogger.info(
      'Exporting database file ${file.path} bytes=${await file.length()}',
      'BackupEntryRegistry',
      '_exportDatabase',
    );
    return BackupEntryPayload(
      fileName: 'store.db',
      bytes: await file.readAsBytes(),
      mimeType: 'application/x-sqlite3',
    );
  }

  Future<File> _exportDatabaseFile(BackupExportOptions options) async {
    final file = File('${await ServiceHandler.getConfigDir()}store.db');
    if (!await file.exists()) {
      throw StateError(loc.settings.backupAndTransfer.databaseFileNotFound);
    }
    BackupTransferLogger.info(
      'Exporting database file reference ${file.path}',
      'BackupEntryRegistry',
      '_exportDatabaseFile',
    );
    return file;
  }

  Future<void> _importDatabase(Uint8List bytes, BackupImportOptions options) async {
    BackupTransferLogger.info(
      'Importing database bytes=${bytes.length}',
      'BackupEntryRegistry',
      '_importDatabase',
    );
    final tempFile = File('${await ServiceHandler.getCacheDir()}backup_transfer_import_store.db');
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsBytes(bytes, flush: true);
    await _forceIndexesForLargeDatabase(tempFile);
    unawaited(tempFile.delete().catchError((_) => tempFile));
    final configDir = await _prepareDatabaseImport();
    final dbFile = File('${configDir}store.db');
    await dbFile.writeAsBytes(bytes, flush: true);
    await _finishDatabaseImport();
  }

  Future<void> _importDatabaseFile(File file, BackupImportOptions options) async {
    BackupTransferLogger.info(
      'Importing database file ${file.path} bytes=${await file.length()}',
      'BackupEntryRegistry',
      '_importDatabaseFile',
    );
    await _forceIndexesForLargeDatabase(file);
    final configDir = await _prepareDatabaseImport();
    final dbFile = File('${configDir}store.db');
    await file.copy(dbFile.path);
    await _finishDatabaseImport();
  }

  Future<void> _forceIndexesForLargeDatabase(File file) async {
    final count = await _countDatabaseItems(file);
    if (count <= 10000 || SX.indexesEnabled.value) return;
    SX.indexesEnabled.state.value = true;
    BackupTransferLogger.info(
      'Enabling database indexes for imported database count=$count',
      'BackupEntryRegistry',
      '_forceIndexesForLargeDatabase',
    );
    await _settingsHandler.saveSettings(restate: false);
  }

  Future<int> _countDatabaseItems(File file) async {
    if (!await file.exists()) return 0;
    Database? db;
    try {
      db = await openDatabase(file.path, readOnly: true, singleInstance: false);
      final result = await db.rawQuery('SELECT COUNT(*) AS count FROM BooruItem');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await db?.close();
    }
  }

  Future<String> _prepareDatabaseImport() async {
    final configDir = await ServiceHandler.getConfigDir();
    _searchHandler.canBackup.value = false;
    BackupTransferLogger.info(
      'Preparing database import',
      'BackupEntryRegistry',
      '_prepareDatabaseImport',
    );
    await _settingsHandler.dbHandler.closeDb();
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${configDir}store.db$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
    return configDir;
  }

  Future<void> _finishDatabaseImport() async {
    BackupTransferLogger.info(
      'Finishing database import and restarting app',
      'BackupEntryRegistry',
      '_finishDatabaseImport',
    );
    await Future.delayed(const Duration(seconds: 1));
    await ServiceHandler.restartApp();
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(seconds: 2));
      exit(0);
    }
  }

  Future<BackupEntryPayload> _exportFlaggedItems({
    required bool isDownloads,
    required BackupExportOptions options,
  }) async {
    const limit = 250;
    final List<Map<String, dynamic>> encodedItems = [];
    int lastSeenId = -1;
    if (options.startIndex > 0) {
      final startId = await _settingsHandler.dbHandler.resolveFlaggedStartId(
        isDownloads: isDownloads,
        startIndex: options.startIndex,
      );
      lastSeenId = (startId ?? 0) - 1;
    }
    BackupTransferLogger.info(
      'Exporting ${isDownloads ? 'snatched' : 'favourites'} startIndex=${options.startIndex} initialLastSeenId=$lastSeenId',
      'BackupEntryRegistry',
      '_exportFlaggedItems',
    );

    while (true) {
      final batch = await _settingsHandler.dbHandler.getFlaggedItemsAfterId(
        isDownloads: isDownloads,
        lastSeenId: lastSeenId,
        limit: limit,
      );
      if (batch.isEmpty) break;
      encodedItems.addAll(
        batch.map((item) {
          if (!isDownloads) item.isSnatched.value = false;
          return item.toJson();
        }),
      );
      final last = batch.last;
      final id =
          await _settingsHandler.dbHandler.getItemID(last.postURL) ??
          await _settingsHandler.dbHandler.getItemID(last.fileURL);
      lastSeenId = int.tryParse(id ?? '') ?? lastSeenId + batch.length;
      if (batch.length < limit) break;
    }

    BackupTransferLogger.info(
      'Exported ${encodedItems.length} ${isDownloads ? 'snatched' : 'favourites'} items',
      'BackupEntryRegistry',
      '_exportFlaggedItems',
    );
    return _jsonPayload(isDownloads ? 'snatched.json' : 'favourites.json', encodedItems);
  }

  Future<void> _importFlaggedItems(Uint8List bytes, BackupImportOptions options) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) return;
    final items = decoded
        .whereType<Map>()
        .map((raw) => BooruItem.fromMap(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    if (items.isNotEmpty) {
      await _settingsHandler.dbHandler.updateMultipleBooruItems(items, BooruUpdateMode.sync);
    }
    BackupTransferLogger.info(
      'Imported flagged items count=${items.length}',
      'BackupEntryRegistry',
      '_importFlaggedItems',
    );
  }

  Future<BackupEntryPayload> _exportTabs(BackupExportOptions options) async {
    final tabs = _searchHandler.generateBackupJson() ?? '[]';
    BackupTransferLogger.info(
      'Exporting tabs bytes=${tabs.length}',
      'BackupEntryRegistry',
      '_exportTabs',
    );
    return BackupEntryPayload(
      fileName: 'tabs.json',
      bytes: Uint8List.fromList(utf8.encode(tabs)),
      mimeType: 'application/json',
    );
  }

  Future<void> _importTabs(Uint8List bytes, BackupImportOptions options) async {
    final text = utf8.decode(bytes);
    BackupTransferLogger.info(
      'Importing tabs bytes=${bytes.length} mode=${options.tabsMode.name}',
      'BackupEntryRegistry',
      '_importTabs',
    );
    switch (options.tabsMode) {
      case BackupTabsMode.merge:
        _searchHandler.mergeTabs(text);
        break;
      case BackupTabsMode.replace:
        _searchHandler.replaceTabs(text);
        break;
    }
    await _searchHandler.backupTabs();
  }

  Future<BackupEntryPayload> _exportTags(BackupExportOptions options) async {
    final tags = _tagHandler.toList();
    BackupTransferLogger.info(
      'Exporting tags count=${tags.length}',
      'BackupEntryRegistry',
      '_exportTags',
    );
    return _jsonPayload('tags.json', tags);
  }

  Future<void> _importTags(Uint8List bytes, BackupImportOptions options) async {
    BackupTransferLogger.info(
      'Importing tags bytes=${bytes.length} mode=${options.tagsMode.name}',
      'BackupEntryRegistry',
      '_importTags',
    );
    await _tagHandler.loadFromJSON(
      utf8.decode(bytes),
      preferTagTypeIfNone: options.tagsMode == BackupTagsMode.preferTypeIfNone,
    );
  }

  Future<BackupEntryPayload> _exportPinnedTags(BackupExportOptions options) async {
    final rows = await _settingsHandler.dbHandler.exportPinnedTagRows();
    BackupTransferLogger.info(
      'Exporting pinned tags count=${rows.length}',
      'BackupEntryRegistry',
      '_exportPinnedTags',
    );
    return _jsonPayload('pinned_tags.json', rows);
  }

  Future<void> _importPinnedTags(Uint8List bytes, BackupImportOptions options) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) return;
    final rows = _mapsFromJsonList(decoded);
    BackupTransferLogger.info(
      'Importing pinned tags count=${rows.length}',
      'BackupEntryRegistry',
      '_importPinnedTags',
    );
    await _settingsHandler.dbHandler.importPinnedTagRows(rows);
  }

  Future<BackupEntryPayload> _exportSearchHistory(BackupExportOptions options) async {
    final rows = await _settingsHandler.dbHandler.exportSearchHistoryRows();
    BackupTransferLogger.info(
      'Exporting search history count=${rows.length}',
      'BackupEntryRegistry',
      '_exportSearchHistory',
    );
    return _jsonPayload('search_history.json', rows);
  }

  Future<void> _importSearchHistory(Uint8List bytes, BackupImportOptions options) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) return;
    final rows = _mapsFromJsonList(decoded);
    BackupTransferLogger.info(
      'Importing search history count=${rows.length}',
      'BackupEntryRegistry',
      '_importSearchHistory',
    );
    await _settingsHandler.dbHandler.importSearchHistoryRows(rows);
  }

  List<Map<String, dynamic>> _mapsFromJsonList(List<dynamic> decoded) {
    return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList(growable: false);
  }

  BackupEntryPayload _jsonPayload(String fileName, Object? data) {
    return BackupEntryPayload(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(data))),
      mimeType: 'application/json',
    );
  }
}
