import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';

class ThemeBuilder extends StatelessWidget {
  const ThemeBuilder({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SX.theme.state.effectiveNotifier,
        SX.themeMode.state.effectiveNotifier,
        SX.isAmoled.state.effectiveNotifier,
        SX.useDynamicColor.state.effectiveNotifier,
        SX.customPrimaryColor.state.effectiveNotifier,
        SX.customAccentColor.state.effectiveNotifier,
        SX.fontFamily.state.effectiveNotifier,
      ]),
      builder: (context, _) {
        final ThemeItem theme = SX.theme.value.name == 'Custom'
            ? ThemeItem(
                name: 'Custom',
                primary: SX.customPrimaryColor.value,
                accent: SX.customAccentColor.value,
              )
            : SX.theme.value;

        final ThemeHandler themeHandler = ThemeHandler(
          theme: theme,
          themeMode: SX.themeMode.value,
          isAmoled: SX.isAmoled.value,
          fontFamily: SX.fontFamily.value,
          context: context,
        );

        return Theme(
          data: themeHandler.isDark ? themeHandler.darkTheme() : themeHandler.lightTheme(),
          child: child,
        );
      },
    );
  }
}
