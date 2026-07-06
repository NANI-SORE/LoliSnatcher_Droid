# Dynamic Settings System - Implementation Plan

## Overview

Create a unified dynamic settings system where all properties and functions of a setting are combined in a single class. This enables:
- Global search through all settings
- Auto-rendered settings pages based on setting definitions
- Type-safe setting management with reactive updates (using Flutter's `ValueNotifier`, not GetX)
- Reduced boilerplate when adding new settings
- Per-booru setting overrides stored in booru config files
- Immutable setting definitions with separate mutable state

## Key Design Decisions

1. **Multiple categories**: A setting can belong to multiple categories (e.g., `enableHeroTransitions` in both `viewer` and `performance`)
2. **Localized search keywords**: `searchKeywords` is a context-dependent function `(BuildContext) => List<String>` for proper localization (compatible with slang package)
3. **Border handling in page builder**: `drawTopBorder`/`drawBottomBorder` removed from `SettingWidgetConfig` - handled by `AutoSettingsPage.settingBuilder`
4. **Special setting types**: Factory functions for `Theme`, `ThemeMode`, `Locale`, `FontFamily` etc.
5. **Category visibility**: Categories have optional `visibleWhen` function to hide entire sections (e.g., debug settings hidden in release)
6. **Dynamic default values**: `defaultValue` is a function `() => T` to support platform-specific defaults (e.g., different column counts for desktop vs mobile)
7. **Per-booru overrides**: Settings can have per-booru values stored in booru config files, overriding the global value when viewing that booru
8. **No GetX**: Use `ValueNotifier<T>` + `ValueListenableBuilder` / `ListenableBuilder` instead of `Rx<T>` / `Obx`
9. **SettingDef/SettingState split**: Immutable definitions describe what a setting IS; mutable state holds current values
10. **Side effects via onChanged**: Settings that trigger app-wide effects (theme, locale, DB) use an `onChanged` callback
11. **No editing mode on singleton**: Per-booru editing context passed through widget tree, not global state

---

## Reactivity: ValueNotifier (not GetX)

The app is moving away from GetX. All reactive state in the settings system uses Flutter built-ins:

### Replacement Mapping

| GetX | Flutter Built-in | Notes |
|------|-----------------|-------|
| `Rx<T>` / `RxBool` / `RxString` | `ValueNotifier<T>` | `.value` get/set identical |
| `RxList<T>` | `ValueNotifier<List<T>>` or custom `ListNotifier<T>` | Need to replace list, not mutate in-place |
| `RxMap<String, T>` | `ValueNotifier<Map<String, T>>` | Same as above |
| `Obx(() => ...)` | `ValueListenableBuilder<T>` or `ListenableBuilder` | More verbose but explicit |
| `.obs` extension | `ValueNotifier(initialValue)` | Direct constructor |

### Single-Setting Reactivity

```dart
// ValueListenableBuilder (explicit type):
ValueListenableBuilder<int>(
  valueListenable: setting.effectiveNotifier,
  builder: (context, value, _) => Text('Columns: $value'),
)

// Or with convenience wrapper:
SettingBuilder<int>(
  setting: setting,
  builder: (context, value) => Text('Columns: $value'),
)
```

### Multi-Setting Reactivity (no nesting)

```dart
// Listenable.merge + ListenableBuilder (Flutter built-in, recommended):
ListenableBuilder(
  listenable: Listenable.merge([
    settingA.effectiveNotifier,
    settingB.effectiveNotifier,
    settingC.effectiveNotifier,
  ]),
  builder: (context, _) {
    final a = settingA.value;
    final b = settingB.value;
    final c = settingC.value;
    return MyWidget(a: a, b: b, c: c);
  },
)

// Or with convenience wrapper:
MultiSettingBuilder(
  settings: [columnsSetting, previewModeSetting, filterSetting],
  builder: (context) => GridView(
    columns: columnsSetting.value,
    previewMode: previewModeSetting.value,
    filtered: filterSetting.value,
  ),
)
```

### Convenience Widgets

```dart
/// Rebuilds when a single setting's effective value changes
class SettingBuilder<T> extends StatelessWidget {
  const SettingBuilder({required this.setting, required this.builder, super.key});
  final SettingState<T> setting;
  final Widget Function(BuildContext, T) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: setting.effectiveNotifier,
      builder: (context, value, _) => builder(context, value),
    );
  }
}

/// Rebuilds when any of the given settings change
class MultiSettingBuilder extends StatelessWidget {
  const MultiSettingBuilder({
    required this.settings,
    required this.builder,
    super.key,
  });
  final List<SettingState> settings;
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
        settings.map((s) => s.effectiveNotifier).toList(),
      ),
      builder: (context, _) => builder(context),
    );
  }
}
```

---

## Per-Booru Setting Overrides

Settings can have per-booru values that override the global default. Overrides are stored in each booru's config file.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   SettingState<T>                             │
├─────────────────────────────────────────────────────────────┤
│  _globalValue: ValueNotifier<T>        // Global value       │
│  _booruOverrides: ValueNotifier<Map>   // Booru -> override  │
│  def.supportsPerBooru: bool            // Flag from def      │
├─────────────────────────────────────────────────────────────┤
│  value (getter):               // Returns effective value:   │
│    1. Check if current booru has override                    │
│    2. If yes, return override                                │
│    3. If no, return global value                             │
├─────────────────────────────────────────────────────────────┤
│  globalValue: T                // Always returns global      │
│  getOverrideFor(booruId): T?   // Get specific override      │
│  setOverrideFor(booruId, val)  // Set specific override      │
│  removeOverrideFor(booruId)    // Remove (use global)        │
│  hasOverrideFor(booruId): bool // Check if override exists   │
│  effectiveNotifier             // Reactive, recomputes on    │
│                                // booru change or override   │
└─────────────────────────────────────────────────────────────┘
```

### Effective Value Reactivity

The `effectiveNotifier` combines three reactive sources: the global value, the override map, and the current booru. When any changes, widgets rebuild automatically.

```dart
class _EffectiveValueNotifier<T> extends ValueNotifier<T> {
  _EffectiveValueNotifier(this._state) : super(_state._computeEffective()) {
    _state._globalValue.addListener(_recompute);
    _state._booruOverrides.addListener(_recompute);
    SettingsRegistry.instance.currentBooruNotifier.addListener(_recompute);
  }

  final SettingState<T> _state;

  void _recompute() {
    value = _state._computeEffective();
  }

  @override
  void dispose() {
    _state._globalValue.removeListener(_recompute);
    _state._booruOverrides.removeListener(_recompute);
    SettingsRegistry.instance.currentBooruNotifier.removeListener(_recompute);
    super.dispose();
  }
}
```

### Data Flow

```
User changes setting for "Danbooru":
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │ Settings UI  │────►│ SettingState  │────►│ Booru JSON   │
  │ (per-booru)  │     │ setOverride   │     │ Save         │
  └──────────────┘     └──────────────┘     └──────────────┘

User views "Danbooru":
  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
  │ SearchHandler│────►│ SettingState  │────►│ Effective    │
  │ currentBooru │     │   .value      │     │ Value Used   │
  └──────────────┘     └──────────────┘     └──────────────┘
                              │
                              ▼
                       Has override? ─Yes─► Return override
                              │
                              No
                              │
                              ▼
                       Return global value
```

### Storage: Overrides in Booru Config Files

Overrides live in each booru's JSON config file (`boorus/{name}.json`):

```json
{
  "name": "Danbooru",
  "type": "Danbooru",
  "faviconURL": "...",
  "baseURL": "https://danbooru.donmai.us",
  "defTags": "",
  "apiKey": "abc123",
  "userID": "42",
  "settingOverrides": {
    "portraitColumns": 4,
    "previewMode": "thumbnail"
  }
}
```

Global settings file stays flat and unchanged:
```json
{
  "portraitColumns": 2,
  "previewMode": "sample",
  "autoPlayEnabled": true
}
```

**Advantages:**
- Global settings JSON untouched - 100% backwards compatible
- Overrides naturally travel with the booru config
- Deleting a booru deletes its overrides automatically (no orphaned data)
- Old app versions ignore the `settingOverrides` key (graceful degradation)
- No booru ID system needed - overrides are part of the booru object

### Booru Config Updates

```dart
class Booru {
  // ... existing fields ...
  Map<String, dynamic>? settingOverrides;  // NEW

  factory Booru.fromJSON(Map<String, dynamic> json) {
    return Booru(
      // ... existing fields ...
      settingOverrides: json['settingOverrides'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // ... existing fields ...
      if (settingOverrides != null && settingOverrides!.isNotEmpty)
        'settingOverrides': settingOverrides,
    };
  }

  // For sharing: exclude overrides (personal preferences, not needed by recipient)
  Map<String, dynamic> toLinkJson({bool withSensitiveData = false}) {
    final json = toJson();
    json.remove('settingOverrides');  // Never share overrides
    if (!withSensitiveData) {
      json.remove('apiKey');
      json.remove('userID');
    }
    return json;
  }
}
```

### Registry <-> Booru Override Loading/Saving

```dart
// In SettingsRegistry:

/// Load overrides from a booru config into in-memory state
void loadOverridesFromBooru(Booru booru) {
  final overrides = booru.settingOverrides;
  if (overrides == null) return;

  for (final entry in overrides.entries) {
    final state = getByJsonKey(entry.key);
    if (state != null && state.def.supportsPerBooru) {
      state.setOverrideFor(booru.name, state.def.valueFromJson(entry.value));
    }
  }
}

/// Save in-memory overrides back to booru config
void saveOverridesToBooru(Booru booru) {
  final overrides = <String, dynamic>{};
  for (final state in _states.values) {
    if (state.def.supportsPerBooru && state.hasOverrideFor(booru.name)) {
      overrides[state.def.key.jsonKey] = state.def.valueToJson(state.getOverrideFor(booru.name) as dynamic);
    }
  }
  booru.settingOverrides = overrides.isEmpty ? null : overrides;
}

/// Clear in-memory overrides when a booru is deleted
void removeAllOverridesForBooru(String booruName) {
  for (final state in _states.values) {
    if (state.def.supportsPerBooru) {
      state.removeOverrideFor(booruName);
    }
  }
}
```

### Per-Booru Editing Context (No Global State)

Per-booru editing context is passed via `InheritedWidget`, not stored on the singleton registry. This avoids bugs when multiple settings-related routes are on the navigation stack.

```dart
class BooruEditingScope extends InheritedWidget {
  const BooruEditingScope({
    required this.booruName,
    required super.child,
    super.key,
  });

  final String booruName;

  static String? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BooruEditingScope>()?.booruName;
  }

  @override
  bool updateShouldNotify(BooruEditingScope oldWidget) => booruName != oldWidget.booruName;
}
```

Usage in the per-booru settings page:
```dart
class BooruSettingsPage extends StatelessWidget {
  const BooruSettingsPage({required this.booru, super.key});
  final Booru booru;

  @override
  Widget build(BuildContext context) {
    return BooruEditingScope(
      booruName: booru.name,
      child: Scaffold(
        appBar: AppBar(title: Text('${booru.name} Settings')),
        body: _BooruSettingsList(booru: booru),
      ),
    );
  }
}
```

### Settings Likely to Support Per-Booru Overrides

| Setting | Reason |
|---------|--------|
| `portraitColumns` | Different sites may need different grid densities |
| `landscapeColumns` | Same as above |
| `previewMode` | Some sites have better thumbnails than others |
| `limit` | Some sites handle pagination differently |
| `autoPlayEnabled` | May want videos on some sites but not others |
| `startVideosMuted` | Site-specific preference |
| `filterHated` | Different filter preferences per site |
| `defTags` | Default search tags per site |

### Settings That Should Stay Global

| Setting | Reason |
|---------|--------|
| `locale` | Language is app-wide |
| `backupPath` | Storage location is device-specific |
| `useLockscreen` | Security is app-wide |

Theme, theme mode, AMOLED mode, dynamic colors, custom colors, font, and
drawer mascot settings intentionally support per-booru overrides.

---

## Migration Audit Notes

- The pre-migration baseline is commit `9dc6817f^`.
- `hatedTags` and `lovedTags` are load-only aliases for the canonical
  `hiddenTags` and `markedTags` keys.
- `captureLogcat` is an intentional persisted addition.
- `showFps`, `showPerf`, `showImageStats`, and `showVideoStats` are intentional
  transient additions and are not written to `settings.json`.

---

## Current System Analysis

The current system has ~100 settings spread across:
- **SettingsHandler** (2500 lines): Individual member variables, `map` getter, `getByString`/`setByString` with ~100 switch cases each
- **15+ settings pages**: Manual ListView construction with hardcoded widgets
- **settings_widgets.dart** (1469 lines): Reusable widgets (`SettingsToggle`, `SettingsDropdown`, `SettingsSegmentedButton`, `SettingsOptionsList`, `SettingsTextInput`, etc.)
- **SettingsEnum mixin + SettingsEnumRegistry**: Unified serialization for enums (15 types registered). Only used in `validateValue()` - will be replaced by `EnumSetting` (see Phase 2)

---

## Implementation Plan

### Phase 0: Centralized Setting Keys Enum

**New file: `lib/src/data/settings/setting_key.dart`**

All setting keys defined in a single enum for type safety:

```dart
/// Centralized enum for all setting keys.
/// Prevents typos and enables IDE autocomplete.
enum SettingKey {
  // Interface
  portraitColumns,
  landscapeColumns,
  previewMode,
  previewDisplay,
  previewDisplayFallback,
  appMode,
  handSide,
  showBottomSearchbar,
  useTopSearchbarInput,
  showSearchbarQuickActions,
  autofocusSearchbar,
  disableImageScaling,
  gifsAsThumbnails,

  // Viewer
  galleryMode,
  preloadCount,
  preloadSizeLimit,
  autoHideImageBar,
  galleryBarPosition,
  galleryScrollDirection,
  zoomButtonPosition,
  changePageButtonsPosition,
  scrollGridButtonsPosition,
  shareAction,
  buttonOrder,
  disabledButtons,
  allowRotation,
  expandDetails,
  hideNotes,
  enableHeroTransitions,
  disableCustomPageTransitions,
  galleryAutoScrollTime,
  useVolumeButtonsForScroll,
  volumeButtonsScrollSpeed,

  // Video
  disableVideo,
  autoPlayEnabled,
  startVideosMuted,
  longTapFastForwardVideo,
  videoBackendMode,
  videoCacheMode,
  altVideoPlayerHwAccel,
  altVideoPlayerVO,
  altVideoPlayerHWDEC,

  // Theme
  theme,
  themeMode,
  isAmoled,
  useDynamicColor,
  customPrimaryColor,
  customAccentColor,
  fontFamily,
  enableDrawerMascot,
  drawerMascotPathOverride,

  // Cache & Storage
  thumbnailCache,
  mediaCache,
  cacheDuration,
  cacheSize,
  snatchMode,
  snatchCooldown,
  jsonWrite,
  extPathOverride,
  backupPath,

  // Database
  dbEnabled,
  indexesEnabled,
  searchHistoryEnabled,
  tagTypeFetchEnabled,

  // Network
  customUserAgent,
  proxyType,
  proxyAddress,
  proxyUsername,
  proxyPassword,
  allowSelfSignedCerts,

  // Privacy & Filters
  filterHated,
  filterFavourites,
  filterSnatched,
  filterAi,
  useLockscreen,
  blurOnLeave,
  autoLockTimeout,
  incognitoKeyboard,

  // Tags
  defTags,
  hatedTags,
  lovedTags,

  // Other
  prefBooru,
  limit,
  loadingGif,
  wakeLockEnabled,
  downloadNotifications,
  snatchOnFavourite,
  favouriteOnSnatch,
  disableVibration,
  desktopListsDrag,
  mousewheelScrollSpeed,
  locale,
  lastSyncIp,
  lastSyncPort,

  // Debug
  shitDevice,
  isDebug,
  showFps,
  showPerf,
  showImageStats,
  showVideoStats,
  ;

  /// JSON key for serialization (matches existing keys for backwards compatibility)
  String get jsonKey {
    // Most keys match the enum name exactly
    // Add special cases here if needed for backwards compatibility
    switch (this) {
      default:
        return name;
    }
  }
}
```

---

### Phase 1: Core SettingDef + SettingState Classes

**New files:**
- `lib/src/data/settings/setting_def.dart` - Immutable definition
- `lib/src/data/settings/setting_state.dart` - Mutable state

#### SettingDef<T> - Immutable Definition

```dart
import 'package:flutter/widgets.dart';

import 'setting_key.dart';
import 'settings_registry.dart';

/// Immutable definition describing what a setting IS.
/// Separate from SettingState which holds current values.
class SettingDef<T> {
  const SettingDef({
    required this.key,
    required this.getDefaultValue,
    required this.localization,
    required this.valueToJson,
    required this.valueFromJson,
    this.categories = const [],
    this.isDeviceSpecific = false,
    this.supportsPerBooru = false,
    this.validate,
    this.widgetBuilder,
    this.dependsOn,
    this.enabledWhen,
    this.onChanged,
  });

  final SettingKey key;                    // Type-safe enum key
  final T Function() getDefaultValue;      // Dynamic default (platform-specific)
  final SettingLocalization localization;
  final dynamic Function(T) valueToJson;   // Serialize any T value
  final T Function(dynamic) valueFromJson; // Deserialize from JSON
  final List<SettingCategory> categories;  // Can belong to MULTIPLE categories
  final bool isDeviceSpecific;             // Not synced across devices
  final bool supportsPerBooru;             // Can be overridden per booru
  final T Function(T)? validate;           // Validation/clamping
  final Widget Function(BuildContext, SettingState<T>)? widgetBuilder;  // Self-rendering
  final List<SettingKey>? dependsOn;       // Other settings this depends on
  final bool Function()? enabledWhen;      // Dynamic enable condition
  final void Function(T oldValue, T newValue)? onChanged;  // Side effects

  /// JSON key for serialization (from enum)
  String get jsonKey => key.jsonKey;

  /// Get searchable text for global search
  List<String> getSearchableText(BuildContext context) {
    final result = <String>[
      localization.title(context),
    ];
    if (localization.subtitle != null) {
      result.add(localization.subtitle!(context));
    }
    if (localization.searchKeywords != null) {
      result.addAll(localization.searchKeywords!(context));
    }
    for (final category in categories) {
      result.add(category.locName(context));
    }
    return result;
  }
}

/// Localization configuration for a setting.
/// All functions take BuildContext for access to slang's context.loc.*
class SettingLocalization {
  const SettingLocalization({
    required this.title,
    this.subtitle,
    this.helpText,
    this.searchKeywords,
  });

  final String Function(BuildContext) title;
  final String Function(BuildContext)? subtitle;
  final String Function(BuildContext)? helpText;
  final List<String> Function(BuildContext)? searchKeywords;
}

/// Widget configuration for a setting
class SettingWidgetConfig {
  const SettingWidgetConfig({
    this.leadingIcon,
    this.trailingIcon,
    this.helpDialog,
  });

  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final Widget Function(BuildContext)? helpDialog;
}
```

#### SettingState<T> - Mutable State

```dart
import 'package:flutter/foundation.dart';

import 'setting_def.dart';
import 'settings_registry.dart';

/// Mutable state holding a setting's current value(s).
/// Created by SettingsRegistry when a SettingDef is registered.
class SettingState<T> {
  SettingState(this.def)
    : _globalValue = ValueNotifier<T>(def.getDefaultValue()),
      _booruOverrides = ValueNotifier<Map<String, T>>({});

  final SettingDef<T> def;
  final ValueNotifier<T> _globalValue;
  final ValueNotifier<Map<String, T>> _booruOverrides;

  /// Reactive notifier for the effective value (considers current booru override).
  /// Widgets should listen to this, not _globalValue directly.
  late final ValueNotifier<T> effectiveNotifier = _createEffectiveNotifier();

  // ============================================
  // VALUE ACCESS
  // ============================================

  /// Get the effective value (considers current booru override)
  T get value => effectiveNotifier.value;

  /// Set the global value (or override if editing per-booru via InheritedWidget)
  set value(T newValue) {
    final validated = def.validate?.call(newValue) ?? newValue;
    final oldValue = _globalValue.value;
    _globalValue.value = validated;
    if (oldValue != validated) {
      def.onChanged?.call(oldValue, validated);
    }
  }

  /// Always get/set the global value (ignoring overrides)
  T get globalValue => _globalValue.value;
  set globalValue(T newValue) {
    _globalValue.value = def.validate?.call(newValue) ?? newValue;
  }

  /// Convenience getter for current default
  T get defaultValue => def.getDefaultValue();

  /// Check if value differs from default
  bool get isModified => globalValue != def.getDefaultValue();

  /// Reset to default value
  void reset() {
    value = def.getDefaultValue();
  }

  // ============================================
  // PER-BOORU OVERRIDE MANAGEMENT
  // ============================================

  bool hasOverrideFor(String booruName) => _booruOverrides.value.containsKey(booruName);

  T? getOverrideFor(String booruName) => _booruOverrides.value[booruName];

  void setOverrideFor(String booruName, T val) {
    final validated = def.validate?.call(val) ?? val;
    final map = Map<String, T>.from(_booruOverrides.value);
    map[booruName] = validated;
    _booruOverrides.value = map;  // Triggers notification
  }

  void removeOverrideFor(String booruName) {
    if (!_booruOverrides.value.containsKey(booruName)) return;
    final map = Map<String, T>.from(_booruOverrides.value);
    map.remove(booruName);
    _booruOverrides.value = map;  // Triggers notification
  }

  Iterable<String> get boorusWithOverrides => _booruOverrides.value.keys;

  void clearAllOverrides() {
    _booruOverrides.value = {};
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  dynamic toJson() => def.valueToJson(globalValue);

  void loadFromJson(dynamic json) {
    _globalValue.value = def.valueFromJson(json);
  }

  // ============================================
  // WIDGET
  // ============================================

  Widget buildWidget(BuildContext context) {
    return def.widgetBuilder?.call(context, this) ?? const SizedBox.shrink();
  }

  // ============================================
  // EFFECTIVE VALUE COMPUTATION
  // ============================================

  T _computeEffective() {
    if (!def.supportsPerBooru) return _globalValue.value;

    final currentBooruName = SettingsRegistry.instance.currentBooruName;
    if (currentBooruName != null && _booruOverrides.value.containsKey(currentBooruName)) {
      return _booruOverrides.value[currentBooruName]!;
    }
    return _globalValue.value;
  }

  ValueNotifier<T> _createEffectiveNotifier() {
    return _EffectiveValueNotifier<T>(this);
  }
}

/// Custom notifier that recomputes when any dependency changes.
class _EffectiveValueNotifier<T> extends ValueNotifier<T> {
  _EffectiveValueNotifier(this._state) : super(_state._computeEffective()) {
    _state._globalValue.addListener(_recompute);
    _state._booruOverrides.addListener(_recompute);
    SettingsRegistry.instance.currentBooruNotifier.addListener(_recompute);
  }

  final SettingState<T> _state;

  void _recompute() {
    value = _state._computeEffective();
  }

  @override
  void dispose() {
    _state._globalValue.removeListener(_recompute);
    _state._booruOverrides.removeListener(_recompute);
    SettingsRegistry.instance.currentBooruNotifier.removeListener(_recompute);
    super.dispose();
  }
}
```

---

### Phase 2: Typed Setting Factories

**New file: `lib/src/data/settings/typed_settings.dart`**

Instead of subclasses, use factory functions that create `SettingDef<T>` with appropriate serialization and widget builders.

#### Basic Types

| Factory | For | Key Features |
|---------|-----|--------------|
| `boolSetting()` | Boolean toggles | Renders `SettingsToggle` |
| `intSetting()` | Integer values | `min`, `max`, `step`; Renders `SettingsTextInput` with number buttons |
| `doubleSetting()` | Decimal values | `min`, `max`, `step` |
| `stringSetting()` | Text inputs | `obscurable`, `copyable`, `pasteable` |
| `enumSetting<T>()` | Enum dropdowns | `displayMode` (dropdown/optionsList/segmented) |
| `colorSetting()` | Color picker | Custom picker widget |
| `durationSetting()` | Duration selection | Dropdown with predefined options |
| `stringListSetting()` | Lists | Custom list editor |
| `tagListSetting()` | Tag lists | Custom fromJson/toJson with Tag cleansing |

#### Example: boolSetting

```dart
SettingDef<bool> boolSetting({
  required SettingKey key,
  required bool Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function()? enabledWhen,
  void Function(bool, bool)? onChanged,
}) {
  return SettingDef<bool>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is bool) return json;
      if (json is String) {
        if (json == 'true') return true;
        if (json == 'false') return false;
      }
      return getDefaultValue();
    },
    widgetBuilder: (context, state) => SettingBuilder<bool>(
      setting: state,
      builder: (ctx, value) => SettingsToggle(
        title: localization.title(ctx),
        subtitle: localization.subtitle?.call(ctx),
        value: value,
        onChanged: enabledWhen?.call() ?? true
          ? (newValue) => state.value = newValue
          : null,
        leadingIcon: widgetConfig?.leadingIcon,
      ),
    ),
  );
}
```

#### Example: intSetting

```dart
SettingDef<int> intSetting({
  required SettingKey key,
  required int Function() getDefaultValue,
  required SettingLocalization localization,
  required int min,
  required int max,
  int step = 1,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function()? enabledWhen,
  void Function(int, int)? onChanged,
}) {
  int validate(int value) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  return SettingDef<int>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    validate: validate,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      final int? parsed = json is String ? int.tryParse(json) : (json is int ? json : null);
      if (parsed == null) return getDefaultValue();
      return validate(parsed);
    },
    widgetBuilder: (context, state) => SettingBuilder<int>(
      setting: state,
      builder: (ctx, value) => SettingsTextInput(
        title: localization.title(ctx),
        subtitle: localization.subtitle?.call(ctx),
        inputType: TextInputType.number,
        value: value.toString(),
        onChanged: (newValue) {
          final parsed = int.tryParse(newValue);
          if (parsed != null) state.value = parsed;
        },
        trailingWidgets: [
          NumberStepper(
            value: value,
            min: min,
            max: max,
            step: step,
            onChanged: (newValue) => state.value = newValue,
          ),
        ],
      ),
    ),
  );
}
```

#### Example: enumSetting

```dart
enum EnumDisplayMode { dropdown, optionsList, segmented }

