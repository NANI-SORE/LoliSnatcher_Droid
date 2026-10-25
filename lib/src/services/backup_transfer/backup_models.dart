import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum BackupEntryId {
  settings,
  booruProfiles,
  database,
  favourites,
  snatched,
  tabs,
  tags,
  pinnedTags,
  searchHistory,
  blacklistedTags,
  bookmarks,
  bulkDownloads,
}

enum BackupEntrySource {
  file,
  clipboard,
  transfer,
}

typedef BackupPreview = ({List<BackupEntryId> entries, DateTime? createdAt});

class BackupEntryPayload {
  const BackupEntryPayload({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
    this.metadata = const {},
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  final Map<String, dynamic> metadata;
}

class BackupEntryDefinition {
  const BackupEntryDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.fileName,
    required this.icon,
    required this.supportsClipboard,
    required this.isAvailable,
    required this.exportEntry,
    required this.importEntry,
    this.exportFile,
    this.importFile,
    this.exportFileIsTemporary = false,
    this.isImportAvailable,
  });

  final BackupEntryId id;
  final String Function() title;
  final String Function() description;
  final String fileName;
  final IconData icon;
  final bool supportsClipboard;
  final Future<bool> Function() isAvailable;
  final Future<BackupEntryPayload> Function(BackupExportOptions options) exportEntry;
  final Future<void> Function(Uint8List bytes, BackupImportOptions options) importEntry;
  final Future<File> Function(BackupExportOptions options)? exportFile;
  final Future<void> Function(File file, BackupImportOptions options)? importFile;
  final bool exportFileIsTemporary;
  final Future<bool> Function()? isImportAvailable;

  Future<bool> canImport() async => await isImportAvailable?.call() ?? true;
}

class BackupExportOptions {
  const BackupExportOptions({
    this.excludeDeviceSpecificSettings = false,
    this.startIndex = 0,
  });

  final bool excludeDeviceSpecificSettings;
  final int startIndex;
}

class BackupImportOptions {
  const BackupImportOptions({
    this.tabsMode = BackupTabsMode.merge,
    this.tagsMode = BackupTagsMode.preferTypeIfNone,
    this.allowedEntryIds,
    this.rejectUnexpectedEntries = true,
    this.booruNameRemap,
    this.onProgress,
  });

  final BackupTabsMode tabsMode;
  final BackupTagsMode tagsMode;
  final Set<BackupEntryId>? allowedEntryIds;
  final bool rejectUnexpectedEntries;

  /// Import-local profile renames shared by dependent categories in one package.
  final Map<String, String>? booruNameRemap;

  final ValueChanged<BackupImportProgress>? onProgress;

  BackupImportOptions withProgress(ValueChanged<BackupImportProgress> callback) => BackupImportOptions(
    tabsMode: tabsMode,
    tagsMode: tagsMode,
    allowedEntryIds: allowedEntryIds,
    rejectUnexpectedEntries: rejectUnexpectedEntries,
    booruNameRemap: booruNameRemap,
    onProgress: callback,
  );
}

enum BackupImportPhase {
  extracting,
  verifying,
  validating,
  rechecking,
  preparingDatabase,
  importing,
  cleaningUp,
  refreshing,
  snapshotting,
  rollingBack,
}

class BackupImportProgress {
  const BackupImportProgress({required this.phase, this.entryId, this.processedItems, this.totalItems});

  final BackupImportPhase phase;
  final BackupEntryId? entryId;
  final int? processedItems;
  final int? totalItems;
}

class BackupRestoreFailure implements Exception {
  const BackupRestoreFailure(this.cause);
  final Object cause;

  @override
  String toString() => cause.toString();
}

enum BackupTabsMode {
  merge,
  replace,
}

enum BackupTagsMode {
  overwrite,
  preferTypeIfNone,
}

class BackupTransferLog {
  BackupTransferLog(this.message) : createdAt = DateTime.now();

  final String message;
  final DateTime createdAt;
}

class BackupTransferStats {
  const BackupTransferStats({
    required this.bytesTransferred,
    required this.startedAt,
    this.totalBytes,
    this.currentEntry,
    this.isComplete = false,
    this.importProgress,
    this.importProgressUpdatedAt,
    this.stage = BackupTransferStage.preparing,
    this.outcome,
    this.message,
    this.details,
    this.peerName,
    this.entryIds = const [],
  });

  final int bytesTransferred;
  final int? totalBytes;
  final DateTime startedAt;
  final String? currentEntry;
  final bool isComplete;
  final BackupImportProgress? importProgress;
  final DateTime? importProgressUpdatedAt;
  final BackupTransferStage stage;
  final BackupTransferOutcome? outcome;
  final String? message;
  final String? details;
  final String? peerName;
  final List<BackupEntryId> entryIds;

  double get bytesPerSecond {
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) return 0;
    return bytesTransferred / (elapsedMs / 1000);
  }

  BackupTransferStats copyWith({
    int? bytesTransferred,
    int? totalBytes,
    DateTime? startedAt,
    String? currentEntry,
    bool? isComplete,
    BackupImportProgress? importProgress,
    DateTime? importProgressUpdatedAt,
    BackupTransferStage? stage,
    BackupTransferOutcome? outcome,
    String? message,
    String? details,
    String? peerName,
    List<BackupEntryId>? entryIds,
  }) {
    return BackupTransferStats(
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      startedAt: startedAt ?? this.startedAt,
      currentEntry: currentEntry ?? this.currentEntry,
      isComplete: isComplete ?? this.isComplete,
      importProgress: importProgress ?? this.importProgress,
      importProgressUpdatedAt: importProgressUpdatedAt ?? this.importProgressUpdatedAt,
      stage: stage ?? this.stage,
      outcome: outcome ?? this.outcome,
      message: message ?? this.message,
      details: details ?? this.details,
      peerName: peerName ?? this.peerName,
      entryIds: entryIds ?? this.entryIds,
    );
  }
}

enum BackupTransferStage {
  connecting,
  selecting,
  approval,
  preparing,
  transferring,
  verifying,
  importing,
  awaitingImport,
}

enum BackupTransferOutcome { success, restoredNotNotified, unconfirmed, failed, cancelled }

class TransferReceiveSelection {
  const TransferReceiveSelection({
    required this.entries,
    this.transferOptions = const {},
    this.importOptions = const BackupImportOptions(),
  });

  final List<BackupEntryId> entries;
  final Map<String, Object?> transferOptions;
  final BackupImportOptions importOptions;
}

class DiscoveredTransferDevice {
  const DiscoveredTransferDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.version,
    required this.build,
    this.deviceId,
    this.isManual = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String version;
  final String? build;
  final String? deviceId;
  final bool isManual;

  String get address => '$host:$port';
}
