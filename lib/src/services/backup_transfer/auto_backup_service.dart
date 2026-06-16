import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';

class AutoBackupConfig {
  const AutoBackupConfig({
    required this.enabled,
    required this.location,
    required this.frequencyDays,
    required this.maximumBackups,
    required this.backupOnUpdate,
    this.lastBackupAt,
    this.lastUpdateBackupBuild,
  });

  final bool enabled;
  final String location;
  final int frequencyDays;
  final int maximumBackups;
  final bool backupOnUpdate;
  final DateTime? lastBackupAt;
  final int? lastUpdateBackupBuild;

  static const defaults = AutoBackupConfig(
    enabled: false,
    location: '',
    frequencyDays: 7,
    maximumBackups: 5,
    backupOnUpdate: true,
  );

  bool get isDue {
    if (!enabled || location.isEmpty) return false;
    if (lastBackupAt == null) return true;
    return DateTime.now().difference(lastBackupAt!).inDays >= frequencyDays;
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'location': location,
      'frequencyDays': frequencyDays,
      'maximumBackups': maximumBackups,
      'backupOnUpdate': backupOnUpdate,
      'lastBackupAt': lastBackupAt?.toIso8601String(),
      'lastUpdateBackupBuild': lastUpdateBackupBuild,
    };
  }

  static AutoBackupConfig fromJson(Map<String, dynamic> json) {
    return AutoBackupConfig(
      enabled: json['enabled'] == true,
      location: json['location']?.toString() ?? '',
      frequencyDays: int.tryParse(json['frequencyDays']?.toString() ?? '') ?? defaults.frequencyDays,
      maximumBackups: int.tryParse(json['maximumBackups']?.toString() ?? '') ?? defaults.maximumBackups,
      backupOnUpdate: json['backupOnUpdate'] == true,
      lastBackupAt: DateTime.tryParse(json['lastBackupAt']?.toString() ?? ''),
      lastUpdateBackupBuild: int.tryParse(json['lastUpdateBackupBuild']?.toString() ?? ''),
    );
  }

  AutoBackupConfig copyWith({
    bool? enabled,
    String? location,
    int? frequencyDays,
    int? maximumBackups,
    bool? backupOnUpdate,
    DateTime? lastBackupAt,
    int? lastUpdateBackupBuild,
  }) {
    return AutoBackupConfig(
      enabled: enabled ?? this.enabled,
      location: location ?? this.location,
      frequencyDays: frequencyDays ?? this.frequencyDays,
      maximumBackups: maximumBackups ?? this.maximumBackups,
      backupOnUpdate: backupOnUpdate ?? this.backupOnUpdate,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastUpdateBackupBuild: lastUpdateBackupBuild ?? this.lastUpdateBackupBuild,
    );
  }
}

class AutoBackupService {
  AutoBackupService({
    BackupPackageService? packageService,
    BackupEntryRegistry? registry,
  }) : packageService = packageService ?? BackupPackageService(),
       registry = registry ?? BackupEntryRegistry.instance;

  static const _maximumUpdateBackups = 5;

  final BackupPackageService packageService;
  final BackupEntryRegistry registry;

