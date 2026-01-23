# Dynamic Settings System - Implementation Plan

## Overview

Create a unified dynamic settings system where all properties and functions of a setting are combined in a single class. This enables:
- Global search through all settings
- Auto-rendered settings pages based on setting definitions
- Type-safe setting management with reactive updates
- Reduced boilerplate when adding new settings

## Key Design Decisions

1. **Multiple categories**: A setting can belong to multiple categories (e.g., `enableHeroTransitions` in both `viewer` and `performance`)
2. **Localized search keywords**: `searchKeywords` is a context-dependent function `(BuildContext) => List<String>` for proper localization
3. **Border handling in page builder**: `drawTopBorder`/`drawBottomBorder` removed from `SettingWidgetConfig` - handled by `AutoSettingsPage.settingBuilder`
4. **Special setting types**: Dedicated classes for `Theme`, `ThemeMode`, `Locale`, `FontFamily` etc.
5. **Category visibility**: Categories have optional `visibleWhen` function to hide entire sections (e.g., debug settings hidden in release)
6. **Dynamic default values**: `defaultValue` is a function `() => T` to support platform-specific defaults (e.g., different column counts for desktop vs mobile)

---

## Current System Analysis

The current system has ~100 settings spread across:
- **SettingsHandler** (2500 lines): Individual member variables, `map` getter, `getByString`/`setByString` with ~100 switch cases each
- **15+ settings pages**: Manual ListView construction with hardcoded widgets
- **settings_widgets.dart**: Reusable widgets (`SettingsToggle`, `SettingsDropdown`, etc.)
- **SettingsEnum mixin**: Unified serialization for enums

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

### Phase 1: Core Setting<T> Class Hierarchy

**New file: `lib/src/data/settings/setting.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'setting_key.dart';
import 'settings_registry.dart';

/// Base class for all settings
abstract class Setting<T> {
  Setting({
    required this.key,
    required this.getDefaultValue,     // Function for dynamic defaults!
    required this.localization,
    this.categories = const [],        // Can belong to MULTIPLE categories
    this.isDeviceSpecific = false,
    this.widgetConfig,
    this.dependsOn,
    this.enabledWhen,
  }) : _value = getDefaultValue().obs;

  final SettingKey key;                // Type-safe enum key
  final T Function() getDefaultValue;  // Dynamic default (e.g., platform-specific)
  final SettingLocalization localization;
  final List<SettingCategory> categories;  // Multiple categories supported
  final bool isDeviceSpecific;
  final SettingWidgetConfig? widgetConfig;
  final List<SettingKey>? dependsOn;   // Other settings this depends on
  final bool Function()? enabledWhen;  // Dynamic enable condition

  final Rx<T> _value;                  // Reactive value using GetX

  /// JSON key for serialization (from enum)
  String get jsonKey => key.jsonKey;

  /// Convenience getter for current default
  T get defaultValue => getDefaultValue();

  T get value => _value.value;
  set value(T newValue) => _value.value = validate(newValue);
  Rx<T> get rx => _value;

  /// Type identifier for map (e.g., 'bool', 'int', 'PreviewQuality')
  String get type;

  /// Validation hook - override to add custom validation
  T validate(T value) => value;

  /// Serialize for storage
  dynamic toJson();

  /// Deserialize from storage
  T fromJson(dynamic json);

  /// Load and set value from JSON
  void loadFromJson(dynamic json) {
    value = fromJson(json);
  }

  /// Reset to default value
  void reset() => value = getDefaultValue();

  /// Check if value differs from default
  bool get isModified => value != getDefaultValue();

  /// Self-rendering widget
  Widget buildWidget(BuildContext context);

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

  /// Backwards compatibility with existing map structure
  Map<String, dynamic> toMapEntry();
}

/// Localization configuration for a setting
class SettingLocalization {
  const SettingLocalization({
    required this.title,
    this.subtitle,
    this.helpText,
    this.searchKeywords,              // Context-dependent for localization
  });

  /// Title shown in settings UI
  final String Function(BuildContext) title;

  /// Optional subtitle/description
  final String Function(BuildContext)? subtitle;

  /// Help text shown in dialogs
  final String Function(BuildContext)? helpText;

  /// Search keywords - context-dependent function for localized search
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

  // NOTE: drawTopBorder/drawBottomBorder removed - handled by AutoSettingsPage builder
}
```

