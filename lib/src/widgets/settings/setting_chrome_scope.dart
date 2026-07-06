import 'package:flutter/widgets.dart';

class SettingChromeScope extends InheritedWidget {
  const SettingChromeScope({
    required super.child,
    this.chip,
    super.key,
  });

  final Widget? chip;

  static Widget? chipOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingChromeScope>()?.chip;
  }

  @override
  bool updateShouldNotify(SettingChromeScope oldWidget) => chip != oldWidget.chip;
}
