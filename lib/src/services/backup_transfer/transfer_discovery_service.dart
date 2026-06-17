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
  final Map<String, DiscoveredTransferDevice> _devices = {};
  String? _ignoredDeviceId;
  Set<String> _ignoredHosts = {};

  Stream<List<DiscoveredTransferDevice>> get devices => _devicesController.stream;

  Future<void> startBroadcast({
    required String deviceName,
    required String deviceId,
    required int port,
  }) async {
    await stopBroadcast();
    final serviceName = '${loc.appName} $port';
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
      },
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();
  }

  Future<void> stopBroadcast() async {
    if (_broadcast != null) {
      BackupTransferLogger.info('Stopping Bonsoir broadcast', 'TransferDiscoveryService', 'stopBroadcast');
    }
    await _broadcast?.stop();
    _broadcast = null;
  }

  Future<void> startDiscovery({
    String? ignoredDeviceId,
    Set<String> ignoredHosts = const {},
  }) async {
    await stopDiscovery();
    _ignoredDeviceId = ignoredDeviceId;
    _ignoredHosts = ignoredHosts.where((host) => host.isNotEmpty).toSet();
    BackupTransferLogger.info(
      'Starting Bonsoir discovery ignoredDeviceId=${ignoredDeviceId ?? '<none>'} ignoredHosts=${_ignoredHosts.join(',')}',
      'TransferDiscoveryService',
      'startDiscovery',
    );
    _devices.clear();
    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();
    _discoverySub = _discovery!.eventStream!.listen(_onDiscoveryEvent);
    await _discovery!.start();
  }

  Future<void> stopDiscovery() async {
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
    _emitDevices();
  }

  Future<void> dispose() async {
    await stopBroadcast();
    await stopDiscovery();
    await _devicesController.close();
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        BackupTransferLogger.info(
          'Found Bonsoir service ${event.service.name}',
          'TransferDiscoveryService',
          '_onDiscoveryEvent',
        );
        event.service.resolve(_discovery!.serviceResolver);
        break;
      case BonsoirDiscoveryServiceResolvedEvent():
      case BonsoirDiscoveryServiceUpdatedEvent():
        final service = event.service;
        if (service == null) return;
        final host = service.hostAddress ?? _extractHost(service.toJson());
        final port = service.port;
        if (host == null) return;
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
        _devices[id] = DiscoveredTransferDevice(
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
        if (host == null) return;
        BackupTransferLogger.info(
          'Lost transfer device $host:$port',
          'TransferDiscoveryService',
          '_onDiscoveryEvent',
        );
        _devices.remove('$host:$port');
        _emitDevices();
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
    _devicesController.add(_devices.values.toList(growable: false));
  }
}
