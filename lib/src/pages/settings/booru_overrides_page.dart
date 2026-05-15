import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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
/// Saves overrides to the booru config file when popped (unless
/// [saveOnPop] is false, e.g. when opened from [BooruEdit] which
/// handles its own save).
class BooruOverridesPage extends StatefulWidget {
  const BooruOverridesPage({
    required this.booru,
    this.saveOnPop = true,
    super.key,
  });

  final Booru booru;

  /// Whether to auto-save overrides to the booru config on pop.
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
    final perBooruSettings = registry.perBooruSettings.where((s) => s.def.widgetBuilder != null).toList();

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

  void _onPop(_, _) {
    if (widget.booru.name != null) {
      SettingsHandler.instance.saveBooru(widget.booru, onlySave: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booruName = widget.booru.name ?? '';
    final registry = SettingsRegistry.instance;
    final perBooruSettings = registry.perBooruSettings.where((s) => s.def.widgetBuilder != null).toList();

    // TODO localize these strings (add booruOverrides section to i18n)
    final Widget body = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('${widget.booru.name} — Overrides'),
        actions: [
          if (perBooruSettings.any((s) => s.hasOverrideFor(booruName)))
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset all overrides',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => SettingsDialog(
                    title: const Text('Reset all overrides?'),
                    contentItems: [
                      Text(
                        'All custom settings for "${widget.booru.name}" will be '
                        'removed. Global defaults will be used instead.',
                      ),
                    ],
                    actionButtons: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.loc.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  registry.removeAllOverridesForBooru(booruName);
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
                      icon: switch (cat.icon) {
                        IconData _ => Icon(cat.icon),
                        FontAwesomeIcons _ => FaIcon(cat.icon),
                        _ => const Icon(null),
                      },
                      text: cat.locName(context),
                    ),
                ],
              )
            : null,
      ),
      body: perBooruSettings.isEmpty
          ? const Center(
              child: Text('No settings support per-booru overrides yet.'),
            )
          : categories.length == 1
          ? _buildCategoryList(categories.first)
          : TabBarView(
              controller: tabController,
              children: [
                for (final cat in categories) _buildCategoryList(cat),
              ],
            ),
    );

    return BooruEditingScope(
      booruName: booruName,
      child: widget.saveOnPop
          ? PopScope(
              onPopInvokedWithResult: _onPop,
              child: body,
            )
          : body,
    );
  }

  Widget _buildCategoryList(SettingCategory category) {
    final settings = grouped[category] ?? [];

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 40),
      children: [
        for (final state in settings) ReactiveSettingWidget(state: state),
      ],
    );
  }
}