SettingDef<T> enumSetting<T extends Enum>({
  required SettingKey key,
  required T Function() getDefaultValue,
  required SettingLocalization localization,
  required List<T> values,
  required T Function(String) fromString,
  required String Function(T) enumToJson,
  required String Function(BuildContext, T) enumLocName,
  EnumDisplayMode displayMode = EnumDisplayMode.dropdown,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  List<SettingKey>? dependsOn,
  bool Function()? enabledWhen,
  void Function(T, T)? onChanged,
}) {
  return SettingDef<T>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => enumToJson(v),
    valueFromJson: (json) {
      if (json is String) {
        try { return fromString(json); } catch (_) {}
      }
      return getDefaultValue();
    },
    // searchKeywords should also include enum option labels for better search
    // (override localization.searchKeywords to include them)
    widgetBuilder: (context, state) {
      switch (displayMode) {
        case EnumDisplayMode.dropdown:
          return SettingBuilder<T>(
            setting: state,
            builder: (ctx, value) => SettingsDropdown<T>(
              title: localization.title(ctx),
              value: value,
              items: values,
              itemLabelBuilder: (item) => enumLocName(ctx, item),
              onChanged: (newValue) {
                if (newValue != null) state.value = newValue;
              },
            ),
          );
        case EnumDisplayMode.optionsList:
          return SettingBuilder<T>(
            setting: state,
            builder: (ctx, value) => SettingsOptionsList<T>(
              title: localization.title(ctx),
              value: value,
              items: values,
              itemLabelBuilder: (item) => enumLocName(ctx, item),
              onChanged: (newValue) => state.value = newValue,
            ),
          );
        case EnumDisplayMode.segmented:
          return SettingBuilder<T>(
            setting: state,
            builder: (ctx, value) => SettingsSegmented<T>(
              title: localization.title(ctx),
              value: value,
              items: values,
              itemLabelBuilder: (item) => enumLocName(ctx, item),
              onChanged: (newValue) => state.value = newValue,
            ),
          );
      }
    },
  );
}
```

#### Special Type Factories

**New file: `lib/src/data/settings/special_settings.dart`**

| Factory | For | Key Features |
|---------|-----|--------------|
| `themeModeSetting()` | System/Light/Dark | Uses Flutter's `ThemeMode`, segmented display |
| `localeSetting()` | App language | Uses `AppLocale`, shows native language names |
| `fontFamilySetting()` | Font selection | Custom dropdown with font previews |
| `tagListSetting()` | Tag lists | Custom fromJson/toJson with Tag object cleansing |
| `buttonOrderSetting()` | Reorderable button list | Drag-to-reorder UI, flexible parsing (string or array) |
| `pathPickerSetting()` | Directory pickers | Triggers SAF picker flow on tap |

#### Example: tagListSetting

```dart
SettingDef<List<Tag>> tagListSetting({
  required SettingKey key,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  // ...
}) {
  return SettingDef<List<Tag>>(
    key: key,
    getDefaultValue: () => [],
    localization: localization,
    categories: categories,
    valueToJson: (tags) => tags.map((t) => t.fullString).toList(),
    valueFromJson: (json) {
      if (json is List) {
        return json.map((e) => Tag.fromString(e.toString())).toList();
      }
      if (json is String && json.isNotEmpty) {
        return json.split(' ').map((e) => Tag.fromString(e)).toList();
      }
      return [];
    },
    widgetBuilder: (context, state) => TagListEditor(
      tags: state.value,
      onChanged: (tags) => state.value = tags,
    ),
  );
}
```

#### EnumSetting replaces SettingsEnumRegistry

The `SettingsEnumRegistry` is only used in `validateValue()` in `settings_handler.dart`. Once all enums are registered as `enumSetting()` instances, the registry is redundant:
- `isRegistered(typeName)` → `SettingsRegistry.instance.get(key) != null`
- `validate(typeName, value, default, toJSON)` → `state.def.valueFromJson(value)` / `state.def.valueToJson(value)`

**Migration:** Remove `SettingsEnumRegistry` and `initSettingsEnumRegistry()` once all enum settings are registered.

---

### Phase 3: SettingsRegistry

**New file: `lib/src/data/settings/settings_registry.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'setting_def.dart';
import 'setting_state.dart';
import 'setting_key.dart';

