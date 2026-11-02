import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_builder.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';

/// Builds a help icon button when [localization.helpText] is provided.
/// Returns null otherwise, so it can be used as a fallback for trailingIcon.
Widget? _buildHelpButton(BuildContext context, SettingLocalization localization) {
  if (localization.helpText == null) return null;
  return IconButton(
    icon: const Icon(Icons.help_outline),
    onPressed: () {
      showDialog(
        context: context,
        builder: (ctx) => SettingsDialog(
          title: Text(localization.title(ctx)),
          contentItems: [Text(localization.helpText!(ctx))],
        ),
      );
    },
  );
}

/// Builds a help icon button when [widgetConfig.helpDialog] is provided.
/// Returns null otherwise, so it can be used as a fallback for trailingIcon.
Widget? _buildHelpDialogButton(
  BuildContext context,
  SettingLocalization localization,
  SettingWidgetConfig? widgetConfig,
) {
  if (widgetConfig?.helpDialog == null) return null;
  return IconButton(
    icon: const Icon(Icons.help_outline),
    onPressed: () {
      showDialog(
        context: context,
        builder: (ctx) => widgetConfig!.helpDialog!(ctx),
      );
    },
  );
}

Widget _withExtraWidgets(
  BuildContext context,
  SettingWidgetConfig? widgetConfig,
  Widget child,
) {
  final extraWidgets = widgetConfig?.extraWidgets?.call(context) ?? const <Widget>[];
  if (extraWidgets.isEmpty) return child;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      child,
      ...extraWidgets,
    ],
  );
}

/// Factory for boolean toggle settings.
///
/// Renders as a [SettingsToggle] widget.
SettingDef<bool> boolSetting({
  required SettingKey key,
  required bool Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isTransient = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(bool oldValue, bool newValue)? onChanged,
}) {
  return SettingDef<bool>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isTransient: isTransient,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
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
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<bool>;
      return SettingBuilder<bool>(
        setting: s,
        builder: (ctx, value) => _withExtraWidgets(
          ctx,
          widgetConfig,
          SettingsToggle(
            title: localization.title(ctx),
            subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
            value: s.scopedValue(ctx),
            defaultValue: s.resetValue(ctx),
            onReset: () => s.resetScoped(ctx),
            onChanged: (newValue) => s.setScopedValue(ctx, newValue),
            enabled: enabledWhen?.call(ctx) ?? true,
            leadingIcon: widgetConfig?.leadingIcon,
            trailingIcon:
                widgetConfig?.trailingIcon ??
                _buildHelpDialogButton(ctx, localization, widgetConfig) ??
                _buildHelpButton(ctx, localization),
          ),
        ),
      );
    },
  );
}

/// Factory for integer settings with min/max validation.
///
/// Renders as a [SettingsTextInput] with number buttons.
SettingDef<int> intSetting({
  required SettingKey key,
  required int Function() getDefaultValue,
  required SettingLocalization localization,
  required int min,
  required int max,
  int step = 1,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(int oldValue, int newValue)? onChanged,
}) {
  int validate(int value) => value.clamp(min, max);

  return SettingDef<int>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    validate: validate,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      final int? parsed = json is String ? int.tryParse(json) : (json is int ? json : null);
      if (parsed == null || parsed < min || parsed > max) {
        return getDefaultValue();
      }
      return parsed;
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<int>;
      return _NumericSettingWidget<int>(
        parse: int.tryParse,
        state: s,
        localization: localization,
        widgetConfig: widgetConfig,
        min: min,
        max: max,
        step: step,
        enabledWhen: enabledWhen,
      );
    },
  );
}

/// Factory for double settings with min/max validation.
///
/// Renders as a [SettingsTextInput].
SettingDef<double> doubleSetting({
  required SettingKey key,
  required double Function() getDefaultValue,
  required SettingLocalization localization,
  required double min,
  required double max,
  double step = 0.1,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(double oldValue, double newValue)? onChanged,
}) {
  double validate(double value) => value.isFinite ? value.clamp(min, max) : getDefaultValue();

  return SettingDef<double>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    validate: validate,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      final double? parsed = json is String
          ? double.tryParse(json)
          : (json is double
                ? json
                : json is int
                ? json.toDouble()
                : null);
      if (parsed == null || !parsed.isFinite || parsed < min || parsed > max) {
        return getDefaultValue();
      }
      return parsed;
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<double>;
      return _NumericSettingWidget<double>(
        parse: double.tryParse,
        decimal: true,
        state: s,
        localization: localization,
        widgetConfig: widgetConfig,
        min: min,
        max: max,
        step: step,
        enabledWhen: enabledWhen,
      );
    },
  );
}

