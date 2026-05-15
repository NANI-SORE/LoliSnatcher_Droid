import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

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
    final grouped = <String, List<SettingState<dynamic>>>{};
    for (final state in results) {
      final categoryName = state.def.categories.isNotEmpty ? state.def.categories.first.locName(context) : 'Other';
      grouped.putIfAbsent(categoryName, () => []).add(state);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search settings...',
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
          ? const Center(child: Text('Type to search settings'))
          : results.isEmpty
          ? const Center(child: Text('No settings found'))
          : ListView.builder(
              itemCount: _countItems(grouped),
              itemBuilder: (context, index) => _buildItem(context, grouped, index),
            ),
    );
  }

  int _countItems(Map<String, List<SettingState<dynamic>>> grouped) {
    int count = 0;
    for (final entry in grouped.entries) {
      count++; // category header
      count += entry.value.where((s) => s.def.widgetBuilder != null).length;
    }
    return count;
  }

  Widget _buildItem(BuildContext context, Map<String, List<SettingState<dynamic>>> grouped, int index) {
    int current = 0;
    for (final entry in grouped.entries) {
      if (current == index) {
        // Category header
        return SettingsButton(
          name: entry.key,
          enabled: false,
        );
      }
      current++;

      final renderableStates = entry.value.where((s) => s.def.widgetBuilder != null).toList();
      for (final state in renderableStates) {
        if (current == index) {
          return state.buildWidget(context);
        }
        current++;
      }
    }

    return const SizedBox.shrink();
  }
}
