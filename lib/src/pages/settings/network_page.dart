import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/settings/cookie_manager_widget.dart';

class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoSettingsPage(
      category: SettingCategory.network,
      extraWidgets: [CookieManagerWidget()],
    );
  }
}
