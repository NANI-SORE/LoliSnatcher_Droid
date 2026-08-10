import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/settings_enum.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_chrome_scope.dart';

/// Callback to get the current booru notifier from the registry.
/// Set by [SettingsRegistry] during initialization to avoid circular imports.
ValueNotifier<String?> Function()? _currentBooruNotifierProvider;

typedef SettingsSaveScheduler =
    void Function({
      bool debounce,
      bool restate,
      String? booruName,
    });

SettingsSaveScheduler? _settingsSaveScheduler;

/// Called by [SettingsRegistry] to wire up the booru notifier provider.
void setCurrentBooruNotifierProvider(ValueNotifier<String?> Function() provider) {
  _currentBooruNotifierProvider = provider;
}

/// Called by [SettingsHandler] to wire autosave without importing handlers here.
void setSettingsSaveScheduler(SettingsSaveScheduler scheduler) {
  _settingsSaveScheduler = scheduler;
}

/// Mutable state holding a setting's current value(s).
///
/// Created by [SettingsRegistry] when a [SettingDef] is registered.
/// Holds the global value and optional per-booru overrides, and provides
/// an [effectiveNotifier] that reactively combines them with the current booru context.
class SettingState<T> {
  SettingState(this.def)
    : _globalValue = ValueNotifier<T>(def.getDefaultValue()),
      _booruOverrides = ValueNotifier<Map<String, T>>(const {});

  /// The immutable definition for this setting.
  final SettingDef<T> def;

  final ValueNotifier<T> _globalValue;
  final ValueNotifier<Map<String, T>> _booruOverrides;
  bool _suppressSideEffects = false;

  /// Reactive notifier for the effective value (considers current booru override).
  /// Widgets should listen to this via [SettingBuilder] or [ValueListenableBuilder].
  late final ValueNotifier<T> effectiveNotifier = _createEffectiveNotifier();

  // ============================================
  // VALUE ACCESS
  // ============================================

  /// Get the effective value (considers current booru override).
  T get value => effectiveNotifier.value;

  /// Set the global value. Validates via [SettingDef.validate] and fires
  /// [SettingDef.onChanged] if the value actually changed.
  set value(T newValue) {
    setValue(newValue);
  }

  void setValue(T newValue, {bool debounceSave = false, bool save = true}) {
    final validated = def.validate?.call(newValue) ?? newValue;
    final oldValue = _globalValue.value;
    _globalValue.value = validated;
    if (!def.supportsPerBooru && !valuesEqual(oldValue, validated)) {
      def.onChanged?.call(oldValue, validated);
    }
    if (save && !valuesEqual(oldValue, validated)) {
      _scheduleSave(debounce: debounceSave);
    }
  }

  /// Always get the global value (ignoring any booru override).
  T get globalValue => _globalValue.value;

  /// Set the global value directly (ignoring overrides).
  set globalValue(T newValue) {
    final validated = def.validate?.call(newValue) ?? newValue;
    final oldValue = _globalValue.value;
    _globalValue.value = validated;
    if (!def.supportsPerBooru && !valuesEqual(oldValue, validated)) {
      def.onChanged?.call(oldValue, validated);
    }
    if (!valuesEqual(oldValue, validated)) {
      _scheduleSave();
    }
  }

  /// The global value notifier. Useful for listening to global-only changes.
  ValueNotifier<T> get globalNotifier => _globalValue;

  /// Convenience getter for the current default.
  T get defaultValue => def.getDefaultValue();

  /// Value used by UI reset controls.
  ///
  /// Global settings pages reset to the app default. Per-booru settings reset
  /// to the current global value, which is equivalent to inheriting global.
  T resetValue(BuildContext context) {
    if (!def.supportsPerBooru || BooruEditingScope.of(context) == null) {
      return defaultValue;
    }
    return globalValue;
  }

  /// Whether the global value differs from the default.
  bool get isModified => !valuesEqual(globalValue, def.getDefaultValue());

  /// Compare values using structural equality for collections.
  ///
  /// Settings commonly use freshly-created lists as defaults, so identity
  /// equality would otherwise report them as modified forever.
  bool valuesEqual(T a, T b) => def.equals?.call(a, b) ?? _deepEquals(a, b);

  /// Reset to the default value.
  void reset() {
    value = def.getDefaultValue();
  }

