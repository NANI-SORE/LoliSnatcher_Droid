import 'dart:async';
import 'dart:io';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_protocol.dart';

class TransferSocketServer {
  TransferSocketServer({
    BackupPackageService? packageService,
    BackupEntryRegistry? registry,
    TransferHistoryService? historyService,
  }) : packageService = packageService ?? BackupPackageService(),
       registry = registry ?? BackupEntryRegistry.instance,
       historyService = historyService ?? const TransferHistoryService();

  final BackupPackageService packageService;
  final BackupEntryRegistry registry;
  final TransferHistoryService historyService;
  final logs = StreamController<BackupTransferLog>.broadcast();
  final stats = StreamController<BackupTransferStats>.broadcast();
  bool includeDeviceSpecificSettings = false;

  ServerSocket? _server;
  final Set<Socket> _activeSockets = {};
  final Set<Socket> _cancelledSockets = {};
  final Map<Socket, TransferSocketConnection> _activeConnections = {};
  bool _cancelled = false;
  String? _deviceName;

  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;

  Future<void> start({String? host, int port = 0, String? deviceName}) async {
    if (_server != null) {
      await stop();
    }
    _cancelled = false;
    _deviceName = deviceName;
    final bindAddress = host == null || host.isEmpty ? InternetAddress.anyIPv4 : InternetAddress(host);
    _server = await ServerSocket.bind(bindAddress, port);
    _log(
      loc.settings.backupAndTransfer.serverListening(
        address: '${_server!.address.address}:${_server!.port}',
      ),
    );
    unawaited(_acceptLoop());
  }

  Future<void> stop() async {
    _cancelled = true;
    await _server?.close();
    _server = null;
    await _cancelActiveConnections();
    _log(loc.settings.backupAndTransfer.serverStopped);
  }

  Future<void> cancelTransfers() async {
    await _cancelActiveConnections();
    stats.add(
      BackupTransferStats(
        bytesTransferred: 0,
        startedAt: DateTime.now(),
        currentEntry: 'package',
        isComplete: true,
      ),
    );
    _log(loc.settings.backupAndTransfer.transferCancelled);
  }

  Future<void> _cancelActiveConnections() async {
    for (final entry in _activeConnections.entries.toList()) {
      _cancelledSockets.add(entry.key);
      try {
        await entry.value
            .writeFrame({
              'type': 'error',
              'message': loc.settings.backupAndTransfer.transferCancelled,
            })
            .timeout(const Duration(milliseconds: 200));
      } catch (_) {}
    }
    for (final socket in _activeSockets.toList()) {
      _cancelledSockets.add(socket);
      socket.destroy();
    }
    _activeSockets.clear();
    _activeConnections.clear();
  }

  Future<void> dispose() async {
    await stop();
    await logs.close();
    await stats.close();
  }

  Future<void> _acceptLoop() async {
    final server = _server;
    if (server == null) return;
    await for (final socket in server) {
      unawaited(serveSocket(socket));
    }
  }

