import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_builder.dart';

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

/// Factory for boolean toggle settings.
///
/// Renders as a [SettingsToggle] widget.
SettingDef<bool> boolSetting({
  required SettingKey key,
  required bool Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isTransient = false,
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
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isTransient: isTransient,
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
        builder: (ctx, value) => SettingsToggle(
          title: localization.title(ctx),
          subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
          value: s.scopedValue(ctx),
          defaultValue: s.defaultValue,
          onChanged: (newValue) => s.setScopedValue(ctx, newValue),
          enabled: enabledWhen?.call() ?? true,
          leadingIcon: widgetConfig?.leadingIcon,
          trailingIcon:
              widgetConfig?.trailingIcon ??
              _buildHelpDialogButton(ctx, localization, widgetConfig) ??
              _buildHelpButton(ctx, localization),
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
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
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
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
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
      return _IntSettingWidget(
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
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(double oldValue, double newValue)? onChanged,
}) {
  double validate(double value) => value.clamp(min, max);

  return SettingDef<double>(
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
      final double? parsed = json is String
          ? double.tryParse(json)
          : (json is double
                ? json
                : json is int
                ? json.toDouble()
                : null);
      if (parsed == null || parsed < min || parsed > max) {
        return getDefaultValue();
      }
      return parsed;
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<double>;
      return _DoubleSettingWidget(
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
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
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
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
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
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
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
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
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
              return SettingsDropdown<T>(
                title: localization.title(ctx),
                subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                value: scopedVal,
                items: values,
                itemTitleBuilder: (item) => item != null ? enumLocName(ctx, item) : '',
                onChanged: (newValue) {
                  if (newValue != null) s.setScopedValue(ctx, newValue);
                },
                trailingIcon: trailingIcon,
              );
            case EnumDisplayMode.optionsList:
              return SettingsOptionsList<T>(
                title: localization.title(ctx),
                subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                value: scopedVal,
                items: values,
                itemTitleBuilder: (item) => item != null ? enumLocName(ctx, item) : '',
                itemLeadingBuilder: itemLeadingBuilder != null ? (item) => itemLeadingBuilder(ctx, item) : null,
                onChanged: (newValue) {
                  if (newValue != null) s.setScopedValue(ctx, newValue);
                },
                trailingIcon: trailingIcon,
              );
            case EnumDisplayMode.segmented:
              return SettingsSegmentedButton<T>(
                title: localization.title(ctx),
                subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
                value: scopedVal,
                values: values,
                defaultValue: s.defaultValue,
                itemTitleBuilder: (item) => enumLocName(ctx, item),
                onChanged: (newValue) => s.setScopedValue(ctx, newValue),
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
  bool isDeviceSpecific = false,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(Duration oldValue, Duration newValue)? onChanged,
}) {
  return SettingDef<Duration>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    isDeviceSpecific: isDeviceSpecific,
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
  IconData? icon,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
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
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is List) return List<String>.from(json);
      if (json is String && json.isNotEmpty) return json.split(',');
      return getDefaultValue();
    },
    widgetBuilder: navigateTo != null
        ? (context, dynamic state) {
            return SettingsButton(
              name: localization.title(context),
              icon: icon != null ? Icon(icon) : null,
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

class _IntSettingWidget extends StatefulWidget {
  const _IntSettingWidget({
    required this.state,
    required this.localization,
    required this.min,
    required this.max,
    required this.step,
    this.widgetConfig,
    this.enabledWhen,
  });

  final SettingState<int> state;
  final SettingLocalization localization;
  final SettingWidgetConfig? widgetConfig;
  final int min;
  final int max;
  final int step;
  final bool Function([BuildContext? context])? enabledWhen;

  @override
  State<_IntSettingWidget> createState() => _IntSettingWidgetState();
}

class _IntSettingWidgetState extends State<_IntSettingWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.value.toString());
    widget.state.effectiveNotifier.addListener(_onValueChanged);
    widget.state.overridesNotifier.addListener(_onValueChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onValueChanged();
  }

  @override
  void dispose() {
    widget.state.effectiveNotifier.removeListener(_onValueChanged);
    widget.state.overridesNotifier.removeListener(_onValueChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    final newText = widget.state.scopedValue(context).toString();
    if (_controller.text != newText) {
      _controller.text = newText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTextInput(
      controller: _controller,
      title: widget.localization.title(context),
      subtitle: widget.localization.subtitle != null ? Text(widget.localization.subtitle!(context)) : null,
      trailingIcon:
          widget.widgetConfig?.trailingIcon ??
          _buildHelpDialogButton(context, widget.localization, widget.widgetConfig) ??
          _buildHelpButton(context, widget.localization),
      inputType: TextInputType.number,
      numberButtons: true,
      numberStep: widget.step.toDouble(),
      numberMin: widget.min.toDouble(),
      numberMax: widget.max.toDouble(),
      resetText: () => widget.state.defaultValue.toString(),
      onChanged: (newValue) {
        final parsed = int.tryParse(newValue);
        if (parsed != null) widget.state.setScopedValue(context, parsed);
      },
    );
  }
}

class _DoubleSettingWidget extends StatefulWidget {
  const _DoubleSettingWidget({
    required this.state,
    required this.localization,
    required this.min,
    required this.max,
    required this.step,
    this.widgetConfig,
    this.enabledWhen,
  });

  final SettingState<double> state;
  final SettingLocalization localization;
  final SettingWidgetConfig? widgetConfig;
  final double min;
  final double max;
  final double step;
  final bool Function([BuildContext? context])? enabledWhen;

  @override
  State<_DoubleSettingWidget> createState() => _DoubleSettingWidgetState();
}

class _DoubleSettingWidgetState extends State<_DoubleSettingWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.value.toString());
    widget.state.effectiveNotifier.addListener(_onValueChanged);
    widget.state.overridesNotifier.addListener(_onValueChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onValueChanged();
  }

  @override
  void dispose() {
    widget.state.effectiveNotifier.removeListener(_onValueChanged);
    widget.state.overridesNotifier.removeListener(_onValueChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    final newText = widget.state.scopedValue(context).toString();
    if (_controller.text != newText) {
      _controller.text = newText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTextInput(
      controller: _controller,
      title: widget.localization.title(context),
      subtitle: widget.localization.subtitle != null ? Text(widget.localization.subtitle!(context)) : null,
      trailingIcon:
          widget.widgetConfig?.trailingIcon ??
          _buildHelpDialogButton(context, widget.localization, widget.widgetConfig) ??
          _buildHelpButton(context, widget.localization),
      inputType: const TextInputType.numberWithOptions(decimal: true),
      resetText: () => widget.state.defaultValue.toString(),
      onChanged: (newValue) {
        final parsed = double.tryParse(newValue);
        if (parsed != null) widget.state.setScopedValue(context, parsed);
      },
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
    widget.state.effectiveNotifier.addListener(_onValueChanged);
    widget.state.overridesNotifier.addListener(_onValueChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onValueChanged();
  }

  @override
  void dispose() {
    widget.state.effectiveNotifier.removeListener(_onValueChanged);
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
    return SettingsTextInput(
      controller: _controller,
      title: widget.localization.title(context),
      subtitle: widget.localization.subtitle != null ? Text(widget.localization.subtitle!(context)) : null,
      trailingIcon:
          widget.widgetConfig?.trailingIcon ??
          _buildHelpDialogButton(context, widget.localization, widget.widgetConfig) ??
          _buildHelpButton(context, widget.localization),
      inputType: widget.inputType,
      obscureable: widget.obscureable,
      copyable: widget.copyable,
      pasteable: widget.pasteable,
      resetText: () => widget.state.defaultValue,
      onChanged: (newValue) => widget.state.setScopedValue(context, newValue),
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
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
}) {
  return SettingDef<bool>(
    key: key,
    getDefaultValue: () => false,
    localization: const SettingLocalization(title: _noop),
    valueToJson: (_) => null,
    valueFromJson: (_) => false,
    categories: categories,
    isWidgetSlot: true,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    widgetBuilder: (context, _) => builder(context),
  );
}

String _noop(BuildContext _) => '';
