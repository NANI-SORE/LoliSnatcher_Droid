import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';

class SaveCachePage extends StatelessWidget {
  const SaveCachePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoSettingsPage(
      category: SettingCategory.cache,
      extraWidgets: [_CacheVideoModeSetting()],
    );
  }
}

class _CacheVideoModeSetting extends StatelessWidget {
  const _CacheVideoModeSetting();

  @override
  Widget build(BuildContext context) => SX.videoCacheMode.state.buildWidget(context);
}
