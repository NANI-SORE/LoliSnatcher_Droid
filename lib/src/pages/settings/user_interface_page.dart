import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';

class UserInterfacePage extends StatelessWidget {
  const UserInterfacePage({super.key});

  void _onPop(_, _) {
    SettingsHandler.instance.saveSettings(restate: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPop,
      child: const AutoSettingsPage(
        category: SettingCategory.interface,
        saveOnPop: false,
      ),
    );
  }
}