class SettingsRegistry {
  SettingsRegistry._();
  static final SettingsRegistry instance = SettingsRegistry._();

  final Map<SettingKey, SettingState> _states = {};

  /// Current booru context (set by SearchHandler when booru changes)
  final ValueNotifier<String?> currentBooruNotifier = ValueNotifier(null);
  String? get currentBooruName => currentBooruNotifier.value;
  void setCurrentBooru(String? booruName) {
    currentBooruNotifier.value = booruName;
  }

  void register<T>(SettingDef<T> def) {
    _states[def.key] = SettingState<T>(def);
  }

  /// Get state by enum key (type-safe)
  SettingState<T>? get<T>(SettingKey key) => _states[key] as SettingState<T>?;

  /// Get state by string key (for backwards compatibility with JSON)
  SettingState? getByJsonKey(String jsonKey) {
    return _states.values.firstWhereOrNull((s) => s.def.jsonKey == jsonKey);
  }

  Iterable<SettingState> get all => _states.values;

  /// Get all states that belong to this category (supports multi-category)
  List<SettingState> byCategory(SettingCategory category) {
    return _states.values.where((s) => s.def.categories.contains(category)).toList();
  }

  /// Get visible categories (respects visibleWhen condition)
  List<SettingCategory> get visibleCategories {
    return SettingCategory.values.where((c) => c.visibleWhen?.call() ?? true).toList();
  }

