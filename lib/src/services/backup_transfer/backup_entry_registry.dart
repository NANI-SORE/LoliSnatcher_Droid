import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/services/database_backup_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_json_array.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
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
    BackupEntryId.tags,
    ...databaseRequiredIds,
  ];

  // Tabs and tag metadata also work without database storage.
  static const List<BackupEntryId> databaseRequiredIds = [
    BackupEntryId.favourites,
    BackupEntryId.snatched,
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
      exportFileIsTemporary: true,
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
      importEntry: (bytes, options) => _importFlaggedBytes(BackupEntryId.favourites, bytes, options),
      exportFile: (options) => _exportFlaggedFile(isDownloads: false, options: options),
      exportFileIsTemporary: true,
      importFile: (file, options) => _importFlaggedFile(BackupEntryId.favourites, file, options),
      isImportAvailable: () async => SX.dbEnabled.value,
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
      importEntry: (bytes, options) => _importFlaggedBytes(BackupEntryId.snatched, bytes, options),
      exportFile: (options) => _exportFlaggedFile(isDownloads: true, options: options),
      exportFileIsTemporary: true,
      importFile: (file, options) => _importFlaggedFile(BackupEntryId.snatched, file, options),
      isImportAvailable: () async => SX.dbEnabled.value,
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
      isImportAvailable: () async => SX.dbEnabled.value,
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
      isImportAvailable: () async => SX.dbEnabled.value,
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
      BackupEntryId.tabs,
      BackupEntryId.tags,
    }.contains(entry.id);
  }).toList();

  BackupEntryDefinition byId(BackupEntryId id) => entries.firstWhere((entry) => entry.id == id);

  bool isDatabaseChild(BackupEntryId id) => databaseChildIds.contains(id);

  bool requiresDatabase(BackupEntryId id) => databaseRequiredIds.contains(id);

  /// The snapshot already includes every child; do not apply child payloads again.
  Set<BackupEntryId> normalizeSelection(Iterable<BackupEntryId> ids) {
    final selected = ids.toSet();
    if (selected.contains(databaseParentId)) selected.removeAll(databaseChildIds);
    return selected;
  }

  static const maximumJsonBytes = 64 * 1024 * 1024;
  String _text(Uint8List bytes) => utf8.decode(bytes).trim().replaceFirst(RegExp(r'^\uFEFF'), '').trimLeft();

  Future<File> _temporaryFile(String suffix) async {
    final root = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
    await root.create(recursive: true);
    // Caller owns only this file. No user-selected directory is ever removed.
    final dir = await root.createTemp('entry-');
    final file = File('${root.path}/${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}.$suffix');
    await dir.delete();
    return file;
  }

  Future<void> ensureImportAllowed(BackupEntryId id, BackupImportOptions options) async {
    if (options.allowedEntryIds != null && !options.allowedEntryIds!.contains(id)) {
      throw const FormatException('This backup category was not selected');
    }
    if (!await byId(id).canImport() ||
        (requiresDatabase(id) && (!SX.dbEnabled.value || _settingsHandler.dbHandler.db == null))) {
      throw StateError('Enable the database before importing this category');
    }
  }

  Future<void> validateEntry(
    BackupEntryId id, {
    Uint8List? bytes,
    File? file,
    ValueChanged<BackupImportProgress>? onProgress,
    BackupImportPhase phase = BackupImportPhase.validating,
  }) async {
    byId(id);
    if ((bytes == null) == (file == null)) throw ArgumentError('Supply exactly one backup payload');
    if ((bytes?.length ?? await file!.length()) > 8 * 1024 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 8 GiB');
    }
    if (id == BackupEntryId.database) {
      final staged = file ?? await _temporaryFile('db');
      try {
        if (bytes != null) await staged.writeAsBytes(bytes, flush: true);
        await const DatabaseBackupService().validate(staged);
        await _validateDatabaseTabs(staged);
      } finally {
        if (file == null && await staged.exists()) await staged.delete();
      }
      return;
    }
    if (id == BackupEntryId.favourites || id == BackupEntryId.snatched) {
      final stream = file?.openRead() ?? Stream<List<int>>.value(bytes!);
      var count = 0;
      void report() => onProgress?.call(BackupImportProgress(phase: phase, entryId: id, processedItems: count));
      report();
      await for (final row in readBackupJsonArray(stream)) {
        _validateFlagged(row);
        if (++count % 250 == 0) report();
      }
      report();
      return;
    }
    if ((bytes?.length ?? await file!.length()) > maximumJsonBytes) {
      throw const FormatException('JSON backup exceeds 64 MiB');
    }
    final text = utf8.decode(bytes ?? await file!.readAsBytes()).trim().replaceFirst(RegExp(r'^\uFEFF'), '').trimLeft();
    if (id == BackupEntryId.tabs) {
      TabBackup.parseImport(text);
      return;
    }
    final decoded = jsonDecode(text);
    if (id == BackupEntryId.settings) {
      if (decoded is! Map<String, dynamic>) throw const FormatException('Expected a settings object');
      _validateSettings(decoded);
      return;
    }
    if (decoded is! List || decoded.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Expected an array of records');
    }
    final profileNames = <String>{};
    for (final row in decoded.cast<Map<String, dynamic>>()) {
      switch (id) {
        case BackupEntryId.booruProfiles:
          final name = row['name'];
          final url = row['baseURL'];
          if (name is! String ||
              name.trim().isEmpty ||
              name.length > 180 ||
              name != name.trim() ||
              name.endsWith('.') ||
              RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
              name == '.' ||
              name == '..' ||
              RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', caseSensitive: false).hasMatch(name) ||
              !profileNames.add(name.toLowerCase()) ||
              url is! String ||
              !['http', 'https'].contains(Uri.tryParse(url)?.scheme) ||
              Uri.tryParse(url)?.host.isNotEmpty != true ||
              !BooruType.saveable.contains(Booru.fromMap(row).type)) {
            throw const FormatException('Invalid or duplicate booru profile');
          }
          for (final field in ['faviconURL', 'apiKey', 'userID', 'defTags']) {
            if (row[field] != null && row[field] is! String) throw FormatException('Invalid profile $field');
          }
          if (row['settingOverrides'] != null) {
            if (row['settingOverrides'] is! Map<String, dynamic>) {
              throw const FormatException('Invalid booru overrides');
            }
            _validateSettings(row['settingOverrides'] as Map<String, dynamic>);
          }
        case BackupEntryId.tags:
          _tagFromBackupJson(row);
        case BackupEntryId.pinnedTags:
          if (row['tagName'] is! String || (row['tagName'] as String).trim().isEmpty) {
            throw const FormatException('Invalid pinned tag');
          }
          for (final field in ['pinnedAt', 'sortOrder']) {
            if (row[field] != null && row[field] is! int) throw FormatException('Invalid pin $field');
          }
          _validateNullableStrings(row, ['booruName', 'booruType', 'label']);
        case BackupEntryId.searchHistory:
          if (row['searchText'] is! String || (row['searchText'] as String).trim().isEmpty) {
            throw const FormatException('Invalid search history');
          }
          if (row['isFavourite'] != null && row['isFavourite'] != 0 && row['isFavourite'] != 1) {
            throw const FormatException('Invalid history flag');
          }
          _validateNullableStrings(row, ['booruName', 'booruType', 'timestamp']);
        default:
          throw const FormatException('Unsupported backup category');
      }
    }
  }

  Tag? _tagFromBackupJson(Map<String, dynamic> row) {
    final name = row['fullString'] ?? row['name'];
    if (name is! String) throw const FormatException('Invalid tag name');
    // Older tag caches can contain blank names. They carry no tag data to restore.
    if (name.trim().isEmpty) return null;
    for (final field in ['count', 'updatedAt']) {
      if (row[field] != null && row[field] is! int) throw FormatException('Invalid tag $field');
    }
    return Tag.fromJson(row);
  }

  void _validateNullableStrings(Map<String, dynamic> row, List<String> fields) {
    for (final field in fields) {
      if (row[field] != null && row[field] is! String) throw FormatException('Invalid $field');
    }
  }

  void _validateSettings(Map<String, dynamic> json) {
    for (final state in SettingsRegistry.instance.all) {
      final def = state.def;
      if (def.isTransient || def.isWidgetSlot) continue;
      final key = json.containsKey(def.jsonKey) ? def.jsonKey : def.legacyJsonKeys.where(json.containsKey).firstOrNull;
      if (key == null) continue;
      final raw = json[key];
      final example = def.serializeValue(def.getDefaultValue());
      if ((example is bool && raw is! bool) ||
          (example is String && raw is! String) ||
          (example is num && raw is! num) ||
          (example is List && raw is! List && raw is! String) ||
          (example is Map && raw is! Map)) {
        throw FormatException('Invalid setting $key');
      }
      final parsed = def.valueFromJson(raw);
      final canonical = def.serializeValue(parsed);
      if ((example is int && raw is! int) ||
          (parsed is Enum && raw is String && canonical.toString().toLowerCase() != raw.toLowerCase()) ||
          (canonical == null && raw != null)) {
        throw FormatException('Invalid setting $key');
      }
      if (raw is List && canonical is List) {
        if (canonical.every((value) => value is String)) {
          final accepted = canonical.cast<String>().map((value) => value.toLowerCase()).toSet();
          if (raw.any((value) => value is! String || !accepted.contains(value.toLowerCase()))) {
            throw FormatException('Invalid setting list $key');
          }
        } else if (!const DeepCollectionEquality().equals(raw, canonical)) {
          throw FormatException('Invalid setting records $key');
        }
      } else if (raw is Map && !const DeepCollectionEquality().equals(raw, canonical)) {
        throw FormatException('Invalid setting object $key');
      }
      def.validateValue(parsed);
    }
  }

  void _validateFlagged(Map<String, dynamic> row) {
    for (final field in ['postURL', 'fileURL', 'sampleURL', 'thumbnailURL']) {
      if (row[field] is! String) throw FormatException('Invalid item $field');
    }
    if ((row['postURL'] as String).isEmpty) throw const FormatException('Invalid item post URL');
    if (row['tags'] is! List || (row['tags'] as List).any((tag) => tag is! String && tag is! Map)) {
      throw const FormatException('Invalid item tags');
    }
    for (final field in ['isFavourite', 'isSnatched']) {
      if (row[field] is! bool) throw FormatException('Invalid item $field');
    }
    for (final tag in row['tags'] as List) {
      if (tag is Map) {
        final name = tag['fullString'] ?? tag['name'];
        if (name is! String || name.isEmpty) throw const FormatException('Invalid item tag');
        Tag.fromJson(Map<String, dynamic>.from(tag));
      }
    }
    // All fields consumed by BooruItem.fromMap are checked above. Avoid
    // allocating viewer keys and reactive state for every preflight record.
  }

  Future<void> refreshAfterImport(
    Set<BackupEntryId> ids, {
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    final renames = options.booruNameRemap ?? const <String, String>{};
    if (ids.contains(BackupEntryId.settings) && renames.containsKey(SX.prefBooru.value)) {
      SX.prefBooru.state.loadFromJson(renames[SX.prefBooru.value]);
      await _settingsHandler.saveSettings(restate: false);
    }
    if (ids.contains(BackupEntryId.database)) {
      final dbHandler = _settingsHandler.dbHandler;
      final temporaryConnection = dbHandler.db == null;
      try {
        if (temporaryConnection) await dbHandler.dbConnect(await ServiceHandler.getConfigDir());
        if (renames.isNotEmpty) {
          final cases = List.filled(renames.length, 'WHEN ? THEN ?').join(' ');
          final args = renames.entries.expand<Object?>((entry) => [entry.key, entry.value]).toList();
          await dbHandler.db!.transaction((txn) async {
            for (final table in ['PinnedTag', 'SearchHistory']) {
              await txn.rawUpdate('UPDATE $table SET booruName = CASE booruName $cases ELSE booruName END', args);
            }
          });
        }
        final restored = await dbHandler.getTabRestore();
        final tabs = restored == null || restored.trim().isEmpty ? '[]' : restored;
        final restoredTags = await dbHandler.getAllTags();
        _tagHandler.tagMap.clear();
        for (final tag in restoredTags) {
          await _tagHandler.putTag(tag, dbEnabled: false, useDB: false, preferTypeIfNone: false);
        }
        _searchHandler.replaceTabs(_remapTabs(tabs, renames), resetIfEmpty: true);
      } finally {
        if (temporaryConnection) await dbHandler.closeDb();
      }
      if (!SX.dbEnabled.value) await _saveTagsWithoutDatabase();
    }
    await _searchHandler.backupTabs();
  }

  String _remapTabs(String text, Map<String, String> renames) => jsonEncode(
    TabBackup.parseImport(text)
        .map(
          (tab) => {
            ...tab.toJson(),
            'b': renames[tab.booru] ?? tab.booru,
            if (tab.secondaryBoorus.isNotEmpty) 'sb': tab.secondaryBoorus.map((name) => renames[name] ?? name).toList(),
          },
        )
        .toList(),
  );

  Future<bool> _databaseExists() async {
    if (!SX.dbEnabled.value) return false;
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
    await ensureImportAllowed(BackupEntryId.settings, options);
    await validateEntry(BackupEntryId.settings, bytes: bytes);
    final json = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '')));
    for (final key in _alwaysLocalSettingKeys) {
      final def = SettingsRegistry.instance.get<dynamic>(key)?.def;
      json.remove(key.jsonKey);
      for (final alias in def?.legacyJsonKeys ?? <String>[]) {
        json.remove(alias);
      }
    }
    SettingsRegistry.instance.loadFromJson(json);
    if (SX.dbEnabled.value && _settingsHandler.dbHandler.db == null) {
      await _settingsHandler.dbHandler.dbConnect(await ServiceHandler.getConfigDir());
    } else if (!SX.dbEnabled.value && _settingsHandler.dbHandler.db != null) {
      await _settingsHandler.dbHandler.closeDb();
    }
    final db = _settingsHandler.dbHandler.db;
    if (SX.dbEnabled.value &&
        db != null &&
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM BooruItem')) ?? 0) > 10000) {
      SX.indexesEnabled.state.loadFromJson(true);
      await _settingsHandler.dbHandler.createIndexes();
    }
    if (!await _settingsHandler.saveSettings(restate: true)) throw StateError('Could not save imported settings');
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
    await for (final entity in dir.list(followLinks: false)) {
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
    await ensureImportAllowed(BackupEntryId.booruProfiles, options);
    await validateEntry(BackupEntryId.booruProfiles, bytes: bytes);
    final decoded = jsonDecode(_text(bytes)) as List;
    final dir = await Directory('${await ServiceHandler.getConfigDir()}boorus').create(recursive: true);
    final existing = await _readBoorusFromFiles();
    final writes = <({File target, String data})>[];
    final used = existing.map((booru) => booru.name!.toLowerCase()).toSet();
    final incomingNames = decoded.map((raw) => ((raw as Map)['name'] as String).toLowerCase()).toSet();
    await for (final file in dir.list(followLinks: false)) {
      final name = file.path.replaceAll(r'\', '/').split('/').last;
      if (name.toLowerCase().endsWith('.json')) used.add(name.substring(0, name.length - 5).toLowerCase());
    }
    for (final raw in decoded) {
      final booru = Booru.fromMap(Map<String, dynamic>.from(raw as Map));
      final originalName = booru.name!;
      final match = existing.where((item) => item.name?.toLowerCase() == booru.name!.toLowerCase()).firstOrNull;
      if ((match != null && (match.baseURL != booru.baseURL || match.type != booru.type)) ||
          (match == null && used.contains(booru.name!.toLowerCase()))) {
        // Preserve both profiles when a filename represents another server.
        final original = booru.name!;
        var suffix = 2;
        while (used.contains(booru.name!.toLowerCase()) ||
            (booru.name != original && incomingNames.contains(booru.name!.toLowerCase()))) {
          booru.name = '$original ($suffix)';
          suffix++;
        }
      } else if (match != null) {
        // Same identity explicitly restores backed-up credentials and overrides.
        booru.name = match.name;
      }
      used.add(booru.name!.toLowerCase());
      if (booru.name != originalName) options.booruNameRemap?[originalName] = booru.name!;
      writes.add((target: File('${dir.path}/${booru.name}.json'), data: jsonEncode(booru.toJson())));
    }
    final stage = await dir.createTemp('.profile-import-');
    final originals = <File, List<int>?>{};
    try {
      for (var i = 0; i < writes.length; i++) {
        final entry = writes[i];
        originals[entry.target] = await entry.target.exists() ? await entry.target.readAsBytes() : null;
        final file = File('${stage.path}/$i.json');
        await file.writeAsString(entry.data, flush: true);
        await file.rename(entry.target.path);
      }
      await _settingsHandler.loadBoorus();
    } catch (_) {
      for (final entry in originals.entries) {
        if (entry.value == null) {
          if (await entry.key.exists()) await entry.key.delete();
        } else {
          await entry.key.writeAsBytes(entry.value!, flush: true);
        }
      }
      await _settingsHandler.loadBoorus();
      rethrow;
    } finally {
      await stage.delete(recursive: true);
    }
  }

  Future<BackupEntryPayload> _exportDatabase(BackupExportOptions options) async {
    final snapshot = await _exportDatabaseFile(options);
    try {
      if (await snapshot.length() > maximumJsonBytes) {
        throw const FormatException('Use file export for large databases');
      }
      return BackupEntryPayload(
        fileName: 'store.db',
        bytes: await snapshot.readAsBytes(),
        mimeType: 'application/x-sqlite3',
      );
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<File> _exportDatabaseFile(BackupExportOptions options) async {
    final snapshot = await _temporaryFile('db');
    // Startup backups must retain persisted tabs until the live session is ready.
    final currentTabs = _searchHandler.canBackup.value
        ? _searchHandler.generateBackupJson(includeDefaultTab: true)
        : null;
    try {
      await const DatabaseBackupService().createSnapshot(
        File('${await ServiceHandler.getConfigDir()}store.db'),
        snapshot,
        database: _settingsHandler.dbHandler.db,
      );
      if (currentTabs != null) {
        final db = await openDatabase(snapshot.path, singleInstance: false);
        try {
          await db.transaction((txn) async {
            await txn.delete('TabRestore');
            await txn.insert('TabRestore', {'restore': currentTabs});
          });
        } finally {
          await db.close();
        }
      }
      await const DatabaseBackupService().validate(snapshot);
      await _validateDatabaseTabs(snapshot);
      return snapshot;
    } catch (_) {
      if (await snapshot.exists()) await snapshot.delete();
      rethrow;
    }
  }

  Future<void> _importDatabase(Uint8List bytes, BackupImportOptions options) async {
    final staged = await _temporaryFile('db');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await _importDatabaseFile(staged, options);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  Future<void> _importDatabaseFile(File file, BackupImportOptions options) async {
    await ensureImportAllowed(BackupEntryId.database, options);
    const backup = DatabaseBackupService();
    await validateEntry(BackupEntryId.database, file: file);
    final config = await ServiceHandler.getConfigDir();
    final root = Directory(config);
    final staging = await root.createTemp('.database-import-');
    final recovery = await root.createTemp('.database-recovery-');
    final originalCanBackup = _searchHandler.canBackup.value;
    final originalEnabled = SX.dbEnabled.value;
    final originalIndexes = SX.indexesEnabled.value;
    var completed = false;
    var rollbackSucceeded = false;
    Future<void> reopen() async {
      await _settingsHandler.dbHandler.dbConnect(config);
      if (_settingsHandler.dbHandler.db == null) throw StateError('Could not reopen database');
      if (SX.indexesEnabled.value) await _settingsHandler.dbHandler.createIndexes();
    }

    try {
      final staged = await file.copy('${staging.path}/store.db');
      final count = await _countDatabaseItems(staged);
      _searchHandler.canBackup.value = false;
      await _settingsHandler.dbHandler.closeDb();
      if (count > 10000) SX.indexesEnabled.state.loadFromJson(true);
      SX.dbEnabled.state.loadFromJson(true);
      try {
        await backup.install(
          staged,
          File('${config}store.db'),
          recovery,
          reopen: reopen,
          close: _settingsHandler.dbHandler.closeDb,
        );
      } catch (_) {
        SX.dbEnabled.state.loadFromJson(originalEnabled);
        SX.indexesEnabled.state.loadFromJson(originalIndexes);
        // install restores the original bytes on failure; retain recovery if it could not.
        if (await recovery.list().isEmpty) {
          if (originalEnabled) await reopen();
          rollbackSucceeded = true;
        }
        rethrow;
      }
      if (!await _settingsHandler.saveSettings(restate: false)) {
        throw StateError('Could not save restored database settings');
      }
      final restoredTags = await _settingsHandler.dbHandler.getAllTags();
      _tagHandler.tagMap.clear();
      for (final tag in restoredTags) {
        await _tagHandler.putTag(tag, dbEnabled: true, useDB: false, preferTypeIfNone: false);
      }
      completed = true;
    } finally {
      _searchHandler.canBackup.value = originalCanBackup;
      await staging.delete(recursive: true);
      if (completed || rollbackSucceeded) await recovery.delete(recursive: true);
    }
  }

  Future<void> _validateDatabaseTabs(File file) async {
    final db = await openDatabase(file.path, readOnly: true, singleInstance: false);
    try {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'TabRestore'");
      if (tables.isEmpty) return; // Older databases gain this optional table when reopened.
      final rows = await db.query('TabRestore', columns: ['restore'], orderBy: 'id DESC', limit: 1);
      final text = rows.firstOrNull?['restore'];
      if (text == null) return;
      if (text is! String) throw const FormatException('Invalid saved database tabs');
      if (text.trim().isNotEmpty) TabBackup.parseImport(text);
    } finally {
      await db.close();
    }
  }

  Future<int> _countDatabaseItems(File file) async {
    final db = await openDatabase(file.path, readOnly: true, singleInstance: false);
    try {
      return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM BooruItem')) ?? 0;
    } finally {
      await db.close();
    }
  }

  Future<BackupEntryPayload> _exportFlaggedItems({
    required bool isDownloads,
    required BackupExportOptions options,
  }) async {
    final file = await _exportFlaggedFile(isDownloads: isDownloads, options: options);
    try {
      if (await file.length() > maximumJsonBytes) throw const FormatException('Use file export for large libraries');
      return BackupEntryPayload(
        fileName: isDownloads ? 'snatched.json' : 'favourites.json',
        bytes: await file.readAsBytes(),
        mimeType: 'application/json',
      );
    } finally {
      await file.delete();
    }
  }

  Future<File> _exportFlaggedFile({required bool isDownloads, required BackupExportOptions options}) async {
    if (options.startIndex < 0) throw const FormatException('Negative library start index');
    final file = await _temporaryFile('json');
    final output = await file.open(mode: FileMode.write);
    try {
      await output.writeString('[');
      final db = _settingsHandler.dbHandler;
      final start = await db.resolveFlaggedStartId(isDownloads: isDownloads, startIndex: options.startIndex);
      var first = true;
      if (start != null) {
        var cursor = start - 1;
        while (true) {
          final batch = await db.getFlaggedBackupItemsAfterId(isDownloads: isDownloads, lastSeenId: cursor, limit: 250);
          if (batch.isEmpty) break;
          for (final row in batch) {
            final json = row.item.toJson();
            json['tags'] = row.item.tagsList.map((tag) => tag.fullString).toList();
            if (!isDownloads) json['isSnatched'] = false;
            if (!first) await output.writeString(',');
            await output.writeString(jsonEncode(json));
            first = false;
          }
          cursor = batch.last.id;
        }
      }
      await output.writeString(']');
      await output.flush();
    } catch (_) {
      await output.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await output.close();
    return file;
  }

  Future<void> _importFlaggedBytes(BackupEntryId id, Uint8List bytes, BackupImportOptions options) async {
    final file = await _temporaryFile('json');
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _importFlaggedFile(id, file, options);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _importFlaggedFile(BackupEntryId id, File file, BackupImportOptions options) async {
    await ensureImportAllowed(id, options);
    var totalItems = 0;
    await validateEntry(
      id,
      file: file,
      phase: BackupImportPhase.rechecking,
      onProgress: (progress) {
        totalItems = progress.processedItems ?? 0;
        options.onProgress?.call(progress);
      },
    );
    final items = readBackupJsonArray(file.openRead()).map((row) {
      // Older exports serialized full Tag records; accept both representations.
      row['tags'] = (row['tags'] as List)
          .map((tag) => tag is Map ? Tag.fromJson(Map<String, dynamic>.from(tag)).fullString : tag)
          .toList();
      return BooruItem.fromMap(row);
    });
    options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.preparingDatabase, entryId: id));
    await _settingsHandler.dbHandler.importBooruItems(
      items,
      keepIndexes: SX.indexesEnabled.value,
      onProgress: (count) => options.onProgress?.call(
        BackupImportProgress(
          phase: BackupImportPhase.importing,
          entryId: id,
          processedItems: count,
          totalItems: totalItems,
        ),
      ),
      onCleanup: () => options.onProgress?.call(BackupImportProgress(phase: BackupImportPhase.cleaningUp, entryId: id)),
    );
  }

  Future<BackupEntryPayload> _exportTabs(BackupExportOptions options) async {
    final tabs = _searchHandler.generateBackupJson(includeDefaultTab: true) ?? '[]';
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
    await ensureImportAllowed(BackupEntryId.tabs, options);
    await validateEntry(BackupEntryId.tabs, bytes: bytes);
    var text = _text(bytes);
    final renames = options.booruNameRemap;
    if (renames != null && renames.isNotEmpty) {
      text = _remapTabs(text, renames);
    }
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
    final cachedTags = _tagHandler.toList();
    final tags = cachedTags.where((tag) => tag.fullString.trim().isNotEmpty).toList();
    BackupTransferLogger.info(
      'Exporting tags count=${tags.length} skippedBlank=${cachedTags.length - tags.length}',
      'BackupEntryRegistry',
      '_exportTags',
    );
    return _jsonPayload('tags.json', tags);
  }

  Future<void> _importTags(Uint8List bytes, BackupImportOptions options) async {
    await ensureImportAllowed(BackupEntryId.tags, options);
    await validateEntry(BackupEntryId.tags, bytes: bytes);
    BackupTransferLogger.info(
      'Importing tags bytes=${bytes.length} mode=${options.tagsMode.name}',
      'BackupEntryRegistry',
      '_importTags',
    );
    final rows = jsonDecode(_text(bytes)) as List;
    var skippedBlank = 0;
    for (final row in rows) {
      final tag = _tagFromBackupJson(Map<String, dynamic>.from(row as Map));
      if (tag == null) {
        skippedBlank++;
        continue;
      }
      await _tagHandler.putTag(
        tag,
        preferTypeIfNone: options.tagsMode == BackupTagsMode.preferTypeIfNone,
        dbEnabled: SX.dbEnabled.value,
      );
    }
    if (skippedBlank > 0) {
      BackupTransferLogger.info(
        'Skipped $skippedBlank blank tag records',
        'BackupEntryRegistry',
        '_importTags',
      );
    }
    if (!SX.dbEnabled.value) await _saveTagsWithoutDatabase();
  }

  Future<void> _saveTagsWithoutDatabase() async {
    final target = File('${await ServiceHandler.getConfigDir()}tags.json');
    final stage = await target.parent.createTemp('.tags-import-');
    try {
      final file = File('${stage.path}/tags.json');
      await file.writeAsString(jsonEncode(_tagHandler.toList()), flush: true);
      await file.rename(target.path);
    } finally {
      await stage.delete(recursive: true);
    }
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
    await ensureImportAllowed(BackupEntryId.pinnedTags, options);
    await validateEntry(BackupEntryId.pinnedTags, bytes: bytes);
    final decoded = jsonDecode(_text(bytes));
    if (decoded is! List) return;
    final rows = _mapsFromJsonList(decoded, options);
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
    await ensureImportAllowed(BackupEntryId.searchHistory, options);
    await validateEntry(BackupEntryId.searchHistory, bytes: bytes);
    final decoded = jsonDecode(_text(bytes));
    if (decoded is! List) return;
    final rows = _mapsFromJsonList(decoded, options);
    BackupTransferLogger.info(
      'Importing search history count=${rows.length}',
      'BackupEntryRegistry',
      '_importSearchHistory',
    );
    await _settingsHandler.dbHandler.importSearchHistoryRows(rows);
  }

  List<Map<String, dynamic>> _mapsFromJsonList(List<dynamic> decoded, BackupImportOptions options) {
    return decoded
        .cast<Map>()
        .map((raw) {
          final row = Map<String, dynamic>.from(raw);
          final renamed = options.booruNameRemap?[row['booruName']];
          if (renamed != null) row['booruName'] = renamed;
          return row;
        })
        .toList(growable: false);
  }

  BackupEntryPayload _jsonPayload(String fileName, Object? data) {
    return BackupEntryPayload(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(data))),
      mimeType: 'application/json',
    );
  }
}
