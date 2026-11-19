import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/pages/snatcher_page.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_action_label.dart';

class DDSelectionActions extends StatelessWidget {
  const DDSelectionActions({required this.controller, required this.toggleDrawer, super.key});
  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;
  @override
  Widget build(BuildContext context) => Obx(() {
    final selected = controller.currentTabOrNull?.selected ?? [];
    final favourites = selected.where((e) => e.isFavourite.value == true).length;
    final notFavourites = selected.where((e) => e.isFavourite.value == false).length;
    final saved = selected.where((e) => e.isSnatched.value == true).length;
    if (selected.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => controller.onStartSnatching(context, false),
              onLongPress: () => controller.onStartSnatching(context, true),
              icon: const Icon(Icons.download_outlined),
              label: Text(downloadText('downloadSelected', {'count': selected.length})),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: downloadText('selectionActions'),
            onSelected: (action) async {
              switch (action) {
                case 'again':
                  await controller.onStartSnatching(context, true);
                case 'favourite':
                  await controller.favouriteSelected();
                case 'unfavourite':
                  await controller.unfavouriteSelected();
                case 'unmark':
                  await controller.removeSnatchedStatusFromSelected();
                case 'clear':
                  controller.currentTabOrNull?.selected.clear();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'again',
                child: DDActionLabel(
                  icon: Icons.download_outlined,
                  label: downloadText('redownload'),
                  count: selected.length,
                ),
              ),
              if (notFavourites > 0)
                PopupMenuItem(
                  value: 'favourite',
                  child: DDActionLabel(
                    icon: Icons.favorite,
                    label: context.loc.settings.downloads.favouriteSelected,
                    count: notFavourites,
                  ),
                ),
              if (favourites > 0)
                PopupMenuItem(
                  value: 'unfavourite',
                  child: DDActionLabel(
                    icon: Icons.heart_broken,
                    label: context.loc.settings.downloads.unfavouriteSelected,
                    count: favourites,
                  ),
                ),
              if (saved > 0)
                PopupMenuItem(
                  value: 'unmark',
                  child: DDActionLabel(
                    icon: Icons.remove_done,
                    label: context.loc.settings.downloads.removeSnatchedStatusFromSelected,
                    count: saved,
                  ),
                ),
              PopupMenuItem(
                value: 'clear',
                child: DDActionLabel(
                  icon: Icons.deselect,
                  label: context.loc.settings.downloads.clearSelected,
                  count: selected.length,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  });
}

class DDNavigationButtons extends StatelessWidget {
  const DDNavigationButtons({required this.controller, required this.toggleDrawer, this.onSelectByQuery, super.key});
  final DownloadsDrawerController controller;
  final VoidCallback toggleDrawer;
  final Future<bool> Function(BuildContext)? onSelectByQuery;
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
          onLongPress: onSelectByQuery == null
              ? null
              : () async {
                  if (await onSelectByQuery!(context)) toggleDrawer();
                },
          tooltip: context.loc.selectAll,
          onPressed: () {
            final tab = controller.currentTabOrNull;
            if (tab == null) return;
            final items = tab.booruHandler.filteredFetched;
            tab.selected.addAll(items.where((item) => !tab.selected.contains(item)));
            toggleDrawer();
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
