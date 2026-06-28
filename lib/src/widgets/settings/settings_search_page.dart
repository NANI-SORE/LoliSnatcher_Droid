import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';

/// Global search page for all registered settings.
///
/// Searches across setting titles, subtitles, and category names.
/// Results are grouped by category with inline headers.
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final results = _query.isEmpty ? <SettingState<dynamic>>[] : registry.search(_query, context);

    // Group results by their first category
    final grouped = <SettingCategory, List<SettingState<dynamic>>>{};
    for (final state in results) {
      final category = state.def.categories.firstWhere(registry.isCategoryVisible);
      grouped.putIfAbsent(category, () => []).add(state);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.loc.search,
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
      ),
      body: _query.isEmpty
          ? Center(child: Text(context.loc.settings.typeToSearch))
          : results.isEmpty
          ? Center(child: Text(context.loc.settings.noSettingsFound))
          : ListView(
              children: [
                for (final entry in grouped.entries) ...[
                  SettingsButton(
                    name: entry.key.locName(context),
                    icon: entry.key.iconWidget(),
                    enabled: false,
                  ),
                  ...buildSettingSubcategorySections(
                    context: context,
                    category: entry.key,
                    states: entry.value.where((s) => s.def.widgetBuilder != null),
                  ),
                ],
              ],
            ),
    );
  }
}