  /// Get device-specific settings
  List<SettingState> get deviceSpecific {
    return _states.values.where((s) => s.def.isDeviceSpecific).toList();
  }

  /// Get syncable settings (not device-specific)
  List<SettingState> get syncable {
    return _states.values.where((s) => !s.def.isDeviceSpecific).toList();
  }

  /// Get all settings that support per-booru overrides
  List<SettingState> get perBooruSettings {
    return _states.values.where((s) => s.def.supportsPerBooru).toList();
  }

  // ============================================
  // SEARCH (simple substring matching)
  // ============================================

  /// Search settings by query. Uses simple substring matching on
  /// localized titles, subtitles, keywords, and category names.
  /// No caching needed - fast enough for ~100 settings.
  /// Locale-safe: always uses current context for localized strings.
  List<SettingState> search(String query, BuildContext context) {
    if (query.isEmpty) return [];

    final queryLower = query.toLowerCase();
    return _states.values.where((state) {
      final searchable = state.def.getSearchableText(context);
      return searchable.any((text) => text.toLowerCase().contains(queryLower));
    }).toList();
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Convert to JSON for saving
  Map<String, dynamic> toJson() {
    return Map.fromEntries(
      _states.values.map((s) => MapEntry(s.def.jsonKey, s.toJson())),
    );
  }

  /// Load from JSON
  void loadFromJson(Map<String, dynamic> json) {
    for (final entry in json.entries) {
      final state = getByJsonKey(entry.key);
      state?.loadFromJson(entry.value);
    }
  }

  /// Reset all settings to defaults
  void resetAll() {
    for (final state in _states.values) {
      state.reset();
    }
  }

  /// Reset settings in a category
  void resetCategory(SettingCategory category) {
    for (final state in byCategory(category)) {
      state.reset();
    }
  }

  // ============================================
  // PER-BOORU OVERRIDE MANAGEMENT
  // ============================================

  void loadOverridesFromBooru(Booru booru) {
    final overrides = booru.settingOverrides;
    if (overrides == null) return;

    for (final entry in overrides.entries) {
      final state = getByJsonKey(entry.key);
      if (state != null && state.def.supportsPerBooru) {
        state.setOverrideFor(booru.name, state.def.valueFromJson(entry.value));
      }
    }
  }

  void saveOverridesToBooru(Booru booru) {
    final overrides = <String, dynamic>{};
    for (final state in _states.values) {
      if (state.def.supportsPerBooru && state.hasOverrideFor(booru.name)) {
        final overrideValue = state.getOverrideFor(booru.name);
        if (overrideValue != null) {
          overrides[state.def.key.jsonKey] = state.def.valueToJson(overrideValue);
        }
      }
    }
    booru.settingOverrides = overrides.isEmpty ? null : overrides;
  }

  void removeAllOverridesForBooru(String booruName) {
    for (final state in _states.values) {
      if (state.def.supportsPerBooru) {
        state.removeOverrideFor(booruName);
      }
    }
  }

  void copyOverrides(String fromBooruName, String toBooruName) {
    for (final state in perBooruSettings) {
      final override = state.getOverrideFor(fromBooruName);
      if (override != null) {
        state.setOverrideFor(toBooruName, override);
      }
    }
  }
}

/// Categories for organizing settings.
/// Registration order within a category determines display order.
enum SettingCategory {
  language,
  booru,
  interface,
  theme,
  viewer,
  video,
  cache,
  tagsFilters,
  database,
  backup,
  network,
  privacy,
  performance,
  debug;

