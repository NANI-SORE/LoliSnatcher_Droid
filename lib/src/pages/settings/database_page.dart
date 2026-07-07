import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/pages/settings/server_favorite_requests_page.dart';
import 'package:lolisnatcher/src/pages/settings/server_favorites_sync_page.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key});

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ScrollController scrollController = ScrollController();

  bool dbEnabled = true,
      indexesEnabled = true,
      changingIndexes = false,
      searchHistoryEnabled = true,
      tagTypeFetchEnabled = true,
      sendFavouritesToServer = true,
      serverFavoriteSuccessAnimation = true;

  @override
  void initState() {
    super.initState();

    dbEnabled = SX.dbEnabled.value;
    indexesEnabled = SX.indexesEnabled.value;
    searchHistoryEnabled = SX.searchHistoryEnabled.value;
    tagTypeFetchEnabled = SX.tagTypeFetchEnabled.value;
    sendFavouritesToServer = SX.sendFavouritesToServer.value;
    serverFavoriteSuccessAnimation = SX.serverFavoriteSuccessAnimation.value;
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    if (changingIndexes) {
      FlashElements.showSnackbar(
        title: Text(context.loc.settings.database.pleaseWaitTitle, style: const TextStyle(fontSize: 20)),
        content: Text(context.loc.settings.database.indexesBeingChanged, style: const TextStyle(fontSize: 16)),
        leadingIcon: Icons.info_outline,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }

    SX.dbEnabled.state.value = dbEnabled;
    SX.indexesEnabled.state.value = indexesEnabled;
    SX.searchHistoryEnabled.state.value = searchHistoryEnabled;
    SX.tagTypeFetchEnabled.state.value = tagTypeFetchEnabled;
    SX.sendFavouritesToServer.state.value = sendFavouritesToServer;
    SX.serverFavoriteSuccessAnimation.state.value = serverFavoriteSuccessAnimation;
    await settingsHandler.saveSettings(restate: false);
  }

  Future<void> changeIndexes(bool newValue) async {
    setState(() {
      changingIndexes = true;
      SX.indexesEnabled.state.value = newValue;
    });

    if (newValue) {
      await settingsHandler.dbHandler.createIndexes();
    } else {
      await settingsHandler.dbHandler.dropIndexes();
    }

    changingIndexes = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !changingIndexes,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.database.title,
        ),
        body: Center(
          child: ListView(
            controller: scrollController,
            children: [
              SettingsToggle(
                value: SX.dbEnabled.state.value,
                onChanged: (newValue) {
                  setState(() {
                    SX.dbEnabled.state.value = newValue;
                  });
                },
                title: context.loc.settings.database.enableDatabase,
                trailingIcon: IconButton(
                  icon: const Icon(Icons.help_outline),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.title),
                          contentItems: [
                            Text(context.loc.settings.database.databaseInfo),
                            Text(context.loc.settings.database.databaseInfoSnatch),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (SX.dbEnabled.state.value) ...[
                Stack(
                  children: [
                    IgnorePointer(
                      ignoring: changingIndexes,
                      child: Column(
                        children: [
                          SettingsToggle(
                            value: SX.indexesEnabled.state.value,
                            onChanged: changeIndexes,
                            title: context.loc.settings.database.enableIndexing,
                            trailingIcon: IconButton(
                              icon: const Icon(Icons.help_outline),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return SettingsDialog(
                                      title: Text(context.loc.settings.database.enableIndexing),
                                      contentItems: [
                                        Text(
                                          context.loc.settings.database.indexingInfo,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (SX.isDebug.value) ...[
                            SettingsButton(
                              name: context.loc.settings.database.createIndexesDebug,
                              icon: const Icon(Icons.create_new_folder_rounded),
                              action: () async {
                                changingIndexes = true;
                                setState(() {});
                                await settingsHandler.dbHandler.createIndexes();
                                changingIndexes = false;
                                setState(() {});
                              },
                            ),
                            SettingsButton(
                              name: context.loc.settings.database.dropIndexesDebug,
                              icon: const Icon(Icons.delete_forever),
                              action: () async {
                                changingIndexes = true;
                                setState(() {});
                                await settingsHandler.dbHandler.dropIndexes();
                                changingIndexes = false;
                                setState(() {});
                              },
                            ),
                            const SettingsButton(name: '', enabled: false),
                          ],
                        ],
                      ),
                    ),
                    if (changingIndexes)
                      Positioned.fill(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                            ),
                            const Align(
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SettingsToggle(
                  value: SX.searchHistoryEnabled.state.value,
                  onChanged: (newValue) {
                    setState(() {
                      SX.searchHistoryEnabled.state.value = newValue;
                    });
                  },
                  title: context.loc.settings.database.enableSearchHistory,
                  trailingIcon: IconButton(
                    icon: const Icon(Icons.help_outline),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.database.enableSearchHistory),
                            contentItems: [
                              Text(context.loc.settings.database.searchHistoryInfo),
                              Text(context.loc.settings.database.searchHistoryRecords(limit: Constants.historyLimit)),
                              Text(context.loc.settings.database.searchHistoryTapInfo),
                              Text(
                                context.loc.settings.database.searchHistoryFavouritesInfo,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SettingsToggle(
                  value: SX.tagTypeFetchEnabled.state.value,
                  onChanged: (newValue) {
                    setState(() {
                      SX.tagTypeFetchEnabled.state.value = newValue;
                    });
                  },
                  title: context.loc.settings.database.enableTagTypeFetching,
                  trailingIcon: IconButton(
                    icon: const Icon(Icons.help_outline),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return SettingsDialog(
                            title: Text(context.loc.settings.database.enableTagTypeFetching),
                            contentItems: [
                              Text(context.loc.settings.database.tagTypeFetchingInfo),
                              Text(context.loc.settings.database.tagTypeFetchingWarning),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SettingsToggle(
                  value: sendFavouritesToServer,
                  onChanged: (newValue) {
                    setState(() {
                      sendFavouritesToServer = newValue;
                    });
                  },
                  title: context.loc.serverFavouritesSync.sendChangesToServer,
                ),
                SettingsToggle(
                  value: serverFavoriteSuccessAnimation,
                  onChanged: (newValue) {
                    if (!sendFavouritesToServer) return;
                    setState(() {
                      serverFavoriteSuccessAnimation = newValue;
                    });
                  },
                  enabled: sendFavouritesToServer,
                  title: context.loc.serverFavouritesSync.successAnimation,
                  subtitle: Text(context.loc.serverFavouritesSync.successAnimationSubtitle),
                ),
                const SettingsButton(name: '', enabled: false),
                SettingsButton(
                  name: context.loc.settings.database.deleteDatabase,
                  icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.deleteDatabaseConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                ServiceHandler.deleteDB(settingsHandler);

                                FlashElements.showSnackbar(
                                  context: context,
                                  title: Text(
                                    context.loc.settings.database.databaseDeleted,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  content: Text(
                                    context.loc.settings.database.appRestartRequired,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  leadingIcon: Icons.delete_forever,
                                  leadingIconColor: Colors.red,
                                  sideColor: Colors.yellow,
                                );
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.delete),
                              icon: const Icon(Icons.delete_forever),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearSnatchedItems,
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Icons.save_alt),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearAllSnatchedConfirm),
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

                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.snatchedItemsCleared,
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
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Icons.delete_forever),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearFavouritedItems,
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Icons.favorite_outline),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearAllFavouritedConfirm),
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

                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.favouritesCleared,
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
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Icons.delete_forever),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SettingsButton(
                  name: context.loc.settings.database.clearSearchHistory,
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  trailingIcon: const Icon(Icons.history),
                  action: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SettingsDialog(
                          title: Text(context.loc.settings.database.clearSearchHistoryConfirm),
                          actionButtons: [
                            const CancelButton(withIcon: true),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (settingsHandler.dbHandler.db != null) {
                                  settingsHandler.dbHandler.deleteFromSearchHistory(null);
                                  FlashElements.showSnackbar(
                                    context: context,
                                    title: Text(
                                      context.loc.settings.database.searchHistoryCleared,
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
                                Navigator.of(context).pop(true);
                              },
                              label: Text(context.loc.clear),
                              icon: const Icon(Icons.delete_forever),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}
