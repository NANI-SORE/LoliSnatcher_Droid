import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/app_alias.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Dropdown for changing the app's launcher display name (Android only).
///
/// Shows a confirmation dialog and restarts the app on change.
class AppAliasWidget extends StatefulWidget {
  const AppAliasWidget({super.key});

  @override
  State<AppAliasWidget> createState() => _AppAliasWidgetState();
}

class _AppAliasWidgetState extends State<AppAliasWidget> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  late AppAlias appAlias;

  @override
  void initState() {
    super.initState();
    appAlias = SX.appAlias.value;
  }

  Future<void> _changeAppAlias(AppAlias? newAlias) async {
    if (newAlias == null || newAlias == appAlias) return;

    final prevAlias = appAlias;
    final nativeCurrentAlias = await ServiceHandler.getCurrentAlias();
    ServiceHandler.log(
      'PrivacyPage app alias change selected: previousSettingsAlias=${prevAlias.toJson()} '
      'selectedAlias=${newAlias.toJson()} nativeCurrentAlias=$nativeCurrentAlias',
    );

    await Future.delayed(const Duration(milliseconds: 100));
    final result = await showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        title: Text(context.loc.settings.privacy.appAliasChanged),
        contentItems: [
          Text(context.loc.settings.privacy.appAliasRestartHint),
        ],
        actionButtons: [
          const CancelButton(
            withIcon: true,
            returnData: false,
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.restart_alt),
            label: Text(context.loc.settings.privacy.restartNow),
          ),
        ],
      ),
    );

    ServiceHandler.log(
      'PrivacyPage app alias restart dialog result: selectedAlias=${newAlias.toJson()} restartRequested=${result == true}',
    );

    if (result == null || !result) {
      return;
    }

    setState(() => appAlias = newAlias);

    final success = await ServiceHandler.setAppAlias(newAlias.toJson());
    if (success) {
      SX.appAlias.state.value = newAlias;
      await settingsHandler.saveSettings(restate: false);
      ServiceHandler.log('PrivacyPage app alias change succeeded: alias=${newAlias.toJson()}');
      await ServiceHandler.restartApp(alias: newAlias.toJson());
    } else {
      setState(() => appAlias = prevAlias);
      SX.appAlias.state.value = prevAlias;
      await settingsHandler.saveSettings(restate: false);
      await ServiceHandler.getAppAliasDiagnostics(alias: newAlias.toJson());
      ServiceHandler.log('PrivacyPage app alias change failed: alias=${newAlias.toJson()}');

      if (!mounted) return;

      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.errorExclamation),
        content: Text(context.loc.settings.privacy.appAliasChangeFailed),
        sideColor: Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    return SettingsDropdown<AppAlias>(
      value: appAlias,
      items: AppAlias.values,
      onChanged: _changeAppAlias,
      title: context.loc.settings.privacy.appDisplayName,
      subtitle: Text(context.loc.settings.privacy.appDisplayNameDescription),
      itemTitleBuilder: (item) => item?.displayName ?? '',
    );
  }
}