---

### Phase 2: Typed Setting Implementations

**New file: `lib/src/data/settings/typed_settings.dart`**

#### Basic Types

| Class | For | Key Features |
|-------|-----|--------------|
| `BoolSetting` | Boolean toggles | Renders `SettingsToggle` |
| `IntSetting` | Integer values | `min`, `max`, `step`; Renders `SettingsTextInput` with number buttons |
| `DoubleSetting` | Decimal values | `min`, `max`, `step` |
| `StringSetting` | Text inputs | `obscurable`, `copyable`, `pasteable` |
| `EnumSetting<T>` | Enum dropdowns | `displayMode` (dropdown/optionsList/segmented) |
| `ColorSetting` | Color picker | Custom picker widget |
| `DurationSetting` | Duration selection | Dropdown with predefined options |
| `StringListSetting` | Tag lists, button order | Custom list editor |

#### Example: BoolSetting

```dart
class BoolSetting extends Setting<bool> {
  BoolSetting({
    required super.key,
    required super.getDefaultValue,
    required super.localization,
    super.categories,
    super.isDeviceSpecific,
    super.widgetConfig,
    super.dependsOn,
    super.enabledWhen,
  });

  @override
  String get type => 'bool';

  @override
  dynamic toJson() => value;

  @override
  bool fromJson(dynamic json) {
    if (json is bool) return json;
    if (json is String) {
      if (json == 'true') return true;
      if (json == 'false') return false;
    }
    return getDefaultValue();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Obx(() => SettingsToggle(
      title: localization.title(context),
      subtitle: localization.subtitle?.call(context),
      value: value,
      onChanged: enabledWhen?.call() ?? true
        ? (newValue) => value = newValue
        : null,
      leadingIcon: widgetConfig?.leadingIcon,
    ));
  }

  @override
  Map<String, dynamic> toMapEntry() => {
    'type': type,
    'default': getDefaultValue(),
  };
}
```

#### Example: IntSetting

```dart
class IntSetting extends Setting<int> {
  IntSetting({
    required super.key,
    required super.getDefaultValue,
    required super.localization,
    required this.min,
    required this.max,
    this.step = 1,
    super.categories,
    super.isDeviceSpecific,
    super.widgetConfig,
    super.dependsOn,
    super.enabledWhen,
  });

  final int min;
  final int max;
  final int step;

  @override
  String get type => 'int';

  @override
  int validate(int value) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  @override
  dynamic toJson() => value;

  @override
  int fromJson(dynamic json) {
    final int? parsed = json is String ? int.tryParse(json) : (json is int ? json : null);
    if (parsed == null) return getDefaultValue();
    return validate(parsed);
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Obx(() => SettingsTextInput(
      title: localization.title(context),
      subtitle: localization.subtitle?.call(context),
      inputType: TextInputType.number,
      value: value.toString(),
      onChanged: (newValue) {
        final parsed = int.tryParse(newValue);
        if (parsed != null) value = parsed;
      },
      trailingWidgets: [
        NumberStepper(
          value: value,
          min: min,
          max: max,
          step: step,
          onChanged: (newValue) => value = newValue,
        ),
      ],
    ));
  }

  @override
  Map<String, dynamic> toMapEntry() => {
    'type': type,
    'default': getDefaultValue(),
    'lowerLimit': min,
    'upperLimit': max,
    'step': step,
  };
}
```

#### Example: EnumSetting

