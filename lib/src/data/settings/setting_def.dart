import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';

/// Forward declaration - actual class is in setting_state.dart.
/// Needed here to type the widgetBuilder callback.
typedef SettingWidgetBuilder<T> = Widget Function(BuildContext context, dynamic state);

/// Immutable definition describing what a setting IS.
///
/// Separate from [SettingState] which holds current mutable values.
/// This class is intentionally not `const` because several fields are functions,
/// but instances should be treated as immutable after construction.
class SettingDef<T> {
  SettingDef({
    required this.key,
    required this.getDefaultValue,
    required this.localization,
    required this.valueToJson,
    required this.valueFromJson,
    this.legacyJsonKeys = const [],
    this.categories = const [],
    this.subcategories = const [],
    this.isDeviceSpecific = false,
    this.supportsPerBooru = false,
    this.isWidgetSlot = false,
    this.isTransient = false,
    this.isSearchable = true,
    this.visibleWhen,
    this.searchVisibleWhen,
    this.validate,
    this.widgetBuilder,
    this.dependsOn,
    this.enabledWhen,
    this.onChanged,
    this.onScopedChanged,
  });

  /// Type-safe enum key used for registration and lookup.
  final SettingKey key;

  /// Returns the default value. A function (not a plain value) to support
  /// platform-specific defaults (e.g., different column counts on desktop vs mobile).
  final T Function() getDefaultValue;

  /// Localized title, subtitle, help text, and search keywords.
  final SettingLocalization localization;

  /// Serialize a value of type [T] to a JSON-compatible primitive.
  final dynamic Function(T value) valueToJson;

  /// Deserialize a JSON-compatible value back to [T].
  /// Must handle invalid input gracefully (return a sensible fallback).
  final T Function(dynamic json) valueFromJson;

  /// Historical JSON keys accepted when loading older settings files.
  /// Serialization always uses [jsonKey].
  final List<String> legacyJsonKeys;

  /// Categories this setting belongs to. A setting can appear in multiple categories
  /// (e.g., `enableHeroTransitions` in both `viewer` and `performance`).
  final List<SettingCategory> categories;

  /// Display subsections this setting belongs to within its categories.
  ///
  /// For settings shown in multiple categories, include one subcategory for
  /// each page where a subsection header should be shown.
  final List<SettingSubcategory> subcategories;

  /// If true, this setting is device-specific and won't be synced across devices.
  final bool isDeviceSpecific;

  /// If true, this setting can be overridden per booru.
  /// Overrides are stored in each booru's config file.
  final bool supportsPerBooru;

  /// If true, this is not a real setting — it's a placeholder slot that only
  /// renders a custom widget inline among auto-generated settings.
  /// Widget slots are excluded from serialization, search, and sync.
  final bool isWidgetSlot;

  /// If true, this setting is not persisted to JSON.
  /// It resets to its default value on each app launch.
  /// Use for runtime-only toggles like debug overlays.
  final bool isTransient;

  /// Whether this setting can ever appear in global settings search.
  final bool isSearchable;

  /// Optional static UI visibility condition.
  ///
  /// Use this for platform or build-target availability, for example Android-only
  /// settings or desktop-only settings. Unlike [enabledWhen], this should not
  /// depend on mutable setting values.
  final bool Function()? visibleWhen;

  /// Optional runtime condition for global settings search visibility.
  ///
  /// Use [isSearchable] for settings that must never be discoverable.
  final bool Function()? searchVisibleWhen;

  /// Optional validation/clamping. Called before setting a new value.
  /// Return the (possibly adjusted) value.
  final T Function(T value)? validate;

  /// Self-rendering widget builder. Receives the [SettingState] so it can
  /// read/write the current value and listen to changes.
  final SettingWidgetBuilder<T>? widgetBuilder;

  /// Other settings this one depends on. Used by [AutoSettingsPage] to
  /// set up reactive listeners for the [enabledWhen] condition.
  final List<SettingKey>? dependsOn;

  /// Dynamic enable condition. When this returns false, the setting is hidden
  /// or disabled on auto-rendered pages. Re-evaluated reactively when
  /// dependency settings change.
  ///
  /// When [context] is provided (e.g., inside a [BooruEditingScope]), the
  /// condition should use scoped values to reflect the booru being edited.
  final bool Function([BuildContext? context])? enabledWhen;

  /// Called after the value changes. Use for side effects like rebuilding the
  /// theme, switching locale, or toggling the database.
  final void Function(T oldValue, T newValue)? onChanged;

  /// Called after stored global or per-booru values change.
  ///
  /// [booruName] is null for global changes and identifies the affected booru
  /// for override changes.
  final void Function(T oldValue, T newValue, String? booruName)? onScopedChanged;

  /// JSON key for serialization (delegates to the enum).
  String get jsonKey => key.jsonKey;

  /// Collect all text that should be searchable for this setting.
  /// Includes title, subtitle, keywords, and category names.
  /// All strings are localized via [BuildContext].
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
    for (final subcategory in subcategories) {
      result.add(subcategory.locName(context));
    }
    return result;
  }
}

/// Localization configuration for a setting.
///
/// All functions take [BuildContext] for access to slang's `context.loc.*` accessors,
/// ensuring strings update correctly when the app locale changes.
class SettingLocalization {
  const SettingLocalization({
    required this.title,
    this.subtitle,
    this.helpText,
    this.searchKeywords,
  });

  /// Title shown in settings UI.
  final String Function(BuildContext context) title;

  /// Optional subtitle/description shown below the title.
  final String Function(BuildContext context)? subtitle;

  /// Help text shown in info dialogs.
  final String Function(BuildContext context)? helpText;

