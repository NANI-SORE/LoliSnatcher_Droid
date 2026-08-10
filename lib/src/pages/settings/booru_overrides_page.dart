import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/delete_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';

enum _OverrideResetAction { category, all }

/// Embedded editor for per-booru setting overrides.
///
/// Wraps its content in a [BooruEditingScope] so that setting widgets
/// automatically read/write override values for the given booru instead
/// of global values.
///
/// Shows all settings that have [SettingDef.supportsPerBooru] == true,
/// grouped by category into tabs. Each setting shows:
/// - "Using default" badge when no override exists (tap to customize)
/// - "Custom" badge with reset button when an override is active
///
/// Override changes are saved immediately when [autosave] is true.
class BooruOverridesEditor extends StatefulWidget {
  const BooruOverridesEditor({
    required this.booruName,
    this.displayName,
    this.initialCategory,
    this.initialSettingKey,
    this.autosave = true,
    super.key,
  });

  final String booruName;
  final String? displayName;
  final SettingCategory? initialCategory;
  final SettingKey? initialSettingKey;
  final bool autosave;

  @override
  State<BooruOverridesEditor> createState() => _BooruOverridesEditorState();
}

class _BooruOverridesEditorState extends State<BooruOverridesEditor> with TickerProviderStateMixin {
  late final Map<SettingCategory, List<SettingState<dynamic>>> grouped;
  late final List<SettingCategory> categories;
  late final TabController tabController;
  late final AnimationController highlightController;
  final Map<SettingKey, GlobalKey> settingKeys = {};
  bool highlightInitialSetting = false;

  @override
  void initState() {
    super.initState();
    highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    final registry = SettingsRegistry.instance;
    final perBooruSettings = registry.perBooruSettings
        .where((s) => registry.isSettingVisible(s) && s.def.widgetBuilder != null)
        .toList();

    grouped = {};
    for (final state in perBooruSettings) {
      final category = state.def.categories.isNotEmpty ? state.def.categories.first : SettingCategory.interface;
      grouped.putIfAbsent(category, () => []).add(state);
    }

    categories = grouped.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    final initialCategory = widget.initialCategory ?? _categoryForSetting(widget.initialSettingKey);
    final initialIndex = initialCategory != null ? categories.indexOf(initialCategory) : -1;
    tabController = TabController(
      length: categories.length,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
      vsync: this,
    );

    if (widget.initialSettingKey != null) {
      highlightInitialSetting = true;
      highlightController.repeat(reverse: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToInitialSetting());
    }
  }

  SettingCategory? _categoryForSetting(SettingKey? key) {
    if (key == null) return null;
    for (final entry in grouped.entries) {
      if (entry.value.any((state) => state.def.key == key)) {
        return entry.key;
      }
    }
    return null;
  }

  GlobalKey _keyForSetting(SettingKey key) {
    return settingKeys.putIfAbsent(key, () => GlobalKey(debugLabel: 'booru-override-${key.name}'));
  }

  Future<void> _scrollToInitialSetting() async {
    final key = widget.initialSettingKey;
    if (key == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final context = settingKeys[key]?.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.18,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (mounted) {
      highlightController.stop();
      setState(() => highlightInitialSetting = false);
    }
  }

  Future<void> _showResetOverridesDialog(
    SettingsRegistry registry,
    String booruName,
  ) async {
    final currentCategory = categories[tabController.index];
    final categoryStates = grouped[currentCategory] ?? const <SettingState<dynamic>>[];

    final action = await showDialog<_OverrideResetAction>(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(context.loc.reset),
        contentItems: [
          Text(
            context.loc.settings.resetAllOverridesDescription(
              booru: widget.displayName ?? widget.booruName,
            ),
          ),
        ],
        actionButtons: [
          DeleteButton(
            withIcon: true,
            returnData: _OverrideResetAction.category,
            text: '${context.loc.reset}: ${currentCategory.locName(context)}',
          ),
          const SizedBox(height: 12),
          DeleteButton(
            withIcon: true,
            returnData: _OverrideResetAction.all,
            text: context.loc.settings.resetAllOverrides,
          ),
          const SizedBox(height: 12),
          const CancelButton(withIcon: true),
        ],
      ),
    );

    switch (action) {
      case _OverrideResetAction.category:
        for (final state in categoryStates) {
          state.removeOverrideFor(booruName, save: widget.autosave);
        }
        setState(() {});
        break;
      case _OverrideResetAction.all:
        registry.removeAllOverridesForBooru(booruName, save: widget.autosave);
        setState(() {});
        break;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    highlightController.dispose();
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booruName = widget.booruName;
    final registry = SettingsRegistry.instance;
    final perBooruSettings = registry.perBooruSettings
        .where((s) => registry.isSettingVisible(s) && s.def.widgetBuilder != null)
        .toList();

    final Widget body = perBooruSettings.isEmpty
        ? Center(child: Text(context.loc.settings.booruEditor.noOverrideSettings))
        : Column(
            children: [
              if (widget.autosave)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_done_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.loc.settings.booruEditor.overrideChangesSavedAutomatically,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Row(
                  children: [
                    if (categories.length > 1)
                      Expanded(
                        child: TabBar(
                          controller: tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            for (final cat in categories)
                              Tab(
                                icon: cat.iconWidget(),
                                text: cat.locName(context),
                              ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.restart_alt),
                      tooltip: context.loc.settings.resetAllOverrides,
                      onPressed: () => _showResetOverridesDialog(registry, booruName),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: categories.length == 1
                    ? _buildCategoryList(categories.first, showHeader: true)
                    : TabBarView(
                        controller: tabController,
                        children: [
                          for (final cat in categories) _buildCategoryList(cat),
                        ],
                      ),
              ),
            ],
          );

    return BooruEditingScope(
      booruName: booruName,
      autosave: widget.autosave,
      child: body,
    );
  }

  Widget _buildCategoryList(
    SettingCategory category, {
    bool showHeader = false,
  }) {
    final settings = grouped[category] ?? [];

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 40),
      children: [
        if (showHeader)
          SettingsButton(
            name: category.locName(context),
            icon: category.iconWidget(),
            enabled: false,
          ),
        ...buildSettingSubcategorySections(
          context: context,
          category: category,
          states: settings,
          settingBuilder: _buildSettingItem,
        ),
      ],
    );
  }

  Widget _buildSettingItem(SettingState<dynamic> state) {
    final isTarget = state.def.key == widget.initialSettingKey;
    final showHighlight = isTarget && highlightInitialSetting;

    return Stack(
      key: _keyForSetting(state.def.key),
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showHighlight ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              child: AnimatedBuilder(
                animation: highlightController,
                builder: (context, _) {
                  final value = highlightController.value;
                  final pulse = 0.24 + (0.14 * (1 - (2 * value - 1).abs()));
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: pulse),
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.9),
                          width: 4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        ReactiveSettingWidget(state: state),
      ],
    );
  }
}