```dart
enum EnumDisplayMode { dropdown, optionsList, segmented }

class EnumSetting<T extends Enum> extends Setting<T> {
  EnumSetting({
    required super.key,
    required super.getDefaultValue,
    required super.localization,
    required this.values,
    required this.fromString,
    required this.enumToJson,
    required this.enumLocName,
    required this.typeName,
    this.displayMode = EnumDisplayMode.dropdown,
    super.categories,
    super.isDeviceSpecific,
    super.widgetConfig,
    super.dependsOn,
    super.enabledWhen,
  });

  final List<T> values;
  final T Function(String) fromString;
  final String Function(T) enumToJson;
  final String Function(BuildContext, T) enumLocName;
  final String typeName;
  final EnumDisplayMode displayMode;

  @override
  String get type => typeName;

  @override
  dynamic toJson() => enumToJson(value);

  @override
  T fromJson(dynamic json) {
    if (json is String) {
      return fromString(json);
    }
    return getDefaultValue();
  }

  @override
  Widget buildWidget(BuildContext context) {
    switch (displayMode) {
      case EnumDisplayMode.dropdown:
        return Obx(() => SettingsDropdown<T>(
          title: localization.title(context),
          value: value,
          items: values,
          itemLabelBuilder: (item) => enumLocName(context, item),
          onChanged: (newValue) {
            if (newValue != null) value = newValue;
          },
        ));
      case EnumDisplayMode.optionsList:
        return Obx(() => SettingsOptionsList<T>(
          title: localization.title(context),
          value: value,
          items: values,
          itemLabelBuilder: (item) => enumLocName(context, item),
          onChanged: (newValue) => value = newValue,
        ));
      case EnumDisplayMode.segmented:
        return Obx(() => SettingsSegmented<T>(
          title: localization.title(context),
          value: value,
          items: values,
          itemLabelBuilder: (item) => enumLocName(context, item),
          onChanged: (newValue) => value = newValue,
        ));
    }
  }

  @override
  Map<String, dynamic> toMapEntry() => {
    'type': type,
    'default': enumToJson(getDefaultValue()),
    'options': values.map(enumToJson).toList(),
  };
}
```

---

### Special/Complex Types

**New file: `lib/src/data/settings/special_settings.dart`**

| Class | For | Key Features |
|-------|-----|--------------|
| `ThemeSetting` | Theme selection | Uses `ThemeItem`, custom preview widget, depends on theme list |
| `ThemeModeSetting` | System/Light/Dark | Uses Flutter's `ThemeMode`, segmented display |
| `LocaleSetting` | App language | Uses `AppLocale`, shows native language names |
| `FontFamilySetting` | Font selection | Custom dropdown with font previews |

#### Example: ThemeModeSetting

```dart
class ThemeModeSetting extends Setting<ThemeMode> {
  ThemeModeSetting({
    required super.key,
    required super.getDefaultValue,
    required super.localization,
    super.categories,
    super.isDeviceSpecific,
    super.widgetConfig,
    super.dependsOn,
    super.enabledWhen,
  });

  @override
  String get type => 'themeMode';

  @override
  dynamic toJson() => value.name;

  @override
  ThemeMode fromJson(dynamic json) {
    if (json is String) {
      final match = ThemeMode.values.where((e) => e.name == json);
      if (match.isNotEmpty) return match.first;
    }
    return getDefaultValue();
  }

  @override
  Widget buildWidget(BuildContext context) {
    return Obx(() => SettingsSegmented<ThemeMode>(
      title: localization.title(context),
      value: value,
      items: ThemeMode.values,
      itemLabelBuilder: (item) => _themeModeName(context, item),
      onChanged: (newValue) => value = newValue,
    ));
  }

  String _themeModeName(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return context.loc.settings.theme.themeModeValues.system;
      case ThemeMode.light:
        return context.loc.settings.theme.themeModeValues.light;
      case ThemeMode.dark:
        return context.loc.settings.theme.themeModeValues.dark;
    }
  }

  @override
  Map<String, dynamic> toMapEntry() => {
    'type': type,
    'default': getDefaultValue().name,
    'options': ThemeMode.values.map((e) => e.name).toList(),
  };
}
```

---

### Phase 3: SettingsRegistry

