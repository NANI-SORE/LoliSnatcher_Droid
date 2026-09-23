import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';

class TransferDiscoveryService {
  // Stable protocol identifier. Do not rebrand unless cross-app discovery is intentionally broken.
  static const serviceType = '_lolisync._tcp';
  static const protocolVersion = 1;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  final _devicesController = StreamController<List<DiscoveredTransferDevice>>.broadcast();
  final Map<(String, String), DiscoveredTransferDevice> _devices = {};
  final Map<(String, String), int> _advertisedAt = {};
  final Map<String, int> _latestDeviceAdvertisements = {};
  final Set<(String, String)> _seenServices = {};
  Timer? _discoveryRetry;
  Timer? _discoveryReconcile;
  int _discoveryRetryAttempt = 0;
  bool _discoveryRequested = false;
  bool _disposed = false;
  int _broadcastGeneration = 0;
  int _discoveryGeneration = 0;
  Future<void> _broadcastTail = Future<void>.value();
  Future<void> _discoveryTail = Future<void>.value();
  String? _ignoredDeviceId;
  Set<String> _ignoredHosts = {};

  Stream<List<DiscoveredTransferDevice>> get devices => _devicesController.stream;

  Future<void> startBroadcast({
    required String deviceName,
    required String deviceId,
    required int port,
  }) async {
    final generation = ++_broadcastGeneration;
    final pending = _broadcastTail;
    final operation = () async {
      await pending;
      if (_disposed || generation != _broadcastGeneration) return;
      await _broadcast?.stop();
      _broadcast = null;
      // Ports change when the server restarts; the advertised device does not.
      final serviceName = 'LoliSnatcher $deviceId';
      BackupTransferLogger.info(
        'Starting Bonsoir broadcast name=$serviceName port=$port deviceId=$deviceId',
        'TransferDiscoveryService',
        'startBroadcast',
      );
      final service = BonsoirService(
        name: serviceName,
        type: serviceType,
        port: port,
        attributes: {
          'protocol': protocolVersion.toString(),
          'version': Constants.updateInfo.versionName,
          'build': Constants.updateInfo.buildNumber.toString(),
          'devName': deviceName,
          'devId': deviceId,
          'startedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final broadcast = BonsoirBroadcast(service: service);
      await broadcast.initialize();
      if (_disposed || generation != _broadcastGeneration) {
        await broadcast.stop();
        return;
      }
      _broadcast = broadcast;
      await broadcast.start();
      if (_disposed || generation != _broadcastGeneration) {
        await broadcast.stop();
        _broadcast = null;
      }
    }();
    _broadcastTail = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return operation;
  }

  Future<void> stopBroadcast() async {
    ++_broadcastGeneration;
    await _broadcastTail;
    final broadcast = _broadcast;
    _broadcast = null;
    await broadcast?.stop();
  }

  Future<void> startDiscovery({
    String? ignoredDeviceId,
    Set<String> ignoredHosts = const {},
  }) async {
    if (_disposed) return;
    _discoveryRequested = true;
    _discoveryRetry?.cancel();
    _discoveryReconcile?.cancel();
    final generation = ++_discoveryGeneration;
    final pending = _discoveryTail;
    final operation = () async {
      await pending;
      if (_disposed || generation != _discoveryGeneration) return;
      await _discoverySub?.cancel();
      _discoverySub = null;
      await _discovery?.stop();
      _discovery = null;
      _ignoredDeviceId = ignoredDeviceId;
      _ignoredHosts = ignoredHosts.where((host) => host.isNotEmpty).toSet();
      BackupTransferLogger.info(
        'Starting Bonsoir discovery ignoredDeviceId=${ignoredDeviceId ?? '<none>'} ignoredHosts=${_ignoredHosts.join(',')}',
        'TransferDiscoveryService',
        'startDiscovery',
      );
      _seenServices.clear();
      final discovery = BonsoirDiscovery(type: serviceType);
      await discovery.initialize();
      if (_disposed || generation != _discoveryGeneration) {
        await discovery.stop();
        return;
      }
      _discovery = discovery;
      _discoverySub = discovery.eventStream!.listen(
        (event) {
          if (!_disposed && generation == _discoveryGeneration) _onDiscoveryEvent(event);
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed || generation != _discoveryGeneration) return;
          BackupTransferLogger.error(error, 'TransferDiscoveryService', 'discovery', stackTrace: stack);
          _scheduleDiscoveryRetry();
        },
        onDone: () {
          if (generation == _discoveryGeneration) _scheduleDiscoveryRetry();
        },
      );
      await discovery.start();
      if (_disposed || generation != _discoveryGeneration) {
        await _discoverySub?.cancel();
        _discoverySub = null;
        await discovery.stop();
        _discovery = null;
        return;
      }
      // Keep the last scan visible while replacement discovery resolves peers,
      // then remove anything that was not found again. Manual entries live in the page.
      _discoveryReconcile = Timer(const Duration(seconds: 10), () {
        if (_disposed || generation != _discoveryGeneration) return;
        _discoveryRetryAttempt = 0;
        _devices.removeWhere((key, _) => !_seenServices.contains(key));
        _advertisedAt.removeWhere((key, _) => !_devices.containsKey(key));
        _emitDevices();
      });
    }();
    _discoveryTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (generation == _discoveryGeneration) _scheduleDiscoveryRetry();
      },
    );
    return operation;
  }

  Future<void> stopDiscovery() async {
    _discoveryRequested = false;
    _discoveryRetryAttempt = 0;
    _discoveryRetry?.cancel();
    _discoveryReconcile?.cancel();
    ++_discoveryGeneration;
    await _discoveryTail;
    if (_discovery != null) {
      BackupTransferLogger.info(
        'Stopping Bonsoir discovery',
        'TransferDiscoveryService',
        'stopDiscovery',
      );
    }
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery?.stop();
    _discovery = null;
    _ignoredDeviceId = null;
    _ignoredHosts = {};
    _devices.clear();
    _advertisedAt.clear();
    _latestDeviceAdvertisements.clear();
    _seenServices.clear();
    _emitDevices();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopBroadcast();
    await stopDiscovery();
    await _devicesController.close();
  }

  Future<void> refreshDiscovery() async {
    if (_disposed || !_discoveryRequested) return;
    try {
      await startDiscovery(ignoredDeviceId: _ignoredDeviceId, ignoredHosts: _ignoredHosts);
    } catch (error, stack) {
      BackupTransferLogger.error(error, 'TransferDiscoveryService', 'refreshDiscovery', stackTrace: stack);
      _scheduleDiscoveryRetry();
    }
  }

  void _scheduleDiscoveryRetry() {
    if (_disposed || !_discoveryRequested || _discoveryRetry?.isActive == true) return;
    const retrySeconds = [3, 6, 12, 24, 30];
    final delay = Duration(seconds: retrySeconds[_discoveryRetryAttempt]);
    if (_discoveryRetryAttempt < retrySeconds.length - 1) _discoveryRetryAttempt++;
    _discoveryRetry = Timer(delay, () => unawaited(refreshDiscovery()));
  }

  void _resolveService(BonsoirService service) {
    final discovery = _discovery;
    final generation = _discoveryGeneration;
    if (discovery == null) return;
    unawaited(
      service.resolve(discovery.serviceResolver).catchError((Object error, StackTrace stack) {
        if (_disposed || generation != _discoveryGeneration) return;
        BackupTransferLogger.error(error, 'TransferDiscoveryService', 'resolve', stackTrace: stack);
        _scheduleDiscoveryRetry();
      }),
    );
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        BackupTransferLogger.info(
          'Found Bonsoir service ${event.service.name}',
          'TransferDiscoveryService',
          '_onDiscoveryEvent',
        );
        _resolveService(event.service);
        break;
      case BonsoirDiscoveryServiceResolvedEvent():
      case BonsoirDiscoveryServiceUpdatedEvent():
        final service = event.service;
        if (service == null) return;
        final host = service.hostAddress ?? _extractHost(service.toJson());
        final port = service.port;
        if (host == null || host.isEmpty || port <= 0) {
          _resolveService(service);
          return;
        }
        final attributes = service.attributes;
        if (_isIgnoredService(host, attributes)) {
          BackupTransferLogger.info(
            'Ignoring local Bonsoir service host=$host port=$port deviceId=${attributes['devId']}',
            'TransferDiscoveryService',
            '_onDiscoveryEvent',
          );
          return;
        }
        final name = attributes['devName']?.toString() ?? service.name;
        final id = '$host:$port';
        BackupTransferLogger.info(
          'Resolved transfer device id=$id name=$name version=${attributes['version']}',
          'TransferDiscoveryService',
          '_onDiscoveryEvent',
        );
        final key = (service.name, service.type);
        final deviceId = attributes['devId'];
        final advertisedAt = int.tryParse(attributes['startedAt'] ?? '') ?? 0;
        if (deviceId != null && deviceId.isNotEmpty) {
          final latest = _latestDeviceAdvertisements[deviceId] ?? 0;
          if (advertisedAt < latest) return;
          _latestDeviceAdvertisements[deviceId] = advertisedAt;
        }
        _seenServices.add(key);
        _advertisedAt[key] = advertisedAt;
        _devices[key] = DiscoveredTransferDevice(
          id: id,
          name: name,
          host: host,
          port: port,
          deviceId: attributes['devId']?.toString(),
          version: attributes['version']?.toString() ?? loc.settings.backupAndTransfer.unknown,
          build: attributes['build'],
        );
        _emitDevices();
        break;
      case BonsoirDiscoveryServiceLostEvent():
        final service = event.service;
        final host = service.hostAddress ?? _extractHost(service.toJson());
        final port = service.port.toString();
        final key = (service.name, service.type);
        final current = _devices[key];
        if (current != null && service.port > 0 && service.port != current.port) return;
        if (current != null && host != null && host.isNotEmpty && host != current.host) return;
        BackupTransferLogger.info(
          'Lost transfer device $host:$port',
          'TransferDiscoveryService',
          '_onDiscoveryEvent',
        );
        _seenServices.remove(key);
        _devices.remove(key);
        _advertisedAt.remove(key);
        _emitDevices();
        _scheduleDiscoveryRetry();
        break;
      case BonsoirDiscoveryStoppedEvent():
      case BonsoirDiscoveryServiceResolveFailedEvent():
        _scheduleDiscoveryRetry();
        break;
      default:
        break;
    }
  }

  String? _extractHost(Map<String, dynamic> json) {
    final host = json['host'] ?? json['serviceHost'] ?? json['hostname'] ?? json['service.hostname'];
    if (host != null && host.toString().isNotEmpty) return host.toString();
    final addresses = json['hostAddresses'] ?? json['service.hostAddresses'];
    if (addresses is List && addresses.isNotEmpty) return addresses.first.toString();
    return null;
  }

  bool _isIgnoredService(String host, Map<String, String> attributes) {
    final deviceId = attributes['devId'];
    if (deviceId != null && deviceId.isNotEmpty && deviceId == _ignoredDeviceId) return true;
    return _ignoredHosts.contains(host);
  }

  void _emitDevices() {
    if (_disposed || _devicesController.isClosed) return;
    final visible = <String, DiscoveredTransferDevice>{};
    for (final entry in _devices.entries) {
      final device = entry.value;
      final deviceId = device.deviceId;
      if (deviceId != null && deviceId.isNotEmpty) {
        // A late cached advertisement must not replace the current endpoint,
        // including when an old service-lost event arrives after a restart.
        if ((_advertisedAt[entry.key] ?? 0) < (_latestDeviceAdvertisements[deviceId] ?? 0)) continue;
        visible['device:$deviceId'] = device;
      } else {
        visible['address:${device.address}'] = device;
      }
    }
    _devicesController.add(visible.values.toList(growable: false));
  }
}
