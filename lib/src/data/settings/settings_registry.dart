import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

/// Central registry for all application settings.
///
/// Holds [SettingState] instances keyed by [SettingKey]. Provides lookup,
/// search, serialization, and per-booru override management.
///
/// Access via [SettingsRegistry.instance].
class SettingsRegistry {
  SettingsRegistry._() {
    // Wire up the booru notifier provider so SettingState can access it
    // without a circular import on this file.
    setCurrentBooruNotifierProvider(() => currentBooruNotifier);
  }

  static final SettingsRegistry instance = SettingsRegistry._();

  final Map<SettingKey, SettingState<dynamic>> _states = {};

  /// Current booru context. Set by SearchHandler when the active booru changes.
  /// [SettingState]'s effective value recomputes when this changes.
  final ValueNotifier<String?> currentBooruNotifier = ValueNotifier<String?>(null);

  /// Convenience getter for the current booru name.
  String? get currentBooruName => currentBooruNotifier.value;

  /// Update the current booru context.
  void setCurrentBooru(String? booruName) {
    currentBooruNotifier.value = booruName;
  }

  // ============================================
  // REGISTRATION & LOOKUP
  // ============================================

  /// Register a setting definition. Creates a [SettingState] and stores it.
  void register<T>(SettingDef<T> def) {
    _states[def.key] = SettingState<T>(def);
  }

  /// Get a setting's state by its enum key. Returns null if not registered.
  SettingState<T>? get<T>(SettingKey key) {
    final state = _states[key];
    if (state == null) return null;
    return state as SettingState<T>;
  }

  /// Get a setting's state by its JSON key string.
  /// Used for backwards compatibility with the existing `getByString`/`setByString` pattern.
  SettingState<dynamic>? getByJsonKey(String jsonKey) {
    for (final state in _states.values) {
      if (state.def.jsonKey == jsonKey || state.def.legacyJsonKeys.contains(jsonKey)) {
        return state;
      }
    }
    return null;
  }

  /// All registered setting states.
  Iterable<SettingState<dynamic>> get all => _states.values;

  /// Whether any settings have been registered.
  bool get isEmpty => _states.isEmpty;

  /// Number of registered settings.
  int get length => _states.length;

  // ============================================
  // CATEGORY QUERIES
  // ============================================

  /// All settings belonging to a category. Respects multi-category membership.
  /// Returns settings in registration order.
  List<SettingState<dynamic>> byCategory(SettingCategory category) {
    return _states.values.where((s) => s.def.categories.contains(category)).toList();
  }

  /// Display subsection for [state] on [category], if one was registered.
  SettingSubcategory? subcategoryFor(SettingCategory category, SettingState<dynamic> state) {
    for (final subcategory in state.def.subcategories) {
      if (subcategory.category == category) return subcategory;
    }
    return null;
  }

  /// Whether a setting should be shown in UI on the current platform/build.
  bool isSettingVisible(SettingState<dynamic> state) {
    final def = state.def;
    if (def.categories.isEmpty || !def.categories.any(isCategoryVisible)) {
      return false;
    }
    return def.visibleWhen?.call() ?? true;
  }

  /// Whether a category is currently visible.
  bool isCategoryVisible(SettingCategory category) {
    switch (category) {
      case SettingCategory.debug:
        return get<bool>(SettingKey.isDebug)?.value ?? false;
      default:
        return true;
    }
  }

  /// All categories that are currently visible.
  List<SettingCategory> get visibleCategories {
    return SettingCategory.values.where(isCategoryVisible).toList();
  }

  /// Settings flagged as device-specific (not synced across devices).
  List<SettingState<dynamic>> get deviceSpecific {
    return _states.values.where((s) => s.def.isDeviceSpecific).toList();
  }

  /// Settings that can be synced (not device-specific).
  List<SettingState<dynamic>> get syncable {
    return _states.values.where((s) => !s.def.isDeviceSpecific).toList();
  }

