import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';

/// Page for editing per-booru setting overrides.
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
/// Saves override changes immediately unless [saveOnPop] is false, e.g. when
/// opened from [BooruEdit] which handles its own save.
class BooruOverridesPage extends StatefulWidget {
  const BooruOverridesPage({
    required this.booru,
    this.saveOnPop = true,
    super.key,
  });

  final Booru booru;

  /// Whether override changes should save immediately.
  /// Set to false when opened from [BooruEdit] which handles its own save.
  final bool saveOnPop;

  @override
  State<BooruOverridesPage> createState() => _BooruOverridesPageState();
}

class _BooruOverridesPageState extends State<BooruOverridesPage> with TickerProviderStateMixin {
  late final Map<SettingCategory, List<dynamic>> grouped;
  late final List<SettingCategory> categories;
  late final TabController tabController;

  @override
  void initState() {
    super.initState();

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
    tabController = TabController(length: categories.length, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booruName = widget.booru.name ?? '';
    final registry = SettingsRegistry.instance;
    final perBooruSettings = registry.perBooruSettings
        .where((s) => registry.isSettingVisible(s) && s.def.widgetBuilder != null)
        .toList();

    final Widget body = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          context.loc.settings.booruOverridesTitle(
            booru: widget.booru.name ?? '',
          ),
        ),
        actions: [
          if (perBooruSettings.any((s) => s.hasOverrideFor(booruName)))
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: context.loc.settings.resetAllOverrides,
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => SettingsDialog(
                    title: Text(context.loc.settings.resetAllOverrides),
                    contentItems: [
                      Text(
                        context.loc.settings.resetAllOverridesDescription(
                          booru: widget.booru.name ?? '',
                        ),
                      ),
                    ],
                    actionButtons: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.loc.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(context.loc.reset),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  registry.removeAllOverridesForBooru(booruName, save: widget.saveOnPop);
                  setState(() {});
                }
              },
            ),
        ],
        bottom: categories.length > 1
            ? TabBar(
                controller: tabController,
                indicatorColor: Theme.of(context).colorScheme.secondary,
                labelColor: Theme.of(context).colorScheme.onSecondary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.66),
                labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 16),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final cat in categories)
                    Tab(
                      icon: cat.iconWidget(),
                      text: cat.locName(context),
                    ),
                ],
              )
            : null,
      ),
      body: perBooruSettings.isEmpty
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : categories.length == 1
          ? _buildCategoryList(categories.first, showHeader: true)
          : TabBarView(
              controller: tabController,
              children: [
                for (final cat in categories) _buildCategoryList(cat),
              ],
            ),
    );

    return BooruEditingScope(
      booruName: booruName,
      autosave: widget.saveOnPop,
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
        for (final state in settings) ReactiveSettingWidget(state: state),
      ],
    );
  }
}