/// Factory for string settings.
///
/// Renders as a [SettingsTextInput].
SettingDef<String> stringSetting({
  required SettingKey key,
  required String Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  bool obscureable = false,
  bool copyable = false,
  bool pasteable = false,
  TextInputType inputType = TextInputType.text,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(String oldValue, String newValue)? onChanged,
}) {
  return SettingDef<String>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is String) return json;
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<String>;
      return _StringSettingWidget(
        state: s,
        localization: localization,
        widgetConfig: widgetConfig,
        inputType: inputType,
        obscureable: obscureable,
        copyable: copyable,
        pasteable: pasteable,
        enabledWhen: enabledWhen,
      );
    },
  );
}

/// Display mode for enum settings.
enum EnumDisplayMode { dropdown, optionsList, segmented }

/// Factory for enum settings.
///
/// Renders as [SettingsDropdown], [SettingsOptionsList], or [SettingsSegmentedButton]
/// depending on [displayMode].
///
/// Replaces [SettingsEnumRegistry] - each enum setting carries its own
/// `fromString`/`toJson` logic.
SettingDef<T> enumSetting<T extends Enum>({
  required SettingKey key,
  required T Function() getDefaultValue,
  required SettingLocalization localization,
  required List<T> values,
  required T Function(String name) fromString,
  required String Function(T value) enumToJson,
  required String Function(BuildContext context, T value) enumLocName,
  Widget? Function(BuildContext context, T? value)? itemLeadingBuilder,
  EnumDisplayMode displayMode = EnumDisplayMode.dropdown,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(T oldValue, T newValue)? onChanged,
}) {
  // Augment search keywords to include enum option labels
  final augmentedLocalization = SettingLocalization(
    title: localization.title,
    subtitle: localization.subtitle,
    helpText: localization.helpText,
    searchKeywords: (ctx) {
      final base = localization.searchKeywords?.call(ctx) ?? [];
      final optionNames = values.map((v) => enumLocName(ctx, v)).toList();
      return [...base, ...optionNames];
    },
  );

  return SettingDef<T>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: augmentedLocalization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => enumToJson(v),
    valueFromJson: (json) {
      if (json is String) {
        try {
          return fromString(json);
        } catch (_) {
          // fromString may throw on invalid input
        }
      }
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<T>;
      return SettingBuilder<T>(
        setting: s,
        builder: (ctx, value) {
          final scopedVal = s.scopedValue(ctx);
          final trailingIcon =
              widgetConfig?.trailingIcon ??
              _buildHelpDialogButton(ctx, augmentedLocalization, widgetConfig) ??
              _buildHelpButton(ctx, augmentedLocalization);
          switch (displayMode) {
            case EnumDisplayMode.dropdown:
              return _withExtraWidgets(
                ctx,
                widgetConfig,
                SettingsDropdown<T>(
                  title: localization.title(ctx),
                  subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                  value: scopedVal,
                  items: values,
                  itemTitleBuilder: (item) => item != null ? enumLocName(ctx, item) : '',
                  onChanged: (newValue) {
                    if (newValue != null) s.setScopedValue(ctx, newValue);
                  },
                  onReset: scopedVal != s.resetValue(ctx) ? () => s.resetScoped(ctx) : null,
                  trailingIcon: trailingIcon,
                ),
              );
            case EnumDisplayMode.optionsList:
              return _withExtraWidgets(
                ctx,
                widgetConfig,
                SettingsOptionsList<T>(
                  title: localization.title(ctx),
                  subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                  value: scopedVal,
                  items: values,
                  itemTitleBuilder: (item) => item != null ? enumLocName(ctx, item) : '',
                  itemLeadingBuilder: itemLeadingBuilder != null ? (item) => itemLeadingBuilder(ctx, item) : null,
                  onChanged: (newValue) {
                    if (newValue != null) s.setScopedValue(ctx, newValue);
                  },
                  onReset: scopedVal != s.resetValue(ctx) ? () => s.resetScoped(ctx) : null,
                  trailingIcon: trailingIcon,
                ),
              );
            case EnumDisplayMode.segmented:
              return _withExtraWidgets(
                ctx,
                widgetConfig,
                SettingsSegmentedButton<T>(
                  title: localization.title(ctx),
                  subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                  value: scopedVal,
                  values: values,
                  defaultValue: s.resetValue(ctx),
                  onReset: () => s.resetScoped(ctx),
                  itemTitleBuilder: (item) => enumLocName(ctx, item),
                  onChanged: (newValue) => s.setScopedValue(ctx, newValue),
                ),
              );
          }
        },
      );
    },
  );
}

