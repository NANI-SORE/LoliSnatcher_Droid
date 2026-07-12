import 'package:flutter/material.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/share_action.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/gallery_share_service.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/gallery/share_action_dialog.dart';
import 'package:lolisnatcher/src/widgets/preview/image_compare_dialog.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

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
        SX.snatchCooldown.value,
        isLongTap,
      );
      if (SX.favouriteOnSnatch.value) {
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

  Future<void> selectFetchedByQuery(BuildContext context) async {
    final controller = TextEditingController();
    final query = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DismissibleConstrainedBottomSheet(
          child: SettingsBottomSheet(
            title: _SelectionSheetTitle('${context.loc.selectAll} (${context.loc.search})'),
            contentItems: [
              TagSearchBox(
                controller: controller,
                booru: searchHandler.currentBooru,
                title: context.loc.search,
                hintText: searchHandler.currentTab.tags,
                allowMultipleTags: true,
                drawTopBorder: false,
                drawBottomBorder: false,
                margin: EdgeInsets.zero,
              ),
            ],
            actionButtons: [
              const CancelButton(withIcon: true),
              ConfirmButton(
                withIcon: true,
                label: context.loc.select,
                action: () => Navigator.of(sheetContext).pop(
                  controller.text.trim(),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);

    if (query == null) {
      return;
    }

    searchHandler.currentTab.selected.assignAll(
      _itemsMatchingTagQuery(searchHandler.currentFetched, query),
    );
  }

  void showSelectedPreview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DismissibleConstrainedBottomSheet(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.66,
            minChildSize: 0.24,
            maxChildSize: 0.92,
            builder: (context, scrollController) => SettingsBottomSheet(
              title: Obx(
                () => _SelectionSheetTitle(
                  '${context.loc.tagView.preview} (${searchHandler.currentSelected.length.toFormattedString()})',
                ),
              ),
              content: Expanded(
                child: Obx(() {
                  final selected = [...searchHandler.currentSelected];
                  if (selected.isEmpty) {
                    return Center(
                      child: Text(context.loc.settings.downloads.noItemsSelected),
                    );
                  }

                  return ReorderableListView.builder(
                    scrollController: scrollController,
                    padding: const EdgeInsets.all(16),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => child,
                    itemCount: selected.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final reordered = [...searchHandler.currentSelected];
                      final item = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, item);
                      searchHandler.currentTab.selected.assignAll(reordered);
                    },
                    itemBuilder: (context, index) {
                      final item = selected[index];
                      final previewTags = _selectedPreviewTags(item);

                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(item.key),
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _showSelectedItemInfo(context, item, index),
                              child: SizedBox(
                                height: 120,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 96,
                                      height: 120,
                                      child: ThumbnailBuild(
                                        item: item,
                                        handler: searchHandler.currentBooruHandler,
                                        selectedIndex: index,
                                        onSelected: () => searchHandler.currentTab.selected.remove(item),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                '#${index + 1}',
                                                style: Theme.of(context).textTheme.titleMedium,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Expanded(
                                              child: LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final style = Theme.of(context).textTheme.bodySmall;
                                                  final fontSize = style?.fontSize ?? 12;
                                                  final lineHeight = fontSize * (style?.height ?? 1.25);
                                                  final linesThatFit = (constraints.maxHeight / lineHeight).floor();
                                                  final maxLines = linesThatFit < 1 ? 1 : linesThatFit;

                                                  return Text.rich(
                                                    TextSpan(
                                                      style: style,
                                                      children: [
                                                        for (final tag in previewTags)
                                                          TextSpan(
                                                            text: '${tag.fullString} ',
                                                            style: TextStyle(
                                                              color: tag.tagType.getColour(),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    maxLines: maxLines,
                                                    overflow: TextOverflow.ellipsis,
                                                    softWrap: true,
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.drag_handle,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSelectedItemInfo(BuildContext context, BooruItem item, int index) {
    final tags = _selectedPreviewTags(item);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _DismissibleConstrainedBottomSheet(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.66,
            minChildSize: 0.33,
            maxChildSize: 0.92,
            builder: (context, scrollController) => SettingsBottomSheet(
              title: _SelectionSheetTitle('${context.loc.item} #${index + 1}'),
              scrollController: scrollController,
              contentItems: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 220,
                      maxHeight: 260,
                    ),
                    child: AspectRatio(
                      aspectRatio: item.previewAspectRatio ?? item.sampleAspectRatio ?? item.fileAspectRatio ?? 0.75,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ThumbnailBuild(
                          item: item,
                          handler: searchHandler.currentBooruHandler,
                          selectable: false,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags)
                      Chip(
                        label: Text(tag.fullString),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: tag.tagType.getColour()?.withValues(alpha: 0.18),
                        side: BorderSide(
                          color: tag.tagType.getColour() ?? Theme.of(context).dividerColor,
                        ),
                      ),
                  ],
                ),
              ],
              actionButtons: [
                IconButton(
                  tooltip: context.loc.move,
                  onPressed: () {
                    _moveSelectedItem(item, 0);
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.vertical_align_top),
                ),
                IconButton(
                  tooltip: context.loc.move,
                  onPressed: () {
                    _moveSelectedItem(item, searchHandler.currentSelected.length - 1);
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.vertical_align_bottom),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _moveSelectedItem(BooruItem item, int targetIndex) {
    final selected = [...searchHandler.currentSelected];
    final currentIndex = selected.indexOf(item);
    if (currentIndex == -1) {
      return;
    }

    final clampedTarget = targetIndex.clamp(0, selected.length - 1);
    selected.removeAt(currentIndex);
    selected.insert(clampedTarget, item);
    searchHandler.currentTab.selected.assignAll(selected);
  }

  List<Tag> _selectedPreviewTags(BooruItem item) {
    final tagHandler = TagHandler.instance;
    final tags = item.tagsList.map((tag) {
      final cachedType = tag.tagType.isNone ? tagHandler.getTag(tag.fullString).tagType : tag.tagType;
      final type = tag.tagType.isNone && !cachedType.isNone ? cachedType : tag.tagType;

      return Tag(
        tag.fullString,
        tagType: type,
      );
    }).toList();

    tags.sort((a, b) {
      final typeComparison = _selectedPreviewTagTypeSortOrder(a.tagType).compareTo(
        _selectedPreviewTagTypeSortOrder(b.tagType),
      );
      if (typeComparison != 0) {
        return typeComparison;
      }

      return a.fullString.compareTo(b.fullString);
    });

    return tags;
  }

  Future<void> onShareSelected(BuildContext context) async {
    await onShareSelectedWithAction(context, SX.shareAction.value);
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
    searchHandler.currentTab.hideItems([...searchHandler.currentSelected]);
    searchHandler.rootRestate?.call();
  }

  void unhideItems() {
    searchHandler.currentTab.unhideItems();
    searchHandler.rootRestate?.call();
  }

  void compareSelected(BuildContext context) {
    final selected = [...searchHandler.currentSelected];
    if (selected.length != 2) {
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

  List<BooruItem> _itemsMatchingTagQuery(
    Iterable<BooruItem> items,
    String rawQuery,
  ) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return items.toList();
    }

    final groups = query.split('~').map((group) => group.trim()).where((group) => group.isNotEmpty).toList();
    if (groups.isEmpty) {
      return items.toList();
    }

    return items.where((item) {
      final searchableTags = _searchableTagsForItem(item);
      return groups.any((group) => _matchesTagQueryGroup(searchableTags, group));
    }).toList();
  }

  Set<String> _searchableTagsForItem(BooruItem item) {
    final tags = item.tagsList.map((tag) => tag.fullString.trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet();

    void addValue(String key, String? value) {
      final normalized = value?.trim().toLowerCase();
      if (normalized?.isNotEmpty == true) {
        tags.add('$key:$normalized');
      }
    }

    addValue('rating', item.rating);
    addValue('score', item.score);
    addValue('id', item.serverId);
    addValue('server_id', item.serverId);
    addValue('md5', item.md5String);
    addValue('uploader', item.uploaderName);
    addValue('uploader_id', item.uploaderId);
    addValue('ext', item.fileExt);

    return tags;
  }

  bool _matchesTagQueryGroup(Set<String> searchableTags, String group) {
    final tokens = group.split(RegExp(r'\s+')).where((token) => token.trim().isNotEmpty);

    for (final rawToken in tokens) {
      final normalizedToken = rawToken.trim().toLowerCase();
      final isNegative = normalizedToken.startsWith('-');
      final token = isNegative ? normalizedToken.substring(1) : normalizedToken;
      if (token.isEmpty) {
        continue;
      }

      final hasTag = _containsQueryTag(searchableTags, token);
      if (isNegative ? hasTag : !hasTag) {
        return false;
      }
    }

    return true;
  }

  bool _containsQueryTag(Set<String> searchableTags, String queryTag) {
    if (!queryTag.contains('*')) {
      return searchableTags.contains(queryTag);
    }

    final pattern = RegExp(
      '^${RegExp.escape(queryTag).replaceAll(r'\*', '.*')}\$',
      caseSensitive: false,
    );
    return searchableTags.any(pattern.hasMatch);
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

        searchHandler.currentTab.selected.remove(record.item);

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
      currentAction: SX.shareAction.value,
      showTagOptions: false,
      showHydrusOption: settingsHandler.hasHydrus && searchHandler.currentBooru.type?.isHydrus != true,
      onRememberAction: (action) async {
        SX.shareAction.state.value = _shareActionWithoutTags(action);
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
      cooldown: SX.snatchCooldown.value,
      ignoreExists: isExists || isLongTap,
    );

    updating.value = false;
  }

  Future<void> onRetryAllFailed(bool isLongTap) async {
    updating.value = true;

    await snatchHandler.onRetryAll(
      cooldown: SX.snatchCooldown.value,
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
      searchHandler.currentTab.selected.remove(item);
    }

    updating.value = false;
  }

  Future<void> favouriteSelected() async {
    final onlyUnfavs = searchHandler.currentSelected.where((e) => e.isFavourite.value == false).toList();

    updating.value = true;

    await _updateFavouriteForSelectedItems(
      onlyUnfavs,
      newValue: true,
    );

    updating.value = false;
  }

  Future<void> unfavouriteSelected() async {
    final onlyFavs = searchHandler.currentSelected.where((e) => e.isFavourite.value == true).toList();

    updating.value = true;

    await _updateFavouriteForSelectedItems(
      onlyFavs,
      newValue: false,
    );

    updating.value = false;
  }

  Future<void> _updateFavouriteForSelectedItems(
    List<BooruItem> items, {
    required bool newValue,
  }) async {
    if (SX.snatchOnFavourite.value && newValue) {
      snatchHandler.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        searchHandler.currentBooru,
        SX.snatchCooldown.value,
        false,
      );
    }

    for (final BooruItem item in items) {
      item.isFavourite.value = newValue;
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );
      searchHandler.currentTab.selected.remove(item);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      searchHandler.currentTab.booruHandler.refilterAll();
    });
  }

  void dispose() {
    scrollController.dispose();
    _handlerCache.clear();
  }
}

int _selectedPreviewTagTypeSortOrder(TagType type) {
  return TagType.values.indexOf(type);
}

class _DismissibleConstrainedBottomSheet extends StatelessWidget {
  const _DismissibleConstrainedBottomSheet({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxSheetWidth = width < 720 ? width : (width * 0.62).clamp(480.0, 680.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxSheetWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SelectionSheetTitle extends StatelessWidget {
  const _SelectionSheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}
