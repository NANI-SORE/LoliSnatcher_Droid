/// Sections that can appear in the main side drawer.
///
/// The user picks which items appear and their order via
/// **Settings → User Interface → Drawer layout**. The list of selected items
/// is persisted in SettingsHandler.mainDrawerItems; the order matters,
/// and absence from the list means the section is disabled. [settings] is
/// pinned and cannot be removed.
enum MainDrawerItem {
  search,
  tabSelector,
  tabButtons,
  eagleFolders,
  uploadManager,
  multibooruToggle,
  lockApp,
  settings,
  webview,
  updateAvailable,
  closeApp,
  mascot;

  /// True if this item cannot be removed from the drawer. The UI hides the
  /// disable toggle for pinned items.
  bool get isPinned => this == MainDrawerItem.settings;

  /// Items in the order they appeared before the modular drawer feature.
  /// Used as the default value for new installs and when restoring defaults.
  static const List<MainDrawerItem> defaultOrder = [
    search,
    tabSelector,
    tabButtons,
    eagleFolders,
    uploadManager,
    multibooruToggle,
    lockApp,
    settings,
    webview,
    updateAvailable,
    closeApp,
    mascot,
  ];

  /// Parse a comma-separated string of enum names. Unknown names are dropped
  /// (forward / backward compatibility). [settings] is forcibly appended if
  /// missing, to honor the pin.
  static List<MainDrawerItem> parseCsv(String csv) {
    final names = csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final byName = {for (final v in values) v.name: v};
    final result = <MainDrawerItem>[];
    for (final n in names) {
      final v = byName[n];
      if (v != null && !result.contains(v)) result.add(v);
    }
    if (!result.contains(MainDrawerItem.settings)) {
      result.add(MainDrawerItem.settings);
    }
    return result;
  }

  static String toCsv(List<MainDrawerItem> items) => items.map((e) => e.name).join(',');
}
