import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/pages/settings/server_favorite_requests_page.dart';
import 'package:lolisnatcher/src/pages/settings/server_favorites_sync_page.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/auto_settings_page.dart';
import 'package:lolisnatcher/src/widgets/settings/database_page_lock.dart';

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DatabasePageLock.isBusy,
      builder: (context, isBusy, _) {
        return PopScope(
          canPop: !isBusy,
          onPopInvokedWithResult: (_, _) {
            if (!DatabasePageLock.isBusy.value) return;

            FlashElements.showSnackbar(
              title: Text(
                context.loc.settings.database.pleaseWaitTitle,
                style: const TextStyle(fontSize: 20),
              ),
              content: Text(
                context.loc.settings.database.indexesBeingChanged,
                style: const TextStyle(fontSize: 16),
              ),
              leadingIcon: Icons.info_outline,
              leadingIconColor: Colors.yellow,
              sideColor: Colors.yellow,
            );
          },
          child: Stack(
            children: [
              const AutoSettingsPage(
                category: SettingCategory.database,
                extraWidgets: [_ServerSyncButtonsWidget()],
              ),
              if (isBusy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ServerSyncButtonsWidget extends StatelessWidget {
  const _ServerSyncButtonsWidget();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SettingsButton(name: '', enabled: false),
        SettingsButton(
          name: context.loc.serverFavouritesSync.title,
          subtitle: Text(context.loc.serverFavouritesSync.settingsSubtitle),
          trailingIcon: const Icon(Icons.sync),
          page: () => const ServerFavoritesSyncPage(),
        ),
        SettingsButton(
          name: context.loc.serverFavouritesSync.sessionRequests,
          trailingIcon: const Icon(Icons.history),
          page: () => const ServerFavoriteRequestsPage(),
        ),
      ],
    );
  }
}