  Future<AutoBackupConfig> loadConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return AutoBackupConfig.defaults;
    try {
      return AutoBackupConfig.fromJson(Map<String, dynamic>.from(jsonDecode(await file.readAsString())));
    } catch (_) {
      return AutoBackupConfig.defaults;
    }
  }

  Future<void> saveConfig(AutoBackupConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  Future<bool> runIfDue() async {
    final config = await loadConfig();
    if (!config.isDue) return false;
    await runNow(config);
    return true;
  }

  Future<AutoBackupConfig> runNow(AutoBackupConfig config) async {
    return _run(config, kind: _AutoBackupKind.normal);
  }

  Future<bool> runAfterUpdateIfDue(VoidCallback beforeStart) async {
    beforeStart();
    final config = await loadConfig();
    if (!config.backupOnUpdate) return false;
    final currentBuild = Constants.updateInfo.buildNumber;
    if (config.lastUpdateBackupBuild == currentBuild) return false;
    await _run(config, kind: _AutoBackupKind.update);
    return true;
  }

  Future<AutoBackupConfig> _run(AutoBackupConfig config, {required _AutoBackupKind kind}) async {
    if (kind == _AutoBackupKind.normal && config.location.isEmpty) {
      throw StateError(loc.settings.backupAndTransfer.autoBackupLocationEmpty);
    }
    final hasConfiguredLocation = config.location.isNotEmpty;
    final now = DateTime.now();
    final fileStem = switch (kind) {
      _AutoBackupKind.normal => BackupFileNaming.autoFileStem(now),
      _AutoBackupKind.update => BackupFileNaming.updateAutoFileStem(
        time: now,
        versionName: Constants.updateInfo.versionName,
        buildNumber: Constants.updateInfo.buildNumber,
      ),
    };
    final fileName = '$fileStem.${BackupFileNaming.extension}';
    if (hasConfiguredLocation && (Platform.isAndroid || config.location.startsWith('content://'))) {
      final tempDir = Directory(
        '${await ServiceHandler.getCacheDir()}backup_transfer${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempDir.create(recursive: true);
      final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
      try {
        await packageService.exportPackageFile(
          entryIds: registry.fullBackupEntries.map((entry) => entry.id).toList(),
          outputFile: tempFile,
        );
        final copied = await ServiceHandler.copyFileToSafDir(
          tempFile.parent.path,
          fileName,
          config.location,
          'application/zip',
        );
        if (!copied) throw FileSystemException('Failed to save backup package', config.location);
      } finally {
        unawaited(tempDir.delete(recursive: true).catchError((_) => tempDir));
      }
      if (kind == _AutoBackupKind.update) {
        await _pruneSafUpdateBackups(config.location, _maximumUpdateBackups);
      }
      final updated = _markComplete(config, kind, now);
      await saveConfig(updated);
      return updated;
    }

    final dir = hasConfiguredLocation ? Directory(config.location) : await _defaultUpdateBackupDir();
    await dir.create(recursive: true);
    await packageService.exportPackageFile(
      entryIds: registry.fullBackupEntries.map((entry) => entry.id).toList(),
      outputFile: File('${dir.path}${Platform.pathSeparator}$fileName'),
    );
    if (kind == _AutoBackupKind.normal) {
      await _prune(dir, config.maximumBackups);
    } else {
      await _pruneUpdateBackups(dir, _maximumUpdateBackups);
    }
    final updated = _markComplete(config, kind, now);
    await saveConfig(updated);
    return updated;
  }

  Future<Directory> _defaultUpdateBackupDir() async {
    final downloadsDir = await ServiceHandler.getDownloadsDir();
    if (downloadsDir.isNotEmpty) {
      return Directory('$downloadsDir${Platform.pathSeparator}LoliSnatcher');
    }
    return Directory('${await ServiceHandler.getConfigDir()}update_backups');
  }

  AutoBackupConfig _markComplete(AutoBackupConfig config, _AutoBackupKind kind, DateTime now) {
    return switch (kind) {
      _AutoBackupKind.normal => config.copyWith(lastBackupAt: now),
      _AutoBackupKind.update => config.copyWith(lastUpdateBackupBuild: Constants.updateInfo.buildNumber),
    };
  }

  Future<void> _prune(Directory dir, int maximumBackups) async {
    if (maximumBackups <= 0) return;
    final backups = await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              entity.path.toLowerCase().endsWith('.${BackupFileNaming.extension}') &&
              !BackupFileNaming.isUpdateAutoBackupPath(entity.path),
        )
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final stale in backups.skip(maximumBackups)) {
      await stale.delete();
    }
  }

  Future<void> _pruneUpdateBackups(Directory dir, int maximumBackups) async {
    if (maximumBackups <= 0) return;
    final backups = await dir
        .list()
        .where(
          (entity) => entity is File && BackupFileNaming.isUpdateAutoBackupPath(entity.path),
        )
        .cast<File>()
        .toList();
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final stale in backups.skip(maximumBackups)) {
      await stale.delete();
    }
  }

  Future<void> _pruneSafUpdateBackups(String safUri, int maximumBackups) async {
    if (maximumBackups <= 0) return;
    final names = await ServiceHandler.listFileNamesFromSAFDirectory(safUri);
    final backups = names.where(BackupFileNaming.isUpdateAutoBackupPath).toList()..sort((a, b) => b.compareTo(a));
    for (final stale in backups.skip(maximumBackups)) {
      await ServiceHandler.deleteFileFromSAFDirectory(safUri, stale);
    }
  }

  Future<File> _configFile() async {
    return File('${await ServiceHandler.getConfigDir()}auto_backup.json');
  }
}

enum _AutoBackupKind {
  normal,
  update,
}