  Future<void> serveSocket(Socket socket) async {
    _activeSockets.add(socket);
    final connection = TransferSocketConnection(socket);
    _activeConnections[socket] = connection;
    final startedAt = DateTime.now();
    File? packageFile;
    try {
      _log(
        loc.settings.backupAndTransfer.clientConnected(
          address: '${socket.remoteAddress.address}:${socket.remotePort}',
        ),
      );
      await connection.writeFrame({
        'type': 'hello',
        'protocol': 1,
        'version': Constants.updateInfo.versionName,
        'build': Constants.updateInfo.buildNumber,
        'deviceName': _deviceName ?? Platform.localHostname,
        'entries': registry.entries
            .map(
              (entry) => {
                'id': entry.id.name,
                'title': entry.title(),
                'supportsClipboard': entry.supportsClipboard,
              },
            )
            .toList(),
      });
      final selection = await connection.readFrame();
      if (selection['type'] != 'selectEntries') {
        throw FormatException(loc.settings.backupAndTransfer.expectedSelectionFrame);
      }
      final rawEntries = selection['entries'];
      if (rawEntries is! List) throw FormatException(loc.settings.backupAndTransfer.missingSelectedEntries);
      final receiverName = selection['receiverName']?.toString();
      final transferOptions = selection['options'] is Map ? Map<String, dynamic>.from(selection['options'] as Map) : {};
      final entryIds = rawEntries
          .map(
            (raw) =>
                BackupEntryId.values.firstWhere((entry) => entry.name == raw, orElse: () => BackupEntryId.settings),
          )
          .toSet()
          .toList();
      _log(loc.settings.backupAndTransfer.exportingEntries(count: entryIds.length));
      final cacheDir = Directory('${await ServiceHandler.getCacheDir()}backup_transfer');
      await cacheDir.create(recursive: true);
      packageFile = File(
        '${cacheDir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-${BackupFileNaming.transferPackageFileName}',
      );
      await packageService.exportPackageFile(
        entryIds: entryIds,
        outputFile: packageFile,
        options: BackupExportOptions(excludeDeviceSpecificSettings: !includeDeviceSpecificSettings),
        entryOptions: {
          BackupEntryId.favourites: BackupExportOptions(
            excludeDeviceSpecificSettings: !includeDeviceSpecificSettings,
            startIndex: int.tryParse(transferOptions['favouritesStartIndex']?.toString() ?? '') ?? 0,
          ),
          BackupEntryId.snatched: BackupExportOptions(
            excludeDeviceSpecificSettings: !includeDeviceSpecificSettings,
            startIndex: int.tryParse(transferOptions['snatchedStartIndex']?.toString() ?? '') ?? 0,
          ),
        },
      );
      if (_cancelled || _cancelledSockets.contains(socket)) return;
      final packageSize = await packageFile.length();
      await connection.writeFrame({
        'type': 'entryStart',
        'entry': 'package',
        'size': packageSize,
      });
      await connection.writeFile(
        packageFile,
        (sent) {
          stats.add(
            BackupTransferStats(
              bytesTransferred: sent,
              totalBytes: packageSize,
              startedAt: startedAt,
              currentEntry: 'package',
            ),
          );
        },
        isCancelled: () => _cancelled || _cancelledSockets.contains(socket),
      );
      await historyService.add(
        TransferHistoryEntry(
          direction: TransferHistoryDirection.sent,
          peerName: receiverName?.isNotEmpty == true ? receiverName! : socket.remoteAddress.address,
          peerAddress: '${socket.remoteAddress.address}:${socket.remotePort}',
          entryIds: entryIds,
          createdAt: DateTime.now(),
        ),
      );
      await connection.writeFrame({'type': 'complete'});
      stats.add(
        BackupTransferStats(
          bytesTransferred: packageSize,
          totalBytes: packageSize,
          startedAt: startedAt,
          currentEntry: 'package',
          isComplete: true,
        ),
      );
      _log(loc.settings.backupAndTransfer.transferComplete);
    } catch (e) {
      final wasCancelled = _cancelled || _cancelledSockets.contains(socket);
      final message = loc.settings.backupAndTransfer.transferFailed(error: e.toString());
      if (wasCancelled) {
        _log(loc.settings.backupAndTransfer.transferCancelled);
      } else {
        _log(message);
        stats.add(
          BackupTransferStats(
            bytesTransferred: 0,
            startedAt: startedAt,
            currentEntry: 'error',
            isComplete: true,
          ),
        );
        try {
          await connection.writeFrame({'type': 'error', 'message': message});
        } catch (_) {}
        unawaited(stop());
      }
    } finally {
      _activeSockets.remove(socket);
      _cancelledSockets.remove(socket);
      _activeConnections.remove(socket);
      if (packageFile != null) {
        unawaited(packageFile.delete().catchError((_) => packageFile!));
      }
      await socket.close();
    }
  }

  void _log(String message) {
    logs.add(BackupTransferLog(message));
  }
}
