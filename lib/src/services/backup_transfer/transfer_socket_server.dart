import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_protocol.dart';

class TransferRequest {
  const TransferRequest({
    required this.deviceName,
    required this.address,
    required this.entries,
    required this.cancelled,
  });

  final String deviceName;
  final String address;
  final List<BackupEntryId> entries;
  final Future<void> cancelled;
}

class TransferSocketServer {
  TransferSocketServer({
    BackupPackageService? packageService,
    BackupEntryRegistry? registry,
    TransferHistoryService? historyService,
    this.approveRequest,
  }) : packageService = packageService ?? BackupPackageService(),
       registry = registry ?? BackupEntryRegistry.instance,
       historyService = historyService ?? const TransferHistoryService();

  final BackupPackageService packageService;
  final BackupEntryRegistry registry;
  final TransferHistoryService historyService;
  final Future<bool> Function(TransferRequest request)? approveRequest;
  final logs = StreamController<BackupTransferLog>.broadcast();
  final stats = StreamController<BackupTransferStats>.broadcast();
  bool includeDeviceSpecificSettings = false;

  ServerSocket? _server;
  // Owned by the server lifetime; stop() cancels it before dispose closes events.
  // ignore: cancel_subscriptions
  StreamSubscription<Socket>? _subscription;
  _SendSession? _active;
  final Set<Future<void>> _rejections = {};
  String? _deviceName;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _disposing;

  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;

  Future<void> start({String? host, int port = 0, String? deviceName}) async {
    if (_disposed) return;
    await stop();
    if (_disposed) return;
    final generation = ++_generation;
    final bindAddress = host == null || host.isEmpty ? InternetAddress.anyIPv4 : InternetAddress(host);
    final server = await ServerSocket.bind(bindAddress, port);
    if (_disposed || generation != _generation) {
      await server.close();
      return;
    }
    _deviceName = deviceName;
    _server = server;
    _subscription = server.listen(
      (socket) => unawaited(serveSocket(socket)),
      onError: (Object error, StackTrace stack) {
        BackupTransferLogger.error(error, 'TransferSocketServer', 'accept', stackTrace: stack);
      },
    );
    _log(loc.settings.backupAndTransfer.serverListening(address: '${server.address.address}:${server.port}'));
  }

  Future<void> stop() async {
    ++_generation;
    final server = _server;
    final subscription = _subscription;
    _server = null;
    _subscription = null;
    await server?.close();
    await subscription?.cancel();
    await cancelTransfers();
    await Future.wait(_rejections.toList());
    _log(loc.settings.backupAndTransfer.serverStopped);
  }

  Future<void> cancelTransfers() async {
    final active = _active;
    if (active == null) return;
    active.cancel();
    await active.connection.close();
    await active.done;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    await stop();
    await logs.close();
    await stats.close();
  }

  Future<void> serveSocket(Socket socket) {
    final connection = TransferSocketConnection(socket);
    if (_disposed || _active != null) {
      late final Future<void> rejected;
      rejected = _reject(connection).whenComplete(() => _rejections.remove(rejected));
      _rejections.add(rejected);
      return rejected;
    }
    final session = _SendSession(connection);
    _active = session;
    return session.done = _serve(session).whenComplete(() {
      if (identical(_active, session)) _active = null;
    });
  }

  Future<void> _reject(TransferSocketConnection connection) async {
    try {
      await connection
          .writeFrame({'type': 'error', 'message': loc.settings.backupAndTransfer.transferBusy})
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // A busy server never retains a second connection.
    } finally {
      await connection.close();
    }
  }