  /// Additional search keywords (localized). Combined with title, subtitle,
  /// and category names for the global settings search.
  final List<String> Function(BuildContext context)? searchKeywords;
}

/// Widget configuration for a setting's leading/trailing decorations.
class SettingWidgetConfig {
  const SettingWidgetConfig({
    this.leadingIcon,
    this.trailingIcon,
    this.helpDialog,
    this.extraWidgets,
  });

  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final Widget Function(BuildContext context)? helpDialog;
  final List<Widget> Function(BuildContext context)? extraWidgets;
}

/// Categories for organizing settings on pages and in search results.
///
/// Registration order of settings within a category determines their display order
/// on auto-rendered pages.
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
  logging,
  debug;

  /// Localized category name.
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
        return context.loc.settings.viewer.title;
      case SettingCategory.video:
        return context.loc.settings.video.title;
      case SettingCategory.cache:
        return context.loc.settings.cache.title;
      case SettingCategory.tagsFilters:
        return context.loc.settings.itemFilters.title;
      case SettingCategory.database:
        return context.loc.settings.database.title;
      case SettingCategory.backup:
        return context.loc.settings.backupAndRestore.title;
      case SettingCategory.network:
        return context.loc.settings.network.title;
      case SettingCategory.privacy:
        return context.loc.settings.privacy.title;
      case SettingCategory.performance:
        return context.loc.settings.performance.title;
      case SettingCategory.logging:
        return context.loc.settings.logging.logger;
      case SettingCategory.debug:
        return context.loc.settings.debug.title;
    }
  }

  Object get icon {
    switch (this) {
      case SettingCategory.language:
        return Icons.translate_rounded;
      case SettingCategory.booru:
        return Icons.image_search;
      case SettingCategory.interface:
        return Icons.grid_on;
      case SettingCategory.theme:
        return Icons.palette;
      case SettingCategory.viewer:
        return Icons.view_carousel;
      case SettingCategory.video:
        return Icons.video_settings;
      case SettingCategory.cache:
        return Icons.sd_storage_sharp;
      case SettingCategory.tagsFilters:
        return CupertinoIcons.tag;
      case SettingCategory.database:
        return Icons.list_alt;
      case SettingCategory.backup:
        return Icons.restore_page;
      case SettingCategory.network:
        return Icons.wifi;
      case SettingCategory.privacy:
        return FontAwesomeIcons.userShield;
      case SettingCategory.performance:
        return Icons.speed;
      case SettingCategory.logging:
        return Icons.print;
      case SettingCategory.debug:
        return Icons.developer_mode;
    }
  }

  /// Builds the icon used for this category throughout the settings UI.
  Widget iconWidget({double? size, Color? color}) {
    return switch (icon) {
      final IconData iconData => Icon(iconData, size: size, color: color),
      final FaIconData iconData => FaIcon(iconData, size: size, color: color),
      _ => const Icon(null),
    };
  }
}

/// Subsections shown inside settings categories.
enum SettingSubcategory {
  layout(SettingCategory.interface, 'layout'),
  previewGrid(SettingCategory.interface, 'previewGrid'),
  rendering(SettingCategory.interface, 'rendering'),
  additionalInterface(SettingCategory.interface, 'additionalInterface'),
  loadingPreloading(SettingCategory.viewer, 'loadingPreloading'),
  toolbar(SettingCategory.viewer, 'toolbar'),
  viewerBehavior(SettingCategory.viewer, 'viewerBehavior'),
  slideshow(SettingCategory.viewer, 'slideshow'),
  physicalButtons(SettingCategory.viewer, 'physicalButtons'),
  playback(SettingCategory.video, 'playback'),
  backend(SettingCategory.video, 'backend'),
  mpv(SettingCategory.video, 'mpv'),
  theme(SettingCategory.theme, 'theme'),
  drawer(SettingCategory.theme, 'drawer'),
  storage(SettingCategory.cache, 'storage'),
  downloads(SettingCategory.cache, 'downloads'),
  cache(SettingCategory.cache, 'cache'),
  cacheStats(SettingCategory.cache, 'cacheStats'),
  backup(SettingCategory.backup, 'backup'),
  database(SettingCategory.database, 'database'),
  security(SettingCategory.network, 'security'),
  proxy(SettingCategory.network, 'proxy'),
  requests(SettingCategory.network, 'requests'),
  sync(SettingCategory.network, 'sync'),
  activeFilters(SettingCategory.tagsFilters, 'activeFilters'),
  tagLists(SettingCategory.tagsFilters, 'tagLists'),
  appLock(SettingCategory.privacy, 'appLock'),
  privacy(SettingCategory.privacy, 'privacy'),
  defaults(SettingCategory.booru, 'defaults'),
  devicePerformance(SettingCategory.performance, 'devicePerformance'),
  previewPerformance(SettingCategory.performance, 'previewPerformance'),
  viewerPerformance(SettingCategory.performance, 'viewerPerformance'),
  videoPerformance(SettingCategory.performance, 'videoPerformance'),
  language(SettingCategory.language, 'language'),
  logs(SettingCategory.logging, 'logs'),
  debugMode(SettingCategory.debug, 'debugMode'),
  overlays(SettingCategory.debug, 'overlays'),
  logging(SettingCategory.debug, 'logging');

  const SettingSubcategory(this.category, this.localizationKey);

  final SettingCategory category;
  final String localizationKey;

  String locName(BuildContext context) {
    final key = 'settings.subcategories.$localizationKey';
    try {
      final localized = context.loc[key];
      return localized == key ? localizationKey : localized;
    } catch (_) {
      return localizationKey;
    }
  }
}
