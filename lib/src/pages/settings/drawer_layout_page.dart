import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/main_drawer_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

/// Lets the user reorder and toggle the items shown in the main side drawer.
///
/// Local state holds a `List<({MainDrawerItem item, bool enabled})>` covering
/// every enum value. On pop we filter to enabled-only and write into
/// [SettingsHandler.mainDrawerItems]. The [MainDrawerItem.settings] entry is
/// pinned — its toggle is hidden and it cannot be disabled.
class DrawerLayoutPage extends StatefulWidget {
  const DrawerLayoutPage({super.key});

  @override
  State<DrawerLayoutPage> createState() => _DrawerLayoutPageState();
}

class _DrawerLayoutPageState extends State<DrawerLayoutPage> {
  final settingsHandler = SettingsHandler.instance;

  late List<({MainDrawerItem item, bool enabled})> rows;

  @override
  void initState() {
    super.initState();
    _loadFromSettings();
  }

  void _loadFromSettings() {
    final enabled = settingsHandler.mainDrawerItems.toList();
    final enabledSet = enabled.toSet();
    final disabled = MainDrawerItem.values.where((v) => !enabledSet.contains(v)).toList();
    rows = [
      for (final v in enabled) (item: v, enabled: true),
      for (final v in disabled) (item: v, enabled: false),
    ];
  }

  void _save() {
    final selected = rows.where((r) => r.enabled).map((r) => r.item).toList();
    // Force-pin settings.
    if (!selected.contains(MainDrawerItem.settings)) {
      selected.add(MainDrawerItem.settings);
    }
    settingsHandler.mainDrawerItems.assignAll(selected);
    settingsHandler.saveSettings(restate: false);
  }

  String _labelFor(MainDrawerItem item) {
    final t = context.loc.settings.interface.drawerItems;
    return switch (item) {
      MainDrawerItem.search => t.search,
      MainDrawerItem.tabSelector => t.tabSelector,
      MainDrawerItem.tabButtons => t.tabButtons,
      MainDrawerItem.eagleFolders => 'Eagle folders',
      MainDrawerItem.uploadManager => 'Upload Manager',
      MainDrawerItem.multibooruToggle => t.multibooruToggle,
      MainDrawerItem.lockApp => t.lockApp,
      MainDrawerItem.settings => t.settings,
      MainDrawerItem.webview => t.webview,
      MainDrawerItem.updateAvailable => t.updateAvailable,
      MainDrawerItem.closeApp => t.closeApp,
      MainDrawerItem.mascot => t.mascot,
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.loc.settings.interface.drawerLayoutTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: context.loc.settings.interface.drawerLayoutRestoreDefaults,
              onPressed: () {
                setState(() {
                  rows = [
                    for (final v in MainDrawerItem.defaultOrder) (item: v, enabled: true),
                  ];
                });
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Obx(() {
              if (!settingsHandler.drawerBottomAlign.value) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.loc.settings.interface.drawerLayoutBottomAlignHint,
                        style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              );
            }),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: rows.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final row = rows.removeAt(oldIndex);
                    rows.insert(newIndex, row);
                  });
                },
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final item = row.item;
                  final pinned = item.isPinned;
                  return Padding(
                    key: ValueKey(item.name),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.drag_indicator),
                          ),
                        ),
                        title: Text(_labelFor(item)),
                        subtitle: pinned
                            ? Text(
                                context.loc.settings.interface.drawerLayoutPinned,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              )
                            : null,
                        trailing: pinned
                            ? const Icon(Icons.lock)
                            : Switch(
                                value: row.enabled,
                                onChanged: (v) {
                                  setState(() {
                                    rows[index] = (item: item, enabled: v);
                                  });
                                },
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