  String locName(BuildContext context) {
    switch (this) {
      case SettingCategory.language:
        return context.loc.settings.language.title;
      case SettingCategory.booru:
        return context.loc.settings.booru.title;
      case SettingCategory.interface:
        return context.loc.settings.interface.title;
      case SettingCategory.theme:
        return context.loc.settings.theme.title;
      case SettingCategory.viewer:
        return context.loc.settings.gallery.title;
      case SettingCategory.video:
        return context.loc.settings.video.title;
      case SettingCategory.cache:
        return context.loc.settings.snatching.title;
      case SettingCategory.tagsFilters:
        return context.loc.settings.tags.title;
      case SettingCategory.database:
        return context.loc.settings.database.title;
      case SettingCategory.backup:
        return context.loc.settings.backup.title;
      case SettingCategory.network:
        return context.loc.settings.network.title;
      case SettingCategory.privacy:
        return context.loc.settings.privacy.title;
      case SettingCategory.performance:
        return context.loc.settings.performance.title;
      case SettingCategory.debug:
        return context.loc.settings.debug.title;
    }
  }

  IconData get icon {
    switch (this) {
      case SettingCategory.language:
        return Icons.language;
      case SettingCategory.booru:
        return Icons.public;
      case SettingCategory.interface:
        return Icons.view_module;
      case SettingCategory.theme:
        return Icons.palette;
      case SettingCategory.viewer:
        return Icons.image;
      case SettingCategory.video:
        return Icons.videocam;
      case SettingCategory.cache:
        return Icons.download;
      case SettingCategory.tagsFilters:
        return Icons.label;
      case SettingCategory.database:
        return Icons.storage;
      case SettingCategory.backup:
        return Icons.backup;
      case SettingCategory.network:
        return Icons.wifi;
      case SettingCategory.privacy:
        return Icons.security;
      case SettingCategory.performance:
        return Icons.speed;
      case SettingCategory.debug:
        return Icons.bug_report;
    }
  }

