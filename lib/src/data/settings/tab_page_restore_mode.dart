import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/settings_enum.dart';

/// Controls how tabs with a saved page number are restored on app start.
enum TabPageRestoreMode with SettingsEnum<TabPageRestoreMode> {
  /// Show a dialog asking the user what to do (per tab)
  ask,

  /// Fetch only the page #N
  fetchOnlyPage,

  /// Fetch pages 1 through N sequentially, stay at page 1
  fetchNoScroll,

  /// Fetch pages 1 through N sequentially, then scroll to page N
  fetchAndScroll,

  /// Ignore saved page, start from page 1 (default behavior)
  ignore,
  ;

  @override
  String toJson() {
    switch (this) {
      case .ask:
        return 'ask';
      case .fetchOnlyPage:
        return 'fetchOnlyPage';
      case .fetchNoScroll:
        return 'fetchNoScroll';
      case .fetchAndScroll:
        return 'fetchAndScroll';
      case .ignore:
        return 'ignore';
    }
  }

  static TabPageRestoreMode fromString(String name) {
    switch (name) {
      case 'ask':
        return .ask;
      case 'fetchOnlyPage':
        return .fetchOnlyPage;
      case 'fetchNoScroll':
        return .fetchNoScroll;
      case 'fetchAndScroll':
        return .fetchAndScroll;
      case 'ignore':
        return .ignore;
    }
    return defaultValue;
  }

  static TabPageRestoreMode get defaultValue => .ask;

  static List<TabPageRestoreMode> get selectableValues => values.where((m) => !m.isAsk).toList();

  bool get isAsk => this == .ask;
  bool get isFetchOnlyPage => this == .fetchOnlyPage;
  bool get isFetchNoScroll => this == .fetchNoScroll;
  bool get isFetchAndScroll => this == .fetchAndScroll;
  bool get isFetchMultiplePages => this == .fetchNoScroll || this == .fetchAndScroll;
  bool get isIgnore => this == .ignore;

  @override
  String get locName {
    switch (this) {
      case .ask:
        return loc.settings.interface.tabPageRestoreModeValues.ask;
      case .fetchOnlyPage:
        return loc.settings.interface.tabPageRestoreModeValues.fetchOnlyPage;
      case .fetchNoScroll:
        return loc.settings.interface.tabPageRestoreModeValues.fetchNoScroll;
      case .fetchAndScroll:
        return loc.settings.interface.tabPageRestoreModeValues.fetchAndScroll;
      case .ignore:
        return loc.settings.interface.tabPageRestoreModeValues.ignore;
    }
  }
}