  /// Settings that support per-booru overrides.
  List<SettingState<dynamic>> get perBooruSettings {
    return _states.values.where((s) => s.def.supportsPerBooru).toList();
  }

  // ============================================
  // SEARCH
  // ============================================

  /// Search settings by query string.
  ///
  /// Uses simple substring matching on localized titles, subtitles, keywords,
  /// and category names. No caching - fast enough for ~100 settings and
  /// automatically uses the current locale (no invalidation needed on language change).
  List<SettingState<dynamic>> search(String query, BuildContext context) {
    if (query.isEmpty) return [];

    final queryLower = query.toLowerCase();
    return _states.values.where((state) {
      if (!isSearchVisible(state, context)) return false;
      final searchable = state.def.getSearchableText(context);
      return searchable.any((text) => text.toLowerCase().contains(queryLower));
    }).toList();
  }

  /// Whether a setting is allowed to appear in global settings search.
  bool isSearchVisible(SettingState<dynamic> state, [BuildContext? context]) {
    final def = state.def;
    if (!def.isSearchable || def.isWidgetSlot || def.widgetBuilder == null) {
      return false;
    }
    if (!isSettingVisible(state)) {
      return false;
    }
    if (!(def.searchVisibleWhen?.call() ?? true)) {
      return false;
    }
    return def.enabledWhen?.call(context) ?? true;
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Whether a setting should be excluded from JSON serialization.
  bool _excludeFromJson(SettingState<dynamic> s) => s.def.isWidgetSlot || s.def.isTransient;

  /// Serialize all global setting values to JSON.
  /// Format is flat: `{"key": value, ...}` matching the existing settings.json format.
  /// Widget slots and transient settings are excluded.
  Map<String, dynamic> toJson() {
    return Map.fromEntries(
      _states.values.where((s) => !_excludeFromJson(s)).map((s) => MapEntry(s.def.jsonKey, s.toJson())),
    );
  }

  /// Load global setting values from JSON.
  /// Unrecognized keys are silently ignored (forwards compatibility).
  /// Full restores reset absent persisted settings; partial updates retain them.
  void loadFromJson(Map<String, dynamic> json, {bool resetMissing = false}) {
    if (resetMissing) {
      for (final state in _states.values) {
        if (!_excludeFromJson(state) &&
            !json.containsKey(state.def.jsonKey) &&
            !state.def.legacyJsonKeys.any(json.containsKey)) {
          state.loadDefaultValue();
        }
      }
    }
    // Load canonical keys first so they win when a file contains both the
    // current key and one of its historical aliases.
    for (final state in _states.values) {
      if (_excludeFromJson(state) || !json.containsKey(state.def.jsonKey)) {
        continue;
      }
      _loadGlobalValue(state, json[state.def.jsonKey]);
    }

    for (final entry in json.entries) {
      final state = getByJsonKey(entry.key);
      if (state != null &&
          !_excludeFromJson(state) &&
          entry.key != state.def.jsonKey &&
          !json.containsKey(state.def.jsonKey)) {
        _loadGlobalValue(state, entry.value);
      }
    }
  }

  /// Clears persisted picker values whose files or directories are no longer
  /// accessible. Global values are reset to their defaults; per-booru values
  /// are removed so the booru resumes inheriting the global value.
  Future<PickerAccessValidationResult> clearInaccessiblePickerValues({
    bool includeGlobal = true,
    Iterable<String> booruNames = const [],
  }) async {
    final result = PickerAccessValidationResult();
    final scopedNames = booruNames.toSet();

    for (final state in _states.values) {
      if (!state.def.hasAccessValidator) continue;

      if (includeGlobal && !state.valuesEqual(state.globalValue, state.defaultValue)) {
        if (!await _hasPickerAccess(state, state.globalValue)) {
          state.loadDefaultValue();
          result.clearedGlobal.add(state.def.key);
        }
      }

      if (!state.def.supportsPerBooru) continue;
      for (final booruName in scopedNames) {
        if (!state.hasOverrideFor(booruName)) continue;
        final value = state.getOverrideFor(booruName);
        if (value == null || state.valuesEqual(value, state.defaultValue)) continue;
        if (!await _hasPickerAccess(state, value)) {
          state.removeOverrideFor(booruName, save: false);
          result.clearedOverrides.putIfAbsent(booruName, () => <SettingKey>{}).add(state.def.key);
        }
      }
    }

    return result;
  }

  Future<bool> _hasPickerAccess(
    SettingState<dynamic> state,
    dynamic value,
  ) async {
    try {
      return await state.def.canAccessValue(value);
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to validate picker setting ${state.def.jsonKey}: $e',
        'SettingsRegistry',
        'clearInaccessiblePickerValues',
        LogTypes.settingsError,
        s: s,
      );
      return false;
    }
  }

