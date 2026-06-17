import 'dart:convert';
import 'dart:io';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';

enum TransferHistoryDirection {
  sent,
  received,
}

class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.direction,
    required this.peerName,
    required this.peerAddress,
    required this.entryIds,
    required this.createdAt,
  });

  final TransferHistoryDirection direction;
  final String peerName;
  final String peerAddress;
  final List<BackupEntryId> entryIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'direction': direction.name,
      'peerName': peerName,
      'peerAddress': peerAddress,
      'entryIds': entryIds.map((entry) => entry.name).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static TransferHistoryEntry? fromJson(Map<String, dynamic> json) {
    final direction = TransferHistoryDirection.values.where((value) => value.name == json['direction']).firstOrNull;
    final rawEntryIds = json['entryIds'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (direction == null || rawEntryIds is! List || createdAt == null) return null;
    return TransferHistoryEntry(
      direction: direction,
      peerName: json['peerName']?.toString() ?? '',
      peerAddress: json['peerAddress']?.toString() ?? '',
      entryIds: rawEntryIds
          .map(
            (raw) => BackupEntryId.values.where((entry) => entry.name == raw).firstOrNull,
          )
          .whereType<BackupEntryId>()
          .toList(growable: false),
      createdAt: createdAt,
    );
  }
}

class TransferHistoryService {
  const TransferHistoryService();

  Future<List<TransferHistoryEntry>> load() async {
    final file = await _file();
    if (!await file.exists()) {
      BackupTransferLogger.info(
        'Transfer history file does not exist',
        'TransferHistoryService',
        'load',
      );
      return [];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final entries = decoded
          .whereType<Map>()
          .map((raw) => TransferHistoryEntry.fromJson(Map<String, dynamic>.from(raw)))
          .whereType<TransferHistoryEntry>()
          .toList(growable: false);
      BackupTransferLogger.info(
        'Loaded ${entries.length} transfer history entries',
        'TransferHistoryService',
        'load',
      );
      return entries;
    } catch (e, s) {
      BackupTransferLogger.error(
        e,
        'TransferHistoryService',
        'load',
        stackTrace: s,
      );
      return [];
    }
  }

  Future<void> add(TransferHistoryEntry entry) async {
    BackupTransferLogger.info(
      'Adding transfer history direction=${entry.direction.name} peer=${entry.peerAddress} entries=${entry.entryIds.map((id) => id.name).join(',')}',
      'TransferHistoryService',
      'add',
    );
    final entries = [
      entry,
      ...await load(),
    ].take(50).toList(growable: false);
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(entries.map((item) => item.toJson()).toList()));
  }

  Future<File> _file() async {
    return File('${await ServiceHandler.getConfigDir()}backup_transfer_history.json');
  }
}