/// Factory for duration settings (stored as seconds in JSON).
///
/// When [options] is provided, renders as a [SettingsDropdown] with those
/// predefined duration choices. When [options] is null, renders as a text input.
SettingDef<Duration> durationSetting({
  required SettingKey key,
  required Duration Function() getDefaultValue,
  required SettingLocalization localization,
  required String Function(BuildContext context, Duration value) durationLocName,
  List<Duration>? options,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(Duration oldValue, Duration newValue)? onChanged,
}) {
  return SettingDef<Duration>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v.inSeconds,
    valueFromJson: (json) {
      if (json is int) return Duration(seconds: json);
      return getDefaultValue();
    },
    widgetBuilder: options != null
        ? (context, dynamic state) {
            final s = state as SettingState<Duration>;
            return SettingBuilder<Duration>(
              setting: s,
              builder: (ctx, value) => SettingsDropdown<Duration>(
                title: localization.title(ctx),
                subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                value: s.scopedValue(ctx),
                items: options,
                itemTitleBuilder: (item) => item != null ? durationLocName(ctx, item) : '',
                onChanged: (newValue) {
                  if (newValue != null) s.setScopedValue(ctx, newValue);
                },
                onReset: s.scopedValue(ctx) != s.resetValue(ctx) ? () => s.resetScoped(ctx) : null,
              ),
            );
          }
        : null,
  );
}

/// Factory for string list settings.
///
/// When [navigateTo] is provided, renders as a [SettingsButton] that navigates
/// to a dedicated editor page. This is appropriate for complex list UIs like
/// drag-to-reorder or tag management. Without [navigateTo], the widget builder
/// is null and the setting won't appear on auto-pages.
SettingDef<List<String>> stringListSetting({
  required SettingKey key,
  required List<String> Function() getDefaultValue,
  required SettingLocalization localization,
  List<String> legacyJsonKeys = const [],
  Widget Function()? navigateTo,
  Object? icon,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(List<String> oldValue, List<String> newValue)? onChanged,
}) {
  return SettingDef<List<String>>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    legacyJsonKeys: legacyJsonKeys,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is List) return json.whereType<String>().toList();
      if (json is String && json.isNotEmpty) return json.split(',');
      return getDefaultValue();
    },
    widgetBuilder: navigateTo != null
        ? (context, dynamic state) {
            return SettingsButton(
              name: localization.title(context),
              icon: icon != null
                  ? switch (icon) {
                      IconData _ => Icon(icon),
                      FaIconData _ => FaIcon(icon),
                      _ => null,
                    }
                  : null,
              page: navigateTo,
            );
          }
        : null,
  );
}

// ============================================
// STATEFUL WIDGET WRAPPERS
// ============================================
// These manage TextEditingControllers for settings that use SettingsTextInput.

class _NumericSettingWidget<T extends num> extends StatefulWidget {
  const _NumericSettingWidget({
    required this.state,
    required this.localization,
    required this.min,
    required this.max,
    required this.step,
    required this.parse,
    this.decimal = false,
    this.widgetConfig,
    this.enabledWhen,
  });

  final SettingState<T> state;
  final SettingLocalization localization;
  final SettingWidgetConfig? widgetConfig;
  final num min;
  final num max;
  final num step;
  final T? Function(String) parse;
  final bool decimal;
  final bool Function([BuildContext? context])? enabledWhen;