  /// Visibility condition - category hidden if returns false.
  /// Returns null if always visible.
  bool Function()? get visibleWhen {
    switch (this) {
      case SettingCategory.debug:
        return () => kDebugMode || SettingKey.isDebug.value() == true;
      default:
        return null;
    }
  }
}
```

---

### Phase 4: Settings Definitions

**New file: `lib/src/data/settings/all_settings.dart`**

Declarative definition of all ~100 settings:

```dart
void registerAllSettings() {
  final registry = SettingsRegistry.instance;

  // ============================================
  // INTERFACE SETTINGS
  // ============================================

  registry.register(intSetting(
    key: SettingKey.portraitColumns,
    getDefaultValue: () => SettingsHandler.isDesktopPlatform ? 5 : 2,
    min: 1, max: 100, step: 1,
    categories: [SettingCategory.interface],
    supportsPerBooru: true,  // Per-booru support!
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewColumnsPortrait,
      searchKeywords: (ctx) => [ctx.loc.search.columns, ctx.loc.search.grid],
    ),
  ));

  registry.register(intSetting(
    key: SettingKey.landscapeColumns,
    getDefaultValue: () => SettingsHandler.isDesktopPlatform ? 7 : 4,
    min: 1, max: 100, step: 1,
    categories: [SettingCategory.interface],
    supportsPerBooru: true,
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewColumnsLandscape,
      searchKeywords: (ctx) => [ctx.loc.search.columns, ctx.loc.search.grid],
    ),
  ));

  registry.register(enumSetting<PreviewQuality>(
    key: SettingKey.previewMode,
    getDefaultValue: () => PreviewQuality.defaultValue,
    values: PreviewQuality.values,
    fromString: PreviewQuality.fromString,
    enumToJson: (v) => v.toJson(),
    enumLocName: (ctx, v) => v.locName(ctx),
    displayMode: EnumDisplayMode.optionsList,
    categories: [SettingCategory.interface],
    supportsPerBooru: true,
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewQuality,
      searchKeywords: (ctx) => [ctx.loc.search.preview, ctx.loc.search.quality],
    ),
  ));

  // ============================================
  // VIDEO SETTINGS
  // ============================================

  registry.register(boolSetting(
    key: SettingKey.disableVideo,
    getDefaultValue: () => false,
    categories: [SettingCategory.video],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.video.disableVideo,
    ),
  ));

  registry.register(boolSetting(
    key: SettingKey.autoPlayEnabled,
    getDefaultValue: () => true,
    categories: [SettingCategory.video],
    supportsPerBooru: true,
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.video.autoplayVideos,
      searchKeywords: (ctx) => [ctx.loc.search.video, ctx.loc.search.autoplay],
    ),
    dependsOn: [SettingKey.disableVideo],
    enabledWhen: () => !SettingsRegistry.instance.get<bool>(SettingKey.disableVideo)!.value,
  ));

  // ============================================
  // VIEWER SETTINGS (multi-category example)
  // ============================================

  registry.register(boolSetting(
    key: SettingKey.enableHeroTransitions,
    getDefaultValue: () => true,
    categories: [SettingCategory.viewer, SettingCategory.performance],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.viewer.enableHeroTransitions,
      searchKeywords: (ctx) => [ctx.loc.search.animation, ctx.loc.search.transition],
    ),
  ));

  // ============================================
  // THEME SETTINGS (with onChanged side effect)
  // ============================================

  registry.register(themeModeSetting(
    key: SettingKey.themeMode,
    getDefaultValue: () => ThemeMode.system,
    categories: [SettingCategory.theme],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.theme.themeMode,
    ),
    onChanged: (oldMode, newMode) {
      // Side effect: trigger app theme rebuild
      // SettingsHandler or ThemeController handles this
    },
  ));

  registry.register(boolSetting(
    key: SettingKey.isAmoled,
    getDefaultValue: () => false,
    categories: [SettingCategory.theme],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.theme.amoled,
    ),
  ));

  // ============================================
  // TAGS (custom type with Tag cleansing)
  // ============================================

  registry.register(tagListSetting(
    key: SettingKey.hatedTags,
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.tags.hatedTags,
    ),
    categories: [SettingCategory.tagsFilters],
    supportsPerBooru: true,
  ));

  // ... continue with all other settings
}
```

---

### Phase 5: Auto-Rendering Settings Pages

**New file: `lib/src/widgets/settings/auto_settings_page.dart`**

```dart
class AutoSettingsPage extends StatelessWidget {
  const AutoSettingsPage({
    super.key,
    this.category,
    this.items,
    this.settingBuilder,
  }) : assert(category != null || items != null);

