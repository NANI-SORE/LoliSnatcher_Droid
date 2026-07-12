import 'package:flutter/material.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/pages/snatcher_page.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';

class DDSelectionActions extends StatelessWidget {
  const DDSelectionActions({
    required this.controller,
    required this.toggleDrawer,
    super.key,
  });

  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;

  @override
  Widget build(BuildContext context) {
    final searchHandler = controller.searchHandler;

    return Obx(() {
      final totalItems = searchHandler.currentFetched.length;
      final selected = searchHandler.currentSelected;
      final hiddenCount = searchHandler.currentTab.hiddenItems.length;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hiddenCount > 0)
            SettingsButton(
              name: '${context.loc.settings.downloads.unhideHidden} ($hiddenCount)',
              icon: const Icon(Icons.visibility_outlined),
              action: controller.unhideItems,
              drawTopBorder: true,
            ),
          if (selected.length != totalItems)
            SettingsButton(
              name: context.loc.selectAll,
              icon: const Icon(Icons.select_all),
              action: () => searchHandler.currentTab.selected.addAll(searchHandler.currentFetched),
              onLongPress: () => controller.selectFetchedByQuery(context),
              drawTopBorder: hiddenCount == 0,
            ),
          if (selected.isNotEmpty)
            SettingsButton(
              name: context.loc.history.clearSelection,
              icon: const Icon(Icons.deselect),
              action: () => searchHandler.currentTab.selected.clear(),
              drawTopBorder: hiddenCount == 0 && selected.length == totalItems,
            ),
        ],
      );
    });
  }
}

class DDNavigationButtons extends StatelessWidget {
  const DDNavigationButtons({
    required this.controller,
    required this.toggleDrawer,
    super.key,
  });

  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;

  @override
  Widget build(BuildContext context) {
    final searchHandler = controller.searchHandler;
    final settingsHandler = controller.settingsHandler;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsButton(
          name: context.loc.snatcher.title,
          icon: const Icon(Icons.download_sharp),
          page: () => const SnatcherPage(),
        ),
        SettingsButton(
          name: context.loc.snatcher.snatchingHistory,
          icon: const Icon(Icons.file_download_outlined),
          action: () {
            final Booru? downloadsBooru = settingsHandler.booruList.firstWhereOrNull(
              (booru) => booru.type?.isDownloads == true,
            );
            final bool hasDownloads = downloadsBooru != null;

            if (!hasDownloads) {
              return;
            }

            searchHandler.addTabByString(
              '',
              switchToNew: true,
              customBooru: downloadsBooru,
            );
            toggleDrawer();
          },
        ),
      ],
    );
  }
}