  /// Reset respecting the current UI scope.
  ///
  /// On global settings pages this resets the global value to the app default.
  /// Inside a booru editing scope this removes the booru override so the booru
  /// inherits the current global value.
  void resetScoped(BuildContext context) {
    if (!def.supportsPerBooru) {
      reset();
      return;
    }
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) {
      reset();
    } else {
      removeOverrideFor(editingBooru, save: BooruEditingScope.autosaveOf(context));
    }
  }

  // ============================================
  // PER-BOORU OVERRIDE MANAGEMENT
  // ============================================

  /// Whether a specific booru has an override for this setting.
  bool hasOverrideFor(String booruName) => _booruOverrides.value.containsKey(booruName);

  /// Get the override value for a specific booru, or null if none exists.
  T? getOverrideFor(String booruName) => _booruOverrides.value[booruName];

  /// Set an override value for a specific booru.
  void setOverrideFor(
    String booruName,
    T val, {
    bool save = true,
    bool debounceSave = false,
  }) {
    final validated = def.validate?.call(val) ?? val;
    final hadOverride = _booruOverrides.value.containsKey(booruName);
    final oldValue = _booruOverrides.value[booruName];
    final map = Map<String, T>.from(_booruOverrides.value);
    map[booruName] = validated;
    _booruOverrides.value = map; // Triggers notification
    if (save && (!hadOverride || !valuesEqual(oldValue as T, validated))) {
      _scheduleSave(debounce: debounceSave, booruName: booruName);
    }
  }

  /// Remove the override for a specific booru (will use global value).
  void removeOverrideFor(String booruName, {bool save = true}) {
    if (!_booruOverrides.value.containsKey(booruName)) return;
    final map = Map<String, T>.from(_booruOverrides.value);
    map.remove(booruName);
    _booruOverrides.value = map; // Triggers notification
    if (save) {
      _scheduleSave(booruName: booruName);
    }
  }

  /// All booru names that have overrides for this setting.
  Iterable<String> get boorusWithOverrides => _booruOverrides.value.keys;

  /// The override map notifier. Useful for listening to override changes
  /// (e.g. in [_ReactiveSettingWidget] when evaluating [enabledWhen] in a
  /// [BooruEditingScope] context).
  ValueNotifier<Map<String, T>> get overridesNotifier => _booruOverrides;

  /// Remove all per-booru overrides.
  void clearAllOverrides() {
    if (_booruOverrides.value.isEmpty) return;
    _booruOverrides.value = const {};
  }

  // ============================================
  // SCOPED VALUE ACCESS (BOORU EDITING)
  // ============================================

  /// Get the value to display in a widget, considering [BooruEditingScope].
  ///
  /// When inside a [BooruEditingScope] and this setting supports per-booru overrides:
  /// - Returns the override value if one exists for that booru
  /// - Returns the global value otherwise (the "default" the user sees)
  ///
  /// When NOT inside a scope, returns the global value for settings UI pages.
  /// Runtime reads through [value] still use the effective active-booru value.
  T scopedValue(BuildContext context) {
    if (!def.supportsPerBooru) return globalValue;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return globalValue;
    return getOverrideFor(editingBooru) ?? globalValue;
  }

  /// Set a value respecting the current [BooruEditingScope].
  ///
  /// When inside a scope: sets a per-booru override for that booru.
  /// When NOT inside a scope: sets the global value.
  void setScopedValue(BuildContext context, T newValue, {bool debounceSave = false}) {
    if (!def.supportsPerBooru) {
      setValue(newValue, debounceSave: debounceSave);
      return;
    }
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) {
      setValue(newValue, debounceSave: debounceSave);
    } else {
      final validated = def.validate?.call(newValue) ?? newValue;
      if (valuesEqual(validated, globalValue)) {
        removeOverrideFor(editingBooru, save: BooruEditingScope.autosaveOf(context));
        return;
      }
      setOverrideFor(
        editingBooru,
        validated,
        save: BooruEditingScope.autosaveOf(context),
        debounceSave: debounceSave,
      );
    }
  }

  /// Whether the current [BooruEditingScope] booru has an override for this setting.
  /// Returns false if not inside a scope or if the setting doesn't support per-booru.
  bool hasScopedOverride(BuildContext context) {
    if (!def.supportsPerBooru) return false;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return false;
    return hasOverrideFor(editingBooru);
  }

  /// Remove the per-booru override for the booru in the current [BooruEditingScope],
  /// reverting to the global value.
  void removeScopedOverride(BuildContext context) {
    if (!def.supportsPerBooru) return;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return;
    removeOverrideFor(editingBooru, save: BooruEditingScope.autosaveOf(context));
  }

  /// The notifier to listen to inside widget builders.
  ///
  /// When inside a [BooruEditingScope], this returns a notifier that reacts to
  /// changes in the override map (so UI updates when the override is set/removed).
  /// When not in a scope, returns the global notifier for settings UI pages.
  ValueNotifier<dynamic> scopedNotifier(BuildContext context) {
    if (!def.supportsPerBooru) return globalNotifier;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return globalNotifier;
    // Override map notifier triggers when any override changes.
    // The widget must read scopedValue() in its builder to get the correct value.
    return _booruOverrides;
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Serialize the global value to JSON.
  dynamic toJson() => def.valueToJson(globalValue);

  /// Serialize a specific override value to JSON.
  /// Uses the properly-typed [SettingDef.valueToJson] without dynamic cast issues.
  dynamic overrideToJson(String booruName) {
    final val = _booruOverrides.value[booruName];
    if (val == null) return null;
    return def.valueToJson(val);
  }

  /// Load the global value from JSON.
  void loadFromJson(dynamic json) {
    _loadGlobalValue(def.valueFromJson(json));
  }

  /// Restore the global default without scheduling a save or firing runtime
  /// side effects. Safe to call through a type-erased `SettingState<dynamic>`.
  void loadDefaultValue() {
    _loadGlobalValue(def.getDefaultValue());
  }

  void _loadGlobalValue(T value) {
    _suppressSideEffects = true;
    try {
      _globalValue.value = value;
    } finally {
      _suppressSideEffects = false;
    }
  }

  void _scheduleSave({bool debounce = false, String? booruName}) {
    if (_suppressSideEffects) return;
    _settingsSaveScheduler?.call(
      debounce: debounce,
      restate: false,
      booruName: booruName,
    );
  }

  // ============================================
  // WIDGET
  // ============================================

  /// Build the self-rendering widget for this setting.
  ///
  /// When inside a [BooruEditingScope] and this setting supports per-booru
  /// overrides, the widget is automatically wrapped with override toggle controls.
  Widget buildWidget(BuildContext context) {
    final widget = def.widgetBuilder?.call(context, this);
    if (widget == null) return const SizedBox.shrink();

    // When inside a booru editing scope, wrap with override controls
    if (def.supportsPerBooru) {
      final editingBooru = BooruEditingScope.of(context);
      if (editingBooru != null) {
        return _BooruOverrideWrapper(
          state: this,
          booruName: editingBooru,
          child: widget,
        );
      }
      return _GlobalOverridesWrapper(
        state: this,
        child: widget,
      );
    }

    return widget;
  }

  // ============================================
  // EFFECTIVE VALUE COMPUTATION
  // ============================================

  T _computeEffective() {
    if (!def.supportsPerBooru) return _globalValue.value;

    final notifierProvider = _currentBooruNotifierProvider;
    if (notifierProvider == null) return _globalValue.value;

    final currentBooruName = notifierProvider().value;
    if (currentBooruName != null && _booruOverrides.value.containsKey(currentBooruName)) {
      return _booruOverrides.value[currentBooruName] as T;
    }
    return _globalValue.value;
  }

  ValueNotifier<T> _createEffectiveNotifier() {
    if (!def.supportsPerBooru) {
      // No per-booru support: effective value is always the global value.
      // Just return the global notifier directly to avoid an extra wrapper.
      return _globalValue;
    }
    return _EffectiveValueNotifier<T>(this);
  }
}

