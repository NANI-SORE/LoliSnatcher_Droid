import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';

class BackupSettingsPolicy {
  BackupSettingsPolicy._();

  static const Set<SettingKey> _alwaysLocal = {
    .appMode,
    .proxyType,
    .proxyAddress,
    .proxyUsername,
    .proxyPassword,
    .useLockscreen,
    .autoLockTimeout,
    .incognitoKeyboard,
    .shitDevice,
    .appAlias,
    .usePredictiveBack,
    .captureLogcat,
    .useImageLogging,
    .drawerMascotPathOverride,
    .extPathOverride,
    .backupPath,
  };

  static Map<String, dynamic> exportValues(
    Map<String, dynamic> values, {
    required bool excludeDeviceSpecificSettings,
  }) {
    final result = Map<String, dynamic>.from(values);
    for (final state in SettingsRegistry.instance.all) {
      if (!_alwaysLocal.contains(state.def.key) && !(excludeDeviceSpecificSettings && state.def.isDeviceSpecific)) {
        continue;
      }
      result.remove(state.def.jsonKey);
      for (final alias in state.def.legacyJsonKeys) {
        result.remove(alias);
      }
    }
    return result;
  }

  static Map<String, dynamic>? importOverrides(
    Map<String, dynamic>? incoming,
    Map<String, dynamic>? existing,
  ) {
    final result = exportValues(incoming ?? const {}, excludeDeviceSpecificSettings: false);
    for (final entry in (existing ?? const <String, dynamic>{}).entries) {
      final state = SettingsRegistry.instance.getByJsonKey(entry.key);
      if (state == null || !state.def.supportsPerBooru) continue;
      final alwaysLocal = _alwaysLocal.contains(state.def.key);
      if (!alwaysLocal && !state.def.isDeviceSpecific) continue;
      final supplied =
          incoming?.containsKey(state.def.jsonKey) == true ||
          state.def.legacyJsonKeys.any((key) => incoming?.containsKey(key) == true);
      if (alwaysLocal || !supplied) {
        // Omitted device values mean "keep this device's preference", not reset.
        for (final alias in state.def.legacyJsonKeys) {
          result.remove(alias);
        }
        result[state.def.jsonKey] = entry.value;
      }
    }
    return result.isEmpty ? null : result;
  }
}
