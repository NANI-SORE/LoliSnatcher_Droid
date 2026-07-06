import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_overrides_page.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/root/theme_builder.dart';

class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  static const List<SettingKey> _themeKeys = [
    .themeMode,
    .theme,
    .customPrimaryColor,
    .customAccentColor,
    .useDynamicColor,
    .isAmoled,
    .fontFamily,
    .enableDrawerMascot,
    .drawerMascotPathOverride,
  ];

  Widget _buildOverrideWarning(BuildContext context) {
    final currentBooru = SettingsRegistry.instance.currentBooruName;
    if (currentBooru == null) return const SizedBox.shrink();

    final themeKeys = [
      SX.themeMode,
      SX.theme,
      SX.customPrimaryColor,
      SX.customAccentColor,
      SX.useDynamicColor,
      SX.isAmoled,
    ];
    final hasOverride = themeKeys.any((key) => key.state.hasOverrideFor(currentBooru));
    if (!hasOverride) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openActiveBooruThemeOverrides(context, currentBooru),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.onTertiaryContainer, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.loc.settings.activeBooruThemeOverrides(
                      booru: currentBooru,
                    ),
                    style: TextStyle(
                      color: colorScheme.onTertiaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onTertiaryContainer, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openActiveBooruThemeOverrides(BuildContext context, String booruName) {
    for (final booru in SettingsHandler.instance.booruList) {
      if (booru.name == booruName) {
        SettingsPageOpen(
          context: context,
          page: (_) => BooruOverridesPage(
            booru: booru,
            initialCategory: SettingCategory.theme,
          ),
        ).open();
        return;
      }
    }
  }

  List<SettingState<dynamic>> _themeStates() {
    final registry = SettingsRegistry.instance;
    return _themeKeys
        .map((key) => registry.get<dynamic>(key))
        .whereType<SettingState<dynamic>>()
        .where((state) => registry.isSettingVisible(state) && state.def.widgetBuilder != null)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final states = _themeStates();

    return DebouncedListenableBuilder(
      immediateListenables: states
          .where(
            (state) => state.def.key != SettingKey.customPrimaryColor && state.def.key != SettingKey.customAccentColor,
          )
          .map((state) => state.scopedNotifier(context))
          .toList(),
      debouncedListenables: states
          .where(
            (state) => state.def.key == SettingKey.customPrimaryColor || state.def.key == SettingKey.customAccentColor,
          )
          .map((state) => state.scopedNotifier(context))
          .toList(),
      builder: (context, _) {
        final localTheme = SX.theme.state.globalValue;
        final themeHandler = ThemeHandler(
          theme: localTheme.name == 'Custom'
              ? ThemeItem(
                  name: 'Custom',
                  primary: SX.customPrimaryColor.state.globalValue,
                  accent: SX.customAccentColor.state.globalValue,
                )
              : localTheme,
          themeMode: SX.themeMode.state.globalValue,
          isAmoled: SX.isAmoled.state.globalValue,
          fontFamily: SX.fontFamily.state.globalValue,
          context: context,
        );

        return Theme(
          data: themeHandler.getTheme(),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: SettingsAppBar(title: context.loc.settings.theme.title),
            body: Center(
              child: ListView(
                children: [
                  _buildOverrideWarning(context),
                  ...buildSettingSubcategorySections(
                    context: context,
                    category: SettingCategory.theme,
                    states: states,
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
