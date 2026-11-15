import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoSettingsPage(category: SettingCategory.viewer);
  }
}
