import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/database_page_lock.dart';

class DatabaseActionsWidget extends StatelessWidget {
  const DatabaseActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsHandler = SettingsHandler.instance;
    final searchHandler = SearchHandler.instance;
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsButton(enabled: false, name: ''),
        if (SX.isDebug.value) ...[
          SettingsButton(
            name: context.loc.settings.database.createIndexesDebug,
            icon: const Icon(Icons.create_new_folder_rounded),
            action: () async {
              await DatabasePageLock.run(settingsHandler.dbHandler.createIndexes);
            },
          ),
          SettingsButton(
            name: context.loc.settings.database.dropIndexesDebug,
            icon: const Icon(Icons.delete_forever),
            action: () async {
              await DatabasePageLock.run(settingsHandler.dbHandler.dropIndexes);
            },
          ),
        ],
        SettingsButton(
          name: context.loc.settings.database.deleteDatabase,
          icon: Icon(Icons.delete_forever, color: errorColor),
          action: () => _confirmDeleteDatabase(context, settingsHandler),
        ),
        SettingsButton(
          name: context.loc.settings.database.clearSnatchedItems,
          icon: Icon(Icons.delete_outline, color: errorColor),
          trailingIcon: const Icon(Icons.save_alt),
          action: () => _confirmClearSnatched(context, settingsHandler, searchHandler),
        ),
        SettingsButton(
          name: context.loc.settings.database.clearFavouritedItems,
          icon: Icon(Icons.delete_outline, color: errorColor),
          trailingIcon: const Icon(Icons.favorite_outline),
          action: () => _confirmClearFavourites(context, settingsHandler, searchHandler),
        ),
        SettingsButton(
          name: context.loc.settings.database.clearSearchHistory,
          icon: Icon(Icons.delete_outline, color: errorColor),
          trailingIcon: const Icon(Icons.history),
          action: () => _confirmClearSearchHistory(context, settingsHandler),
        ),
        const SettingsButton(enabled: false, name: ''),
      ],
    );
  }

  void _confirmDeleteDatabase(BuildContext context, SettingsHandler settingsHandler) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.database.deleteDatabaseConfirm),
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton.icon(
            onPressed: () {
              ServiceHandler.deleteDB(settingsHandler);
              FlashElements.showSnackbar(
                context: context,
                title: Text(
                  ctx.loc.settings.database.databaseDeleted,
                  style: const TextStyle(fontSize: 20),
                ),
                content: Text(
                  ctx.loc.settings.database.appRestartRequired,
                  style: const TextStyle(fontSize: 16),
                ),
                leadingIcon: Icons.delete_forever,
                leadingIconColor: Colors.red,
                sideColor: Colors.yellow,
              );
              Navigator.of(ctx).pop(true);
            },
            label: Text(ctx.loc.delete),
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
    );
  }

  void _confirmClearSnatched(
    BuildContext context,
    SettingsHandler settingsHandler,
    SearchHandler searchHandler,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.database.clearAllSnatchedConfirm),
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton.icon(
            onPressed: () {
              if (settingsHandler.dbHandler.db != null) {
                settingsHandler.dbHandler.clearSnatched();
                for (final tab in searchHandler.tabs) {
                  for (final item in tab.booruHandler.fetched) {
                    if (item.isSnatched.value == true) {
                      item.isSnatched.value = false;
                    }
                  }
                }
                _showClearedSnackbar(
                  context: context,
                  title: ctx.loc.settings.database.snatchedItemsCleared,
                );
              }
              Navigator.of(ctx).pop(true);
            },
            label: Text(ctx.loc.clear),
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
    );
  }

  void _confirmClearFavourites(
    BuildContext context,
    SettingsHandler settingsHandler,
    SearchHandler searchHandler,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.database.clearAllFavouritedConfirm),
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton.icon(
            onPressed: () {
              if (settingsHandler.dbHandler.db != null) {
                settingsHandler.dbHandler.clearFavourites();
                for (final tab in searchHandler.tabs) {
                  for (final item in tab.booruHandler.fetched) {
                    if (item.isFavourite.value == true) {
                      item.isFavourite.value = false;
                    }
                  }
                }
                _showClearedSnackbar(
                  context: context,
                  title: ctx.loc.settings.database.favouritesCleared,
                );
              }
              Navigator.of(ctx).pop(true);
            },
            label: Text(ctx.loc.clear),
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
    );
  }

  void _confirmClearSearchHistory(
    BuildContext context,
    SettingsHandler settingsHandler,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.database.clearSearchHistoryConfirm),
        actionButtons: [
          const CancelButton(withIcon: true),
          ElevatedButton.icon(
            onPressed: () {
              if (settingsHandler.dbHandler.db != null) {
                settingsHandler.dbHandler.deleteFromSearchHistory(null);
                _showClearedSnackbar(
                  context: context,
                  title: ctx.loc.settings.database.searchHistoryCleared,
                );
              }
              Navigator.of(ctx).pop(true);
            },
            label: Text(ctx.loc.clear),
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
    );
  }

  void _showClearedSnackbar({
    required BuildContext context,
    required String title,
  }) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        title,
        style: const TextStyle(fontSize: 20),
      ),
      content: Text(
        context.loc.settings.database.appRestartMayBeRequired,
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Icons.delete_forever,
      leadingIconColor: Colors.red,
      sideColor: Colors.yellow,
    );
  }
}