/// Custom [ValueNotifier] that recomputes the effective value whenever
/// the global value, booru overrides, or current booru context changes.
class _EffectiveValueNotifier<T> extends ValueNotifier<T> {
  _EffectiveValueNotifier(this._state) : super(_state._computeEffective()) {
    _state._globalValue.addListener(_recompute);
    _state._booruOverrides.addListener(_recompute);

    final notifierProvider = _currentBooruNotifierProvider;
    if (notifierProvider != null) {
      _booruNotifier = notifierProvider();
      _booruNotifier!.addListener(_recompute);
    }
  }

  final SettingState<T> _state;
  ValueNotifier<String?>? _booruNotifier;

  void _recompute() {
    final oldValue = value;
    final newValue = _state._computeEffective();
    value = newValue;
    if (!_state._suppressSideEffects && !_state.valuesEqual(oldValue, newValue)) {
      _state.def.onChanged?.call(oldValue, newValue);
    }
  }

  @override
  void dispose() {
    _state._globalValue.removeListener(_recompute);
    _state._booruOverrides.removeListener(_recompute);
    _booruNotifier?.removeListener(_recompute);
    super.dispose();
  }
}

/// Format a setting value for display in a badge label.
/// Keeps it short — truncates long strings.
String _formatValue(BuildContext context, dynamic value) {
  if (value is bool) return value ? context.loc.yes : context.loc.no;
  if (value is ThemeMode) return context.loc['settings.theme.${value.name}'];
  if (value is SettingsEnum) return value.locName;
  if (value is Enum) return value.name;
  if (value is ThemeItem) return value.locName(context);
  if (value is Color) {
    return '#${value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
  if (value is List) return '${value.length} items';
  final str = value.toString();
  if (str.isEmpty) return context.loc.tabs.empty;
  if (str.length > 20) return '${str.substring(0, 17)}...';
  return str;
}

/// Shows explicit per-booru override values next to a global setting.
class _GlobalOverridesWrapper extends StatelessWidget {
  const _GlobalOverridesWrapper({
    required this.state,
    required this.child,
  });

  final SettingState<dynamic> state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: state._booruOverrides,
      builder: (context, overrides, _) {
        final entries = overrides.entries.where((entry) => !state.valuesEqual(entry.value, state.globalValue)).toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

        return SettingChromeScope(
          chip: entries.isEmpty ? null : _GlobalOverridesChip(state: state, entries: entries),
          child: child,
        );
      },
    );
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !_deepEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length && a.every(b.contains);
  }
  return a == b;
}