**New file: `lib/src/data/settings/settings_registry.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'setting.dart';
import 'setting_key.dart';

class SettingsRegistry {
  SettingsRegistry._();
  static final SettingsRegistry instance = SettingsRegistry._();

  final Map<SettingKey, Setting> _settings = {};
  Map<String, List<String>>? _searchIndex;

  void register(Setting setting) {
    _settings[setting.key] = setting;
    _searchIndex = null; // Invalidate cache
  }

  /// Get setting by enum key (type-safe)
  Setting<T>? get<T>(SettingKey key) => _settings[key] as Setting<T>?;

  /// Get setting by string key (for backwards compatibility with JSON)
  Setting? getByJsonKey(String jsonKey) {
    return _settings.values.firstWhereOrNull((s) => s.jsonKey == jsonKey);
  }

  Iterable<Setting> get all => _settings.values;

  /// Get all settings that belong to this category (supports multi-category)
  List<Setting> byCategory(SettingCategory category) {
    return _settings.values.where((s) => s.categories.contains(category)).toList();
  }

  /// Get visible categories (respects visibleWhen condition)
  List<SettingCategory> get visibleCategories {
    return SettingCategory.values.where((c) => c.visibleWhen?.call() ?? true).toList();
  }

  /// Get device-specific settings
  List<Setting> get deviceSpecific {
    return _settings.values.where((s) => s.isDeviceSpecific).toList();
  }

  /// Get syncable settings (not device-specific)
  List<Setting> get syncable {
    return _settings.values.where((s) => !s.isDeviceSpecific).toList();
  }

  /// Build search index (call once after registration or when locale changes)
  void buildSearchIndex(BuildContext context) {
    _searchIndex = {};
    for (final setting in _settings.values) {
      final searchableText = setting.getSearchableText(context);
      for (final text in searchableText) {
        final words = text.toLowerCase().split(RegExp(r'\s+'));
        for (final word in words) {
          _searchIndex![word] ??= [];
          if (!_searchIndex![word]!.contains(setting.jsonKey)) {
            _searchIndex![word]!.add(setting.jsonKey);
          }
        }
      }
    }
  }

  /// Search settings by query
  List<Setting> search(String query, BuildContext context) {
    if (_searchIndex == null) {
      buildSearchIndex(context);
    }

    final queryLower = query.toLowerCase();
    final matchingKeys = <String>{};

    for (final entry in _searchIndex!.entries) {
      if (entry.key.contains(queryLower)) {
        matchingKeys.addAll(entry.value);
      }
    }

    return matchingKeys
        .map((key) => getByJsonKey(key))
        .whereType<Setting>()
        .toList();
  }

  /// Convert to map for backwards compatibility
  Map<String, Map<String, dynamic>> toMap() {
    return Map.fromEntries(
      _settings.values.map((s) => MapEntry(s.jsonKey, s.toMapEntry())),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return Map.fromEntries(
      _settings.values.map((s) => MapEntry(s.jsonKey, s.toJson())),
    );
  }

  /// Load from JSON
  void loadFromJson(Map<String, dynamic> json) {
    for (final entry in json.entries) {
      final setting = getByJsonKey(entry.key);
      setting?.loadFromJson(entry.value);
    }
  }

  /// Reset all settings to defaults
  void resetAll() {
    for (final setting in _settings.values) {
      setting.reset();
    }
  }

  /// Reset settings in a category
  void resetCategory(SettingCategory category) {
    for (final setting in byCategory(category)) {
      setting.reset();
    }
  }
}

/// Categories for organizing settings
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

  /// Visibility condition - category hidden if returns false
  /// Returns null if always visible
  bool Function()? get visibleWhen {
    switch (this) {
      case SettingCategory.debug:
        // Only show debug category in debug mode or when isDebug setting enabled
        return () => kDebugMode || SettingsRegistry.instance.get<bool>(SettingKey.isDebug)?.value == true;
      default:
        return null; // Always visible
    }
  }
}
```

---

### Phase 4: Settings Definitions

**New file: `lib/src/data/settings/all_settings.dart`**

Declarative definition of all ~100 settings using `SettingKey` enum:

