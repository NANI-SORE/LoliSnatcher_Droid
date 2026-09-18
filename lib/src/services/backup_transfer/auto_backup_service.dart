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
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';

class AutoBackupConfig {
  const AutoBackupConfig({
    required this.enabled,
    required this.location,
    required this.frequencyDays,
    required this.maximumBackups,
    required this.backupOnUpdate,
    this.lastBackupAt,
    this.lastUpdateBackupBuild,
    this.lastBackupError,
    this.lastUpdateBackupAttemptBuild,
    this.lastUpdateBackupAttemptAt,
    this.updateBackupAttemptCount = 0,
    this.lastUpdateBackupError,
  });

  final bool enabled;
  final String location;
  final int frequencyDays;
  final int maximumBackups;
  final bool backupOnUpdate;
  final DateTime? lastBackupAt;
  final int? lastUpdateBackupBuild;
  final String? lastBackupError;
  final int? lastUpdateBackupAttemptBuild;
  final DateTime? lastUpdateBackupAttemptAt;
  final int updateBackupAttemptCount;
  final String? lastUpdateBackupError;

  static const supportedFrequencyDays = [1, 7, 30];
  static const supportedMaximumBackups = [0, 3, 5, 10, 20];

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
      'lastBackupError': lastBackupError,
      'lastUpdateBackupAttemptBuild': lastUpdateBackupAttemptBuild,
      'lastUpdateBackupAttemptAt': lastUpdateBackupAttemptAt?.toIso8601String(),
      'updateBackupAttemptCount': updateBackupAttemptCount,
      'lastUpdateBackupError': lastUpdateBackupError,
    };
  }

  static AutoBackupConfig fromJson(Map<String, dynamic> json) {
    final frequency = int.tryParse(json['frequencyDays']?.toString() ?? '');
    final maximum = int.tryParse(json['maximumBackups']?.toString() ?? '');
    final attempts = int.tryParse(json['updateBackupAttemptCount']?.toString() ?? '') ?? 0;
    return AutoBackupConfig(
      enabled: json['enabled'] == true,
      location: json['location']?.toString() ?? '',
      frequencyDays: supportedFrequencyDays.contains(frequency) ? frequency! : defaults.frequencyDays,
      maximumBackups: supportedMaximumBackups.contains(maximum) ? maximum! : defaults.maximumBackups,
      backupOnUpdate: json['backupOnUpdate'] is bool ? json['backupOnUpdate'] as bool : defaults.backupOnUpdate,
      lastBackupAt: DateTime.tryParse(json['lastBackupAt']?.toString() ?? ''),
      lastUpdateBackupBuild: int.tryParse(json['lastUpdateBackupBuild']?.toString() ?? ''),
      lastBackupError: json['lastBackupError'] is String ? json['lastBackupError'] as String : null,
      lastUpdateBackupAttemptBuild: int.tryParse(json['lastUpdateBackupAttemptBuild']?.toString() ?? ''),
      lastUpdateBackupAttemptAt: DateTime.tryParse(json['lastUpdateBackupAttemptAt']?.toString() ?? ''),
      updateBackupAttemptCount: attempts.clamp(0, 1000000),
      lastUpdateBackupError: json['lastUpdateBackupError'] is String ? json['lastUpdateBackupError'] as String : null,
    );
  }

  AutoBackupConfig copyWith({
    bool? enabled,
    String? location,
    int? frequencyDays,
    int? maximumBackups,
    bool? backupOnUpdate,
    DateTime? lastBackupAt,
    bool clearLastBackupAt = false,
    int? lastUpdateBackupBuild,
    String? lastBackupError,
    bool clearLastBackupError = false,
    int? lastUpdateBackupAttemptBuild,
    DateTime? lastUpdateBackupAttemptAt,
    int? updateBackupAttemptCount,
    String? lastUpdateBackupError,
    bool clearLastUpdateBackupError = false,
  }) {
    return AutoBackupConfig(
      enabled: enabled ?? this.enabled,
      location: location ?? this.location,
      frequencyDays: frequencyDays ?? this.frequencyDays,
      maximumBackups: maximumBackups ?? this.maximumBackups,
      backupOnUpdate: backupOnUpdate ?? this.backupOnUpdate,
      lastBackupAt: clearLastBackupAt ? null : lastBackupAt ?? this.lastBackupAt,
      lastUpdateBackupBuild: lastUpdateBackupBuild ?? this.lastUpdateBackupBuild,
      lastBackupError: clearLastBackupError ? null : lastBackupError ?? this.lastBackupError,
      lastUpdateBackupAttemptBuild: lastUpdateBackupAttemptBuild ?? this.lastUpdateBackupAttemptBuild,
      lastUpdateBackupAttemptAt: lastUpdateBackupAttemptAt ?? this.lastUpdateBackupAttemptAt,
      updateBackupAttemptCount: updateBackupAttemptCount ?? this.updateBackupAttemptCount,
      lastUpdateBackupError: clearLastUpdateBackupError ? null : lastUpdateBackupError ?? this.lastUpdateBackupError,
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
  static const maximumAutomaticUpdateAttempts = 3;
  static const updateRetryDelay = Duration(hours: 6);

  // All entry points, including distinct settings-page/lifecycle service instances,
  // share these queues. Config updates remain possible during a long export.
  static Future<void> _runTail = Future<void>.value();
  static Future<void> _configTail = Future<void>.value();
  static int _configGeneration = 0;

  final BackupPackageService packageService;
  final BackupEntryRegistry registry;

  static Future<T> _withRunLock<T>(Future<T> Function() action) {
    final result = _runTail.then((_) => action());
    _runTail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  static Future<T> _withConfigLock<T>(Future<T> Function() action) {
    final result = _configTail.then((_) => action());
    _configTail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<AutoBackupConfig> loadConfig() => _withConfigLock(_readConfig);

  Future<AutoBackupConfig> _readConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return AutoBackupConfig.defaults;
    try {
      return AutoBackupConfig.fromJson(Map<String, dynamic>.from(jsonDecode(await file.readAsString())));
    } catch (_) {
      return AutoBackupConfig.defaults;
    }
  }

  /// Save user preferences without overwriting newer service-owned completion or
  /// failure metadata with a settings page's older snapshot.
  Future<void> saveConfig(AutoBackupConfig config) => _withConfigLock(() async {
    final latest = await _readConfig();
    final normalized = AutoBackupConfig.fromJson(config.toJson());
    await _writeConfig(
      latest.copyWith(
        enabled: normalized.enabled,
        location: normalized.location,
        clearLastBackupAt: latest.location != normalized.location,
        frequencyDays: normalized.frequencyDays,
        maximumBackups: normalized.maximumBackups,
        backupOnUpdate: normalized.backupOnUpdate,
      ),
    );
  });

  Future<void> _writeConfig(AutoBackupConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    final staging = await file.parent.createTemp('.auto-backup-config-');
    try {
      final temporary = File('${staging.path}${Platform.pathSeparator}auto_backup.json');
      await temporary.writeAsString(jsonEncode(config.toJson()), flush: true);
      await temporary.rename(file.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<void> resetConfig() => _withConfigLock(() async {
    _configGeneration++;
    final file = await _configFile();
    if (await file.exists()) {
      await file.delete();
    }
    BackupTransferLogger.info('Reset auto backup config', 'AutoBackupService', 'resetConfig');
  });

  Future<AutoBackupConfig> _updateStatus(
    int generation,
    AutoBackupConfig Function(AutoBackupConfig latest) update,
  ) => _withConfigLock(() async {
    final latest = await _readConfig();
    if (generation != _configGeneration) return latest;
    final updated = update(latest);
    await _writeConfig(updated);
    return updated;
  });

  Future<bool> runIfDue() => _withRunLock(() async {
    final config = await loadConfig();
    if (!config.isDue) return false;
    BackupTransferLogger.info(
      'Auto backup is due',
      'AutoBackupService',
      'runIfDue',
    );
    await _run(config, kind: _AutoBackupKind.normal);
    return true;
  });

  Future<void> runIfDueSafely() async {
    try {
      await runIfDue();
    } catch (error, stack) {
      BackupTransferLogger.error(error, 'AutoBackupService', 'lifecycle', stackTrace: stack);
    }
  }

  Future<AutoBackupConfig> runNow(AutoBackupConfig config) => _withRunLock(() async {
    // The caller's snapshot can be stale while another queued operation runs.
    final latest = await loadConfig();
    return _run(latest, kind: _AutoBackupKind.normal);
  });

  Future<bool> runAfterUpdateIfDue(AsyncCallback? beforeStart) =>
      _withRunLock(() => _runAfterUpdate(beforeStart, forceRetry: false));

  /// Explicit user retry bypasses the automatic retry limit and update toggle.
  Future<bool> retryAfterUpdateBackup([AsyncCallback? beforeStart]) =>
      _withRunLock(() => _runAfterUpdate(beforeStart, forceRetry: true));

  Future<bool> _runAfterUpdate(AsyncCallback? beforeStart, {required bool forceRetry}) async {
    final config = await loadConfig();
    if (!forceRetry && !config.backupOnUpdate) return false;
    final currentBuild = Constants.updateInfo.buildNumber;
    if (!forceRetry && config.lastUpdateBackupBuild == currentBuild) return false;
    final sameBuild = config.lastUpdateBackupAttemptBuild == currentBuild;
    final attempts = sameBuild ? config.updateBackupAttemptCount : 0;
    final lastAttempt = sameBuild ? config.lastUpdateBackupAttemptAt : null;
    if (!forceRetry &&
        (attempts >= maximumAutomaticUpdateAttempts ||
            (lastAttempt != null && DateTime.now().difference(lastAttempt) < updateRetryDelay))) {
      return false;
    }
    await beforeStart?.call();
    await _updateStatus(
      _configGeneration,
      (latest) => latest.copyWith(
        lastUpdateBackupAttemptBuild: currentBuild,
        lastUpdateBackupAttemptAt: DateTime.now(),
        updateBackupAttemptCount: attempts + 1,
        clearLastUpdateBackupError: true,
      ),
    );
    await _run(await loadConfig(), kind: _AutoBackupKind.update);
    return true;
  }

  Future<AutoBackupConfig> _run(AutoBackupConfig config, {required _AutoBackupKind kind}) async {
    final generation = _configGeneration;
    try {
      await _createBackup(config, kind: kind);
      return await _updateStatus(
        generation,
        (latest) => switch (kind) {
          _AutoBackupKind.normal =>
            latest.location == config.location
                ? latest.copyWith(lastBackupAt: DateTime.now(), clearLastBackupError: true)
                : latest,
          _AutoBackupKind.update => latest.copyWith(
            lastUpdateBackupBuild: Constants.updateInfo.buildNumber,
            clearLastUpdateBackupError: true,
          ),
        },
      );
    } catch (error, stack) {
      try {
        await _updateStatus(
          generation,
          (latest) => switch (kind) {
            _AutoBackupKind.normal =>
              latest.location == config.location ? latest.copyWith(lastBackupError: error.toString()) : latest,
            _AutoBackupKind.update => latest.copyWith(lastUpdateBackupError: error.toString()),
          },
        );
      } catch (statusError, statusStack) {
        BackupTransferLogger.error(statusError, 'AutoBackupService', 'saveFailureStatus', stackTrace: statusStack);
      }
      BackupTransferLogger.error(error, 'AutoBackupService', '_run', stackTrace: stack);
      rethrow;
    }
  }

  Future<void> _createBackup(AutoBackupConfig config, {required _AutoBackupKind kind}) async {
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
    BackupTransferLogger.info(
      'Starting ${kind.name} auto backup: file=$fileName location=${config.location.isEmpty ? '<default>' : config.location}',
      'AutoBackupService',
      '_run',
    );
    if (hasConfiguredLocation && config.location.startsWith('content://')) {
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
          BackupFileNaming.mimeType,
        );
        if (!copied) throw FileSystemException('Failed to save backup package', config.location);
      } finally {
        unawaited(tempDir.delete(recursive: true).catchError((_) => tempDir));
      }
      await _pruneSaf(
        config.location,
        kind == _AutoBackupKind.update ? _maximumUpdateBackups : config.maximumBackups,
        kind: kind,
      );
      BackupTransferLogger.info(
        'Finished ${kind.name} auto backup to SAF location',
        'AutoBackupService',
        '_run',
      );
      return;
    }

    final dir = hasConfiguredLocation ? Directory(config.location) : await _defaultUpdateBackupDir();
    await dir.create(recursive: true);
    await packageService.exportPackageFile(
      entryIds: registry.fullBackupEntries.map((entry) => entry.id).toList(),
      outputFile: File('${dir.path}${Platform.pathSeparator}$fileName'),
    );
    await _prune(dir, kind == _AutoBackupKind.normal ? config.maximumBackups : _maximumUpdateBackups, kind: kind);
    BackupTransferLogger.info(
      'Finished ${kind.name} auto backup to ${dir.path}',
      'AutoBackupService',
      '_run',
    );
  }

  Future<Directory> _defaultUpdateBackupDir() async {
    final downloadsDir = await ServiceHandler.getDownloadsDir();
    if (downloadsDir.isNotEmpty) {
      return Directory('$downloadsDir${Platform.pathSeparator}LoliSnatcher');
    }
    return Directory('${await ServiceHandler.getConfigDir()}update_backups');
  }

  Future<void> _prune(Directory dir, int maximumBackups, {required _AutoBackupKind kind}) async {
    if (maximumBackups <= 0) return;
    final backups = await dir
        .list()
        .where(
          (entity) =>
              entity is File &&
              BackupFileNaming.autoBackupTime(entity.path, isUpdate: kind == _AutoBackupKind.update) != null,
        )
        .cast<File>()
        .toList();
    backups.sort(
      (a, b) => BackupFileNaming.autoBackupTime(
        b.path,
        isUpdate: kind == _AutoBackupKind.update,
      )!.compareTo(BackupFileNaming.autoBackupTime(a.path, isUpdate: kind == _AutoBackupKind.update)!),
    );
    final staleBackups = backups.skip(maximumBackups).toList();
    BackupTransferLogger.info(
      'Pruning ${staleBackups.length} normal auto backups from ${dir.path}',
      'AutoBackupService',
      '_prune',
    );
    for (final stale in staleBackups) {
      await stale.delete();
    }
  }

  Future<void> _pruneSaf(String safUri, int maximumBackups, {required _AutoBackupKind kind}) async {
    if (maximumBackups <= 0) return;
    final names = await ServiceHandler.listFileNamesFromSAFDirectory(safUri);
    final isUpdate = kind == _AutoBackupKind.update;
    final backups = names.where((name) => BackupFileNaming.autoBackupTime(name, isUpdate: isUpdate) != null).toList()
      ..sort(
        (a, b) => BackupFileNaming.autoBackupTime(
          b,
          isUpdate: isUpdate,
        )!.compareTo(BackupFileNaming.autoBackupTime(a, isUpdate: isUpdate)!),
      );
    final staleBackups = backups.skip(maximumBackups).toList();
    BackupTransferLogger.info(
      'Pruning ${staleBackups.length} update backups from SAF location',
      'AutoBackupService',
      '_pruneSafUpdateBackups',
    );
    for (final stale in staleBackups) {
      if (!await ServiceHandler.deleteFileFromSAFDirectory(safUri, stale)) {
        throw FileSystemException('Failed to remove expired automatic backup', stale);
      }
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