  void _loadGlobalValue(SettingState<dynamic> state, dynamic value) {
    try {
      state.loadFromJson(value);
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to load setting ${state.def.jsonKey}: $e',
        'SettingsRegistry',
        'loadFromJson',
        LogTypes.settingsError,
        s: s,
      );
    }
  }

  /// Reset all settings to their default values.
  void resetAll() {
    for (final state in _states.values) {
      state.reset();
    }
  }

  /// Reset all settings in a specific category to defaults.
  void resetCategory(SettingCategory category) {
    for (final state in byCategory(category)) {
      state.reset();
    }
  }

  // ============================================
  // PER-BOORU OVERRIDE MANAGEMENT
  // ============================================

  /// Load per-booru overrides from a booru's `settingOverrides` map into
  /// the in-memory [SettingState] instances.
  ///
  /// Call this after loading each booru config from disk.
  void loadOverridesFromMap(String booruName, Map<String, dynamic>? overrides) {
    if (overrides == null) return;

    for (final entry in overrides.entries) {
      final state = getByJsonKey(entry.key);
      if (state != null && state.def.supportsPerBooru) {
        try {
          state.setOverrideFor(booruName, state.def.valueFromJson(entry.value), save: false);
        } catch (e, s) {
          Logger.Inst().log(
            'Failed to load ${state.def.jsonKey} override for $booruName: $e',
            'SettingsRegistry',
            'loadOverridesFromMap',
            LogTypes.settingsError,
            s: s,
          );
        }
      }
    }
  }

  /// Collect all in-memory overrides for a booru into a JSON-compatible map.
  ///
  /// Saves every explicit override, even if it currently matches the global value.
  /// Keeping equal overrides explicit prevents future global changes from silently
  /// changing a booru that the user customized.
  /// Returns null if no meaningful overrides exist (so the field can be omitted from the booru config).
  Map<String, dynamic>? saveOverridesToMap(String booruName) {
    final overrides = <String, dynamic>{};
    for (final state in _states.values) {
      if (state.def.supportsPerBooru && state.hasOverrideFor(booruName)) {
        final json = state.overrideToJson(booruName);
        if (json != null) {
          overrides[state.def.key.jsonKey] = json;
        }
      }
    }
    return overrides.isEmpty ? null : overrides;
  }

  /// Clear all in-memory overrides for a booru.
  /// Call this when a booru is deleted.
  void removeAllOverridesForBooru(String booruName, {bool save = true}) {
    for (final state in _states.values) {
      if (state.def.supportsPerBooru) {
        state.removeOverrideFor(booruName, save: save);
      }
    }
  }

  /// Copy all overrides from one booru to another.
  void copyOverrides(String fromBooruName, String toBooruName, {bool save = true}) {
    for (final state in perBooruSettings) {
      if (state.hasOverrideFor(fromBooruName)) {
        final override = state.getOverrideFor(fromBooruName);
        state.setOverrideFor(toBooruName, override, save: save);
      }
    }
  }
}

class PickerAccessValidationResult {
  final Set<SettingKey> clearedGlobal = <SettingKey>{};
  final Map<String, Set<SettingKey>> clearedOverrides = <String, Set<SettingKey>>{};

  bool get isEmpty => clearedGlobal.isEmpty && clearedOverrides.isEmpty;
}