  final SettingCategory? category;
  /// Mixed list of SettingState and Widget items for flexible page composition.
  /// Use this for pages with non-setting widgets (action buttons, info text, etc.)
  final List<dynamic>? items;
  final Widget Function(BuildContext, SettingState, int, int)? settingBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(category?.locName(context) ?? 'Settings'),
      ),
      body: _SettingsListView(
        category: category,
        items: items,
        settingBuilder: settingBuilder,
      ),
    );
  }
}

/// Separate widget so filtering can be reactive (rebuilds when dependencies change).
class _SettingsListView extends StatelessWidget {
  const _SettingsListView({
    this.category,
    this.items,
    this.settingBuilder,
  });

  final SettingCategory? category;
  final List<dynamic>? items;
  final Widget Function(BuildContext, SettingState, int, int)? settingBuilder;

  List<dynamic> _getItems() {
    if (items != null) return items!;
    return SettingsRegistry.instance.byCategory(category!);
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _getItems();

    // For reactive filtering: wrap in ListenableBuilder listening to
    // all dependency settings so enabledWhen re-evaluates on change
    return ListenableBuilder(
      listenable: Listenable.merge(
        allItems
          .whereType<SettingState>()
          .expand((s) => (s.def.dependsOn ?? [])
            .map((key) => SettingsRegistry.instance.get(key)?.effectiveNotifier)
            .whereType<Listenable>())
          .toSet()
          .toList(),
      ),
      builder: (context, _) {
        // Filter: only show enabled settings (dynamic, re-evaluated on rebuild)
        final visibleItems = allItems.where((item) {
          if (item is SettingState) {
            return item.def.enabledWhen?.call() ?? true;
          }
          return true; // Non-setting widgets always shown
        }).toList();

        return ListView.builder(
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final item = visibleItems[index];

            // Non-setting widget: render directly
            if (item is Widget) return item;

            // Setting: use custom builder or default
            final setting = item as SettingState;
            if (settingBuilder != null) {
              return settingBuilder!(context, setting, index, visibleItems.length);
            }
            return _defaultSettingBuilder(context, setting, index);
          },
        );
      },
    );
  }

  Widget _defaultSettingBuilder(BuildContext context, SettingState setting, int index) {
    return Column(
      children: [
        if (index == 0) const Divider(height: 1),
        setting.buildWidget(context),
        const Divider(height: 1),
      ],
    );
  }
}
```

---

### Phase 6: Global Settings Search

**New file: `lib/src/widgets/settings/settings_search_page.dart`**

```dart
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<SettingState> _results = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text);
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    // No index caching - simple substring search is fast for ~100 settings
    // and automatically uses current locale (no invalidation needed)
    setState(() {
      _results = SettingsRegistry.instance.search(query, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.loc.settings.search.hint,
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() => _results = []);
              },
            ),
        ],
      ),
      body: _results.isEmpty
          ? Center(
              child: Text(
                _searchController.text.isEmpty
                    ? context.loc.settings.search.startTyping
                    : context.loc.settings.search.noResults,
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final state = _results[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badges
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Wrap(
                        spacing: 4,
                        children: state.def.categories.map((cat) {
                          return Chip(
                            label: Text(
                              cat.locName(context),
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ),
                    // Per-booru override indicator
                    if (state.def.supportsPerBooru &&
                        SettingsRegistry.instance.currentBooruName != null &&
                        state.hasOverrideFor(SettingsRegistry.instance.currentBooruName!))
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune, size: 14, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Custom value for current booru',
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    // Setting widget
                    state.buildWidget(context),
                    const Divider(),
                  ],
                );
              },
            ),
    );
  }
}
```

### Search: Enum Option Names

For enum settings, `getSearchableText` should also include the localized names of all enum options. This way searching "dark" finds `themeMode`. This is handled in the `enumSetting()` factory by overriding `searchKeywords` to include option labels:

```dart
// In enumSetting() factory, augment searchKeywords:
localization: SettingLocalization(
  title: localization.title,
  subtitle: localization.subtitle,
  helpText: localization.helpText,
  searchKeywords: (ctx) {
    final base = localization.searchKeywords?.call(ctx) ?? [];
    final optionNames = values.map((v) => enumLocName(ctx, v)).toList();
    return [...base, ...optionNames];
  },
),
```

---

### Phase 7: Per-Booru Settings Page

```dart
class BooruSettingsPage extends StatelessWidget {
  const BooruSettingsPage({required this.booru, super.key});
  final Booru booru;

  @override
  Widget build(BuildContext context) {
    return BooruEditingScope(
      booruName: booru.name,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${booru.name} Settings'),
        ),
        body: _BooruSettingsList(booru: booru),
      ),
    );
  }
}

class _BooruSettingsList extends StatelessWidget {
  const _BooruSettingsList({required this.booru});
  final Booru booru;

  @override
  Widget build(BuildContext context) {
    final perBooruSettings = SettingsRegistry.instance.perBooruSettings;

    return ListView.builder(
      itemCount: perBooruSettings.length,
      itemBuilder: (context, index) {
        final state = perBooruSettings[index];
        final hasOverride = state.hasOverrideFor(booru.name);

        return Column(
          children: [
            // Override toggle
            SwitchListTile(
              title: Text(state.def.localization.title(context)),
              subtitle: Text(hasOverride
                  ? 'Custom value for ${booru.name}'
                  : 'Using global value'),
              value: hasOverride,
              onChanged: (enabled) {
                if (enabled) {
                  state.setOverrideFor(booru.name, state.globalValue);
                } else {
                  state.removeOverrideFor(booru.name);
                }
              },
            ),
            // Setting widget (only editable if override enabled)
            if (hasOverride)
              state.buildWidget(context),
            const Divider(),
          ],
        );
      },
    );
  }
}
```

---

### Phase 8: Bridge with Existing System

Modify `lib/src/handlers/settings_handler.dart` for gradual migration:

```dart
class SettingsHandler extends GetxController {
  // ... existing code ...

