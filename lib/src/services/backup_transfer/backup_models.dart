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
  });

  final BackupTabsMode tabsMode;
  final BackupTagsMode tagsMode;
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
  });

  final int bytesTransferred;
  final int? totalBytes;
  final DateTime startedAt;
  final String? currentEntry;
  final bool isComplete;

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
  }) {
    return BackupTransferStats(
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      startedAt: startedAt ?? this.startedAt,
      currentEntry: currentEntry ?? this.currentEntry,
      isComplete: isComplete ?? this.isComplete,
    );
  }
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
