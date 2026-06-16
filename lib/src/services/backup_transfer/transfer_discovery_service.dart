import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';

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
    _devices.clear();
    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();
    _discoverySub = _discovery!.eventStream!.listen(_onDiscoveryEvent);
    await _discovery!.start();
  }

  Future<void> stopDiscovery() async {
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
        if (_isIgnoredService(host, attributes)) return;
        final name = attributes['devName']?.toString() ?? service.name;
        final id = '$host:$port';
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