  Future<void> _serve(_SendSession session) async {
    final connection = session.connection;
    final socket = connection.socket;
    final startedAt = DateTime.now();
    final peerAddress = '${socket.remoteAddress.address}:${socket.remotePort}';
    File? packageFile;
    Directory? packageDirectory;
    String? requestId;
    var transferred = 0;
    int? size;
    void emit({bool complete = false, String entry = 'package'}) {
      if (!stats.isClosed) {
        stats.add(
          BackupTransferStats(
            bytesTransferred: transferred,
            totalBytes: size,
            startedAt: startedAt,
            currentEntry: entry,
            isComplete: complete,
          ),
        );
      }
    }

    try {
      final available = <BackupEntryDefinition>[];
      for (final entry in registry.entries) {
        if (await entry.isAvailable()) available.add(entry);
      }
      session.checkCancelled();
      await connection.writeFrame({
        'type': 'hello',
        'protocol': TransferProtocol.version,
        'capabilities': TransferProtocol.capabilities,
        'version': Constants.updateInfo.versionName,
        'build': Constants.updateInfo.buildNumber,
        'deviceName': _deviceName ?? Platform.localHostname,
        'entries': available
            .map((entry) => {'id': entry.id.name, 'title': entry.title(), 'supportsClipboard': entry.supportsClipboard})
            .toList(),
      });
      final selection = await connection.readFrame();
      if (selection['type'] != 'selectEntries' || !TransferProtocol.validRequestId(selection['requestId'])) {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      TransferProtocol.validatePeer(selection);
      requestId = selection['requestId'] as String;
      final rawEntries = selection['entries'];
      final receiverName = selection['receiverName'];
      final rawOptions = selection['options'];
      if (rawEntries is! List ||
          rawEntries.isEmpty ||
          rawEntries.length > available.length ||
          receiverName is! String ||
          receiverName.trim().isEmpty ||
          receiverName.length > 256 ||
          rawOptions is! Map<String, dynamic>) {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      final entryIds = <BackupEntryId>[];
      for (final raw in rawEntries) {
        final entry = available.where((entry) => entry.id.name == raw).firstOrNull;
        if (entry == null || entryIds.contains(entry.id)) {
          throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
        }
        entryIds.add(entry.id);
      }
      if (entryIds.contains(BackupEntryId.database) && entryIds.any(BackupEntryRegistry.databaseChildIds.contains)) {
        throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
      }
      for (final option in rawOptions.entries) {
        if (!const ['favouritesStartIndex', 'snatchedStartIndex'].contains(option.key) ||
            option.value is! int ||
            (option.value as int) < 0 ||
            (option.value as int) > 0x7fffffff) {
          throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
        }
      }
      session.checkCancelled();
      final approve = approveRequest;
      final accepted =
          approve != null &&
          await Future.any<bool>([
            approve(
              TransferRequest(
                deviceName: receiverName,
                address: peerAddress,
                entries: List.unmodifiable(entryIds),
                cancelled: session.cancelled.future,
              ),
            ),
            session.cancelled.future.then((_) => false),
          ]).timeout(TransferProtocol.approvalTimeout, onTimeout: () => false);
      session.checkCancelled();
      if (!accepted) throw StateError(loc.settings.backupAndTransfer.transferDeclined);
      final includeDeviceSettings = includeDeviceSpecificSettings;
      await connection.writeFrame({'type': 'approved', 'requestId': requestId});
      emit();
      _log(loc.settings.backupAndTransfer.exportingEntries(count: entryIds.length));
      final cacheDir = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
      await cacheDir.create(recursive: true);
      packageDirectory = await cacheDir.createTemp('transfer-');
      packageFile = File(
        '${packageDirectory.path}${Platform.pathSeparator}${BackupFileNaming.transferPackageFileName}',
      );
      await packageService.exportPackageFile(
        entryIds: entryIds,
        outputFile: packageFile,
        options: BackupExportOptions(excludeDeviceSpecificSettings: !includeDeviceSettings),
        entryOptions: {
          BackupEntryId.favourites: BackupExportOptions(
            excludeDeviceSpecificSettings: !includeDeviceSettings,
            startIndex: rawOptions['favouritesStartIndex'] as int? ?? 0,
          ),
          BackupEntryId.snatched: BackupExportOptions(
            excludeDeviceSpecificSettings: !includeDeviceSettings,
            startIndex: rawOptions['snatchedStartIndex'] as int? ?? 0,
          ),
        },
      );
      session.checkCancelled();
      final packageSize = await packageFile.length();
      TransferProtocol.validateSize(packageSize);
      size = packageSize;
      final digest = await sha256.bind(packageFile.openRead()).first;
      session.checkCancelled();
      await connection.writeFrame({
        'type': 'entryStart',
        'requestId': requestId,
        'entry': 'package',
        'size': packageSize,
        'sha256': digest.toString(),
      });
      await connection.writeFile(packageFile, (sent) {
        transferred = sent;
        emit();
      }, isCancelled: () => session.isCancelled);
      session.checkCancelled();
      await connection.writeFrame({'type': 'complete', 'requestId': requestId});
      final ack = await connection.readFrame(timeout: TransferProtocol.importTimeout);
      if (ack['type'] != 'imported' || ack['requestId'] != requestId) {
        throw StateError(
          ack['type'] == 'error'
              ? ack['message']?.toString() ?? loc.settings.backupAndTransfer.invalidTransferData
              : loc.settings.backupAndTransfer.invalidTransferData,
        );
      }
      try {
        await historyService.add(
          TransferHistoryEntry(
            direction: TransferHistoryDirection.sent,
            peerName: receiverName,
            peerAddress: peerAddress,
            entryIds: entryIds,
            createdAt: DateTime.now(),
          ),
        );
      } catch (e, s) {
        BackupTransferLogger.error(e, 'TransferSocketServer', 'history', stackTrace: s);
      }
      emit(complete: true);
      _log(loc.settings.backupAndTransfer.transferComplete);
    } catch (e, s) {
      final message = session.isCancelled
          ? loc.settings.backupAndTransfer.transferCancelled
          : loc.settings.backupAndTransfer.transferFailed(error: e.toString());
      _log(message);
      if (!session.isCancelled) BackupTransferLogger.error(e, 'TransferSocketServer', 'serveSocket', stackTrace: s);
      emit(complete: true, entry: 'error');
      try {
        await connection
            .writeFrame({'type': 'error', 'requestId': requestId, 'message': message})
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
    } finally {
      session.cancel();
      await connection.close();
      if (packageFile != null) {
        try {
          if (packageDirectory != null && await packageDirectory.exists()) {
            await packageDirectory.delete(recursive: true);
          }
        } catch (e, s) {
          BackupTransferLogger.error(e, 'TransferSocketServer', 'cleanup', stackTrace: s);
        }
      }
    }
  }

  void _log(String message) {
    if (!logs.isClosed) logs.add(BackupTransferLog(message));
    BackupTransferLogger.info(message, 'TransferSocketServer', '_log');
  }
}

class _SendSession {
  _SendSession(this.connection);
  final TransferSocketConnection connection;
  final cancelled = Completer<void>();
  late Future<void> done;
  bool get isCancelled => cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) cancelled.complete();
  }

  void checkCancelled() {
    if (isCancelled) throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
  }
}