  final SettingsRegistry _registry = SettingsRegistry.instance;

  @override
  void onInit() {
    super.onInit();
    registerAllSettings();
    // ... existing init code ...
  }

  // Bridge methods - delegate to registry
  dynamic getByString(String varName) {
    final state = _registry.getByJsonKey(varName);
    if (state != null) return state.value;
    return _legacyGetByString(varName);  // Fallback
  }

  void setByString(String varName, dynamic value) {
    final state = _registry.getByJsonKey(varName);
    if (state != null) {
      state.loadFromJson(value);
      return;
    }
    _legacySetByString(varName, value);  // Fallback
  }

  // Validation now delegates to setting's own validation
  dynamic validateValue(String varName, dynamic value, {bool toJSON = false}) {
    final state = _registry.getByJsonKey(varName);
    if (state != null) {
      if (toJSON) return state.def.valueToJson(value);
      return state.def.valueFromJson(value);
    }
    return _legacyValidateValue(varName, value, toJSON: toJSON);
  }

  // Override loading to also load per-booru overrides
  Future<void> loadBoorus() async {
    // ... existing booru loading logic ...
    // After loading all boorus:
    for (final booru in booruList) {
      _registry.loadOverridesFromBooru(booru);
    }
  }

  // Override saving to also save per-booru overrides
  Future<void> saveBooru(Booru booru) async {
    _registry.saveOverridesToBooru(booru);
    // ... existing save logic ...
  }

  // Override deletion to clear overrides
  Future<void> deleteBooru(Booru booru) async {
    _registry.removeAllOverridesForBooru(booru.name);
    // ... existing delete logic ...
  }

  // Keep legacy methods during migration
  dynamic _legacyGetByString(String varName) { /* ... */ }
  void _legacySetByString(String varName, dynamic value) { /* ... */ }
  dynamic _legacyValidateValue(String varName, dynamic value, {bool toJSON = false}) { /* ... */ }
}
```

---

## File Structure

```
lib/src/data/settings/
  setting_key.dart              # Centralized enum for all setting keys
  setting_def.dart              # SettingDef<T> - immutable definition
  setting_state.dart            # SettingState<T> - mutable state
  typed_settings.dart           # boolSetting(), intSetting(), enumSetting(), etc.
  special_settings.dart         # themeModeSetting(), tagListSetting(), pathPickerSetting(), etc.
  settings_registry.dart        # SettingsRegistry + SettingCategory
  all_settings.dart             # All setting definitions

  # Keep existing (until migration complete):
  settings_enum.dart            # SettingsEnum mixin (remove after migration)
  preview_quality.dart          # Enum definition (keep)
  ... (other enum files)

lib/src/widgets/settings/
  auto_settings_page.dart       # Auto-rendering page (supports mixed Setting/Widget items)
  settings_search_page.dart     # Global search
  setting_builder.dart          # SettingBuilder<T> + MultiSettingBuilder convenience widgets
  booru_editing_scope.dart      # BooruEditingScope InheritedWidget
  booru_settings_page.dart      # Per-booru settings page
```

---

## Migration Strategy

### Step 1: Create Infrastructure (Non-Breaking)
1. Create `setting_key.dart` with all setting keys
2. Create `SettingDef<T>` and `SettingState<T>`
3. Create typed setting factories
4. Create `SettingsRegistry`
5. Create `SettingBuilder`, `MultiSettingBuilder`, `BooruEditingScope`
6. Create `AutoSettingsPage` and `SettingsSearchPage`
7. Call `registerAllSettings()` at app startup
8. Add `settingOverrides` field to `Booru` class

### Step 2: Add Search Feature
1. Add search button to main settings page
2. Link to `SettingsSearchPage`
3. Users can now search all settings

### Step 3: Gradual Page Migration
Migrate one page at a time (e.g., start with `GalleryPage`):
```dart
// OLD: 650 lines of manual widget construction
// NEW: ~20 lines
class GalleryPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AutoSettingsPage(category: SettingCategory.viewer);
  }
}

// For pages with non-setting widgets (action buttons, info text):
class SaveCachePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AutoSettingsPage(
      category: SettingCategory.cache,
      items: [
        ...SettingsRegistry.instance.byCategory(SettingCategory.cache),
        // Action buttons mixed in with settings
        SettingsButton(
          title: context.loc.settings.cache.clearCache,
          icon: Icons.delete,
          onTap: () => _clearCache(context),
        ),
        CacheInfoWidget(),  // Custom info display
      ],
    );
  }
}
```

### Step 4: Remove Legacy Code (Final)
Once all pages migrated:
- Remove individual member variables from SettingsHandler
- Remove `getByString`/`setByString` switch statements
- Remove `deviceSpecificSettings` list (use `isDeviceSpecific` flag)
- Remove `SettingsEnumRegistry` and `initSettingsEnumRegistry()`
- Remove `validateValue` method (each setting validates itself)

---

## Localization Notes

- The app uses **slang** package with `context.loc.settings.*` access pattern
- `SettingLocalization` uses `(BuildContext) => String` functions - fully compatible with slang
- Locale changes trigger a full app rebuild via `TranslationProvider`, so all setting strings re-evaluate automatically
- Search uses no cached index - simple substring matching re-evaluates with current locale on every search
- **New i18n keys needed** in `assets/i18n/*.json`:
  - `settings.search.hint` - Search field placeholder
  - `settings.search.startTyping` - Empty state message
  - `settings.search.noResults` - No results message
  - Various `search.*` keywords for setting searchability

---

## Backwards Compatibility

- **JSON format**: Global settings use same flat keys and values - no migration needed
- **Per-booru overrides**: Stored in booru config files, old versions ignore the new `settingOverrides` key
- **API**: `settingsHandler.autoHideImageBar` works via bridge during migration
- **Sync**: `isDeviceSpecific` flag replaces `deviceSpecificSettings` list
- **Sharing**: `toLinkJson()` excludes `settingOverrides` - recipients use their own global defaults

---

## Verification

1. `flutter analyze` - no errors
2. App loads existing settings.json correctly (flat format unchanged)
3. Changing a setting persists correctly
4. Fresh install uses correct defaults (including platform-specific dynamic defaults)
5. Search finds settings by title, keyword, category name, and enum option names
6. Search works correctly after switching locale
7. AutoSettingsPage renders all settings in category
8. Conditional settings show/hide dynamically when dependencies change
9. Per-booru overrides save to booru config files
10. Per-booru overrides load correctly from booru config files
11. Sharing a booru config does NOT include setting overrides
12. Deleting a booru clears its in-memory overrides
13. `onChanged` callbacks fire for theme/locale/DB settings
14. Multiple settings pages on nav stack don't conflict (no global editing state)
