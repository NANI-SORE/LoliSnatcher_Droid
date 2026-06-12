import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/settings/cookie_manager_widget.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_builder.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class NetworkPage extends StatelessWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AutoSettingsPage(
      category: SettingCategory.network,
      extraWidgets: [_BrowserUserAgentButton(), CookieManagerWidget()],
    );
  }
}

class _BrowserUserAgentButton extends StatelessWidget {
  const _BrowserUserAgentButton();

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<String>(
      setting: SX.customUserAgent.state,
      builder: (context, value) {
        if (value == Constants.defaultBrowserUserAgent) {
          return const SizedBox.shrink();
        }
        return SettingsButton(
          name: context.loc.settings.network.setBrowserUserAgent,
          action: () => SX.customUserAgent.state.value = Constants.defaultBrowserUserAgent,
        );
      },
    );
  }
}