  @override
  State<_NumericSettingWidget<T>> createState() => _NumericSettingWidgetState<T>();
}

class _NumericSettingWidgetState<T extends num> extends State<_NumericSettingWidget<T>> with WidgetsBindingObserver {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  late SettingState<T> _observed;
  String? _scopeName;
  bool _autosave = true;
  bool _dirty = false;
  bool _writing = false;
  T? _lastValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.globalValue.toString());
    _observe(widget.state);
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _observe(SettingState<T> state) {
    _observed = state;
    state.globalNotifier.addListener(_onValueChanged);
    state.overridesNotifier.addListener(_onValueChanged);
  }

  void _stopObserving() {
    _observed.globalNotifier.removeListener(_onValueChanged);
    _observed.overridesNotifier.removeListener(_onValueChanged);
  }

  @override
  void didUpdateWidget(covariant _NumericSettingWidget<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      _commit(target: oldWidget.state, refresh: false);
      _stopObserving();
      _observe(widget.state);
      _sync(force: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = widget.state.def.supportsPerBooru ? BooruEditingScope.of(context) : null;
    final scopeChanged = scope != _scopeName;
    if (scopeChanged) _commit(refresh: false);
    _scopeName = scope;
    _autosave = BooruEditingScope.autosaveOf(context);
    _sync(force: scopeChanged || _lastValue == null);
  }

  T _value(SettingState<T> state) => _scopeName == null ? state.globalValue : state.valueForBooru(_scopeName);

  void _sync({bool force = false}) {
    final value = _value(widget.state);
    if (force || _lastValue == null || !widget.state.valuesEqual(_lastValue!, value)) {
      _lastValue = value;
      _dirty = false;
      if (_controller.text != value.toString()) _controller.text = value.toString();
    }
  }

  void _onValueChanged() {
    if (_writing) return;
    _sync();
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _commit();
    }
  }

  void _commit({SettingState<T>? target, bool refresh = true}) {
    final publish = _takeDraftCommit(target);
    if (publish != null) {
      _writing = true;
      try {
        publish();
      } finally {
        _writing = false;
      }
    }
    if (refresh) {
      _sync(force: true);
      if (mounted) setState(() {});
    }
  }

  VoidCallback? _takeDraftCommit([SettingState<T>? target]) {
    if (!_dirty) return null;
    _dirty = false;
    final parsed = widget.parse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) return null;
    final state = target ?? widget.state;
    final scope = _scopeName;
    final autosave = _autosave;
    return () {
      if (scope == null) {
        state.setValue(parsed, debounceSave: true);
      } else {
        // A cancelled draft's parent removes its overrides during unmount.
        if (!autosave && !state.hasOverrideFor(scope)) return;
        final validated = state.def.validate?.call(parsed) ?? parsed;
        if (state.valuesEqual(validated, state.globalValue)) {
          state.removeOverrideFor(scope, save: autosave);
        } else {
          state.setOverrideFor(scope, validated, save: autosave, debounceSave: true);
        }
      }
    };
  }

  void _reset() {
    _dirty = false;
    _writing = true;
    try {
      if (_scopeName == null) {
        widget.state.reset();
      } else {
        widget.state.removeOverrideFor(_scopeName!, save: _autosave);
      }
    } finally {
      _writing = false;
    }
    _sync(force: true);
    setState(() {});
  }

  @override
  void dispose() {
    // Publish after the locked unmount phase, without retaining widget state.
    final publish = _takeDraftCommit();
    WidgetsBinding.instance.removeObserver(this);
    _stopObserving();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
    if (publish != null) scheduleMicrotask(publish);
  }

  @override
  Widget build(BuildContext context) {
    return _withExtraWidgets(
      context,
      widget.widgetConfig,
      SettingsTextInput(
        controller: _controller,
        focusNode: _focus,
        title: widget.localization.title(context),
        subtitle: widget.localization.subtitle != null ? Text(widget.localization.subtitle!(context)) : null,
        trailingIcon:
            widget.widgetConfig?.trailingIcon ??
            _buildHelpDialogButton(context, widget.localization, widget.widgetConfig) ??
            _buildHelpButton(context, widget.localization),
        inputType: TextInputType.numberWithOptions(decimal: widget.decimal, signed: widget.min < 0),
        textInputAction: TextInputAction.done,
        enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
        numberButtons: !widget.decimal,
        numberStep: widget.step.toDouble(),
        numberMin: widget.min.toDouble(),
        numberMax: widget.max.toDouble(),
        resetText: () => widget.state.resetValue(context).toString(),
        onReset: _reset,
        validator: (text) {
          final parsed = widget.parse(text?.trim() ?? '');
          return parsed == null || !parsed.isFinite || parsed < widget.min || parsed > widget.max
              ? '${widget.min} – ${widget.max}'
              : null;
        },
        onChanged: (_) => _dirty = true,
        onNumberChanged: (_) {
          _dirty = true;
          _commit();
        },
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _StringSettingWidget extends StatefulWidget {
  const _StringSettingWidget({
    required this.state,
    required this.localization,
    this.widgetConfig,
    this.inputType = TextInputType.text,
    this.obscureable = false,
    this.copyable = false,
    this.pasteable = false,
    this.enabledWhen,
  });

  final SettingState<String> state;
  final SettingLocalization localization;
  final SettingWidgetConfig? widgetConfig;
  final TextInputType inputType;
  final bool obscureable;
  final bool copyable;
  final bool pasteable;
  final bool Function([BuildContext? context])? enabledWhen;

  @override
  State<_StringSettingWidget> createState() => _StringSettingWidgetState();
}

class _StringSettingWidgetState extends State<_StringSettingWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.value);
    widget.state.globalNotifier.addListener(_onValueChanged);
    widget.state.overridesNotifier.addListener(_onValueChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onValueChanged();
  }

  @override
  void didUpdateWidget(covariant _StringSettingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.globalNotifier.removeListener(_onValueChanged);
      oldWidget.state.overridesNotifier.removeListener(_onValueChanged);
      widget.state.globalNotifier.addListener(_onValueChanged);
      widget.state.overridesNotifier.addListener(_onValueChanged);
      _onValueChanged();
    }
  }

  @override
  void dispose() {
    widget.state.globalNotifier.removeListener(_onValueChanged);
    widget.state.overridesNotifier.removeListener(_onValueChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    final newText = widget.state.scopedValue(context);
    if (_controller.text != newText) {
      _controller.text = newText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _withExtraWidgets(
      context,
      widget.widgetConfig,
      SettingsTextInput(
        controller: _controller,
        title: widget.localization.title(context),
        subtitle: widget.localization.subtitle != null ? Text(widget.localization.subtitle!(context)) : null,
        trailingIcon:
            widget.widgetConfig?.trailingIcon ??
            _buildHelpDialogButton(context, widget.localization, widget.widgetConfig) ??
            _buildHelpButton(context, widget.localization),
        inputType: widget.inputType,
        obscureable: widget.obscureable,
        enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
        enableSuggestions: !widget.obscureable,
        autocorrect: !widget.obscureable,
        copyable: widget.copyable,
        pasteable: widget.pasteable,
        resetText: () => widget.state.resetValue(context),
        onReset: () => widget.state.resetScoped(context),
        onChanged: (newValue) => widget.state.setScopedValue(context, newValue, debounceSave: true),
      ),
    );
  }
}

/// Factory for widget-only slots — custom inline widgets that appear among
/// auto-generated settings without being actual settings.
///
/// Widget slots are excluded from serialization, search, and sync.
/// Use for custom UI like drag-to-reorder lists, action buttons, cache stats,
/// etc. that need to appear in a specific position within a category.
SettingDef<bool> widgetSlot({
  required SettingKey key,
  required List<SettingCategory> categories,
  required Widget Function(BuildContext context) builder,
  List<SettingSubcategory> subcategories = const [],
  List<SettingKey>? dependsOn,
  bool Function()? visibleWhen,
  bool Function([BuildContext? context])? enabledWhen,
}) {
  return SettingDef<bool>(
    key: key,
    getDefaultValue: () => false,
    localization: const SettingLocalization(title: _noop),
    valueToJson: (_) => null,
    valueFromJson: (_) => false,
    categories: categories,
    subcategories: subcategories,
    isWidgetSlot: true,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    widgetBuilder: (context, _) => builder(context),
  );
}

String _noop(BuildContext _) => '';
