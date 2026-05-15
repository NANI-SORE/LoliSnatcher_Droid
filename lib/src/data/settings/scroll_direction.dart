import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/settings_enum.dart';

enum UiScrollDirection with SettingsEnum<UiScrollDirection> {
  horizontal,
  vertical,
  ;

  // For JSON serialization - returns ORIGINAL string values for backwards compatibility
  // New format (uncomment after grace period): horizontal => 'horizontal', vertical => 'vertical'
  @override
  String toJson() {
    switch (this) {
      case UiScrollDirection.horizontal:
        return 'Horizontal';
      case UiScrollDirection.vertical:
        return 'Vertical';
    }
  }

  static UiScrollDirection fromString(String name) {
    switch (name) {
      case 'Horizontal':
      case 'horizontal':
        return UiScrollDirection.horizontal;
      case 'Vertical':
      case 'vertical':
        return UiScrollDirection.vertical;
    }
    return defaultValue;
  }

  static UiScrollDirection get defaultValue => UiScrollDirection.horizontal;

  bool get isHorizontal => this == UiScrollDirection.horizontal;
  bool get isVertical => this == UiScrollDirection.vertical;

  @override
  String get locName {
    switch (this) {
      case UiScrollDirection.horizontal:
        return loc.settings.viewer.scrollDirectionValues.horizontal;
      case UiScrollDirection.vertical:
        return loc.settings.viewer.scrollDirectionValues.vertical;
    }
  }
}
