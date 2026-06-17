import 'dart:async';
import 'dart:io';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_import_compat_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_protocol.dart';

class TransferSocketClient {
  TransferSocketClient({
    BackupImportCompatService? importService,
    TransferHistoryService? historyService,
  }) : importService = importService ?? BackupImportCompatService(),
       historyService = historyService ?? const TransferHistoryService();

  final BackupImportCompatService importService;
  final TransferHistoryService historyService;
  final logs = StreamController<BackupTransferLog>.broadcast();
  final stats = StreamController<BackupTransferStats>.broadcast();

  Socket? _socket;
  bool _cancelled = false;

  Future<void> receive({
    required String host,
    required int port,
    required List<BackupEntryId> entries,
    required String receiverName,
    required String senderName,
    required String senderAddress,
    Map<String, Object?> transferOptions = const {},
    BackupImportOptions options = const BackupImportOptions(),
  }) async {
    _cancelled = false;
    final startedAt = DateTime.now();
    TransferSocketConnection? connection;
    var lastBytesTransferred = 0;
    int? totalBytes;
    try {
      BackupTransferLogger.info(
        'Connecting to sender $host:$port entries=${entries.map((entry) => entry.name).join(',')} options=$transferOptions',
        'TransferSocketClient',
        'receive',
      );
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      final activeConnection = TransferSocketConnection(_socket!);
      connection = activeConnection;
      final hello = await activeConnection.readFrame();
      if (hello['type'] != 'hello') throw FormatException(loc.settings.backupAndTransfer.invalidSenderHello);
      _log(
        loc.settings.backupAndTransfer.connectedTo(
          device: hello['deviceName']?.toString() ?? host,
        ),
      );
      BackupTransferLogger.info(
        'Received hello $hello',
        'TransferSocketClient',
        'receive',
      );
      await activeConnection.writeFrame({
        'type': 'selectEntries',
        'entries': entries.map((entry) => entry.name).toList(),
        'receiverName': receiverName,
        'options': transferOptions,
      });

      while (!_cancelled) {
        final frame = await activeConnection.readFrame();
        switch (frame['type']) {
          case 'entryStart':
            final size = frame['size'] as int;
            totalBytes = size;
            _log(
              loc.settings.backupAndTransfer.receivingEntry(
                entry: frame['entry']?.toString() ?? '',
                size: TransferFormatters.bytes(size),
              ),
            );
            final cacheDir = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
            await cacheDir.create(recursive: true);
            final packageFile = File(
              '${cacheDir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-${BackupFileNaming.transferPackageFileName}',
            );
            BackupTransferLogger.info(
              'Receiving package entry=${frame['entry']} bytes=$size path=${packageFile.path}',
              'TransferSocketClient',
              'receive',
            );
            await activeConnection.readBytesToFile(
              size,
              packageFile,
              (read) {
                lastBytesTransferred = read;
                stats.add(
                  BackupTransferStats(
                    bytesTransferred: read,
                    totalBytes: size,
                    startedAt: startedAt,
                    currentEntry: frame['entry']?.toString(),
                  ),
                );
              },
              isCancelled: () => _cancelled,
            );
            if (_cancelled) {
              BackupTransferLogger.info(
                'Receive cancelled, deleting partial package ${packageFile.path}',
                'TransferSocketClient',
                'receive',
              );
              unawaited(packageFile.delete().catchError((_) => packageFile));
              return;
            }
            await historyService.add(
              TransferHistoryEntry(
                direction: TransferHistoryDirection.received,
                peerName: senderName,
                peerAddress: senderAddress,
                entryIds: entries,
                createdAt: DateTime.now(),
              ),
            );
            await importService.importNamedFile(
              BackupFileNaming.transferPackageFileName,
              packageFile,
              options: options,
            );
            BackupTransferLogger.info(
              'Imported received package ${packageFile.path}',
              'TransferSocketClient',
              'receive',
            );
            unawaited(packageFile.delete().catchError((_) => packageFile));
            _log(loc.settings.backupAndTransfer.importedReceivedPackage);
            break;
          case 'complete':
            stats.add(
              BackupTransferStats(
                bytesTransferred: lastBytesTransferred,
                totalBytes: totalBytes,
                startedAt: startedAt,
                isComplete: true,
              ),
            );
            _log(loc.settings.backupAndTransfer.transferComplete);
            BackupTransferLogger.info(
              'Receive complete bytes=$lastBytesTransferred total=$totalBytes',
              'TransferSocketClient',
              'receive',
            );
            return;
          case 'error':
            throw StateError(frame['message']?.toString() ?? loc.settings.backupAndTransfer.senderError);
          default:
            _log(loc.settings.backupAndTransfer.ignoredFrame(frame: frame['type']?.toString() ?? ''));
            break;
        }
      }
    } catch (e) {
      final wasCancelled = _cancelled;
      final message = loc.settings.backupAndTransfer.transferFailed(error: e.toString());
      if (!wasCancelled) {
        _log(message);
        BackupTransferLogger.error(e, 'TransferSocketClient', 'receive');
      } else {
        BackupTransferLogger.info('Receive cancelled', 'TransferSocketClient', 'receive');
      }
      stats.add(
        BackupTransferStats(
          bytesTransferred: lastBytesTransferred,
          totalBytes: totalBytes,
          startedAt: startedAt,
          currentEntry: 'error',
          isComplete: true,
        ),
      );
      try {
        await connection
            ?.writeFrame({
              'type': 'error',
              'message': wasCancelled ? loc.settings.backupAndTransfer.transferCancelled : message,
            })
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
    } finally {
      await _socket?.close();
      _socket = null;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    BackupTransferLogger.info('Cancelling receiver socket', 'TransferSocketClient', 'cancel');
    _socket?.destroy();
    _socket = null;
    _log(loc.settings.backupAndTransfer.transferCancelled);
  }

  Future<void> dispose() async {
    await cancel();
    await logs.close();
    await stats.close();
  }

  void _log(String message) {
    logs.add(BackupTransferLog(message));
    BackupTransferLogger.info(
      message,
      'TransferSocketClient',
      '_log',
    );
  }
}
