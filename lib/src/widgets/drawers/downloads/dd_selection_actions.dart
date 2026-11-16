import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/pages/snatcher_page.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/hidden_items_page.dart';

class DDSelectionActions extends StatelessWidget {
  const DDSelectionActions({required this.controller, required this.toggleDrawer, super.key});
  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;
  @override
  Widget build(BuildContext context) => Obx(() {
    final selected = controller.searchHandler.currentSelectedOrNull ?? [];
    final tab = controller.searchHandler.currentTabOrNull;
    if (selected.isEmpty) {
      if (tab == null || tab.allHiddenItems.isEmpty) return const SizedBox.shrink();
      return ListTile(
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text('${context.loc.settings.downloads.hiddenItems} (${tab.allHiddenItems.length})'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HiddenItemsPage(tab: tab))),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => controller.onStartSnatching(context, false),
              icon: const Icon(Icons.download_outlined),
              label: Text(downloadText('downloadSelected', {'count': selected.length})),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: downloadText('selectionActions'),
            onSelected: (action) async {
              switch (action) {
                case 'hidden':
                  if (tab != null)
                    await Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => HiddenItemsPage(tab: tab)));
                case 'again':
                  await controller.onStartSnatching(context, true);
                case 'favourite':
                  await controller.favouriteSelected();
                case 'unfavourite':
                  await controller.unfavouriteSelected();
                case 'unmark':
                  await controller.removeSnatchedStatusFromSelected();
                case 'clear':
                  controller.searchHandler.currentTabOrNull?.selected.clear();
              }
            },
            itemBuilder: (_) => [
              if (tab != null && tab.allHiddenItems.isNotEmpty)
                PopupMenuItem(value: 'hidden', child: Text(context.loc.settings.downloads.hiddenItems)),
              PopupMenuItem(value: 'again', child: Text(downloadText('redownload'))),
              if (selected.any((e) => e.isFavourite.value != true))
                PopupMenuItem(value: 'favourite', child: Text(context.loc.settings.downloads.favouriteSelected)),
              if (selected.any((e) => e.isFavourite.value == true))
                PopupMenuItem(value: 'unfavourite', child: Text(context.loc.settings.downloads.unfavouriteSelected)),
              if (selected.any((e) => e.isSnatched.value == true))
                PopupMenuItem(
                  value: 'unmark',
                  child: Text(context.loc.settings.downloads.removeSnatchedStatusFromSelected),
                ),
              PopupMenuItem(value: 'clear', child: Text(context.loc.settings.downloads.clearSelected)),
            ],
          ),
        ],
      ),
    );
  });
}

class DDNavigationButtons extends StatelessWidget {
  const DDNavigationButtons({required this.controller, required this.toggleDrawer, super.key});
  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SnatcherPage())),
            icon: const Icon(Icons.add),
            label: Text(context.loc.snatcher.title),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: context.loc.selectAll,
          onPressed: () {
            final tab = controller.searchHandler.currentTabOrNull;
            final items = controller.searchHandler.currentFetchedOrNull;
            if (tab != null && items != null) tab.selected.addAll(items.where((item) => !tab.selected.contains(item)));
          },
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: context.loc.snatcher.snatchingHistory,
          onPressed: controller.settingsHandler.booruList.any((b) => b.type?.isDownloads == true)
              ? () {
                  final source = controller.settingsHandler.booruList.where((b) => b.type?.isDownloads == true).first;
                  controller.searchHandler.addTabByString('', switchToNew: true, customBooru: source);
                  toggleDrawer();
                }
              : null,
          icon: const Icon(Icons.photo_library_outlined),
        ),
      ],
    ),
  );
}
