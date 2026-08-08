import 'dart:async';

import 'package:flutter/material.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/eagle_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/main_drawer_item.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/upload_handler.dart';
import 'package:lolisnatcher/src/pages/settings_page.dart';
import 'package:lolisnatcher/src/pages/upload_manager_page.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/mascot_image.dart';
import 'package:lolisnatcher/src/widgets/common/multibooru_toggle.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/eagle_folder_drawer.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_bar.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_buttons.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  Future<Booru?> _showSelectWebviewBooruDialog(BuildContext context, List<Booru> boorus) {
    return showDialog<Booru?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.loc.mobileHome.selectBooruForWebview),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width,
                height: 52,
                child: SettingsBooruDropdown(
                  value: null,
                  items: boorus,
                  onChanged: (Booru? newBooru) {
                    if (newBooru == null) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      Navigator.of(context).pop(newBooru);
                    });
                  },
                  title: context.loc.booru,
                  contentPadding: EdgeInsets.zero,
                  titleAsLabel: true,
                  drawBottomBorder: false,
                ),
              ),
              const CancelButton(withIcon: true),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, MainDrawerItem item) {
    final settingsHandler = SettingsHandler.instance;
    final searchHandler = SearchHandler.instance;
    switch (item) {
      case MainDrawerItem.search:
        return RepaintBoundary(
          child: Obx(() {
            if (settingsHandler.booruList.isNotEmpty && searchHandler.tabs.isNotEmpty) {
              return Container(
                height: MainSearchBar.height,
                margin: const EdgeInsets.fromLTRB(2, 24, 2, 12),
                child: const MainSearchBarWithActions('drawer'),
              );
            }
            return const SizedBox.shrink();
          }),
        );

      case MainDrawerItem.tabSelector:
        return const TabSelector();

      case MainDrawerItem.tabButtons:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: TabButtons(true, WrapAlignment.spaceEvenly),
        );

      case MainDrawerItem.eagleFolders:
        return Obx(() {
          searchHandler.index.value; // react to tab switches
          if (searchHandler.tabs.isEmpty) return const SizedBox.shrink();
          if (searchHandler.currentBooru.type?.isEagle != true) return const SizedBox.shrink();
          final handler = searchHandler.currentBooruHandler;
          if (handler is! EagleHandler) return const SizedBox.shrink();
          return EagleFolderDrawer(handler: handler);
        });

      case MainDrawerItem.uploadManager:
        return Obx(() {
          settingsHandler.booruList.length; // react to booru add/remove
          final hasTarget = settingsHandler.booruList.any((b) => b.type?.supportsItemAdd == true);
          if (!hasTarget) return const SizedBox.shrink();
          final uploadHandler = UploadHandler.instance;
          return Obx(() {
            uploadHandler.queue.length; // react to queue changes
            final int pending = uploadHandler.activeCount;
            return SettingsButton(
              name: 'Upload Manager',
              icon: pending > 0
                  ? Badge(
                      label: Text('$pending'),
                      child: const Icon(Icons.cloud_upload_outlined),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              action: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const UploadManagerPage()),
                );
              },
            );
          });
        });

      case MainDrawerItem.multibooruToggle:
        return const MergeBooruToggleAndSelector();

      case MainDrawerItem.lockApp:
        return ListenableBuilder(
          listenable: Listenable.merge([
            LocalAuthHandler.instance.deviceSupportsBiometrics,
            SettingsHandler.instance.useLockscreen,
          ]),
          builder: (_, child) {
            final supports = LocalAuthHandler.instance.deviceSupportsBiometrics.value;
            final useLock = SettingsHandler.instance.useLockscreen.value;
            if (supports && useLock) return child!;
            return const SizedBox.shrink();
          },
          child: SettingsButton(
            name: context.loc.mobileHome.lockApp,
            icon: const Icon(Icons.lock),
            action: () => LocalAuthHandler.instance.lock(manually: true),
          ),
        );

      case MainDrawerItem.settings:
        return SettingsButton(
          name: context.loc.settings.title,
          icon: const Icon(Icons.settings),
          page: () => const SettingsPage(),
        );

      case MainDrawerItem.webview:
        return Obx(() {
          if (settingsHandler.booruList.isNotEmpty &&
              searchHandler.tabs.isNotEmpty &&
              PlatformExt.hasWebviewSupport &&
              ContentPolicy.canOpenWebview) {
            final currentBooru = searchHandler.currentBooruOrNull;
            if (currentBooru == null) return const SizedBox.shrink();

            final boorus = <Booru>[
              currentBooru,
              ...searchHandler.currentSecondaryBoorusOrNull?.value ?? <Booru>[],
            ].where((b) => b.baseURL?.isNotEmpty == true && BooruType.saveable.contains(b.type)).toList();
            if (boorus.isEmpty) return const SizedBox.shrink();
            return SettingsButton(
              name: context.loc.settings.webview.openWebview,
              icon: const Icon(Icons.public),
              action: () async {
                final selected = boorus.length == 1
                    ? boorus.first
                    : await _showSelectWebviewBooruDialog(context, boorus);
                if (selected == null) return;
                final url = selected.baseURL;
                final ua = Tools.browserUserAgent;
                if (url == null || url.isEmpty) return;
                unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => InAppWebviewView(initialUrl: url, userAgent: ua),
                    ),
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        });

      case MainDrawerItem.updateAvailable:
        return Obx(() {
          if (settingsHandler.updateInfo.value != null &&
              Constants.updateInfo.buildNumber < (settingsHandler.updateInfo.value!.buildNumber)) {
            return SettingsButton(
              name: context.loc.settings.checkForUpdates.updateAvailable,
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.update),
                  Positioned(
                    top: 1,
                    left: 1,
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              action: () async {
                settingsHandler.showUpdate(true);
              },
            );
          }
          return const SizedBox.shrink();
        });

      case MainDrawerItem.closeApp:
        if (!PlatformExt.isDesktop) return const SizedBox.shrink();
        return SettingsButton(
          name: context.loc.closeTheApp,
          icon: const Icon(Icons.exit_to_app),
          action: () async {
            await Navigator.of(context).maybePop();
            await Future.delayed(const Duration(milliseconds: 400));
            await Navigator.of(context).maybePop();
          },
        );

      case MainDrawerItem.mascot:
        return Obx(() {
          if (settingsHandler.enableDrawerMascot.value) return const MascotImage();
          return const SizedBox.shrink();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsHandler = SettingsHandler.instance;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Obx(() {
          final bottomAlign = settingsHandler.drawerBottomAlign.value;
          // Touch length so adding/removing items rebuilds via Obx.
          settingsHandler.mainDrawerItems.length;
          final items = settingsHandler.mainDrawerItems;
          return ListView.builder(
            controller: ScrollController(),
            reverse: bottomAlign,
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(context, items[index]),
          );
        }),
      ),
    );
  }
}
