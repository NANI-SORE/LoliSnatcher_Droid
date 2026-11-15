import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Debug-only helpers for stress-testing the tab system.
class TestingPage extends StatefulWidget {
  const TestingPage({super.key});

  @override
  State<TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends State<TestingPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final TextEditingController countController = TextEditingController(text: '10');

  @override
  void dispose() {
    countController.dispose();
    super.dispose();
  }

  // Upper bound is an arbitrary safety limit, not a tab-system constraint: each
  // added tab allocates a full SearchTab + BooruHandler, so a huge count can
  // hang/OOM the app while they all spin up.
  static const int _maxTabsToAdd = 5000;

  int get _requestedCount {
    final parsed = int.tryParse(countController.text.trim()) ?? 0;
    return parsed.clamp(1, _maxTabsToAdd);
  }

  void _addDefaultTabs() {
    final SearchHandler searchHandler = SearchHandler.instance;
    final int count = _requestedCount;

    // A "default" tab = current booru (or the first configured one) + its
    // default tags, mirroring how the app seeds the very first tab.
    final booru = searchHandler.tabs.isNotEmpty
        ? searchHandler.currentBooru
        : (settingsHandler.booruList.isNotEmpty ? settingsHandler.booruList.first : null);
    if (booru == null) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('No booru configured', style: TextStyle(fontSize: 20)),
        leadingIcon: Icons.warning_amber,
        sideColor: Colors.red,
      );
      return;
    }

    final String defaultText = booru.defTags?.isNotEmpty == true ? booru.defTags! : SX.defTags.value;

    for (int i = 0; i < count; i++) {
      searchHandler.addTabByString(defaultText, customBooru: booru);
    }
    unawaited(searchHandler.backupTabs());

    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: Text('Added $count default tab${count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 20)),
      content: Text('Total tabs: ${searchHandler.total}', style: const TextStyle(fontSize: 16)),
      leadingIcon: Icons.add,
      sideColor: Colors.green,
    );
  }

  void _deleteAllTabsExceptOne() {
    final SearchHandler searchHandler = SearchHandler.instance;
    if (searchHandler.total <= 1) {
      FlashElements.showSnackbar(
        context: context,
        title: const Text('Nothing to delete', style: TextStyle(fontSize: 20)),
        content: const Text('There is already only one tab.', style: TextStyle(fontSize: 16)),
        leadingIcon: Icons.info_outline,
        sideColor: Colors.blue,
      );
      return;
    }

    // Keep the currently selected tab, drop the rest.
    final keep = searchHandler.currentTab;
    final toRemove = searchHandler.tabs.where((t) => t.id != keep.id).toList();
    searchHandler.removeTabs(toRemove);

    // Drop any groups that were left empty by the removal.
    searchHandler.tabGroups.removeWhere(
      (g) => searchHandler.tabs.every((t) => t.groupId.value != g.id),
    );

    // removeTabs mutates tabs.value in place; reassign to notify observers.
    searchHandler.tabs.value = searchHandler.tabs.toList();
    unawaited(searchHandler.backupTabs());

    FlashElements.showSnackbar(
      context: context,
      duration: const Duration(seconds: 2),
      title: const Text('Deleted all tabs except one', style: TextStyle(fontSize: 20)),
      leadingIcon: Icons.delete_sweep,
      sideColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SettingsAppBar(title: 'Testing'),
      body: Center(
        child: ListView(
          children: [
            Obx(
              () => SettingsButton(
                name: 'Current tab count: ${SearchHandler.instance.total}',
                enabled: false,
              ),
            ),
            const SettingsButton(name: '', enabled: false),

            SettingsTextInput(
              controller: countController,
              title: 'Number of tabs to add',
              inputType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              numberButtons: true,
              numberMin: 1,
              numberMax: _maxTabsToAdd.toDouble(),
              clearable: true,
              resetText: () => '10',
            ),
            SettingsButton(
              name: 'Add default tabs',
              icon: const Icon(Icons.add_box_outlined),
              action: _addDefaultTabs,
            ),

            const SettingsButton(name: '', enabled: false),

            SettingsButton(
              name: 'Delete all tabs except 1',
              icon: const Icon(Icons.delete_sweep_outlined),
              action: _deleteAllTabsExceptOne,
            ),
          ],
        ),
      ),
    );
  }
}
