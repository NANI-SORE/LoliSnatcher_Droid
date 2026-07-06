import 'package:flutter/material.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/share_action.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/services/gallery_share_service.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/gallery/share_action_dialog.dart';
import 'package:lolisnatcher/src/widgets/preview/image_compare_dialog.dart';

class DownloadsDrawerController {
  DownloadsDrawerController() {
    scrollController = ScrollController();
  }

  final SnatchHandler snatchHandler = SnatchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final GalleryShareService galleryShareService = GalleryShareService();

  final RxBool updating = false.obs;
  late final ScrollController scrollController;

  // Handler cache to avoid duplicate BooruHandlerFactory calls
  final Map<int, BooruHandler> _handlerCache = {};

  BooruHandler getHandler(Booru booru) {
    return _handlerCache.putIfAbsent(
      booru.hashCode,
      () => BooruHandlerFactory().getBooruHandler([booru], null).booruHandler,
    );
  }

  void clearHandlerCache() => _handlerCache.clear();

  Future<void> onStartSnatching(BuildContext context, bool isLongTap) async {
    if (!await setPermissions()) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.downloads.pleaseProvideStoragePermission,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Icons.warning,
        sideColor: Colors.red,
        leadingIconColor: Colors.red,
      );
      return;
    }

    if (searchHandler.currentSelected.isNotEmpty) {
      snatchHandler.queue(
        [...searchHandler.currentSelected],
        searchHandler.currentBooru,
        settingsHandler.snatchCooldown,
        isLongTap,
      );
      if (settingsHandler.favouriteOnSnatch) {
        await searchHandler.currentTab.updateFavForMultipleItems(
          searchHandler.currentSelected,
          newValue: true,
          skipSnatching: true,
        );
      }
      await Future.delayed(const Duration(milliseconds: 100));
      searchHandler.currentTab.selected.clear();
    } else {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.downloads.noItemsSelected,
          style: const TextStyle(fontSize: 20),
        ),
        overrideLeadingIconWidget: const Kaomoji(
          category: KaomojiCategory.dissatisfaction,
          style: TextStyle(fontSize: 18),
        ),
      );
    }
  }

  Future<void> onShareSelected(BuildContext context) async {
    await onShareSelectedWithAction(context, settingsHandler.shareAction);
  }

  void onShareSelectedLongPress(BuildContext context) {
    showShareSelectedDialog(context);
  }

  Future<void> onShareSelectedWithAction(BuildContext context, ShareAction shareAction) async {
    if (searchHandler.currentSelected.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.downloads.noItemsSelected,
          style: const TextStyle(fontSize: 20),
        ),
        overrideLeadingIconWidget: const Kaomoji(
          category: KaomojiCategory.dissatisfaction,
          style: TextStyle(fontSize: 18),
        ),
      );
      return;
    }

    await shareActionController(context).run(_shareActionWithoutTags(shareAction), context);
  }

  Future<void> shareSelectedText(
    BuildContext context,
    String Function(BooruItem item) itemText, {
    bool requirePostUrl = false,
  }) async {
    final selected = [...searchHandler.currentSelected];
    final lines = <String>[];

    for (final item in selected) {
      if (requirePostUrl && item.postURL.isEmpty) {
        continue;
      }

      final text = itemText(item).trim();
      if (text.isNotEmpty) {
        lines.add(text);
      }
    }

    if (lines.isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.gallery.noPostUrl, style: const TextStyle(fontSize: 20)),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return;
    }

    await galleryShareService.shareText(
      lines.join('\n\n'),
      subtitle: '',
    );
  }

  Future<void> shareSelectedFiles(BuildContext context, {String? text}) async {
    final selected = [...searchHandler.currentSelected];
    if (selected.isEmpty) {
      return;
    }

    final maxFilesToShare = PlatformExt.isDesktop ? 1 : 100;
    if (selected.length > maxFilesToShare) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.downloads.fileShareLimit(max: maxFilesToShare),
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }

    if (snatchHandler.currentShare.value != null) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.viewer.appBar.shareFile, style: const TextStyle(fontSize: 20)),
        content: Text(context.loc.viewer.appBar.alreadyDownloadingFile, style: const TextStyle(fontSize: 16)),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
      return;
    }

    FlashElements.showSnackbar(
      context: context,
      title: Text(context.loc.gallery.loadingFile, style: const TextStyle(fontSize: 20)),
      content: Text(context.loc.gallery.loadingFileMessage, style: const TextStyle(fontSize: 16)),
      overrideLeadingIconWidget: const SizedBox(
        width: 50,
        height: 50,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      ),
      sideColor: Colors.yellow,
    );

    final success = await galleryShareService.shareFiles(
      items: selected,
      booru: searchHandler.currentBooru,
      context: context,
      text: text,
    );

    if (!success) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.viewer.appBar.error, style: const TextStyle(fontSize: 20)),
        content: Text(
          context.loc.viewer.appBar.savingFileError,
          style: const TextStyle(fontSize: 16),
        ),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return;
    }

    searchHandler.currentTab.selected.clear();
  }

  Future<void> shareSelectedHydrus(BuildContext context) async {
    if (!settingsHandler.hasHydrus) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.viewer.appBar.hydrusNotConfigured, style: const TextStyle(fontSize: 20)),
      );
      return;
    }

    final Booru? hydrus = settingsHandler.booruList.firstWhereOrNull((element) => element.type?.isHydrus == true);
    if (hydrus == null) {
      return;
    }

    final res = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.loc.viewer.appBar.hydrusShare),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.loc.viewer.appBar.whichUrlToShareToHydrus),
              const SizedBox(height: 12),
              ListTile(
                title: Text(context.loc.viewer.appBar.postURL),
                leading: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).pop('post'),
              ),
              ListTile(
                title: Text(context.loc.viewer.appBar.fileURL),
                leading: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).pop('file'),
              ),
              ListTile(
                title: Text(context.loc.cancel),
                leading: const Icon(Icons.cancel_outlined),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (res == null) {
      return;
    }

    final hydrusHandler = HydrusHandler(hydrus, 10);
    for (final item in [...searchHandler.currentSelected]) {
      await hydrusHandler.addURL(item, usePostUrl: res == 'post');
    }
  }

  void showShareSelectedDialog(BuildContext context) {
    shareActionController(context).showDialog(context);
  }

  void invertSelection() {
    final selectedItems = Set<BooruItem>.identity()..addAll(searchHandler.currentSelected);
    searchHandler.currentTab.selected.assignAll(
      searchHandler.currentFetched.where((item) => !selectedItems.contains(item)),
    );
  }

  void reverseSelectedOrder() {
    searchHandler.currentTab.selected.assignAll([...searchHandler.currentSelected.reversed]);
  }

  void hideSelected() {
    final selectedItems = Set<BooruItem>.identity()..addAll(searchHandler.currentSelected);
    final handler = searchHandler.currentTab.booruHandler;
    handler.fetched.removeWhere(selectedItems.contains);
    handler.filterFetched();
    searchHandler.currentTab.selected.clear();
  }

  void compareSelected(BuildContext context) {
    final selected = [...searchHandler.currentSelected];
    if (selected.length != 2 || selected.any((item) => !item.mediaType.value.isImageOrAnimation)) {
      return;
    }

    final firstBooru = searchHandler.currentBooru.type?.isFavouritesOrDownloads == true
        ? _sourceBooruForItem(selected.first) ?? searchHandler.currentBooru
        : searchHandler.currentBooru;
    final secondBooru = searchHandler.currentBooru.type?.isFavouritesOrDownloads == true
        ? _sourceBooruForItem(selected.last) ?? searchHandler.currentBooru
        : searchHandler.currentBooru;

    showImageCompareDialog(
      context,
      selected.first,
      selected.last,
      firstBooru: firstBooru,
      secondBooru: secondBooru,
    );
  }

  Future<void> refreshSelectedMetadata(BuildContext context) async {
    if (searchHandler.currentBooru.type?.isFavouritesOrDownloads != true) {
      _showNoRefreshableItems(context);
      return;
    }

    final selected = [...searchHandler.currentSelected];
    final refreshableItems = selected
        .map((item) => (item: item, booru: _sourceBooruForItem(item)))
        .where((record) => record.booru != null && getHandler(record.booru!).hasLoadItemSupport)
        .toList();

    if (refreshableItems.isEmpty) {
      _showNoRefreshableItems(context);
      return;
    }

    final delayMs = await _askRefreshDelay(context);
    if (delayMs == null) {
      return;
    }

    updating.value = true;
    FlashElements.showSnackbar(
      context: context,
      title: Text(context.loc.settings.downloads.updatingData, style: const TextStyle(fontSize: 20)),
      overrideLeadingIconWidget: const SizedBox(
        width: 50,
        height: 50,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      ),
      sideColor: Colors.yellow,
    );

    try {
      for (int i = 0; i < refreshableItems.length; i++) {
        final record = refreshableItems[i];
        final handler = getHandler(record.booru!);

        try {
          final result = await handler.loadItem(
            item: record.item,
            withCapcthaCheck: true,
          );
          if (!result.failed && result.item != null) {
            await settingsHandler.dbHandler.updateBooruItem(
              result.item!,
              BooruUpdateMode.urlUpdate,
            );
          }
        } catch (_) {}

        if (delayMs > 0 && i < refreshableItems.length - 1) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    } finally {
      searchHandler.currentFetched.assignAll([...searchHandler.currentFetched]);
      searchHandler.currentTab.selected.clear();
      updating.value = false;
    }
  }

  ShareActionController shareActionController(BuildContext context) {
    return ShareActionController(
      currentAction: settingsHandler.shareAction,
      showTagOptions: false,
      showHydrusOption: settingsHandler.hasHydrus && searchHandler.currentBooru.type?.isHydrus != true,
      onRememberAction: (action) async {
        settingsHandler.shareAction = _shareActionWithoutTags(action);
        await settingsHandler.saveSettings(restate: false);
      },
      postUrl: () => shareSelectedText(
        context,
        (item) => item.postURL,
        requirePostUrl: true,
      ),
      postUrlWithTags: () => shareSelectedText(
        context,
        (item) => _withTags(item.postURL, item),
        requirePostUrl: true,
      ),
      fileUrl: () => shareSelectedText(context, (item) => item.fileURL),
      fileUrlWithTags: () => shareSelectedText(context, (item) => _withTags(item.fileURL, item)),
      file: () => shareSelectedFiles(context),
      fileWithTags: () => shareSelectedFiles(context, text: _selectedTagsText()),
      hydrus: () => shareSelectedHydrus(context),
    );
  }

  ShareAction _shareActionWithoutTags(ShareAction action) {
    return switch (action) {
      ShareAction.postUrlWithTags => ShareAction.postUrl,
      ShareAction.fileUrlWithTags => ShareAction.fileUrl,
      ShareAction.fileWithTags => ShareAction.file,
      _ => action,
    };
  }

  String _withTags(String value, BooruItem item) {
    final tags = item.tagsList.join(' ');
    return tags.isEmpty ? value : '$value \n $tags';
  }

  String? _selectedTagsText() {
    final tags = searchHandler.currentSelected.expand((item) => item.tagsList).toSet().join(' ');
    return tags.isEmpty ? null : tags;
  }

  Booru? _sourceBooruForItem(BooruItem item) {
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;

    final booru = settingsHandler.booruList.firstWhereOrNull((booru) {
      if (booru.type?.isFavouritesOrDownloads == true) {
        return false;
      }

      final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
      return (itemPostHost?.isNotEmpty == true &&
              booruHost?.isNotEmpty == true &&
              (itemPostHost! == booruHost! ||
                  switch (booru.type) {
                    BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                    BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                    _ => false,
                  })) ||
          (itemFileHost?.isNotEmpty == true && booruHost?.isNotEmpty == true && itemFileHost! == booruHost!);
    });

    return booru;
  }

  Future<int?> _askRefreshDelay(BuildContext context) async {
    final controller = TextEditingController(text: '500');
    try {
      return showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(context.loc.settings.downloads.refreshDelayTitle),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.loc.settings.downloads.refreshDelayMessage,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.loc.cancel),
              ),
              TextButton(
                onPressed: () {
                  final delay = int.tryParse(controller.text.trim()) ?? 0;
                  Navigator.of(dialogContext).pop(delay < 0 ? 0 : delay);
                },
                child: Text(context.loc.ok),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  void _showNoRefreshableItems(BuildContext context) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        context.loc.settings.downloads.refreshSelectedUnavailable,
        style: const TextStyle(fontSize: 20),
      ),
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
    );
  }

  Future<void> onRetryFailedItem(
    ({Booru booru, BooruItem item}) record,
    bool isExists,
    bool isLongTap,
  ) async {
    updating.value = true;

    final booruHandler = BooruHandlerFactory().getBooruHandler([record.booru], 10).booruHandler;
    if (booruHandler.hasLoadItemSupport) {
      try {
        await booruHandler.loadItem(
          item: record.item,
          withCapcthaCheck: true,
        );
      } catch (_) {}
    }
    snatchHandler.onRetryItem(
      record,
      cooldown: settingsHandler.snatchCooldown,
      ignoreExists: isExists || isLongTap,
    );

    updating.value = false;
  }

  Future<void> onRetryAllFailed(bool isLongTap) async {
    updating.value = true;

    await snatchHandler.onRetryAll(
      cooldown: settingsHandler.snatchCooldown,
      ignoreExists: isLongTap,
    );

    updating.value = false;
  }

  Future<void> removeSnatchedStatusFromSelected() async {
    final onlySnatched = searchHandler.currentSelected.where((e) => e.isSnatched.value == true).toList();

    updating.value = true;

    for (final item in onlySnatched) {
      item.isSnatched.value = false;
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );
    }
    searchHandler.currentTab.selected.clear();

    updating.value = false;
  }

  Future<void> favouriteSelected() async {
    final onlyUnfavs = searchHandler.currentSelected.where((e) => e.isFavourite.value == false).toList();

    updating.value = true;

    await searchHandler.currentTab.updateFavForMultipleItems(
      searchHandler.currentFetched.where(onlyUnfavs.contains).toList(),
      newValue: true,
    );
    searchHandler.currentTab.selected.clear();

    updating.value = false;
  }

  Future<void> unfavouriteSelected() async {
    final onlyFavs = searchHandler.currentSelected.where((e) => e.isFavourite.value == true).toList();

    updating.value = true;

    await searchHandler.currentTab.updateFavForMultipleItems(
      searchHandler.currentFetched.where(onlyFavs.contains).toList(),
      newValue: false,
    );
    searchHandler.currentTab.selected.clear();

    updating.value = false;
  }

  void dispose() {
    scrollController.dispose();
    _handlerCache.clear();
  }
}
