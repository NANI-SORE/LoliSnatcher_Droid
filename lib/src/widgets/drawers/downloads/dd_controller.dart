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
import 'package:lolisnatcher/src/widgets/drawers/downloads/selected_preview_sheet.dart';
import 'package:lolisnatcher/src/widgets/gallery/share_action_dialog.dart';
import 'package:lolisnatcher/src/widgets/preview/image_compare_dialog.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';

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
    final currentTab = searchHandler.currentTabOrNull;
    if (currentTab == null) return;
    final currentBooru = currentTab.selectedBooru.value;
    final currentSelected = [...currentTab.selected];
    if (!await setPermissions()) {
      if (!context.mounted) return;
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

    if (currentSelected.isNotEmpty) {
      snatchHandler.queue(
        [...currentSelected],
        currentBooru,
        SX.snatchCooldown.value,
        isLongTap,
      );
      if (SX.favouriteOnSnatch.value) {
        await currentTab.updateFavForMultipleItems(
          currentSelected,
          newValue: true,
          skipSnatching: true,
        );
      }
      await Future.delayed(const Duration(milliseconds: 100));
      currentTab.selected.removeWhere(currentSelected.contains);
    } else {
      if (!context.mounted) return;
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

  Future<bool> selectFetchedByQuery(BuildContext context) async {
    final tab = searchHandler.currentTab;
    final fetched = [...tab.booruHandler.filteredFetched];
    final selected = [...tab.selected];
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
                booru: tab.selectedBooru.value,
                title: context.loc.search,
                hintText: tab.tags,
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
      return false;
    }

    tab.selected.removeWhere(selected.contains);
    tab.selected.addAll(
      _itemsMatchingTagQuery(fetched, query).where((item) => !tab.selected.contains(item)),
    );
    return true;
  }

  void showSelectedPreview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectedPreviewSheet(
        itemsMatchingTagQuery: _itemsMatchingTagQuery,
        selectedPreviewTags: _selectedPreviewTags,
        searchSuggestions: _selectedPreviewSearchSuggestions,
        onReorderItem: _reorderSelectedPreviewItem,
        onShowItemInfo: _showSelectedItemInfo,
        onReverseSelected: reverseSelectedOrder,
        onStartSnatching: onStartSnatching,
        onShareSelected: onShareSelected,
        onShareSelectedLongPress: onShareSelectedLongPress,
      ),
    );
  }

  void _showSelectedItemInfo(BuildContext context, BooruItem item, int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectedItemPreviewSheet(
        initialItem: item,
        initialIndex: index,
        selectedPreviewTags: _selectedPreviewTags,
        onMoveItem: _moveSelectedItem,
      ),
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

  void _reorderSelectedPreviewItem({
    required List<BooruItem> visibleItems,
    required int oldIndex,
    required int newIndex,
  }) {
    final item = visibleItems[oldIndex];
    final visibleAfterRemoval = [...visibleItems]..removeAt(oldIndex);
    final selected = [...searchHandler.currentSelected]..remove(item);

    int insertIndex;
    if (visibleAfterRemoval.isEmpty) {
      insertIndex = selected.length;
    } else if (newIndex >= visibleAfterRemoval.length) {
      final previousVisibleItem = visibleAfterRemoval.last;
      insertIndex = selected.indexOf(previousVisibleItem) + 1;
    } else {
      final nextVisibleItem = visibleAfterRemoval[newIndex];
      insertIndex = selected.indexOf(nextVisibleItem);
    }

    if (insertIndex < 0) {
      insertIndex = selected.length;
    }

    selected.insert(insertIndex.clamp(0, selected.length), item);
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

  List<Tag> _selectedPreviewSearchSuggestions(String rawToken) {
    final token = rawToken.trim().toLowerCase();
    final normalizedToken = token.startsWith('-') ? token.substring(1) : token;
    final suggestionsByName = <String, Tag>{};

    for (final item in searchHandler.currentSelected) {
      for (final tag in _selectedPreviewTags(item)) {
        final name = tag.fullString.trim();
        if (name.isEmpty) {
          continue;
        }

        final key = name.toLowerCase();
        final existing = suggestionsByName[key];
        if (existing == null || (existing.tagType.isNone && !tag.tagType.isNone)) {
          suggestionsByName[key] = tag;
        }
      }
    }

    final suggestions = suggestionsByName.values.where((tag) {
      if (normalizedToken.isEmpty) {
        return true;
      }

      return tag.fullString.toLowerCase().contains(normalizedToken);
    }).toList();

    suggestions.sort((a, b) {
      if (normalizedToken.isNotEmpty) {
        final aName = a.fullString.toLowerCase();
        final bName = b.fullString.toLowerCase();
        final aStartsWith = aName.startsWith(normalizedToken);
        final bStartsWith = bName.startsWith(normalizedToken);
        if (aStartsWith != bStartsWith) {
          return aStartsWith ? -1 : 1;
        }
      }

      final typeComparison = _selectedPreviewTagTypeSortOrder(a.tagType).compareTo(
        _selectedPreviewTagTypeSortOrder(b.tagType),
      );
      if (typeComparison != 0) {
        return typeComparison;
      }

      return a.fullString.compareTo(b.fullString);
    });

    return suggestions.take(40).toList();
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

  Future<void> _shareSelectedText(
    BuildContext context,
    String Function(BooruItem item) itemText, {
    required List<BooruItem> selected,
    bool requirePostUrl = false,
  }) async {
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
      context: context,
    );
  }

  Future<void> _shareSelectedFiles(
    BuildContext context, {
    required SearchTab tab,
    required List<BooruItem> selected,
    required Map<BooruItem, Booru> sources,
    String? text,
  }) async {
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

    bool cancelled = false;
    final success = await galleryShareService.shareFiles(
      items: selected,
      booru: tab.selectedBooru.value,
      sourceBooruFor: (item) => sources[item]!,
      context: context,
      text: text,
      onCancelled: () => cancelled = true,
    );

    if (!success) {
      if (cancelled || !context.mounted) return;
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

    tab.selected.removeWhere(selected.contains);
  }

  Future<void> _shareSelectedHydrus(BuildContext context, List<BooruItem> selected) async {
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
    for (final item in selected) {
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
    final tab = searchHandler.currentTab;
    final selected = [...searchHandler.currentSelected];
    if (selected.length != 2) {
      return;
    }

    final firstBooru = _sourceBooruForTabItem(tab, selected.first);
    final secondBooru = _sourceBooruForTabItem(tab, selected.last);

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
    if (updating.value) return;
    final tab = searchHandler.currentTab;
    if (tab.selectedBooru.value.type?.isFavouritesOrDownloads != true) {
      _showNoRefreshableItems(context);
      return;
    }

    final selected = [...tab.selected];
    final refreshableItems = selected
        .map((item) => (item: item, booru: _sourceBooruForTabItem(tab, item)))
        .where((record) => getHandler(record.booru).hasLoadItemSupport)
        .toList();

    if (refreshableItems.isEmpty) {
      _showNoRefreshableItems(context);
      return;
    }

    final delayMs = await _askRefreshDelay(context);
    if (delayMs == null || !context.mounted || updating.value) {
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
        final handler = getHandler(record.booru);

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
            tab.selected.remove(record.item);
          }
        } catch (_) {}

        if (delayMs > 0 && i < refreshableItems.length - 1) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    } finally {
      tab.booruHandler.refilterAll();
      updating.value = false;
    }
  }

  ShareActionController shareActionController(BuildContext context) {
    final tab = searchHandler.currentTab;
    final selected = [...tab.selected];
    final sources = Map<BooruItem, Booru>.identity()
      ..addEntries(selected.map((item) => MapEntry(item, _sourceBooruForTabItem(tab, item))));
    return ShareActionController(
      currentAction: SX.shareAction.value,
      showTagOptions: false,
      showHydrusOption: settingsHandler.hasHydrus && tab.selectedBooru.value.type?.isHydrus != true,
      onRememberAction: (action) async {
        SX.shareAction.state.value = _shareActionWithoutTags(action);
        await settingsHandler.saveSettings(restate: false);
      },
      postUrl: () => _shareSelectedText(
        context,
        (item) => item.postURL,
        requirePostUrl: true,
        selected: selected,
      ),
      postUrlWithTags: () => _shareSelectedText(
        context,
        (item) => _withTags(item.postURL, item),
        requirePostUrl: true,
        selected: selected,
      ),
      fileUrl: () => _shareSelectedText(context, (item) => item.fileURL, selected: selected),
      fileUrlWithTags: () => _shareSelectedText(context, (item) => _withTags(item.fileURL, item), selected: selected),
      file: () => _shareSelectedFiles(context, tab: tab, selected: selected, sources: sources),
      fileWithTags: () => _shareSelectedFiles(
        context,
        tab: tab,
        selected: selected,
        sources: sources,
        text: _selectedTagsText(selected),
      ),
      hydrus: () => _shareSelectedHydrus(context, selected),
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

  String? _selectedTagsText(List<BooruItem> selected) {
    final tags = selected.expand((item) => item.tagsList).toSet().join(' ');
    return tags.isEmpty ? null : tags;
  }

  Booru _sourceBooruForTabItem(SearchTab tab, BooruItem item) {
    final source = tab.booruHandler.sourceBooruFor(item);
    return source.type?.isFavouritesOrDownloads == true ? _sourceBooruForItem(item) ?? source : source;
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
      return await showDialog<int>(
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
    if (updating.value) return;
    final currentTab = searchHandler.currentTabOrNull;
    final currentSelected = searchHandler.currentSelectedOrNull;
    if (currentTab == null || currentSelected == null) return;

    final onlySnatched = currentSelected.where((e) => e.isSnatched.value == true).toList();

    updating.value = true;

    try {
      for (final item in onlySnatched) {
        item.isSnatched.value = false;
        await settingsHandler.dbHandler.updateBooruItem(
          item,
          BooruUpdateMode.local,
        );
        currentTab.selected.remove(item);
      }
    } finally {
      updating.value = false;
    }
  }

  Future<void> favouriteSelected() async {
    if (updating.value) return;
    final currentTab = searchHandler.currentTabOrNull;
    final currentFetched = searchHandler.currentFetchedOrNull;
    final currentSelected = searchHandler.currentSelectedOrNull;
    if (currentTab == null || currentFetched == null || currentSelected == null) return;

    final onlyUnfavs = currentSelected.where((e) => e.isFavourite.value == false).toList();

    updating.value = true;

    try {
      await _updateFavouriteForSelectedItems(
        onlyUnfavs,
        tab: currentTab,
        newValue: true,
      );
    } finally {
      updating.value = false;
    }
  }

  Future<void> unfavouriteSelected() async {
    if (updating.value) return;
    final currentTab = searchHandler.currentTabOrNull;
    final currentFetched = searchHandler.currentFetchedOrNull;
    final currentSelected = searchHandler.currentSelectedOrNull;
    if (currentTab == null || currentFetched == null || currentSelected == null) return;

    final onlyFavs = currentSelected.where((e) => e.isFavourite.value == true).toList();

    updating.value = true;

    try {
      await _updateFavouriteForSelectedItems(
        onlyFavs,
        tab: currentTab,
        newValue: false,
      );
    } finally {
      updating.value = false;
    }
  }

  Future<void> _updateFavouriteForSelectedItems(
    List<BooruItem> items, {
    required SearchTab tab,
    required bool newValue,
  }) async {
    if (SX.snatchOnFavourite.value && newValue) {
      snatchHandler.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        tab.selectedBooru.value,
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
      tab.selected.remove(item);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 200));
      tab.booruHandler.refilterAll();
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