```dart
import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/typed_settings.dart';
import 'package:lolisnatcher/src/data/settings/special_settings.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

void registerAllSettings() {
  final registry = SettingsRegistry.instance;

  // ============================================
  // INTERFACE SETTINGS
  // ============================================

  registry.register(IntSetting(
    key: SettingKey.portraitColumns,
    getDefaultValue: () => SettingsHandler.isDesktopPlatform ? 5 : 2,  // Dynamic default!
    min: 1, max: 100, step: 1,
    categories: [SettingCategory.interface],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewColumnsPortrait,
      searchKeywords: (ctx) => [ctx.loc.search.columns, ctx.loc.search.grid],
    ),
  ));

  registry.register(IntSetting(
    key: SettingKey.landscapeColumns,
    getDefaultValue: () => SettingsHandler.isDesktopPlatform ? 7 : 4,
    min: 1, max: 100, step: 1,
    categories: [SettingCategory.interface],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewColumnsLandscape,
      searchKeywords: (ctx) => [ctx.loc.search.columns, ctx.loc.search.grid],
    ),
  ));

  registry.register(EnumSetting<PreviewQuality>(
    key: SettingKey.previewMode,
    getDefaultValue: () => PreviewQuality.defaultValue,
    values: PreviewQuality.values,
    fromString: PreviewQuality.fromString,
    enumToJson: (v) => v.toJson(),
    enumLocName: (ctx, v) => v.locName(ctx),
    typeName: 'previewQuality',
    displayMode: EnumDisplayMode.optionsList,
    categories: [SettingCategory.interface],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.interface.previewQuality,
      searchKeywords: (ctx) => [ctx.loc.search.preview, ctx.loc.search.quality],
    ),
  ));

  // ============================================
  // VIDEO SETTINGS
  // ============================================

  registry.register(BoolSetting(
    key: SettingKey.disableVideo,
    getDefaultValue: () => false,
    categories: [SettingCategory.video],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.video.disableVideo,
    ),
  ));

  registry.register(BoolSetting(
    key: SettingKey.autoPlayEnabled,
    getDefaultValue: () => true,
    categories: [SettingCategory.video],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.video.autoplayVideos,
      searchKeywords: (ctx) => [ctx.loc.search.video, ctx.loc.search.autoplay],
    ),
    // Only enabled when disableVideo is false
    dependsOn: [SettingKey.disableVideo],
    enabledWhen: () => !SettingsRegistry.instance.get<bool>(SettingKey.disableVideo)!.value,
  ));

  // ============================================
  // VIEWER SETTINGS
  // ============================================

  // Setting in MULTIPLE categories
  registry.register(BoolSetting(
    key: SettingKey.enableHeroTransitions,
    getDefaultValue: () => true,
    categories: [SettingCategory.viewer, SettingCategory.performance],  // Shows in both!
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.viewer.enableHeroTransitions,
      searchKeywords: (ctx) => [ctx.loc.search.animation, ctx.loc.search.transition],
    ),
  ));

  // ============================================
  // THEME SETTINGS
  // ============================================

  registry.register(ThemeModeSetting(
    key: SettingKey.themeMode,
    getDefaultValue: () => ThemeMode.system,
    categories: [SettingCategory.theme],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.theme.themeMode,
    ),
  ));

  registry.register(BoolSetting(
    key: SettingKey.isAmoled,
    getDefaultValue: () => false,
    categories: [SettingCategory.theme],
    localization: SettingLocalization(
      title: (ctx) => ctx.loc.settings.theme.amoled,
    ),
  ));

  // ... continue with all other settings
}
```

---

### Phase 5: Auto-Rendering Settings Pages

**New file: `lib/src/widgets/settings/auto_settings_page.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/settings/setting.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class AutoSettingsPage extends StatefulWidget {
  const AutoSettingsPage({
    super.key,
    this.category,
    this.customSettings,
    this.header,
    this.footer,
    this.settingBuilder,
  }) : assert(category != null || customSettings != null);

  final SettingCategory? category;
  final List<Setting>? customSettings;
  final Widget? header;
  final Widget? footer;
  /// Custom builder for controlling borders, spacing, grouping etc.
  final Widget Function(BuildContext context, Setting setting, int index, int total)? settingBuilder;

  @override
  State<AutoSettingsPage> createState() => _AutoSettingsPageState();
}

class _AutoSettingsPageState extends State<AutoSettingsPage> {
  late List<Setting> _settings;
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    if (widget.customSettings != null) {
      _settings = widget.customSettings!;
    } else {
      _settings = SettingsRegistry.instance.byCategory(widget.category!);
    }

    // Filter out disabled settings
    _settings = _settings.where((s) {
      final enabledWhen = s.enabledWhen;
      return enabledWhen == null || enabledWhen();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          settingsHandler.saveSettings();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category?.locName(context) ?? 'Settings'),
        ),
        body: ListView.builder(
          itemCount: _settings.length +
            (widget.header != null ? 1 : 0) +
            (widget.footer != null ? 1 : 0),
          itemBuilder: (context, index) {
            // Header
            if (widget.header != null && index == 0) {
              return widget.header!;
            }

            // Adjust index for header
            final settingIndex = index - (widget.header != null ? 1 : 0);

            // Footer
            if (widget.footer != null && settingIndex >= _settings.length) {
              return widget.footer!;
            }

            final setting = _settings[settingIndex];

            // Use custom builder or default
            if (widget.settingBuilder != null) {
              return widget.settingBuilder!(
                context,
                setting,
                settingIndex,
                _settings.length,
              );
            }

            // Default: add borders based on position
            return _defaultSettingBuilder(context, setting, settingIndex);
          },
        ),
      ),
    );
  }

  Widget _defaultSettingBuilder(BuildContext context, Setting setting, int index) {
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
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Setting> _results = [];
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
                final setting = _results[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badges
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: Wrap(
                        spacing: 4,
                        children: setting.categories.map((cat) {
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
                    // Setting widget
                    setting.buildWidget(context),
                    const Divider(),
                  ],
                );
              },
            ),
    );
  }
}
```

