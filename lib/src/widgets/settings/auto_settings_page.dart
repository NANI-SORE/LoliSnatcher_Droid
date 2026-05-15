import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';

/// A settings page that auto-renders all settings for a given [SettingCategory].
///
/// Reads settings from [SettingsRegistry], filters by category, and builds
/// each setting's widget via [SettingState.buildWidget]. Settings without a
/// `widgetBuilder` are skipped.
///
/// Settings with [SettingDef.enabledWhen] + [SettingDef.dependsOn] are
/// reactively shown/hidden when their dependency settings change value.
///
/// By default, syncs and saves settings when the page is popped
/// (see [saveOnPop], [restateOnPop]). Set [saveOnPop] to false if the
/// parent widget handles saving itself (e.g. via a custom [PopScope]).
///
/// Usage:
/// ```dart
/// // Simple — auto-saves on pop:
/// const AutoSettingsPage(category: SettingCategory.video)
///
/// // Custom pop handling:
/// PopScope(
///   onPopInvokedWithResult: myCustomOnPop,
///   child: const AutoSettingsPage(
///     category: SettingCategory.interface,
///     saveOnPop: false,
///   ),
/// )
/// ```
class AutoSettingsPage extends StatelessWidget {
  const AutoSettingsPage({
    required this.category,
    this.header,
    this.footer,
    this.extraWidgets = const [],
    this.saveOnPop = true,
    this.restateOnPop = false,
    super.key,
  });

  /// The category of settings to display.
  final SettingCategory category;

  /// Optional widget shown above the settings list.
  final Widget? header;

  /// Optional widget shown below the settings list.
  final Widget? footer;

  /// Additional widgets to insert after the auto-generated setting widgets.
  /// Useful for action buttons (e.g. "Clear cache"), info text, etc.
  final List<Widget> extraWidgets;

  /// Whether to automatically sync and save settings when the page is popped.
  /// Defaults to true. Set to false when using a custom [PopScope] wrapper.
  final bool saveOnPop;

  /// Whether to trigger a global restate after saving.
  /// Only applies when [saveOnPop] is true.
  final bool restateOnPop;

  void _onPop(_, _) {
    final settingsHandler = SettingsHandler.instance;
    settingsHandler.saveSettings(restate: restateOnPop);
  }

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final states = registry.byCategory(category);

    // Filter to only settings that have a widget builder
    final renderableStates = states.where((s) => s.def.widgetBuilder != null).toList();

    // Listen to all settings in this category to reactively show/hide reset button
    final allNotifiers = renderableStates
        .where((s) => !s.def.isWidgetSlot)
        .map((s) => s.effectiveNotifier as Listenable)
        .toList();

    Widget body = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: SettingsAppBar(
        title: category.locName(context),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge(allNotifiers),
            builder: (context, _) {
              final hasModified = renderableStates.any((s) => !s.def.isWidgetSlot && s.isModified);
              if (!hasModified) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.restart_alt),
                tooltip: context.loc.reset,
                onPressed: () => _confirmReset(context, registry, renderableStates),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ListView(
          children: [
            ?header,
            for (final state in renderableStates) ReactiveSettingWidget(state: state),
            ...extraWidgets,
            ?footer,
          ],
        ),
      ),
    );

    if (saveOnPop) {
      body = PopScope(
        onPopInvokedWithResult: _onPop,
        child: body,
      );
    }

    return body;
  }

  void _confirmReset(
    BuildContext context,
    SettingsRegistry registry,
    List<SettingState<dynamic>> states,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(context.loc.reset),
        contentItems: [
          Text(
            'Reset all ${category.locName(context)} settings to their defaults?'.temploc,
          ),
        ],
        actionButtons: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.loc.cancel),
          ),
          TextButton(
            onPressed: () {
              for (final state in states) {
                if (!state.def.isWidgetSlot) {
                  state.reset();
                }
              }
              Navigator.pop(ctx, true);
            },
            child: Text(context.loc.reset),
          ),
        ],
      ),
    );
  }
}

/// A settings page that renders multiple categories, each as a section with
/// a header divider.
///
/// Useful for pages that combine settings from several related categories
/// (e.g. a "General" page showing interface + theme settings).
class MultiCategorySettingsPage extends StatelessWidget {
  const MultiCategorySettingsPage({
    required this.title,
    required this.categories,
    this.extraWidgets = const [],
    super.key,
  });

  /// Page title shown in the app bar.
  final String title;

  /// Categories to display, in order.
  final List<SettingCategory> categories;

  /// Additional widgets appended after all category sections.
  final List<Widget> extraWidgets;

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: SettingsAppBar(title: title),
      body: Center(
        child: ListView(
          children: [
            for (final cat in categories) ...[
              if (categories.length > 1) ...[
                SettingsButton(
                  name: cat.locName(context),
                  icon: switch (cat.icon) {
                    IconData _ => Icon(cat.icon),
                    FontAwesomeIcons _ => FaIcon(cat.icon),
                    _ => const Icon(null),
                  },
                  enabled: false,
                ),
              ],
              for (final state in registry.byCategory(cat))
                if (state.def.widgetBuilder != null) ReactiveSettingWidget(state: state),
            ],
            ...extraWidgets,
          ],
        ),
      ),
    );
  }
}

/// Wraps a single setting widget with reactive visibility.
///
/// When the setting has [SettingDef.dependsOn] + [SettingDef.enabledWhen],
/// this widget listens to all dependency settings and reactively shows/hides
/// the setting widget when the condition changes. Settings without dependencies
/// are always shown.
///
/// When inside a [BooruEditingScope], the [enabledWhen] condition receives
/// the [BuildContext] so that `_val()` reads scoped (per-booru) values instead
/// of global/effective values. Dependency notifiers include the override map
/// notifiers so that changes to per-booru overrides trigger re-evaluation.
class ReactiveSettingWidget extends StatelessWidget {
  const ReactiveSettingWidget({required this.state, super.key});

  final SettingState<dynamic> state;

  @override
  Widget build(BuildContext context) {
    final dependsOn = state.def.dependsOn;
    final enabledWhen = state.def.enabledWhen;

    // No enabledWhen — always show
    if (enabledWhen == null) {
      return state.buildWidget(context);
    }

    final isEditingBooru = BooruEditingScope.of(context) != null;

    // Static condition (no dependencies to listen to) — evaluate once
    if (dependsOn == null || dependsOn.isEmpty) {
      // Pass context when editing a booru so _val reads scoped values
      if (!enabledWhen(isEditingBooru ? context : null)) {
        return const SizedBox.shrink();
      }
      return state.buildWidget(context);
    }

    // Collect dependency notifiers for reactive rebuild
    final registry = SettingsRegistry.instance;
    final dependencyNotifiers = <Listenable>[];
    for (final depKey in dependsOn) {
      final depState = registry.get<dynamic>(depKey);
      if (depState != null) {
        dependencyNotifiers.add(depState.effectiveNotifier);
        // When editing a booru, also listen to the override map so that
        // changes to per-booru overrides trigger re-evaluation.
        if (isEditingBooru && depState.def.supportsPerBooru) {
          dependencyNotifiers.add(depState.overridesNotifier);
        }
      }
    }

    if (dependencyNotifiers.isEmpty) {
      return state.buildWidget(context);
    }

    return ListenableBuilder(
      listenable: Listenable.merge(dependencyNotifiers),
      builder: (context, _) {
        final enabled = enabledWhen(isEditingBooru ? context : null);
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: enabled ? state.buildWidget(context) : const SizedBox(width: double.infinity, height: 0),
        );
      },
    );
  }
}
