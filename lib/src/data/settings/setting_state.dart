import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';

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

  void setValue(T newValue, {bool debounceSave = false}) {
    final validated = def.validate?.call(newValue) ?? newValue;
    final oldValue = _globalValue.value;
    _globalValue.value = validated;
    if (oldValue != validated) {
      def.onScopedChanged?.call(oldValue, validated, null);
    }
    if (!def.supportsPerBooru && oldValue != validated) {
      def.onChanged?.call(oldValue, validated);
    }
    if (oldValue != validated) {
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
    if (oldValue != validated) {
      def.onScopedChanged?.call(oldValue, validated, null);
    }
    if (!def.supportsPerBooru && oldValue != validated) {
      def.onChanged?.call(oldValue, validated);
    }
    if (oldValue != validated) {
      _scheduleSave();
    }
  }

  /// The global value notifier. Useful for listening to global-only changes.
  ValueNotifier<T> get globalNotifier => _globalValue;

  /// Convenience getter for the current default.
  T get defaultValue => def.getDefaultValue();

  /// Whether the global value differs from the default.
  bool get isModified => globalValue != def.getDefaultValue();

  /// Reset to the default value.
  void reset() {
    value = def.getDefaultValue();
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
    final oldValue = _booruOverrides.value[booruName] ?? _globalValue.value;
    final map = Map<String, T>.from(_booruOverrides.value);
    map[booruName] = validated;
    _booruOverrides.value = map; // Triggers notification
    if (save && oldValue != validated) {
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
  /// When NOT inside a scope, returns the effective value (global or active booru override).
  T scopedValue(BuildContext context) {
    if (!def.supportsPerBooru) return value;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return value;
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
      setOverrideFor(
        editingBooru,
        newValue,
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
  /// When not in a scope, returns the effective notifier.
  ValueNotifier<dynamic> scopedNotifier(BuildContext context) {
    if (!def.supportsPerBooru) return effectiveNotifier;
    final editingBooru = BooruEditingScope.of(context);
    if (editingBooru == null) return effectiveNotifier;
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
    _suppressSideEffects = true;
    try {
      _globalValue.value = def.valueFromJson(json);
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
    if (!_state._suppressSideEffects && oldValue != newValue) {
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
String _formatValue(dynamic value) {
  if (value is bool) return value ? 'On' : 'Off';
  if (value is Enum) return value.name;
  if (value is ThemeItem) return value.name;
  if (value is Color) {
    return '#${value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
  if (value is List) return '${value.length} items';
  final str = value.toString();
  if (str.length > 20) return '${str.substring(0, 17)}...';
  return str;
}

/// Wraps a setting widget with per-booru override controls when editing
/// booru-specific settings inside a [BooruEditingScope].
///
/// The setting is always fully interactive. When the user changes the value,
/// [setScopedValue] creates a per-booru override automatically.
/// A badge appears when the override differs from the global default,
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
        final overrideValue = hasOverride ? overrides[booruName] : null;
        final globalValue = state.globalValue;
        final isDifferent = hasOverride && overrideValue != globalValue;

        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .end,

          children: [
            if (isDifferent)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4, right: 4),
                child: _OverrideBadge(
                  globalValueLabel: _formatValue(globalValue),
                  onReset: () => state.removeOverrideFor(
                    booruName,
                    save: BooruEditingScope.autosaveOf(context),
                  ),
                ),
              ),
            child,
          ],
        );
      },
    );
  }
}

/// Small badge shown on settings that have an active per-booru override
/// that differs from the global default. Tapping resets to the global value.
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
