import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/widgets/settings/app_alias_widget.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoSettingsPage(
      category: SettingCategory.privacy,
      header: AppAliasWidget(),
    );
  }
}
