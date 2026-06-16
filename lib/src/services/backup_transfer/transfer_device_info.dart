import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class TransferDeviceInfo {
  const TransferDeviceInfo._();

  static const _uuid = Uuid();
  static const _instanceIdFileName = 'backup_transfer_device_id.txt';

  static Future<String> instanceId() async {
    final file = File('${await ServiceHandler.getConfigDir()}$_instanceIdFileName');
    try {
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (existing.isNotEmpty) return existing;
      }
      final next = _uuid.v4();
      await file.parent.create(recursive: true);
      await file.writeAsString(next, flush: true);
      return next;
    } catch (_) {
      return _uuid.v4();
    }
  }

  static Future<String> displayName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return _join([
          info.manufacturer,
          info.model,
        ]);
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return _join([
          info.name,
          info.model,
        ]);
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return _join([
          info.productName,
          info.computerName,
        ]);
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return _join([
          info.prettyName,
          info.name,
        ]);
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return _join([
          info.computerName,
          info.model,
        ]);
      }
    } catch (_) {}
    return loc.appName;
  }

  static String _join(List<String?> parts) {
    final values = parts
        .map((part) => part?.trim())
        .where((part) => part != null && part.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    if (values.isEmpty) return loc.appName;
    return values.join(' ');
  }
}