---

### Phase 7: Bridge with Existing System

Modify `lib/src/handlers/settings_handler.dart` for gradual migration:

```dart
class SettingsHandler extends GetxController {
  // ... existing code ...

  final SettingsRegistry _registry = SettingsRegistry.instance;

  @override
  void onInit() {
    super.onInit();
    registerAllSettings();  // Register all settings
    // ... existing init code ...
  }

  // Bridge methods - delegate to registry
  Map<String, Map<String, dynamic>> get map => _registry.toMap();

  dynamic getByString(String varName) {
    final setting = _registry.getByJsonKey(varName);
    if (setting != null) return setting.value;
    return _legacyGetByString(varName);  // Fallback
  }

  void setByString(String varName, dynamic value) {
    final setting = _registry.getByJsonKey(varName);
    if (setting != null) {
      setting.loadFromJson(value);
      return;
    }
    _legacySetByString(varName, value);  // Fallback
  }

  // Keep legacy methods during migration
  dynamic _legacyGetByString(String varName) {
    // ... existing switch statement ...
  }

  void _legacySetByString(String varName, dynamic value) {
    // ... existing switch statement ...
  }
}
```

---

## File Structure

```
lib/src/data/settings/
  setting_key.dart              # Centralized enum for all setting keys
  setting.dart                  # Base Setting<T> class
  typed_settings.dart           # BoolSetting, IntSetting, EnumSetting, etc.
  special_settings.dart         # ThemeSetting, ThemeModeSetting, LocaleSetting, etc.
  settings_registry.dart        # SettingsRegistry + SettingCategory
  all_settings.dart             # All setting definitions

  # Keep existing:
  settings_enum.dart            # SettingsEnum mixin (for enum values)
  preview_quality.dart          # Enum definition
  ... (other enum files)

lib/src/widgets/settings/
  auto_settings_page.dart       # Auto-rendering page
  settings_search_page.dart     # Global search
```

---

## Migration Strategy

### Step 1: Create Infrastructure (Non-Breaking)
1. Create `setting_key.dart` with all setting keys
2. Create `Setting<T>` base class and typed implementations
3. Create `SettingsRegistry`
4. Create `AutoSettingsPage` and `SettingsSearchPage`
5. Call `registerAllSettings()` at app startup

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
```

### Step 4: Remove Legacy Code (Final)
Once all pages migrated:
- Remove individual member variables from SettingsHandler
- Remove `getByString`/`setByString` switch statements
- Remove `deviceSpecificSettings` list (use `isDeviceSpecific` flag)

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `lib/src/handlers/settings_handler.dart` | Add registry bridge, initialize at startup |
| `lib/src/pages/settings_page.dart` | Add search button |
| `lib/src/pages/settings/gallery_page.dart` | First page to migrate (demo) |
| `lib/main.dart` | Call `registerAllSettings()` |

---

## Backwards Compatibility

- **JSON format**: Same keys and values - no migration needed
- **API**: `settingsHandler.autoHideImageBar` works via bridge
- **Sync**: `isDeviceSpecific` flag replaces `deviceSpecificSettings` list

---

## Verification

1. `flutter analyze` - no errors
2. App loads existing settings.json correctly
3. Changing a setting persists correctly
4. Fresh install uses correct defaults
5. Search finds settings by title/keyword
6. AutoSettingsPage renders all settings in category
7. Conditional settings show/hide correctly

---

## Notes

- The `SettingKey` enum provides type-safe access to settings and prevents typos
- Settings can belong to multiple categories (useful for settings like `enableHeroTransitions` that fit both `viewer` and `performance`)
- `searchKeywords` is a function `(BuildContext) => List<String>` to support localized search
- `getDefaultValue` is a function to support platform-specific defaults (desktop vs mobile)
- `visibleWhen` on categories allows hiding entire sections conditionally (e.g., debug settings)
- Border handling moved to `AutoSettingsPage.settingBuilder` for flexibility
