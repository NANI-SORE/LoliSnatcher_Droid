import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
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
/// Usage:
/// ```dart
/// const AutoSettingsPage(category: SettingCategory.video)
/// ```
class AutoSettingsPage extends StatelessWidget {
  const AutoSettingsPage({
    required this.category,
    this.header,
    this.footer,
    this.extraWidgets = const [],
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

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final states = registry.byCategory(category);

    // Filter to only settings that have a widget builder
    final renderableStates = states.where((s) => registry.isSettingVisible(s) && s.def.widgetBuilder != null).toList();

    // Listen to all settings in this category to reactively show/hide reset button
    final allNotifiers = renderableStates
        .where((s) => !s.def.isWidgetSlot)
        .map((s) => s.scopedNotifier(context) as Listenable)
        .toList();

    return Scaffold(
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
            ...buildSettingSubcategorySections(
              context: context,
              category: category,
              states: renderableStates,
            ),
            ...extraWidgets,
            ?footer,
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
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
            context.loc.settings.resetCategoryQuestion(
              category: category.locName(context),
            ),
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
                  icon: cat.iconWidget(),
                  enabled: false,
                ),
              ],
              ...buildSettingSubcategorySections(
                context: context,
                category: cat,
                states: registry
                    .byCategory(cat)
                    .where((s) => registry.isSettingVisible(s) && s.def.widgetBuilder != null),
              ),
            ],
            ...extraWidgets,
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }
}

List<Widget> buildSettingSubcategorySections({
  required BuildContext context,
  required SettingCategory category,
  required Iterable<SettingState<dynamic>> states,
  Widget Function(SettingState<dynamic> state)? settingBuilder,
}) {
  final stateList = states.toList();
  if (stateList.isEmpty) return const [];

  return [
    _ReactiveSettingSubcategoryList(
      category: category,
      states: stateList,
      settingBuilder: settingBuilder,
    ),
  ];
}

class _ReactiveSettingSubcategoryList extends StatelessWidget {
  const _ReactiveSettingSubcategoryList({
    required this.category,
    required this.states,
    this.settingBuilder,
  });

  final SettingCategory category;
  final List<SettingState<dynamic>> states;
  final Widget Function(SettingState<dynamic> state)? settingBuilder;

  @override
  Widget build(BuildContext context) {
    final notifiers = _dependencyNotifiers(context);
    if (notifiers.isEmpty) {
      return _buildSectionList(context);
    }

    return ListenableBuilder(
      listenable: Listenable.merge(notifiers),
      builder: (context, _) => _buildSectionList(context),
    );
  }

  Widget _buildSectionList(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final children = <Widget>[];
    var hasRenderedSettings = false;

    final subcategories = SettingSubcategory.values.where((subcategory) => subcategory.category == category);

    for (final subcategory in subcategories) {
      final sectionStates = states
          .where((state) => registry.subcategoryFor(category, state) == subcategory)
          .where((state) => _shouldShowSetting(context, state))
          .toList();
      if (sectionStates.isEmpty) continue;

      children.add(
        SettingsSubcategoryHeader(
          title: subcategory.locName(context),
          showTopDivider: hasRenderedSettings,
        ),
      );
      children.addAll(
        sectionStates.map((state) => settingBuilder?.call(state) ?? ReactiveSettingWidget(state: state)),
      );
      hasRenderedSettings = true;
    }

    for (final state in states) {
      if (registry.subcategoryFor(category, state) == null && _shouldShowSetting(context, state)) {
        children.add(settingBuilder?.call(state) ?? ReactiveSettingWidget(state: state));
        hasRenderedSettings = true;
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<Listenable> _dependencyNotifiers(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final notifiers = <Listenable>[];
    for (final state in states) {
      final dependsOn = state.def.dependsOn;
      if (dependsOn == null || dependsOn.isEmpty) continue;

      for (final depKey in dependsOn) {
        final depState = registry.get<dynamic>(depKey);
        if (depState != null) {
          notifiers.add(depState.scopedNotifier(context));
        }
      }
    }
    return notifiers;
  }
}

bool _shouldShowSetting(BuildContext context, SettingState<dynamic> state) {
  if (!SettingsRegistry.instance.isSettingVisible(state)) {
    return false;
  }

  final enabledWhen = state.def.enabledWhen;
  if (enabledWhen == null) {
    return true;
  }

  return enabledWhen(context);
}

class SettingsSubcategoryHeader extends StatelessWidget {
  const SettingsSubcategoryHeader({
    required this.title,
    this.showTopDivider = true,
    super.key,
  });

  final String title;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = _readableAccentColor(
      foreground: theme.colorScheme.primary,
      background: theme.colorScheme.surface,
      fallback: theme.colorScheme.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTopDivider)
          Container(
            margin: const EdgeInsets.only(top: kMinInteractiveDimension),
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
            height: 4,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

Color _readableAccentColor({
  required Color foreground,
  required Color background,
  required Color fallback,
}) {
  const minReadableContrast = 3.0;
  if (_contrastRatio(foreground, background) >= minReadableContrast) {
    return foreground;
  }

  return fallback;
}

double _contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;

  return (lighter + 0.05) / (darker + 0.05);
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
/// of global values.
class ReactiveSettingWidget extends StatelessWidget {
  const ReactiveSettingWidget({required this.state, super.key});

  final SettingState<dynamic> state;

  @override
  Widget build(BuildContext context) {
    final dependsOn = state.def.dependsOn;
    final enabledWhen = state.def.enabledWhen;

    if (!SettingsRegistry.instance.isSettingVisible(state)) {
      return const SizedBox.shrink();
    }

    // No enabledWhen — always show
    if (enabledWhen == null) {
      return state.buildWidget(context);
    }

    // Static condition (no dependencies to listen to) — evaluate once
    if (dependsOn == null || dependsOn.isEmpty) {
      if (!enabledWhen(context)) {
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
        dependencyNotifiers.add(depState.scopedNotifier(context));
      }
    }

    if (dependencyNotifiers.isEmpty) {
      return state.buildWidget(context);
    }

    return ListenableBuilder(
      listenable: Listenable.merge(dependencyNotifiers),
      builder: (context, _) {
        final enabled = enabledWhen(context);
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
