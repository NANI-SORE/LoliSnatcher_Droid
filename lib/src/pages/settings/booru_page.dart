import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

// TODO move all buttons to separate widgets/unified functions to be used in other places?

class BooruPage extends StatefulWidget {
  const BooruPage({super.key});

  @override
  State<BooruPage> createState() => _BooruPageState();
}

class _BooruPageState extends State<BooruPage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  final defaultTagsController = TextEditingController();
  Booru? selectedBooru, initPrefBooru;
  bool _currentPrefBooruWasDeleted = false;

  @override
  void initState() {
    super.initState();
    defaultTagsController.text = SX.defTags.value;

    if (SX.prefBooru.value.isNotEmpty) {
      selectedBooru = settingsHandler.booruList.firstWhereOrNull(
        (booru) => booru.type?.isSaveable == true && booru.name == SX.prefBooru.value,
      );
    } else if (settingsHandler.booruList.isNotEmpty) {
      selectedBooru = settingsHandler.booruList[0];
    }

    initPrefBooru = selectedBooru;
  }

  @override
  void dispose() {
    defaultTagsController.dispose();
    super.dispose();
  }

  void copyBooruLink(bool withSensitiveData) {
    Navigator.of(context).pop(true); // remove dialog
    final String link = selectedBooru?.toLink(withSensitiveData) ?? '';
    if (PlatformExt.isDesktop) {
      ClipboardUtils.copyTextToClipboard(link, subtitle: '');
    } else if (Platform.isAndroid) {
      ServiceHandler.loadShareTextIntent(link);
    }
  }

  Future<void> _onPopInvoked(_, _) async {
    SX.defTags.state.value = selectedBooru == null
        ? defaultTagsController.text
        : ContentPolicy.safeSearchTagsFor(
            selectedBooru!,
            defaultTagsController.text,
          );

    if (selectedBooru == null && settingsHandler.booruList.isNotEmpty) {
      selectedBooru = settingsHandler.booruList[0];
    }
    if (selectedBooru != null) {
      if (_currentPrefBooruWasDeleted) {
        SX.prefBooru.state.value = selectedBooru?.name ?? '';
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
        final res = await askToChangePrefBooru(
          NavigationHandler.instance.navContext,
          initPrefBooru,
          selectedBooru!,
        );

        SX.prefBooru.state.value = (res == true ? selectedBooru?.name : initPrefBooru?.name) ?? '';
      }
    }
    await settingsHandler.saveSettings(restate: false);
    await settingsHandler.sortBooruList();
  }

  Widget addButton() {
    return SettingsButton(
      name: context.loc.settings.booru.addBooru,
      icon: const Icon(Icons.add),
      page: BooruEdit.add,
    );
  }

  Widget sourceLimitNotice() {
    if (!ContentPolicy.isFromStore) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.settings.booru.sourceLimitNotice,
      icon: const Icon(Icons.tune),
      enabled: false,
      dense: true,
    );
  }

  Widget expandedSourceCompatibilityToggle() {
    if (!ContentPolicy.isFromStore) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        SettingsButton(
          name: context.loc.settings.booru.advanced,
          icon: const Icon(Icons.tune),
          enabled: false,
          drawTopBorder: true,
        ),
        SettingsToggle(
          value: SX.expandedSourceCompatibilityEnabled.value,
          title: context.loc.settings.booru.expandedSourceCompatibility,
          subtitle: Text(context.loc.settings.booru.expandedSourceCompatibilitySubtitle),
          onChanged: (value) async {
            if (value) {
              final bool confirm =
                  await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return SettingsDialog(
                        title: Text(context.loc.settings.booru.expandedSourceCompatibility),
                        contentItems: [
                          Text(context.loc.settings.booru.expandedSourceCompatibilityConfirm),
                        ],
                        actionButtons: const [
                          CancelButton(returnData: false, withIcon: true),
                          ConfirmButton(
                            returnData: true,
                            withIcon: true,
                          ),
                        ],
                      );
                    },
                  ) ??
                  false;
              if (!confirm) {
                return;
              }
            }

            setState(() {
              SX.expandedSourceCompatibilityEnabled.state.value = value;
              if (selectedBooru != null && !ContentPolicy.isBooruAllowed(selectedBooru)) {
                selectedBooru = null;
              }
            });
            await settingsHandler.saveSettings(restate: true);
            await settingsHandler.loadBoorus();
            setState(() {
              if (selectedBooru == null && settingsHandler.booruList.isNotEmpty) {
                selectedBooru = settingsHandler.booruList[0];
              }
            });
          },
        ),
      ],
    );
  }

  Widget booruSelector() {
    return SettingsBooruDropdown(
      value: settingsHandler.booruList.contains(selectedBooru) ? selectedBooru : settingsHandler.booruList[0],
      onChanged: (Booru? newValue) {
        final bool isNewValuePresent = settingsHandler.booruList.contains(newValue);
        setState(() {
          selectedBooru = isNewValuePresent ? newValue : settingsHandler.booruList[0];
        });
      },
      title: context.loc.settings.booru.addedBoorus,
      trailingIcon: IconButton(
        icon: const Icon(Icons.help_outline),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              return SettingsDialog(
                title: Text(context.loc.booru),
                contentItems: [
                  Text(context.loc.settings.booru.booruDropdownInfo),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget shareButton() {
    if (!BooruType.saveable.contains(selectedBooru?.type)) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.settings.booru.shareBooru,
      icon: const Icon(Icons.share),
      action: () {
        showDialog(
          context: context,
          builder: (context) {
            return SettingsDialog(
              title: Text(context.loc.settings.booru.shareBooru),
              contentItems: [
                Text(
                  Platform.isAndroid
                      ? context.loc.settings.booru.shareBooruDialogMsgMobile(booruName: selectedBooru?.name ?? '')
                      : context.loc.settings.booru.shareBooruDialogMsgDesktop(booruName: selectedBooru?.name ?? ''),
                ),
              ],
              actionButtons: [
                const CancelButton(withIcon: true),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(context.loc.no),
                  onPressed: () {
                    copyBooruLink(false);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(context.loc.yes),
                  onPressed: () {
                    copyBooruLink(true);
                  },
                ),
              ],
            );
          },
        );
      },
      trailingIcon: Platform.isAndroid
          ? IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return SettingsDialog(
                      title: Text(context.loc.settings.booru.booruSharing),
                      contentItems: [
                        // TODO more explanations about booru sharing, add screenshot, etc
                        const Text(''),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(context.loc.settings.booru.booruSharingMsgAndroid),
                        ),
                        ElevatedButton(
                          onPressed: ServiceHandler.openLinkDefaultsSettings,
                          child: Text(context.loc.goToSettings),
                        ),
                      ],
                    );
                  },
                );
              },
            )
          : null,
    );
  }

  Widget editButton() {
    if (!BooruType.saveable.contains(selectedBooru?.type)) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.settings.booru.editBooru,
      icon: const Icon(Icons.edit),
      // do nothing if no selected or selected "Favourites/Dowloads"
      // TODO update all tabs with old booru with a new one
      // TODO if you open edit after already editing - it will open old instance + possible exception due to old data
      page: (selectedBooru != null && BooruType.saveable.contains(selectedBooru?.type))
          ? () => BooruEdit.edit(selectedBooru!)
          : null,
    );
  }

  Booru? _preferredBooru() {
    return settingsHandler.booruList.firstWhereOrNull((booru) => booru.name == SX.prefBooru.value) ??
        (settingsHandler.booruList.contains(initPrefBooru) ? initPrefBooru : null);
  }

  Booru? _fallbackAfterDeleting(Booru removed) {
    final preferred = _preferredBooru();
    if (preferred != null && !preferred.matchesIdentity(removed)) return preferred;
    return settingsHandler.booruList.firstWhereOrNull((booru) => !booru.matchesIdentity(removed));
  }

  Widget deleteButton() {
    if (!BooruType.saveable.contains(selectedBooru?.type)) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.settings.booru.deleteBooru,
      icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
      action: () {
        // do nothing if no selected or selected "Favourites/Downloads" or there are tabs with it
        if (selectedBooru == null) {
          FlashElements.showSnackbar(
            context: context,
            title: Text(
              context.loc.settings.booru.noBooruSelected,
              style: const TextStyle(fontSize: 20),
            ),
            leadingIcon: Icons.warning_amber,
            leadingIconColor: Colors.red,
            sideColor: Colors.red,
          );
          return;
        }

        final List<SearchTab> tabsWithBooru = searchHandler.tabs
            .where((tab) => tab.selectedBooru.value.matchesIdentity(selectedBooru))
            .toList();
        final fallbackAfterDeletion = _fallbackAfterDeleting(selectedBooru!);
        if (tabsWithBooru.isNotEmpty && fallbackAfterDeletion == null) {
          FlashElements.showSnackbar(
            context: context,
            title: Text(
              context.loc.settings.booru.cantDeleteThisBooru,
              style: const TextStyle(fontSize: 20),
            ),
            content: Text(
              context.loc.settings.booru.removeRelatedTabsFirst,
              style: const TextStyle(fontSize: 16),
            ),
            leadingIcon: Icons.warning_amber,
            leadingIconColor: Colors.red,
            sideColor: Colors.red,
          );
          return;
        }

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return SettingsDialog(
              title: Text('${context.loc.settings.booru.deleteBooru}: ${selectedBooru?.name}?'),
              actionButtons: [
                const CancelButton(withIcon: true),
                ElevatedButton.icon(
                  onPressed: () async {
                    final Booru tempSelected = selectedBooru!;
                    final preferredBooru = _preferredBooru();
                    final fallbackBooru = _fallbackAfterDeleting(tempSelected);
                    final deletedPreferredBooru = tempSelected.matchesIdentity(preferredBooru);

                    selectedBooru = fallbackBooru;
                    if (deletedPreferredBooru) {
                      _currentPrefBooruWasDeleted = true;
                      SX.prefBooru.state.setValue(fallbackBooru?.name ?? '', save: false);
                    }
                    setState(() {});

                    var deleted = false;
                    try {
                      deleted = await settingsHandler.deleteBooru(tempSelected);
                    } catch (e, s) {
                      Logger.Inst().log(
                        'Failed to delete booru ${tempSelected.name}: $e',
                        'BooruPage',
                        'deleteButton',
                        LogTypes.exception,
                        s: s,
                      );
                    }

                    if (deleted) {
                      if (deletedPreferredBooru) {
                        try {
                          await settingsHandler.saveSettings(restate: false);
                        } catch (e, s) {
                          Logger.Inst().log(
                            'Failed to persist preferred booru after deletion: $e',
                            'BooruPage',
                            'deleteButton',
                            LogTypes.settingsError,
                            s: s,
                          );
                        }
                      }
                      if (fallbackBooru != null) {
                        searchHandler.replaceBooruInTabs(tempSelected, fallbackBooru);
                      }
                    } else {
                      // restore selected and prefbooru if something went wrong
                      selectedBooru = tempSelected;
                      _currentPrefBooruWasDeleted = false;
                      if (deletedPreferredBooru) {
                        SX.prefBooru.state.setValue(tempSelected.name ?? '', save: false);
                      }
                      await settingsHandler.sortBooruList();
                    }

                    if (!context.mounted) return;
                    if (deleted) {
                      FlashElements.showSnackbar(
                        context: context,
                        title: Text(
                          context.loc.settings.booru.booruDeleted,
                          style: const TextStyle(fontSize: 20),
                        ),
                        leadingIcon: Icons.delete_forever,
                        leadingIconColor: Colors.red,
                        sideColor: Colors.yellow,
                      );
                    } else {
                      FlashElements.showSnackbar(
                        context: context,
                        title: Text(
                          context.loc.errorExclamation,
                          style: const TextStyle(fontSize: 20),
                        ),
                        content: Text(
                          context.loc.settings.booru.deleteBooruError,
                          style: const TextStyle(fontSize: 16),
                        ),
                        leadingIcon: Icons.warning_amber,
                        leadingIconColor: Colors.red,
                        sideColor: Colors.red,
                      );
                    }

                    setState(() {});
                    Navigator.of(context).pop(true);
                  },
                  label: Text(context.loc.settings.booru.deleteBooru),
                  icon: const Icon(Icons.delete_forever),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget webviewButton() {
    if (BooruType.saveable.contains(selectedBooru?.type) &&
        PlatformExt.hasWebviewSupport &&
        ContentPolicy.canOpenWebview) {
      // TODO add help button and explain how to properly setup cookies?
      return SettingsButton(
        name: context.loc.settings.webview.openWebview,
        subtitle: Text(context.loc.settings.webview.openWebviewTip),
        icon: const Icon(Icons.public),
        page: () => InAppWebviewView(initialUrl: selectedBooru!.baseURL!),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget addFromClipboardButton() {
    return SettingsButton(
      name: context.loc.settings.booru.importBooru,
      icon: const Icon(Icons.paste),
      action: () async {
        final ClipboardData? cdata = await Clipboard.getData(Clipboard.kTextPlain);
        final String url = cdata?.text ?? '';
        Logger.Inst().log(
          url,
          'BooruPage',
          'getBooruFromClipboard',
          LogTypes.settingsLoad,
        );
        if (url.isNotEmpty) {
          if (url.contains('loli.snatcher')) {
            final Booru booru = Booru.fromLink(url);
            if (booru.name != null && booru.name!.isNotEmpty && booru.type!.isSaveable) {
              if (!ContentPolicy.isBooruAllowed(booru)) {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booru.sourceUnavailableCurrentSettings,
                    style: const TextStyle(fontSize: 20),
                  ),
                  leadingIcon: Icons.warning_amber,
                  leadingIconColor: Colors.yellow,
                  sideColor: Colors.yellow,
                );
                return;
              }
              if (settingsHandler.booruList.indexWhere((b) => b.name == booru.name) != -1) {
                // Rename config if its already in the list
                booru.name = '${booru.name!} (duplicate)';
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) => BooruEdit.add(initialBooru: booru),
                ),
              );
            }
          } else {
            FlashElements.showSnackbar(
              context: context,
              title: Text(
                context.loc.invalidUrl,
                style: const TextStyle(fontSize: 20),
              ),
              content: Text(
                context.loc.settings.booru.onlyLSURLsSupported,
                style: const TextStyle(fontSize: 16),
              ),
              leadingIcon: Icons.warning_amber,
              leadingIconColor: Colors.red,
              sideColor: Colors.red,
            );
          }
        } else {
          FlashElements.showSnackbar(
            context: context,
            title: Text(
              context.loc.clipboardIsEmpty,
              style: const TextStyle(fontSize: 20),
            ),
            leadingIcon: Icons.warning_amber,
            leadingIconColor: Colors.red,
            sideColor: Colors.red,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsChildren = <Widget>[
      sourceLimitNotice(),
      TagSearchBox(
        controller: defaultTagsController,
        title: context.loc.settings.booru.defaultTags,
        hintText: context.loc.snatcher.enterTags,
        booru: selectedBooru,
        allowMultipleTags: true,
        showBooruSelector: true,
        clearable: true,
        // resetText: () => 'rating:safe', // TODO
      ),
      SX.limit.state.buildWidget(context),
      const SettingsButton(name: '', enabled: false),
      addFromClipboardButton(),
      addButton(),
      if (settingsHandler.booruList.isNotEmpty) ...[
        booruSelector(),
        if (selectedBooru != null) ...[
          editButton(),
          shareButton(),
          webviewButton(),
          deleteButton(),
        ],
      ],
    ];

    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: SettingsAppBar(
          title: context.loc.settings.booru.title,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ListView(
                children: [
                  if (ContentPolicy.isFromStore) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight + 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: settingsChildren,
                      ),
                    ),
                    ...List.generate(
                      constraints.maxHeight < 800 ? 2 : 1,
                      (_) => const SettingsButton(
                        name: '',
                        enabled: false,
                        drawBottomBorder: false,
                      ),
                    ),
                    //
                    expandedSourceCompatibilityToggle(),
                  ] else ...[
                    ...settingsChildren,
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<bool?> askToChangePrefBooru(
  BuildContext context,
  Booru? initBooru,
  Booru selectedBooru,
) async {
  if (initBooru != null && initBooru.name != selectedBooru.name) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: Text(context.loc.settings.booru.changeDefaultBooru),
          contentItems: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: context.loc.settings.booru.changeTo),
                  TextSpan(
                    text: selectedBooru.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  WidgetSpan(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: BooruFavicon(selectedBooru),
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: context.loc.settings.booru.keepCurrentBooru),
                  TextSpan(
                    text: initBooru.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  WidgetSpan(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: BooruFavicon(initBooru),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: context.loc.settings.booru.changeToNewBooru),
                  TextSpan(
                    text: selectedBooru.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  WidgetSpan(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: BooruFavicon(selectedBooru),
                    ),
                  ),
                ],
              ),
            ),
          ],
          actionButtons: [
            ElevatedButton.icon(
              icon: Row(
                children: [
                  const Icon(Icons.cancel_outlined),
                  const SizedBox(width: 4),
                  BooruFavicon(initBooru),
                ],
              ),
              label: Text(context.loc.no),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton.icon(
              icon: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded),
                  const SizedBox(width: 4),
                  BooruFavicon(selectedBooru),
                ],
              ),
              label: Text(context.loc.yes),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  } else {
    return true;
  }
}
