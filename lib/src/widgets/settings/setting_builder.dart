import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/data/settings/setting_state.dart';

/// Convenience widget that rebuilds when a single setting's effective value changes.
///
/// Wraps [ValueListenableBuilder] for less boilerplate:
/// ```dart
/// SettingBuilder<int>(
///   setting: columnsSetting,
///   builder: (context, value) => Text('Columns: $value'),
/// )
/// ```
class SettingBuilder<T> extends StatelessWidget {
  const SettingBuilder({
    required this.setting,
    required this.builder,
    super.key,
  });

  /// The setting state to listen to.
  final SettingState<T> setting;

  /// Builder called with the current effective value whenever it changes.
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<dynamic>(
      valueListenable: setting.scopedNotifier(context),
      builder: (context, _, _) => builder(context, setting.scopedValue(context)),
    );
  }
}

/// Convenience widget that rebuilds when ANY of the given settings change.
///
/// Uses [Listenable.merge] under the hood - no nesting required:
/// ```dart
/// MultiSettingBuilder(
///   settings: [columnsSetting, previewModeSetting, filterSetting],
///   builder: (context) => GridView(
///     columns: columnsSetting.value,
///     previewMode: previewModeSetting.value,
///   ),
/// )
/// ```
class MultiSettingBuilder extends StatelessWidget {
  const MultiSettingBuilder({
    required this.settings,
    required this.builder,
    super.key,
  });

  /// The settings to listen to. Rebuilds when any of them change.
  final List<SettingState<dynamic>> settings;

  /// Builder called whenever any of the settings change.
  /// Read values directly from the setting states.
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
        settings.map((s) => s.scopedNotifier(context)).toList(),
      ),
      builder: (context, _) => builder(context),
    );
  }
}