/// Small read-only chip shown on global settings that have booru overrides.
class _GlobalOverridesChip extends StatelessWidget {
  const _GlobalOverridesChip({
    required this.state,
    required this.entries,
  });

  final SettingState<dynamic> state;
  final List<MapEntry<String, dynamic>> entries;

  String label(BuildContext context) {
    if (entries.length == 1) {
      final entry = entries.first;
      return '${entry.key}: ${_formatValue(context, entry.value)}';
    }

    final first = entries.first;
    return '${first.key}: ${_formatValue(context, first.value)}, +${entries.length - 1}';
  }

  Future<void> _openOverride(BuildContext context, BuildContext dialogContext, String booruName) async {
    final booruList = SettingsHandler.instance.booruList;
    final booruIndex = booruList.indexWhere((item) => item.name == booruName);
    final booru = booruIndex >= 0 ? booruList[booruIndex] : null;
    if (booru == null) return;

    Navigator.pop(dialogContext);

    final initialCategory = state.def.categories.isNotEmpty ? state.def.categories.first : null;
    await SettingsPageOpen(
      context: context,
      page: (_) => BooruEdit.edit(
        booru,
        initialSection: BooruEditSection.overrides,
        initialOverrideCategory: initialCategory,
        initialOverrideSettingKey: state.def.key,
      ),
    ).open();
  }

  void _showAllOverrides(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(state.def.localization.title(context)),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _formatValue(context, entry.value),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openOverride(context, ctx, entry.key),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    context.loc.settings.perBooruSettings,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: const [
          CloseDialogButton(withIcon: true),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.secondaryContainer;
    final onColor = theme.colorScheme.onSecondaryContainer;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAllOverrides(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: 12,
                color: onColor,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: onColor,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 12,
                color: onColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a setting widget with per-booru override controls when editing
/// booru-specific settings inside a [BooruEditingScope].
///
/// The setting is always fully interactive. When the user changes the value,
/// [setScopedValue] creates a per-booru override automatically.
/// A badge appears when the override differs from the global value,
/// allowing the user to reset it.
class _BooruOverrideWrapper extends StatelessWidget {
  const _BooruOverrideWrapper({
    required this.state,
    required this.booruName,
    required this.child,
  });

  final SettingState<dynamic> state;
  final String booruName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: state._booruOverrides,
      builder: (context, overrides, _) {
        final hasOverride = overrides.containsKey(booruName);
        final globalValue = state.globalValue;

        return SettingChromeScope(
          chip: hasOverride
              ? _OverrideBadge(
                  globalValueLabel: _formatValue(context, globalValue),
                  onReset: () => state.removeOverrideFor(
                    booruName,
                    save: BooruEditingScope.autosaveOf(context),
                  ),
                )
              : null,
          child: child,
        );
      },
    );
  }
}

/// Small badge shown on settings that have an active per-booru override
/// that differs from the global value. Tapping resets to the global value.
class _OverrideBadge extends StatelessWidget {
  const _OverrideBadge({
    required this.onReset,
    this.globalValueLabel,
  });

  final VoidCallback onReset;
  final String? globalValueLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primaryContainer;
    final onColor = theme.colorScheme.onPrimaryContainer;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onReset,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune,
                size: 12,
                color: onColor,
              ),
              const SizedBox(width: 2),
              Text(
                globalValueLabel != null
                    ? context.loc.settings.globalValue(value: globalValueLabel!)
                    : context.loc.settings.theme.custom,
                style: TextStyle(
                  fontSize: 10,
                  color: onColor,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.close,
                size: 12,
                color: onColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
