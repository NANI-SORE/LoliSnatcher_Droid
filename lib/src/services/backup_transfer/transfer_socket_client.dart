import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_import_compat_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';
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
  _ReceiveSession? _active;
  bool _disposed = false;
  Future<void>? _disposing;

  bool get importing => _active?.importing == true;

  Future<void> receive({
    required String host,
    required int port,
    required List<BackupEntryId> entries,
    required String receiverName,
    required String senderName,
    required String senderAddress,
    Map<String, Object?> transferOptions = const {},
    BackupImportOptions options = const BackupImportOptions(),
  }) {
    if (_disposed || _active != null) {
      return Future.error(StateError(loc.settings.backupAndTransfer.transferBusy));
    }
    if (host.isEmpty || port < 1 || port > 65535 || entries.isEmpty) {
      return Future.error(FormatException(loc.settings.backupAndTransfer.invalidTransferData));
    }
    final session = _ReceiveSession();
    _active = session;
    return session.done =
        _receive(
          session,
          host: host,
          port: port,
          entries: List.unmodifiable(entries.toSet()),
          receiverName: receiverName,
          senderName: senderName,
          senderAddress: senderAddress,
          transferOptions: Map.unmodifiable(transferOptions),
          options: options,
        ).whenComplete(() {
          if (identical(_active, session)) _active = null;
        });
  }

  Future<void> _receive(
    _ReceiveSession session, {
    required String host,
    required int port,
    required List<BackupEntryId> entries,
    required String receiverName,
    required String senderName,
    required String senderAddress,
    required Map<String, Object?> transferOptions,
    required BackupImportOptions options,
  }) async {
    final startedAt = DateTime.now();
    final requestId = const Uuid().v4();
    File? packageFile;
    Directory? packageDirectory;
    var transferred = 0;
    int? total;
    BackupImportProgress? importProgress;
    DateTime? importProgressUpdatedAt;
    Timer? importHeartbeat;
    final importLogTimer = Stopwatch();
    final importUiTimer = Stopwatch();
    void emit({String? entry, bool complete = false}) {
      if (!stats.isClosed) {
        stats.add(
          BackupTransferStats(
            bytesTransferred: transferred,
            totalBytes: total,
            startedAt: startedAt,
            currentEntry: entry,
            isComplete: complete,
            importProgress: importProgress,
            importProgressUpdatedAt: importProgressUpdatedAt,
          ),
        );
      }
    }

    try {
      final connect = await Socket.startConnect(host, port);
      session.connect = connect;
      if (session.cancelled) connect.cancel();
      final socket = await connect.socket.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          connect.cancel();
          throw TimeoutException(loc.settings.backupAndTransfer.transferCancelled);
        },
      );
      session.connection = TransferSocketConnection(socket);
      session.checkCancelled();
      final connection = session.connection!;
      final hello = await connection.readFrame();
      if (hello['type'] == 'error') {
        throw StateError(hello['message']?.toString() ?? loc.settings.backupAndTransfer.senderError);
      }
      if (hello['type'] != 'hello') throw FormatException(loc.settings.backupAndTransfer.invalidSenderHello);
      TransferProtocol.validatePeer(hello);
      final advertised = hello['entries'];
      if (advertised is! List ||
          !entries.every((id) => advertised.any((entry) => entry is Map && entry['id'] == id.name))) {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      session.checkCancelled();
      _log(loc.settings.backupAndTransfer.connectedTo(device: hello['deviceName']?.toString() ?? host));
      await connection.writeFrame({
        'type': 'selectEntries',
        'protocol': TransferProtocol.version,
        'capabilities': TransferProtocol.capabilities,
        'requestId': requestId,
        'entries': entries.map((entry) => entry.name).toList(),
        'receiverName': receiverName,
        'options': transferOptions,
      });
      Future<Map<String, dynamic>> response(Duration timeout) async {
        final frame = await connection.readFrame(timeout: timeout);
        if (frame['type'] == 'error') {
          throw StateError(frame['message']?.toString() ?? loc.settings.backupAndTransfer.senderError);
        }
        if (frame['requestId'] != requestId) {
          throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
        }
        session.checkCancelled();
        return frame;
      }

      final approval = await response(TransferProtocol.approvalTimeout + TransferProtocol.idleTimeout);
      if (approval['type'] != 'approved') {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      final frame = await response(TransferProtocol.importTimeout);
      final size = frame['size'];
      final checksum = frame['sha256'];
      if (frame['type'] != 'entryStart' ||
          frame['entry'] != 'package' ||
          size is! int ||
          checksum is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      TransferProtocol.validateSize(size);
      total = size;
      final cacheDir = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
      await cacheDir.create(recursive: true);
      packageDirectory = await cacheDir.createTemp('transfer-');
      packageFile = File(
        '${packageDirectory.path}${Platform.pathSeparator}${BackupFileNaming.transferPackageFileName}',
      );
      await connection.readBytesToFile(size, packageFile, (read) {
        transferred = read;
        emit(entry: 'package');
      }, isCancelled: () => session.cancelled);
      session.checkCancelled();
      final digest = await sha256.bind(packageFile.openRead()).first;
      if (digest.toString() != checksum) {
        throw FormatException(loc.settings.backupAndTransfer.transferChecksumMismatch);
      }
      final completed = await response(TransferProtocol.idleTimeout);
      if (completed['type'] != 'complete') {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      session.checkCancelled();
      // Import commits are allowed to finish. The UI disables cancellation during
      // this phase, and dispose joins it instead of claiming rollback occurred.
      session.importing = true;
      emit(entry: 'importing');
      // Keep elapsed/stall information live without pretending that a timer is
      // actual import progress. Only work callbacks update the progress time.
      importHeartbeat = Timer.periodic(const Duration(seconds: 1), (_) => emit(entry: 'importing'));
      _log(loc.settings.backupAndTransfer.importingPackage);
      final imported = await importService.importNamedFile(
        BackupFileNaming.transferPackageFileName,
        packageFile,
        options: BackupImportOptions(
          tabsMode: options.tabsMode,
          tagsMode: options.tagsMode,
          allowedEntryIds: entries.toSet(),
          onProgress: (progress) {
            final changedStage = importProgress?.phase != progress.phase || importProgress?.entryId != progress.entryId;
            importProgress = progress;
            importProgressUpdatedAt = DateTime.now();
            if (changedStage || importUiTimer.elapsedMilliseconds >= 250) {
              emit(entry: 'importing');
              importUiTimer
                ..reset()
                ..start();
            }
            if (changedStage || importLogTimer.elapsed >= const Duration(seconds: 10)) {
              BackupTransferLogger.info(
                'Import phase=${progress.phase.name} entry=${progress.entryId?.name} '
                    'records=${progress.processedItems}/${progress.totalItems} '
                    'elapsed=${DateTime.now().difference(startedAt).inSeconds}s',
                'TransferSocketClient',
                'receive',
              );
              importLogTimer
                ..reset()
                ..start();
            }
          },
        ),
      );
      importHeartbeat.cancel();
      await connection.writeFrame({'type': 'imported', 'requestId': requestId});
      try {
        await historyService.add(
          TransferHistoryEntry(
            direction: TransferHistoryDirection.received,
            peerName: senderName,
            peerAddress: senderAddress,
            entryIds: imported,
            createdAt: DateTime.now(),
          ),
        );
      } catch (e, s) {
        BackupTransferLogger.error(e, 'TransferSocketClient', 'history', stackTrace: s);
      }
      emit(complete: true);
      _log(loc.settings.backupAndTransfer.transferComplete);
    } catch (e, s) {
      importHeartbeat?.cancel();
      final message = session.cancelled
          ? loc.settings.backupAndTransfer.transferCancelled
          : loc.settings.backupAndTransfer.transferFailed(error: e.toString());
      _log(message);
      if (!session.cancelled) BackupTransferLogger.error(e, 'TransferSocketClient', 'receive', stackTrace: s);
      emit(entry: 'error', complete: true);
      try {
        await session.connection
            ?.writeFrame({'type': 'error', 'requestId': requestId, 'message': message})
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
    } finally {
      importHeartbeat?.cancel();
      session.connect?.cancel();
      await session.connection?.close();
      if (packageFile != null) {
        try {
          if (packageDirectory != null && await packageDirectory.exists()) {
            await packageDirectory.delete(recursive: true);
          }
        } catch (e, s) {
          BackupTransferLogger.error(e, 'TransferSocketClient', 'cleanup', stackTrace: s);
        }
      }
    }
  }

  Future<void> cancel() async {
    final session = _active;
    if (session == null) return;
    if (!session.importing) {
      session.cancelled = true;
      session.connect?.cancel();
      await session.connection?.close();
    }
    await session.done;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await cancel();
    await logs.close();
    await stats.close();
  }

  void _log(String message) {
    if (!logs.isClosed) logs.add(BackupTransferLog(message));
    BackupTransferLogger.info(message, 'TransferSocketClient', '_log');
  }
}

class _ReceiveSession {
  ConnectionTask<Socket>? connect;
  TransferSocketConnection? connection;
  late Future<void> done;
  bool cancelled = false;
  bool importing = false;

  void checkCancelled() {
    if (cancelled) throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
  }
}
