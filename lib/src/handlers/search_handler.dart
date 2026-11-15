import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart' hide FirstWhereOrNullExt;
import 'package:get_it/get_it.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/data/settings/tab_page_restore_mode.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/dialogs/tab_restore_dialog.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/ordered_selection_index.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';

Uuid uuid = const Uuid();

EventChannel? volumeKeyChannel = Platform.isAndroid ? const EventChannel('com.noaisu.loliSnatcher/volume') : null;

// special strings used to separate parts of tab backup string
const String tabDivider = '|||', listDivider = '~~~';
List<List<String>> decodeBackupString(String input) {
  final List<List<String>> result = [];
  final List<String> splitInput = input.split(listDivider);
  for (final String str in splitInput) {
    final List<String> booruAndTags = str.split(tabDivider);
    result.add(booruAndTags);
  }
  return result;
}

class SearchHandler {
  SearchHandler() {
    _volumeStreamController = Platform.isAndroid ? StreamController.broadcast() : null;
    _scrollStream = StreamController.broadcast();
    _rootVolumeListener = volumeKeyChannel?.receiveBroadcastStream().listen((event) {
      _volumeStreamController?.sink.add(event);
    });
  }
  // alternative way to get instance of the controller
  // i.e. "SearchHandler.to.tabs" instead of "Get.find<SearchHandler>().tabs"
  static SearchHandler get instance => GetIt.instance<SearchHandler>();

  static SearchHandler register() {
    if (!GetIt.instance.isRegistered<SearchHandler>()) {
      GetIt.instance.registerSingleton(
        SearchHandler(),
        dispose: (searchHandler) => searchHandler.dispose(),
      );
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SearchHandler>();

  // search tabs list
  RxList<SearchTab> tabs = RxList<SearchTab>([]);
  // tab groups
  RxList<TabGroup> tabGroups = RxList<TabGroup>([]);
  // collapsed state of the "ungrouped" section in the tab manager (only
  // relevant/visible when at least one group exists)
  final RxBool ungroupedCollapsed = false.obs;
  // current tab index
  RxInt index = 0.obs;
  RxnString tabId = RxnString(null);
  SearchTab? _publishingTab;

  /// Publishes a structural change while retaining the actual active tab.
  /// Background changes leave its editor and in-flight search state intact.
  void _publishTabs(
    List<SearchTab> next, {
    List<TabGroup>? groups,
    SearchTab? selected,
    bool? collapsed,
    bool activate = true,
  }) {
    if (next.isEmpty) {
      if (tabs.isNotEmpty) return;
      if (groups != null) tabGroups.value = groups;
      if (collapsed != null) ungroupedCollapsed.value = collapsed;
      _scheduleTabsBackup();
      return;
    }
    final previous = currentTabOrNull;
    final nextGroups = groups ?? tabGroups.toList();
    final normalized = _normalizeTabsByGroup(next, nextGroups);
    final target = selected != null && normalized.contains(selected)
        ? selected
        : previous != null && normalized.contains(previous)
        ? previous
        : normalized.first;
    final targetIndex = normalized.indexOf(target);

    // Reactive listeners using currentTab/currentIndex must resolve the same
    // tab even between the separate group/list/index notifications.
    if (groups != null) tabGroups.value = nextGroups;
    if (collapsed != null) ungroupedCollapsed.value = collapsed;
    _publishingTab = target;
    try {
      tabs.value = normalized;
      index.value = targetIndex;
      tabId.value = target.id;
      if (!identical(previous, target)) {
        Tools.forceClearMemoryCache(withLive: true);
        changeTabIndex(targetIndex, switchOnly: !activate);
      }
    } finally {
      _publishingTab = null;
    }
    _scheduleTabsBackup();
  }

  TabGroup? groupById(String? id) {
    if (id == null) return null;
    return tabGroups.firstWhereOrNull((g) => g.id == id);
  }

  TabGroup? groupOf(SearchTab tab) => groupById(tab.groupId.value);

  // add new tab by the given search string
  void addTabByString(
    String searchText, {
    bool switchToNew = false,
    Booru? customBooru,
    List<Booru>? secondaryBoorus,
    TabAddMode addMode = TabAddMode.end,
    int? customPage,
  }) {
    final Booru booru = customBooru ?? currentBooru;

    // §0.1.1: prev/next inherit current tab's group; end is always ungrouped.
    String? inheritedGroupId;
    if (tabs.isNotEmpty) {
      switch (addMode) {
        case TabAddMode.prev:
        case TabAddMode.next:
          inheritedGroupId = currentTab.groupId.value;
          break;
        case TabAddMode.end:
          inheritedGroupId = null;
          break;
      }
    }

    // Add new tab depending on the add mode
    final SearchTab newTab = SearchTab(
      booru,
      secondaryBoorus,
      searchText,
      groupId: inheritedGroupId,
    );
    newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
    if (customPage != null) {
      final targetPage = newTab.apiPage(max(customPage, 1));
      newTab.booruHandler.pageNum = targetPage - 1;
      newTab.scrollPage = targetPage;
    }

    final next = tabs.toList();
    switch (addMode) {
      case TabAddMode.prev:
        next.insert(currentIndex, newTab);
        break;
      case TabAddMode.next:
        next.insert(tabs.isEmpty ? 0 : currentIndex + 1, newTab);
        break;
      case TabAddMode.end:
        // §0.1: ungrouped tab must land in the ungrouped block, before any
        // grouped tabs. With no groups, the list end is the ungrouped block end.
        if (tabGroups.isEmpty) {
          next.add(newTab);
        } else {
          int insertAt = tabs.length;
          for (int i = 0; i < tabs.length; i++) {
            if (tabs[i].groupId.value != null) {
              insertAt = i;
              break;
            }
          }
          next.insert(insertAt, newTab);
        }
        break;
    }

    _publishTabs(
      next,
      selected: switchToNew ? newTab : null,
      activate: switchToNew,
    );

    // record search query to db
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (searchText != '' && SX.searchHistoryEnabled.value) {
      settingsHandler.dbHandler.updateSearchHistory(
        searchText,
        booru.type?.name,
        booru.name,
      );
    }
  }

  // remove tab (or current if not provided) index and set new index and search text values
  void removeTabAt({int tabIndex = -1}) {
    final position = tabIndex == -1 ? currentIndex : tabIndex;
    if (position < 0 || position >= tabs.length) return;
    if (tabs.length == 1) {
      removeTabs([tabs.single]);
      return;
    }
    final active = currentTab;
    final next = tabs.toList()..removeAt(position);
    final selected = identical(active, tabs[position]) ? next[position.clamp(0, next.length - 1)] : active;
    _publishTabs(next, selected: selected);
  }

  void removeTabs(List<SearchTab> tabsToRemove) {
    if (tabs.isEmpty || tabsToRemove.isEmpty) return;
    final curTab = currentTab;
    final fallbackBooru = currentBooru;
    final removed = tabsToRemove.toSet();
    final remaining = tabs.where((tab) => !removed.contains(tab)).toList();
    if (remaining.length == tabs.length) return;

    if (remaining.isEmpty) {
      final String defaultText = fallbackBooru.defTags?.isNotEmpty == true ? fallbackBooru.defTags! : SX.defTags.value;
      final SearchTab newTab = SearchTab(fallbackBooru, null, defaultText);
      _publishTabs([newTab], selected: newTab);

      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.removedLastTab, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.loc.searchHandler.resettingSearchToDefaultTags),
          ],
        ),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.yellow,
        sideColor: Colors.yellow,
      );
    } else {
      final preservedIndex = remaining.indexWhere((tab) => tab.id == curTab.id);
      final newIndex = preservedIndex == -1 ? remaining.length - 1 : preservedIndex;
      _publishTabs(remaining, selected: remaining[newIndex]);
    }
  }

  /// Rebuilds tabs that reference a removed booru so their handlers no longer
  /// retain the deleted configuration.
  int replaceBooruInTabs(
    Booru removed,
    Booru replacement, {
    bool refreshCurrent = true,
  }) {
    var replacedCount = 0;
    var currentTabWasReplaced = false;

    for (var i = 0; i < tabs.length; i++) {
      final oldTab = tabs[i];
      final selectedWasRemoved = oldTab.selectedBooru.value.matchesIdentity(removed);
      final oldSecondary = oldTab.secondaryBoorus.value ?? const <Booru>[];
      final secondaryContainedRemoved = oldSecondary.any((booru) => booru.matchesIdentity(removed));
      if (!selectedWasRemoved && !secondaryContainedRemoved) continue;

      final newSelected = selectedWasRemoved ? replacement : oldTab.selectedBooru.value;
      final newSecondary = oldSecondary
          .where((booru) => !booru.matchesIdentity(removed) && !booru.matchesIdentity(newSelected))
          .toList(growable: false);
      tabs[i] = SearchTab(
        newSelected,
        newSecondary.isEmpty ? null : newSecondary,
        oldTab.tags,
        groupId: oldTab.groupId.value,
      )..savePageEnabled.value = oldTab.savePageEnabled.value;
      replacedCount++;
      currentTabWasReplaced |= i == currentIndex;
    }

    if (currentTabWasReplaced) {
      changeTabIndex(
        currentIndex,
        switchOnly: !refreshCurrent,
        ignoreSameIndexCheck: true,
      );
    }
    return replacedCount;
  }

  void moveTab(int fromIndex, int toIndex) {
    // value checks
    if (fromIndex == toIndex) {
      return;
    }
    if (fromIndex < 0 || fromIndex >= total || toIndex < 0 || toIndex >= total) {
      return;
    }

    final SearchTab tab = tabs[fromIndex];
    final SearchTab targetTab = tabs[toIndex];

    // Absolute moves use the final list index. Relative row/header drops use
    // assignTabToGroup instead, because removing the source shifts the target.
    if (tab.groupId.value != targetTab.groupId.value) {
      tab.groupId.value = targetTab.groupId.value;
    }

    final next = tabs.toList();
    next.removeAt(fromIndex);
    next.insert(toIndex, tab);
    _publishTabs(next);
  }

  /// Applies an order of the complete live tab set without changing selection.
  /// Stale/partial orders are rejected instead of dropping or duplicating tabs.
  bool applyTabOrder(List<SearchTab> ordered) {
    final current = tabs.toSet();
    if (ordered.length != tabs.length || ordered.toSet().length != current.length || !ordered.every(current.contains)) {
      return false;
    }
    _publishTabs(ordered.toList());
    return true;
  }

  // ---------------------------------------------------------------------------
  // Tab groups: CRUD + invariant maintenance (§2)
  // ---------------------------------------------------------------------------

  TabGroup createGroup({
    required String name,
    Color? color,
  }) {
    final group = TabGroup(
      name: name,
      color: color ?? nextDefaultGroupColor(tabGroups.length),
    );
    tabGroups.add(group);
    _scheduleTabsBackup();
    return group;
  }

  void renameGroup(String id, String newName) {
    final g = groupById(id);
    if (g == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    g.name.value = trimmed;
    _scheduleTabsBackup();
  }

  void recolorGroup(String id, Color color) {
    final g = groupById(id);
    if (g == null) return;
    g.color.value = color;
    _scheduleTabsBackup();
  }

  void toggleGroupCollapsed(String id, {bool? forcedValue}) {
    final g = groupById(id);
    if (g == null) return;
    g.collapsed.value = forcedValue ?? !g.collapsed.value;
    _scheduleTabsBackup();
  }

  void toggleUngroupedCollapsed({bool? forcedValue}) {
    ungroupedCollapsed.value = forcedValue ?? !ungroupedCollapsed.value;
    _scheduleTabsBackup();
  }

  /// Remove a group. With [deleteTabs] = false, contained tabs become ungrouped
  /// and are moved to the end of the ungrouped section (§0.1.2). With
  /// [deleteTabs] = true, contained tabs are removed via [removeTabs] (which
  /// handles the "removed last tab" reset).
  void deleteGroup(String id, {bool deleteTabs = false}) {
    final group = groupById(id);
    if (group == null) return;

    final List<SearchTab> tabsInGroup = tabs.where((t) => t.groupId.value == id).toList();

    if (deleteTabs && tabsInGroup.isNotEmpty) {
      removeTabs(tabsInGroup);
      tabGroups.removeWhere((g) => g.id == id);
    } else {
      for (final t in tabsInGroup) {
        t.groupId.value = null;
      }
      tabGroups.removeWhere((g) => g.id == id);

      _publishTabs(tabs.toList());

      if (tabsInGroup.isNotEmpty) {
        try {
          final context = NavigationHandler.instance.navContext;
          FlashElements.showSnackbar(
            title: Text(
              context.loc.tabs.groups.tabsMovedToUngrouped(count: tabsInGroup.length),
              style: const TextStyle(fontSize: 18),
            ),
            sideColor: Colors.blue,
            leadingIcon: Icons.folder_off,
            duration: const Duration(seconds: 3),
          );
        } catch (_) {
          // navContext may not be available during tests; ignore.
        }
      }
    }

    _scheduleTabsBackup();
  }

  /// Assign a single tab to [newGroupId] (or `null` for ungrouped).
  ///
  /// By default the tab lands at the end of the destination group's
  /// contiguous range (§0.1). When [targetTab] belongs to that destination,
  /// the tab is placed at its position instead. Both changes are persisted as
  /// one operation so drag/drop previews match the restored order.
  void assignTabToGroup(
    SearchTab tab,
    String? newGroupId, {
    SearchTab? targetTab,
  }) {
    if (!tabs.contains(tab)) return;
    if (tab.groupId.value == newGroupId) return;
    if (newGroupId != null && groupById(newGroupId) == null) return;

    tab.groupId.value = newGroupId;

    // Move the tab to the end of the source list before normalizing so that
    // _normalizeTabsByGroup appends it last to the destination bucket.
    final List<SearchTab> input = List<SearchTab>.from(tabs.value);
    input.remove(tab);
    input.add(tab);

    final normalizedTabs = _normalizeTabsByGroup(input, tabGroups.value);
    if (targetTab != null && targetTab != tab && targetTab.groupId.value == newGroupId) {
      final fromIndex = normalizedTabs.indexOf(tab);
      final toIndex = normalizedTabs.indexOf(targetTab);
      if (fromIndex >= 0 && toIndex >= 0 && fromIndex != toIndex) {
        normalizedTabs.removeAt(fromIndex);
        normalizedTabs.insert(toIndex, tab);
      }
    }

    _publishTabs(normalizedTabs);
  }

  /// Batched version of [assignTabToGroup] (§2.3). Mutates `tabs.value` in one
  /// shot to avoid N-fold cache clears + index recomputes.
  void assignTabsToGroup(List<SearchTab> tabsToMove, String? newGroupId) {
    if (tabsToMove.isEmpty) return;
    if (newGroupId != null && groupById(newGroupId) == null) return;

    final Set<SearchTab> requestedTabs = tabsToMove.toSet();
    final List<SearchTab> orderedTabsToMove = [
      for (final tab in tabs)
        if (requestedTabs.contains(tab)) tab,
    ];
    if (orderedTabsToMove.isEmpty) return;

    for (final t in orderedTabsToMove) {
      t.groupId.value = newGroupId;
    }

    final List<SearchTab> input = List<SearchTab>.from(tabs.value);
    input.removeWhere(requestedTabs.contains);
    input.addAll(orderedTabsToMove);

    _publishTabs(input);
  }

  /// Move a group from [fromIndex] to [toIndex] in [tabGroups] order. The
  /// contiguous block of tabs in that group moves with it (§2.4).
  void moveGroup(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || fromIndex >= tabGroups.length) return;
    if (toIndex < 0 || toIndex >= tabGroups.length) return;

    final groups = tabGroups.toList();
    final group = groups.removeAt(fromIndex);
    groups.insert(toIndex, group);
    _publishTabs(tabs.toList(), groups: groups);
  }

  SearchTab? getTabByIndex(int index) {
    if (index < 0 || index >= total) {
      return null;
    }
    return tabs[index];
  }

  int getTabIndex(SearchTab tab) {
    return tabs.indexOf(tab);
  }

  int getItemIndex(BooruItem item) {
    return currentFetched.indexOf(item);
  }

  // grid scroll controller
  AutoScrollController gridScrollController =
      AutoScrollController(); // will be overwritten on the first render because there is hasClients check
  RxDouble scrollOffset = 0.0.obs;

  /// The current page number based on scroll position (first visible item's page)
  RxInt currentScrollPage = 0.obs;

  /// Last known column count, updated by the grid builders
  int currentColumnCount = 2;

  // stream that will notify it's listeners about scroll events of the grid controller
  StreamController<ScrollNotification>? _scrollStream;
  Stream<ScrollNotification>? get scrollStream => _scrollStream?.stream;
  bool _scrollPageUpdateScheduled = false;

  void sendToScrollStream(ScrollNotification notification) {
    if (!hasCurrentTab || !gridScrollController.hasClients) return;
    _scrollStream?.sink.add(notification);

    scrollOffset.value = gridScrollController.offset;
    currentTab.scrollPosition = gridScrollController.offset;

    if (!_scrollPageUpdateScheduled) {
      _scrollPageUpdateScheduled = true;
      final tab = currentTab;
      final controller = gridScrollController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPageUpdateScheduled = false;
        if (currentTabOrNull != tab || gridScrollController != controller) return;
        _updateCurrentScrollPage();
      });
    }
  }

  void _updateCurrentScrollPage() {
    if (!hasCurrentTab) return;
    if (currentTab.pageRestored == false) return;
    if (currentFetched.isEmpty) return;
    if (!gridScrollController.hasClients) return;

    final tagMap = gridScrollController.tagMap;
    if (tagMap.isEmpty) return;

    final double viewportHeight = gridScrollController.position.viewportDimension;

    // Collect visible items with their vertical positions
    double? topRowTop;
    int highestPageOnTopRow = -1;

    for (final entry in tagMap.entries) {
      if (!entry.value.mounted) continue;
      final RenderObject? renderObj = entry.value.context.findRenderObject();
      if (renderObj is! RenderBox || !renderObj.attached || !renderObj.hasSize) continue;

      final double itemTop =
          renderObj.localToGlobal(Offset.zero).dy - gridScrollController.viewportBoundaryGetter().top;
      final double itemBottom = itemTop + renderObj.size.height;

      // Skip items outside the viewport
      if (itemBottom <= 0 || itemTop >= viewportHeight) continue;

      if (entry.key < 0 || entry.key >= currentFetched.length) continue;

      final int page = currentFetched[entry.key].fetchedPage;
      if (page <= -1) continue;

      // Identify the topmost row: items sharing roughly the same top position (within 8px tolerance for staggered)
      if (topRowTop == null || itemTop < topRowTop - 8) {
        // New topmost row found.
        topRowTop = itemTop;
        highestPageOnTopRow = page;
      } else if ((itemTop - topRowTop).abs() <= 8) {
        // Same row - pick the highest page number (new page wins)
        if (page > highestPageOnTopRow) {
          highestPageOnTopRow = page;
        }
      }
    }

    if (highestPageOnTopRow > -1 && currentScrollPage.value != highestPageOnTopRow) {
      currentTab.scrollPage = highestPageOnTopRow;
      currentScrollPage.value = highestPageOnTopRow;
    }
  }

  void refreshCurrentScrollPage({bool showIndicator = false}) {
    final tab = currentTabOrNull;
    final controller = gridScrollController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (tab == null || currentTabOrNull != tab || gridScrollController != controller) return;
      _updateCurrentScrollPage();
      if (showIndicator) currentScrollPage.trigger(currentScrollPage.value);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // search box text controller
  final TextEditingController searchTextController = TextEditingController();
  void addTagToSearch(String tag) {
    if (tag.isNotEmpty) {
      if (currentBooru.type?.isHydrus == true) {
        searchTextController.text += ', $tag';
      } else {
        searchTextController.text += ' $tag';
      }
    }
  }

  List<String> get searchTextControllerTags =>
      searchTextController.text.trim().split(' ').where((t) => t.isNotEmpty).toList();

  void removeTagFromSearch(String tag) {
    if (tag.isNotEmpty) {
      searchTextController.text = searchTextController.text
          .replaceAll(RegExp(r'(?:-|~)?\d+#(?:-|~)?' + tag.regexpEscape()), '')
          .replaceAll('-$tag', '')
          .replaceAll('~$tag', '')
          .replaceAll(tag, '');
    }
  }

  // search box focus node
  FocusNode searchBoxFocus = FocusNode();

  final GlobalKey mainDrawerKey = GlobalKey();

  // switch to tab #index
  Future<void> changeTabIndex(
    int i, {
    bool switchOnly = false,
    bool ignoreSameIndexCheck = false,
  }) async {
    // change only if new index != current index
    // final int oldIndex = currentIndex;
    int newIndex = i;

    // protection from early execution on start
    if (tabs.isEmpty) {
      return;
    }

    // protection from out of bounds
    if (newIndex > (total - 1)) {
      newIndex = total - 1;
    } else if (newIndex < 0) {
      newIndex = 0;
    }

    // change index only when it's different
    if (newIndex != currentIndex || tabId.value != tabs[newIndex].id || ignoreSameIndexCheck) {
      index.value = newIndex;
      tabId.value = tabs[newIndex].id;
      Tools.forceClearMemoryCache(withLive: true);
    }
    final tab = currentTab;
    if (_autoSearchTab != null && _autoSearchTab != tab) {
      _cancelAutoSearch();
    }

    // Sync current booru context to the settings registry for per-booru overrides
    SettingsRegistry.instance.setCurrentBooru(currentTab.selectedBooru.value.name);

    // set search text (even if index didn't change)
    searchTextController.text = currentTab.tags;

    /// Get state from (new) current tab (current page, is end of search, did stop on error)
    pageNum.value = currentBooruHandler.pageNum;
    isLastPage.value = currentBooruHandler.locked;
    errorString.value = currentBooruHandler.errorString;
    currentScrollPage.value = tab.scrollPage ?? tab.firstPage;

    if (switchOnly) {
      // only used when we need to switch tabs around, but don't trigger new search call (e.g. when removing tabs)
      return;
    }

    // reset search bool
    isLoading.value = _pageFetches.containsKey(tab) || (_autoSearchTab == tab && isRunningAutoSearch.value);

    // trigger first search OR just get old filteredFetched list
    final bool isNewSearch = tab.booruHandler.fetchedPageNumbers.isEmpty;
    // print('isNEW: $isNewSearch ${currentIndex}');
    // trigger search if there are items inside booruHandler
    if (isNewSearch) {
      await runSearch();
    }
    if (currentTabOrNull != tab) return;
    tabId.value = tab.id;
    if (tab.booruHandler.errorString.isEmpty && tab.pendingRestorePage != null) {
      unawaited(tryRestoreTabPage(tabs.indexOf(tab)));
    }

    // print('changed index from $oldIndex to $newIndex');
  }

  // recreate current tab with custom starting page number
  Future<void> changeCurrentTabPageNumber(int newPageNum) async {
    if (!hasCurrentTab) return;
    _cancelAutoSearch();
    final SearchTab newTab = SearchTab(
      currentBooru,
      currentSecondaryBoorus.value,
      currentTab.tags,
      groupId: currentTab.groupId.value,
    );
    final targetPage = max(newTab.firstPage, newPageNum);
    newTab.booruHandler.pageNum = targetPage - 1;
    newTab.scrollPage = targetPage;
    pageNum.value = targetPage - 1;
    newTab.savePageEnabled.value = tabs[currentIndex].savePageEnabled.value;
    tabs[currentIndex] = newTab;

    await changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  HasTabWithTagResult hasTabWithTag(String tag, {Booru? customBooru}) {
    tag = tag.toLowerCase().trim();
    final Booru targetBooru = customBooru ?? currentBooru;

    final onlyTagMatches = tabs.where((tab) => tab.tags.toLowerCase().trim() == tag);
    if (onlyTagMatches.isNotEmpty) {
      if (onlyTagMatches.any((tab) => tab.selectedBooru.value.matchesIdentity(targetBooru))) {
        return HasTabWithTagResult.onlyTag;
      }
      return HasTabWithTagResult.onlyTagDifferentBooru;
    }

    if (getTabsContainingTag(tag).isNotEmpty) {
      return HasTabWithTagResult.containsTag;
    }

    return HasTabWithTagResult.noTag;
  }

  List<(int, SearchTab)> getTabsWithOnlyTag(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final parts = tab.tags.toLowerCase().trim().split(' ');
      if (parts.length == 1 && parts[0] == tag && tab.selectedBooru.value.matchesIdentity(currentBooru)) {
        result.add((i, tab));
      }
    }
    return result;
  }

  List<(int, SearchTab)> getTabsWithOnlyTagDifferentBooru(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final parts = tab.tags.toLowerCase().trim().split(' ');
      if (parts.length == 1 && parts[0] == tag && !tab.selectedBooru.value.matchesIdentity(currentBooru)) {
        result.add((i, tab));
      }
    }
    return result;
  }

  List<(int, SearchTab)> getTabsContainingTag(String tag) {
    tag = tag.toLowerCase().trim();
    final result = <(int, SearchTab)>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      if (tab.tags.toLowerCase().trim().split(' ').contains(tag)) {
        result.add((i, tab));
      }
    }
    return result;
  }

  int get currentIndex {
    final publishing = _publishingTab;
    if (publishing != null) {
      final position = tabs.indexOf(publishing);
      if (position >= 0) return position;
    }
    return index.value;
  }

  String? get currentTabId => _publishingTab?.id ?? tabId.value;
  int get total => tabs.length;
  bool get hasCurrentTab =>
      _publishingTab != null || (tabs.isNotEmpty && currentIndex >= 0 && currentIndex < tabs.length);
  SearchTab? get currentTabOrNull => _publishingTab ?? (hasCurrentTab ? tabs[currentIndex] : null);
  BooruHandler? get currentBooruHandlerOrNull => currentTabOrNull?.booruHandler;
  Booru? get currentBooruOrNull => currentTabOrNull?.selectedBooru.value;
  Rxn<List<Booru>?>? get currentSecondaryBoorusOrNull => currentTabOrNull?.secondaryBoorus;
  RxList<BooruItem>? get currentSelectedOrNull => currentTabOrNull?.selected;
  RxList<BooruItem>? get currentFetchedOrNull => currentBooruHandlerOrNull?.filteredFetched;
  SearchTab get currentTab => _publishingTab ?? tabs[currentIndex];
  BooruHandler get currentBooruHandler => currentTab.booruHandler;
  Booru get currentBooru => currentTab.selectedBooru.value;
  Rxn<List<Booru>?> get currentSecondaryBoorus => currentTab.secondaryBoorus;
  RxList<BooruItem> get currentSelected => currentTab.selected;
  RxList<BooruItem> get currentFetched => currentBooruHandler.filteredFetched;
  void filterCurrentFetched() {
    if (tabs.isNotEmpty) {
      currentBooruHandler.refilterAll();
    }
  }

  void invalidateSavedPages({String? booruName}) {
    bool changed = false;
    for (final tab in tabs) {
      final affected = tab.hasPageSizeChanges(booruName: booruName);
      if (!affected || !tab.hasValidPageCoordinates) {
        continue;
      }
      tab
        ..hasValidPageCoordinates = false
        ..pageRestored = true
        ..pendingRestorePage = null
        ..scrollPage = null;
      if (_autoSearchTab == tab) _cancelAutoSearch();
      changed = true;
    }
    // Background tabs must also schedule a backup to remove their saved page.
    if (changed) tabs.value = List.of(tabs);
  }

  // runs search on current tab
  Future<void> searchAction(String text, Booru? newBooru) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // Remove extra spaces
    text = text.trim();
    final Booru targetBooru =
        newBooru ??
        (tabs.isNotEmpty
            ? currentBooru
            : (settingsHandler.booruList.isNotEmpty ? settingsHandler.booruList[0] : Booru.unknown()));

    // clear image memory cache
    Tools.forceClearMemoryCache(withLive: true);

    // set new tab data
    if (tabs.isEmpty) {
      if (settingsHandler.booruList.isNotEmpty) {
        final SearchTab newTab = SearchTab(
          settingsHandler.booruList[0],
          currentSecondaryBoorus.value,
          text,
        );
        newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
        tabs.add(newTab);
      } else {
        return;
      }
    } else {
      final SearchTab newTab = SearchTab(
        targetBooru,
        currentSecondaryBoorus.value,
        text,
        groupId: currentTab.groupId.value,
      );
      newTab.savePageEnabled.value = tabs[currentIndex].savePageEnabled.value;
      tabs[currentIndex] = newTab;
    }

    unawaited(searchReactions(text, newBooru ?? currentBooru));

    // run search
    await changeTabIndex(currentIndex, ignoreSameIndexCheck: true);

    // write to history
    if (text != '' && SX.searchHistoryEnabled.value) {
      unawaited(
        settingsHandler.dbHandler.updateSearchHistory(
          text,
          currentBooru.type?.name,
          currentBooru.name,
        ),
      );
    }
  }

  //

  final Map<SearchReaction, int> _reactionsCount = {};
  int getSearchReactionCount(SearchReaction r) => _reactionsCount[r] ?? 0;
  void incrementSearchReactionCount(SearchReaction r) => _reactionsCount[r] = (_reactionsCount[r] ?? 0) + 1;
  bool canSendSearchReaction(SearchReaction r) => getSearchReactionCount(r) < r.limit;

  Future<void> searchReactions(String text, Booru booru) async {
    final context = NavigationHandler.instance.navContext;

    // UOOOOOHHHHH
    if (text.toLowerCase().contains('loli') && canSendSearchReaction(.uoh)) {
      incrementSearchReactionCount(.uoh);
      await FlashElements.showSnackbar(
        duration: const Duration(seconds: 2),
        title: Text(
          context.loc.searchHandler.uoh,
          style: const TextStyle(fontSize: 20),
        ),
        // TODO replace with image asset to avoid system-to-system font differences
        overrideLeadingIconWidget: const Text(
          ' 😭 ',
          style: TextStyle(fontSize: 40),
        ),
        sideColor: Colors.pink,
      );
    }
  }

  //

  // add secondary boorus and run search
  void mergeAction(List<Booru>? secondaryBoorus) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final bool canAddSecondary = secondaryBoorus != null && settingsHandler.booruList.length > 1;
    final List<Booru>? secondary = canAddSecondary ? secondaryBoorus : null;

    final SearchTab newTab = SearchTab(
      currentBooru,
      secondary,
      currentTab.tags,
      groupId: currentTab.groupId.value,
    );
    newTab.savePageEnabled.value = currentTab.savePageEnabled.value;
    tabs[currentIndex] = newTab;

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  // current page number
  RxInt pageNum = (-1).obs;
  // is currently loading
  RxBool isLoading = true.obs;
  // did search detect last page (usually when response is an empty array)
  RxBool isLastPage = false.obs;
  // did search encounter an error
  RxString errorString = ''.obs;

  final Map<SearchTab, Future<bool>> _pageFetches = {};

  // Capture the tab before awaiting; requests for the same tab share one fetch.
  Future<void> runSearch() async {
    final tab = currentTabOrNull;
    if (tab == null || (_autoSearchTab == tab && isRunningAutoSearch.value)) return;
    await _fetchNextPage(tab);
  }

  Future<bool> _fetchNextPage(SearchTab tab) async {
    final pending = _pageFetches[tab];
    if (pending != null) return pending;
    if (!tabs.contains(tab) || tab.booruHandler.locked || tab.booruHandler.errorString.isNotEmpty) return false;
    final fetch = _performPageFetch(tab);
    _pageFetches[tab] = fetch;
    try {
      return await fetch;
    } finally {
      unawaited(_pageFetches.remove(tab));
      if (currentTabOrNull == tab) {
        pageNum.value = tab.booruHandler.pageNum;
        isLastPage.value = tab.booruHandler.locked;
        errorString.value = tab.booruHandler.errorString;
        isLoading.value = _autoSearchTab == tab && isRunningAutoSearch.value;
      }
    }
  }

  Future<bool> _performPageFetch(SearchTab tab) async {
    final handler = tab.booruHandler;
    handler.pageNum++;
    if (currentTabOrNull == tab) {
      isLoading.value = true;
      pageNum.value = handler.pageNum;
    }
    final requestTags = ContentPolicy.safeSearchTagsFor(tab.selectedBooru.value, tab.tags);
    try {
      await handler.search(requestTags, null);
      if (handler.errorString.isEmpty && handler.totalCount.value == 0) {
        unawaited(handler.searchCount(requestTags));
      }
    } catch (error) {
      handler.errorString = error.toString();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return handler.errorString.isEmpty;
  }

  // reset search to previous page and run again
  Future<void> retrySearch() async {
    if (!hasCurrentTab || _pageFetches.containsKey(currentTab)) return;
    final tab = currentTab;
    _cancelAutoSearch();
    currentBooruHandler.errorString = '';
    errorString.value = '';

    currentBooruHandler.locked = false;
    isLastPage.value = false;

    currentBooruHandler.pageNum--;
    pageNum--;
    await runSearch();
    if (currentTabOrNull == tab && tab.booruHandler.errorString.isEmpty && tab.pendingRestorePage != null) {
      await tryRestoreTabPage(tabs.indexOf(tab));
    }
    return;
  }

  void reset() {
    _cancelAutoSearch();
    tabs.clear();
    index.value = 0;
    pageNum.value = -1;
    isLoading.value = true;
    isLastPage.value = false;
    errorString.value = '';
  }

  // stream that will notify it's listeners when it receives a volume button event
  StreamController<String>? _volumeStreamController;
  Stream<String>? get volumeStream => _volumeStreamController?.stream;

  // listener for native volume button events
  StreamSubscription? _rootVolumeListener;

  // hack to allow global restates to force refresh of everything (mainly used when saving settings when exiting settings page)
  VoidCallback? rootRestate;
  void setRootRestate(VoidCallback? rootSetStateCallback) => rootRestate = rootSetStateCallback;

  void dispose() {
    _tabsBackupDebounceTimer?.cancel();
    _scrollStream?.close();
    _rootVolumeListener?.cancel();
    _volumeStreamController?.close();
  }

  // Backup/restore tabs stuff

  // special strings used to separate parts of tab backup string
  // tab - separates info parts about tab itself, list - separates tabs list entries
  // example of backup string: "booruName1|||tags1|||tab~~~booruName2|||tags2|||selected~~~booruName3|||tags3|||tab"

  // bool to notify the main build that tab restoratiuon is complete
  RxBool isRestored = false.obs;
  RxBool canBackup = false.obs;
  Timer? _tabsBackupDebounceTimer;
  Future<void> _tabsBackupWriteChain = Future<void>.value();

  // keeps track of the last time tabs were backupped
  DateTime lastBackupTime = DateTime.now();

  @Deprecated('Switched to new json format. Remove this after a few versions')
  Future<void> restoreTabsLegacy(String? result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<SearchTab> restoredGlobals = [];

    bool foundBrokenItem = false;
    final List<String> brokenItems = [];
    int newIndex = 0;
    if (result != null) {
      final List<List<String>> splitInput = await compute(decodeBackupString, result);
      for (final List<String> booruAndTags in splitInput) {
        // check for parsing errors
        final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
        if (isEntryValid) {
          // find booru by name and create searchtab with given tags
          Booru findBooru = settingsHandler.booruList.firstWhere(
            (booru) => booru.name == booruAndTags[0],
            orElse: Booru.unknown,
          );
          findBooru = handleFavDlsNameChange(findBooru, backupName: booruAndTags[0]);
          if (findBooru.name != null) {
            final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
            restoredGlobals.add(newTab);
          } else {
            foundBrokenItem = true;
            brokenItems.add('${booruAndTags[0]}: ${booruAndTags[1]}');
            final SearchTab newTab = SearchTab(
              settingsHandler.booruList[0],
              null,
              booruAndTags[1],
            );
            restoredGlobals.add(newTab);
          }

          // check if tab was marked as selected and set current selected index accordingly
          if (booruAndTags.length > 2 && booruAndTags[2] == 'selected') {
            // if split has third item (selected) - set as current tab
            final int index = splitInput.indexWhere((si) => si == booruAndTags);
            newIndex = index;
          }
        } else {
          foundBrokenItem = true;
          brokenItems.add(
            '${booruAndTags[0]}: ${booruAndTags.length > 1 ? booruAndTags[1] : ""}',
          );
        }
      }
    }

    isRestored.value = true;

    // set parsed tabs OR set first default tab if nothing to restore
    if (restoredGlobals.isNotEmpty) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.searchHandler.restoredTabsCount(count: restoredGlobals.length),
            ),
            if (foundBrokenItem)
            // notify user if there was unknown booru or invalid entry in the tabs
            ...[
              Text(
                context.loc.searchHandler.someRestoredTabsHadIssues,
              ),
              Text(context.loc.searchHandler.theyWereSetToDefaultOrIgnored),
              Text(context.loc.searchHandler.listOfBrokenTabs),
              Text(brokenItems.join(', ')),
            ],
          ],
        ),
        sideColor: foundBrokenItem ? Colors.yellow : Colors.green,
        leadingIcon: foundBrokenItem ? Icons.warning_amber : Icons.settings_backup_restore,
        duration: Duration(seconds: brokenItems.isEmpty ? 4 : 10),
      );

      tabs.value = restoredGlobals;
      await changeTabIndex(newIndex, switchOnly: true);
    } else {
      Booru defaultBooru = Booru.unknown();
      // Set the default booru and tags at the start
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true ? defaultBooru.defTags! : SX.defTags.value;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        tabs.add(newTab);
        await changeTabIndex(0, switchOnly: true);
      }
      searchTextController.text = defaultText;
    }
  }

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void mergeTabsLegacy(String tabStr) => mergeTabs(tabStr);

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void replaceTabsLegacy(String tabStr) => replaceTabs(tabStr);

  //

  Future<void> restoreTabsNew(String? result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<SearchTab> restoredTabs = [];

    bool foundBrokenItems = false;
    final List<TabBackup> brokenItems = [];
    int newSelectedIndex = 0;
    bool foundSelected = false;
    final List<TabBackup> tabBackups = result != null ? await compute(TabBackup.fromJsonList, result) : [];
    for (final tabBackup in tabBackups) {
      try {
        final newTab = parseTabFromBackup(tabBackup);
        if (newTab.selectedBooru.value.name != null) {
          restoredTabs.add(newTab);
        } else {
          foundBrokenItems = true;
          brokenItems.add(tabBackup);
          restoredTabs.add(
            SearchTab(
              settingsHandler.booruList[0],
              null,
              tabBackup.tags,
            ),
          );
        }

        // get index of selected tab
        // newSelectedIndex == 0 check is to ensure that the first tab with selected:true is used
        if (tabBackup.selected && !foundSelected) {
          newSelectedIndex = restoredTabs.length - 1;
          foundSelected = true;
        }
      } catch (e, s) {
        Logger.Inst().log(
          e,
          'SearchHandler',
          'restoreTabs',
          LogTypes.exception,
          s: s,
        );
      }
    }

    isRestored.value = true;

    if (restoredTabs.isNotEmpty) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.searchHandler.restoredTabsCount(count: restoredTabs.length),
            ),
            if (foundBrokenItems) ...[
              // notify user if there was unknown booru or invalid entry in the tabs
              Text(context.loc.searchHandler.someRestoredTabsHadIssues),
              Text(context.loc.searchHandler.theyWereSetToDefaultOrIgnored),
              Text(context.loc.searchHandler.listOfBrokenTabs),
              Text(
                brokenItems
                    .map(
                      (t) => '${tabBackups.indexOf(t)}${t.booru}: ${t.tags.isEmpty ? context.loc.tabs.empty : t.tags}',
                    )
                    .join(', '),
              ),
            ],
          ],
        ),
        sideColor: foundBrokenItems ? Colors.yellow : Colors.green,
        leadingIcon: foundBrokenItems ? Icons.warning_amber : Icons.settings_backup_restore,
        duration: Duration(seconds: brokenItems.isEmpty ? 4 : 10),
      );

      tabs.value = restoredTabs;
      await changeTabIndex(newSelectedIndex, switchOnly: true);
    } else {
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true ? defaultBooru.defTags! : SX.defTags.value;
      searchTextController.text = defaultText;
      if (defaultBooru.type != null) {
        final defaultTab = SearchTab(defaultBooru, null, defaultText);
        defaultTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
        tabs.add(defaultTab);
        await changeTabIndex(0, switchOnly: true);
      }
    }
    return;
  }

  String _tabMergeIdentity(SearchTab tab) {
    return jsonEncode([
      tab.selectedBooru.value.name,
      [for (final booru in tab.secondaryBoorus.value ?? const <Booru>[]) booru.name],
      tab.tags,
    ]);
  }

  _TabImportSnapshot _decodeTabsImport(String input) {
    final trimmed = input.trimLeft();
    if (trimmed.startsWith('{')) {
      final parsed = _parseEnvelope(input);
      if (parsed.envelope == null) throw FormatException(parsed.failureReason ?? 'Invalid tab backup');
      final envelope = parsed.envelope!;
      final groupsJson = (envelope['groups'] as List<dynamic>?) ?? const [];
      final tabsJson = (envelope['tabs'] as List<dynamic>?) ?? const [];
      final groups = TabGroup.fromJsonList(groupsJson);
      final backups = TabBackup.fromJsonList(jsonEncode(tabsJson));
      return _TabImportSnapshot(
        tabs: backups,
        groups: groups,
        collapsed: (envelope['uc'] as bool?) ?? false,
        hadIssues: groups.length != groupsJson.length || backups.length != tabsJson.length,
      );
    }
    if (trimmed.startsWith('[')) {
      final decoded = jsonDecode(input) as List<dynamic>;
      final backups = TabBackup.fromJsonList(input);
      return _TabImportSnapshot(tabs: backups, hadIssues: backups.length != decoded.length);
    }
    final entries = decodeBackupString(input);
    final backups = <TabBackup>[];
    for (final entry in entries) {
      if (entry.length < 2 || entry.first.isEmpty) continue;
      backups.add(TabBackup(tags: entry[1], booru: entry.first, selected: entry.length > 2 && entry[2] == 'selected'));
    }
    if (backups.isEmpty) throw const FormatException('Invalid legacy tab backup');
    return _TabImportSnapshot(tabs: backups, hadIssues: backups.length != entries.length);
  }

  SearchTab? _defaultImportedTab() {
    final settings = SettingsHandler.instance;
    final available = settings.booruList.where((booru) => booru.type != null).toList();
    if (available.isEmpty) return null;
    final booru = available.firstWhere((booru) => booru.name == SX.prefBooru.value, orElse: () => available.first);
    final tags = booru.defTags?.isNotEmpty == true ? booru.defTags! : SX.defTags.value;
    return SearchTab(booru, null, tags);
  }

  bool _sameImportedGroup(TabGroup existing, TabGroup incoming) =>
      existing.name.value == incoming.name.value && existing.color.value == incoming.color.value;

  void _importTabs(String input, {required bool replace}) {
    final _TabImportSnapshot snapshot;
    try {
      snapshot = _decodeTabsImport(input);
    } on FormatException {
      _showTabsImportResult(replace: replace, count: 0, failed: true);
      return;
    }
    final restored = <SearchTab>[];
    final identities = replace ? <String>{} : tabs.map(_tabMergeIdentity).toSet();
    SearchTab? selected;
    bool hadIssues = snapshot.hadIssues;
    for (final backup in snapshot.tabs) {
      final tab = parseTabFromBackup(backup);
      if (tab.selectedBooru.value.name == null || tab.selectedBooru.value.type == null) {
        hadIssues = true;
        continue;
      }
      if (!replace && !identities.add(_tabMergeIdentity(tab))) continue;
      restored.add(tab);
      if (selected == null && backup.selected) selected = tab;
    }
    final count = restored.length;
    if (replace) {
      final groups = snapshot.groups.toList();
      bool collapsed = snapshot.collapsed;
      if (restored.isEmpty) {
        final fallback = _defaultImportedTab();
        if (fallback == null) {
          // Nothing usable to install; preserve the current session/onboarding.
          _showTabsImportResult(replace: true, count: 0, hadIssues: true);
          return;
        }
        restored.add(fallback);
        selected = fallback;
        groups.clear();
        collapsed = false;
      }
      _publishTabs(restored, groups: groups, selected: selected ?? restored.first, collapsed: collapsed);
    } else {
      final groups = tabGroups.toList();
      final byId = {for (final group in groups) group.id: group};
      final importedIds = snapshot.groups.map((group) => group.id).toSet();
      final populatedIds = snapshot.tabs.map((tab) => tab.groupId).whereType<String>().toSet();
      final retainedIds = restored.map((tab) => tab.groupId.value).whereType<String>().toSet();
      final remapped = <String, String>{};
      for (final group in snapshot.groups) {
        // Don't create empty groups as a side effect of tab deduplication.
        if (populatedIds.contains(group.id) && !retainedIds.contains(group.id)) continue;
        final existing = byId[group.id];
        if (existing != null && _sameImportedGroup(existing, group)) {
          remapped[group.id] = existing.id;
          continue;
        }
        String id = group.id;
        if (existing != null) {
          // A stable remap permits later imports to add tabs to the same
          // imported group without overwriting a different local group.
          id = uuid.v5(Namespace.url.value, jsonEncode(['LoliSnatcher tab group', group.toJson()..remove('cl')]));
          while (importedIds.contains(id) || (byId[id] != null && !_sameImportedGroup(byId[id]!, group))) {
            id = uuid.v4();
          }
        }
        remapped[group.id] = id;
        if (byId.containsKey(id)) continue;
        final imported = TabGroup(
          id: id,
          name: group.name.value,
          color: group.color.value,
          collapsed: group.collapsed.value,
        );
        byId[id] = imported;
        groups.add(imported);
      }
      for (final tab in restored) {
        final sourceId = tab.groupId.value;
        tab.groupId.value = sourceId != null && importedIds.contains(sourceId) ? remapped[sourceId] : null;
      }
      if (restored.isNotEmpty || groups.length != tabGroups.length) {
        _publishTabs([...tabs, ...restored], groups: groups);
      }
    }
    _showTabsImportResult(replace: replace, count: count, hadIssues: hadIssues);
  }

  void _showTabsImportResult({required bool replace, required int count, bool failed = false, bool hadIssues = false}) {
    final context = NavigationHandler.instance.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(replace ? context.loc.searchHandler.tabsReplaced : context.loc.searchHandler.tabsMerged),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed
                ? context.loc.tabs.groups.backupImportFailed
                : replace
                ? context.loc.searchHandler.receivedTabsCount(count: count)
                : context.loc.searchHandler.addedTabsCount(count: count),
          ),
          if (!failed && hadIssues) Text(context.loc.searchHandler.someRestoredTabsHadIssues),
        ],
      ),
      sideColor: failed || hadIssues ? Colors.orange : Colors.green,
      leadingIcon: failed || hadIssues ? Icons.warning_amber : Icons.settings_backup_restore,
    );
  }

  void mergeTabsNew(String tabStr) => mergeTabs(tabStr);

  void replaceTabsNew(String tabStr) => replaceTabs(tabStr);

  // ---------------------------------------------------------------------------
  // V2 envelope (groups)
  // ---------------------------------------------------------------------------

  ({Map<String, dynamic>? envelope, String? failureReason}) _parseEnvelope(
    String input,
  ) {
    Map<String, dynamic> decoded;
    try {
      final dyn = jsonDecode(input);
      if (dyn is! Map<String, dynamic>) {
        return (envelope: null, failureReason: 'not-object');
      }
      decoded = dyn;
    } catch (_) {
      return (envelope: null, failureReason: 'parse-error');
    }
    final v = decoded['v'];
    if (v != 2) {
      return (envelope: null, failureReason: 'unsupported-version');
    }
    if ((decoded['groups'] != null && decoded['groups'] is! List) ||
        (decoded['tabs'] != null && decoded['tabs'] is! List) ||
        (decoded['uc'] != null && decoded['uc'] is! bool)) {
      return (envelope: null, failureReason: 'malformed-shape');
    }
    return (envelope: decoded, failureReason: null);
  }

  // Re-orders a list of tabs to satisfy the contiguous-block invariant
  // (§0.1): [ungrouped] + [group_0 tabs] + [group_1 tabs] + …
  List<SearchTab> _normalizeTabsByGroup(
    List<SearchTab> input,
    List<TabGroup> groups,
  ) {
    final ungrouped = <SearchTab>[];
    final byGroup = <String, List<SearchTab>>{
      for (final g in groups) g.id: <SearchTab>[],
    };
    for (final t in input) {
      final gid = t.groupId.value;
      if (gid != null && byGroup.containsKey(gid)) {
        byGroup[gid]!.add(t);
      } else {
        // dangling group ids are dropped to ungrouped
        if (gid != null) t.groupId.value = null;
        ungrouped.add(t);
      }
    }
    return [
      ...ungrouped,
      for (final g in groups) ...byGroup[g.id]!,
    ];
  }

  Future<void> restoreTabsV2(String result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final parsed = _parseEnvelope(result);
    if (parsed.envelope == null) {
      isRestored.value = true;
      // Don't clobber current tabs on unrecognized envelope. If current tabs
      // are also empty, fall back to a single default tab.
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Text(
          parsed.failureReason == 'unsupported-version'
              ? context.loc.tabs.groups.newerVersionBackup
              : context.loc.tabs.groups.malformedBackup,
        ),
        sideColor: Colors.orange,
        leadingIcon: Icons.warning_amber,
        duration: const Duration(seconds: 8),
      );

      if (tabs.isEmpty && settingsHandler.booruList.isNotEmpty) {
        final Booru defaultBooru = settingsHandler.booruList[0];
        final String defaultText = defaultBooru.defTags?.isNotEmpty == true
            ? defaultBooru.defTags!
            : SX.defTags.value;
        if (defaultBooru.type != null) {
          tabs.add(SearchTab(defaultBooru, null, defaultText));
          await changeTabIndex(0);
        }
        searchTextController.text = defaultText;
      }
      return;
    }

    final envelope = parsed.envelope!;
    ungroupedCollapsed.value = (envelope['uc'] as bool?) ?? false;
    final List<dynamic> groupsJson = (envelope['groups'] as List<dynamic>?) ?? const [];
    final List<dynamic> tabsJson = (envelope['tabs'] as List<dynamic>?) ?? const [];

    // groups are parsed on the main isolate (cheap)
    final List<TabGroup> restoredGroups = TabGroup.fromJsonList(groupsJson);

    // tabs are parsed on a background isolate (potentially many)
    final String tabsString = jsonEncode(tabsJson);
    final List<TabBackup> tabBackups = await compute(TabBackup.fromJsonList, tabsString);

    bool foundBrokenItems = false;
    final List<TabBackup> brokenItems = [];
    final List<SearchTab> restoredTabs = [];
    SearchTab? selectedTab;

    for (final tabBackup in tabBackups) {
      try {
        final newTab = parseTabFromBackup(tabBackup);
        if (newTab.selectedBooru.value.name != null) {
          restoredTabs.add(newTab);
        } else {
          foundBrokenItems = true;
          brokenItems.add(tabBackup);
          if (settingsHandler.booruList.isNotEmpty) {
            restoredTabs.add(
              SearchTab(
                settingsHandler.booruList[0],
                null,
                tabBackup.tags,
                groupId: tabBackup.groupId,
              ),
            );
          }
        }
        if (selectedTab == null && tabBackup.selected) {
          selectedTab = restoredTabs.isNotEmpty ? restoredTabs.last : null;
        }
      } catch (e, s) {
        Logger.Inst().log(
          e,
          'SearchHandler',
          'restoreTabsV2',
          LogTypes.exception,
          s: s,
        );
      }
    }

    isRestored.value = true;

    if (restoredTabs.isNotEmpty) {
      // §3.6: groups MUST be assigned before tabs so any reactive listener
      // resolving tab.group sees a valid group id, not a dangling one.
      tabGroups.value = restoredGroups;

      final List<SearchTab> normalized = _normalizeTabsByGroup(restoredTabs, restoredGroups);
      tabs.value = normalized;

      final int newSelectedIndex = selectedTab != null ? normalized.indexOf(selectedTab) : 0;
      await changeTabIndex(newSelectedIndex < 0 ? 0 : newSelectedIndex);

      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsRestored, style: const TextStyle(fontSize: 20)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.searchHandler.restoredTabsCount(count: restoredTabs.length),
            ),
            if (foundBrokenItems) ...[
              Text(context.loc.searchHandler.someRestoredTabsHadIssues),
              Text(context.loc.searchHandler.theyWereSetToDefaultOrIgnored),
              Text(context.loc.searchHandler.listOfBrokenTabs),
              Text(
                brokenItems
                    .map(
                      (t) => '${tabBackups.indexOf(t)}${t.booru}: ${t.tags.isEmpty ? context.loc.tabs.empty : t.tags}',
                    )
                    .join(', '),
              ),
            ],
          ],
        ),
        sideColor: foundBrokenItems ? Colors.yellow : Colors.green,
        leadingIcon: foundBrokenItems ? Icons.warning_amber : Icons.settings_backup_restore,
        duration: Duration(seconds: brokenItems.isEmpty ? 4 : 10),
      );
    } else {
      // No valid tabs in envelope — set a default tab. Don't keep the imported
      // groups around since they have no tabs.
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : SX.defTags.value;
      if (defaultBooru.type != null) {
        tabs.add(SearchTab(defaultBooru, null, defaultText));
        await changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
  }

  void mergeTabsV2(String tabStr) => mergeTabs(tabStr);

  void replaceTabsV2(String tabStr) => replaceTabs(tabStr);

  String? generateBackupJson() {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // if there are only one tab - check that its not with default booru and tags
    // if there are more than 1 tab or check return false - start backup
    final int tabIndex = currentIndex;
    final bool onlyDefaultTab =
        tabs.length == 1 &&
        tabs[0].booruHandler.booru.name == SX.prefBooru.value &&
        tabs[0].tags == SX.defTags.value &&
        (_getTabCurrentPage(tabs[0]) ?? tabs[0].firstPage) <= tabs[0].firstPage &&
        tabs[0].savePageEnabled.value == SX.defaultSavePageEnabled.value && tabGroups.isEmpty;
    if (!onlyDefaultTab && settingsHandler.booruList.isNotEmpty) {
      final List<String> dump = tabs.map((tab) {
        final String tags = tab.tags;
        final String booruName = tab.selectedBooru.value.name ?? 'unknown';
        final List<String> secondaryBoorusNames =
            tab.secondaryBoorus.value?.map((b) => b.name ?? 'unknown').toList() ?? [];
        final bool selected = tab == tabs[tabIndex];

        // Save page number only if enabled for this tab
        final int? savedPageNum = tab.savePageEnabled.value ? _getTabCurrentPage(tab) : null;

        return jsonEncode(
          TabBackup(
            tags: tags,
            booru: booruName,
            secondaryBoorus: secondaryBoorusNames,
            selected: selected,
            pageNum: savedPageNum,
            savePageEnabled: tab.savePageEnabled.value,
            groupId: tab.groupId.value,
          ).toJson(),
        );
      }).toList();

      final String tabsBody = '[${dump.join(',')}]';

      // Wrap in envelope only when groups exist; otherwise keep emitting the
      // bare array so older app versions (and external tooling) can still read
      // backups produced by this version.
      if (tabGroups.isNotEmpty) {
        final List<String> groupsDump = tabGroups.map((g) => jsonEncode(g.toJson())).toList();
        final String groupsBody = '[${groupsDump.join(',')}]';
        final String ungroupedCollapsedBody = ungroupedCollapsed.value ? ',"uc":true' : '';
        return '{"v":2,"groups":$groupsBody,"tabs":$tabsBody$ungroupedCollapsedBody}';
      }

      return tabsBody;
    } else {
      return null;
    }
  }

  /// Gets the current page for a specific tab based on its scroll position
  int? _getTabCurrentPage(SearchTab tab) {
    if (!tab.hasValidPageCoordinates || tab.hasPageSizeChanges()) return null;
    if (tab.pendingRestorePage != null) return tab.pendingRestorePage;
    if (tab == currentTabOrNull && currentScrollPage.value >= tab.firstPage) {
      return currentScrollPage.value;
    }
    return tab.scrollPage;
  }

  SearchTab parseTabFromBackup(TabBackup backup) {
    final booruList = SettingsHandler.instance.booruList;

    Booru selectedBooru = booruList.firstWhere(
      (b) => b.name == backup.booru,
      orElse: Booru.unknown,
    );
    selectedBooru = handleFavDlsNameChange(selectedBooru, backupName: backup.booru);
    final List<Booru> secondaryBoorus = backup.secondaryBoorus
        .map(
          (name) => handleFavDlsNameChange(
            booruList.firstWhere((booru) => booru.name == name, orElse: Booru.unknown),
            backupName: name,
          ),
        )
        .where((b) => b.name != null)
        .toList();

    final tab = SearchTab(
      selectedBooru,
      secondaryBoorus.isEmpty ? null : secondaryBoorus,
      backup.tags,
      groupId: backup.groupId,
    );
    tab.savePageEnabled.value = backup.savePageEnabled;
    if (backup.savePageEnabled && backup.pageNum != null && backup.pageNum! >= tab.firstPage) {
      tab.scrollPage = backup.pageNum;
      if (backup.pageNum! > tab.firstPage && selectedBooru.name != null) {
        tab.pendingRestorePage = backup.pageNum;
        tab.pageRestored = false;
      }
    }
    return tab;
  }

  Booru handleFavDlsNameChange(Booru booru, {String? backupName}) {
    if (booru.name != null || backupName == null) {
      return booru;
    }

    final sources = SettingsHandler.instance.booruList.where((booru) => booru.type?.isFavouritesOrDownloads == true);
    if (sources.isEmpty) return booru;
    // Only a known old localized name can resolve to the corresponding local
    // source. An unrelated removed server must never silently become favourites.
    for (final l in AppLocale.values) {
      final favourite = backupName == l.translations['favourites'];
      final downloads = backupName == l.translations['downloads'];
      if (!favourite && !downloads) continue;
      final match = sources.firstWhereOrNull(
        (booru) => (favourite && booru.type?.isFavourites == true) || (downloads && booru.type?.isDownloads == true),
      );
      if (match != null) return match;
    }
    return booru;
  }

  Future<void> restoreTabs() async {
    // TODO restoring database from the backup may have corrupted tab data when there are a lot of tabs?
    final settingsHandler = SettingsHandler.instance;
    try {
      final String? result = await settingsHandler.dbHandler.getTabRestore();
      if (result == null) {
        await restoreTabsNew(null);
      } else {
        final String trimmed = result.trimLeft();
        if (trimmed.startsWith('{')) {
          await restoreTabsV2(result);
        } else if (trimmed.startsWith('[')) {
          await restoreTabsNew(result);
        } else {
          // ignore: deprecated_member_use_from_same_package
          await restoreTabsLegacy(result);
        }
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Error restoring tabs: $e',
        'SearchHandler',
        'restoreTabs',
        LogTypes.exception,
        s: s,
      );
      // await settingsHandler.dbHandler.clearTabRestore();
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true ? defaultBooru.defTags! : SX.defTags.value;
      searchTextController.text = defaultText;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
        tabs.clear();
        tabs.add(newTab);
        await changeTabIndex(0, switchOnly: true);
      }
    }

    // allow backup only after restoring to avoid long operations (i.e. database fixes) delaying restore and therefore causing backup to run before tabs were restored
    canBackup.value = true;

    // Startup only waits for local tab state. Load the selected tab in the
    // background so a slow search does not keep the gallery on the init screen.
    unawaited(_loadRestoredTab());
  }

  Future<void> _loadRestoredTab() async {
    final tab = currentTabOrNull;
    if (tab == null) return;

    try {
      // Keep the normal search -> saved-page restore sequence.
      await changeTabIndex(currentIndex);
    } catch (e, s) {
      Logger.Inst().log(
        'Error loading restored tab: $e',
        'SearchHandler',
        '_loadRestoredTab',
        LogTypes.exception,
        s: s,
      );
      // A search failure must not replace successfully restored tabs.
      tab.booruHandler.errorString = e.toString();
      if (currentTabOrNull == tab) {
        errorString.value = tab.booruHandler.errorString;
        isLoading.value = false;
      }
    }
  }

  void mergeTabs(String tabStr) => _importTabs(tabStr, replace: false);

  void replaceTabs(String tabStr) => _importTabs(tabStr, replace: true);

  void _scheduleTabsBackup() {
    if (!canBackup.value) {
      return;
    }
    _tabsBackupDebounceTimer?.cancel();
    _tabsBackupDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      _tabsBackupDebounceTimer = null;
      unawaited(backupTabs());
    });
  }

  Future<void> backupTabs() {
    if (!canBackup.value) {
      return Future<void>.value();
    }

    _tabsBackupDebounceTimer?.cancel();
    _tabsBackupDebounceTimer = null;
    final String? backupString = generateBackupJson();
    final write = _tabsBackupWriteChain.then((_) async {
      final SettingsHandler settingsHandler = SettingsHandler.instance;
      if (backupString != null) {
        await settingsHandler.dbHandler.addTabRestore(backupString);
      } else {
        await settingsHandler.dbHandler.clearTabRestore();
      }
      lastBackupTime = DateTime.now();
    });
    _tabsBackupWriteChain = write.catchError((Object error, StackTrace stackTrace) {
      Logger.Inst().log(
        error,
        'SearchHandler',
        'backupTabs',
        LogTypes.exception,
        s: stackTrace,
      );
    });
    return write;
  }

  // --- Page restore logic ---

  final Set<SearchTab> _restoringTabs = {};

  /// Attempts to restore the page for the given tab index.
  /// Called when a tab is switched to for the first time after restore.
  Future<void> tryRestoreTabPage(int tabIndex) async {
    final tab = getTabByIndex(tabIndex);
    if (tab == null || currentTabOrNull != tab || tab.pageRestored || isRunningAutoSearch.value) return;
    final savedPage = tab.pendingRestorePage;
    if (savedPage == null || savedPage <= tab.firstPage) {
      tab.pageRestored = true;
      tab.pendingRestorePage = null;
      return;
    }
    if (!_restoringTabs.add(tab)) return;
    try {
      TabPageRestoreMode mode = SX.tabPageRestoreMode.valueForBooru(tab.selectedBooru.value.name);
      int delay = 200;
      final context = NavigationHandler.instance.navContext;
      if (mode.isAsk) {
        final res = await showDialog<TabRestoreDialogResult>(
          context: context,
          barrierDismissible: false,
          builder: (context) => TabRestoreDialog(pageNum: savedPage, tab: tab),
        );
        if (res == null || currentTabOrNull != tab || tab.pendingRestorePage != savedPage) return;
        if (res.rememberChoice) {
          SX.tabPageRestoreMode.state.value = res.selectedMode;
          await SettingsHandler.instance.saveSettings(restate: false);
        }
        mode = res.selectedMode;
        delay = res.delay;
      } else if (!mode.isIgnore) {
        FlashElements.showSnackbar(
          context: context,
          title: Text('${context.loc.searchHandler.restoringPage}: ${tab.displayPage(savedPage)}'),
          content: Text('${context.loc.searchHandler.pageRestoreMode} ${mode.locName}'),
        );
      }
      if (currentTabOrNull != tab || tab.pendingRestorePage != savedPage) return;
      if (mode.isIgnore) {
        tab.pendingRestorePage = null;
        tab.pageRestored = true;
        tab.scrollPage = tab.firstPage;
        currentScrollPage.value = tab.firstPage;
        refreshCurrentScrollPage();
        return;
      }
      await executePageRestore(tab, savedPage, mode, customDelay: delay);
    } finally {
      _restoringTabs.remove(tab);
    }
  }

  RxBool isRunningAutoSearch = false.obs;
  final RxnInt autoSearchTargetPage = RxnInt();
  SearchTab? _autoSearchTab;
  int _autoSearchGeneration = 0;

  bool isAutoSearchingTab(SearchTab tab) => isRunningAutoSearch.value && identical(_autoSearchTab, tab);

  void _cancelAutoSearch() {
    final tab = _autoSearchTab;
    _autoSearchGeneration++;
    _autoSearchTab = null;
    isRunningAutoSearch.value = false;
    autoSearchTargetPage.value = null;
    if (tab != null && currentTabOrNull == tab) isLoading.value = _pageFetches.containsKey(tab);
  }

  void stopAutoSearch() {
    final tab = _autoSearchTab;
    _cancelAutoSearch();
    if (tab == null) return;
    tab
      ..pendingRestorePage = null
      ..pageRestored = true;
    if (currentTabOrNull == tab) {
      tab.scrollPage = currentScrollPage.value;
      refreshCurrentScrollPage();
    }
    tabs.value = List.of(tabs);
  }

  /// Executes the page restore for a tab with the given mode.
  Future<void> executePageRestore(
    SearchTab tab,
    int targetPage,
    TabPageRestoreMode mode, {
    int? customDelay,
  }) async {
    if (currentTabOrNull != tab || targetPage < tab.firstPage || isRunningAutoSearch.value) return;
    if (mode.isFetchOnlyPage) {
      await changeCurrentTabPageNumber(targetPage);
      return;
    }
    if (!mode.isFetchMultiplePages) return;
    final generation = ++_autoSearchGeneration;
    _autoSearchTab = tab;
    autoSearchTargetPage.value = targetPage;
    isRunningAutoSearch.value = true;
    var restoredPage = tab.pendingRestorePage != null ? tab.firstPage : currentScrollPage.value;
    bool isActive() => generation == _autoSearchGeneration && isRunningAutoSearch.value && currentTabOrNull == tab;
    try {
      final alreadyVisible =
          mode.isFetchAndScroll && tab.booruHandler.filteredFetched.any((item) => item.fetchedPage == targetPage);
      // Navigating loaded content must not wait for an unrelated request or
      // require that request to succeed.
      if (!alreadyVisible) {
        final pending = _pageFetches[tab];
        if (pending != null && !await pending) return;
        while (isActive() && tab.booruHandler.pageNum < targetPage && !tab.booruHandler.locked) {
          if (!await _fetchNextPage(tab)) return;
          if (!isActive()) return;
          final extraDelay = max((customDelay ?? 200) - 200, 0);
          if (extraDelay > 0) await Future<void>.delayed(Duration(milliseconds: extraDelay));
        }
        if (tab.booruHandler.errorString.isNotEmpty) return;
      }
      if (!isActive()) return;
      if (mode.isFetchAndScroll) {
        final items = tab.booruHandler.filteredFetched;
        // If the target page is filtered out or past the end, use the nearest loaded page.
        var targetIndex = items.indexWhere((item) => item.fetchedPage >= targetPage);
        if (targetIndex < 0 && items.isNotEmpty) {
          targetIndex = items.indexWhere((item) => item.fetchedPage == items.last.fetchedPage);
        }
        if (targetIndex >= 0) {
          final visiblePage = items[targetIndex].fetchedPage;
          final controller = gridScrollController;
          await WidgetsBinding.instance.endOfFrame;
          if (!isActive() || controller != gridScrollController || !controller.hasClients) return;
          await controller.scrollToIndex(
            targetIndex,
            duration: const Duration(milliseconds: 10),
            preferPosition: AutoScrollPosition.begin,
          );
          if (!isActive() || controller != gridScrollController) return;
          restoredPage = visiblePage;
          if (visiblePage != targetPage) {
            final context = NavigationHandler.instance.navContext;
            FlashElements.showSnackbar(
              title: Text(
                context.loc.pageNavigation.showingNearbyPage(
                  requested: tab.displayPage(targetPage),
                  actual: tab.displayPage(visiblePage),
                ),
              ),
            );
          }
        } else {
          FlashElements.showSnackbar(
            title: Text(NavigationHandler.instance.navContext.loc.pageNavigation.noVisiblePosts),
          );
        }
      }
      tab.pendingRestorePage = null;
      tab.pageRestored = true;
      tab.scrollPage = restoredPage;
      currentScrollPage.value = restoredPage;
      refreshCurrentScrollPage();
    } catch (error, stack) {
      Logger.Inst().log(error, 'SearchHandler', 'executePageRestore', LogTypes.exception, s: stack);
    } finally {
      if (generation == _autoSearchGeneration) {
        _autoSearchTab = null;
        isRunningAutoSearch.value = false;
        autoSearchTargetPage.value = null;
        if (currentTabOrNull == tab) isLoading.value = _pageFetches.containsKey(tab);
      }
    }
  }
}

class _TabImportSnapshot {
  const _TabImportSnapshot({
    required this.tabs,
    this.groups = const [],
    this.collapsed = false,
    this.hadIssues = false,
  });

  final List<TabBackup> tabs;
  final List<TabGroup> groups;
  final bool collapsed;
  final bool hadIssues;
}

class SearchTab {
  SearchTab(
    Booru selectedBooru,
    List<Booru>? secondaryBoorus,
    this.tags, {
    String? groupId,
  }) {
    this.selectedBooru = selectedBooru.obs;
    this.secondaryBoorus = Rxn<List<Booru>?>(secondaryBoorus);
    this.groupId = RxnString(groupId);

    final List<Booru> tempBooruList = [];
    tempBooruList.add(selectedBooru);
    if (secondaryBoorus?.isNotEmpty == true) {
      tempBooruList.addAll(secondaryBoorus!);
    }
    _pageSizes = [for (final booru in tempBooruList) SX.limit.valueForBooru(booru.name)];
    final temp = BooruHandlerFactory().getBooruHandler(tempBooruList, null);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    firstPage = temp.startingPage + 1;
    selected.addListener(_updateSelectedIndices);
  }
  // unique id to use for booru controller
  final String id = uuid.v4();
  String tags;

  late final Rx<Booru> selectedBooru;
  late final Rxn<List<Booru>?> secondaryBoorus;
  late final BooruHandler booruHandler;
  late final int firstPage;

  // Loaded items keep the coordinates of the limits used to create this tab.
  // After settings change, only a fresh tab/search can save a page again.
  late final List<int> _pageSizes;
  bool hasValidPageCoordinates = true;

  bool hasPageSizeChanges({String? booruName}) {
    final sources = [selectedBooru.value, ...?secondaryBoorus.value];
    if (sources.length != _pageSizes.length) return true;
    for (var i = 0; i < sources.length; i++) {
      // Resolve current names so a renamed source still invalidates its tab.
      final name = sources[i].name;
      if ((booruName == null || name == booruName) && _pageSizes[i] != SX.limit.valueForBooru(name)) {
        return true;
      }
    }
    return false;
  }

  int displayPage(int apiPage) => apiPage - firstPage + 1;
  int apiPage(int displayPage) => displayPage + firstPage - 1;
  // group membership; null = ungrouped
  late final RxnString groupId;

  TabGroup? get group => SearchHandler.instance.groupOf(this);

  double scrollPosition = 0;
  int? scrollPage;
  RxList<BooruItem> selected = RxList<BooruItem>.from([]);
  final OrderedSelectionIndex<BooruItem> _selectedIndices = OrderedSelectionIndex();

  int? selectedIndexOf(BooruItem item) => _selectedIndices.indexOf(item);

  bool get hasSelectedItems => _selectedIndices.isNotEmpty;

  bool shouldSnatchOnFavourite(BooruItem item) =>
      SX.snatchOnFavourite.valueForBooru(booruHandler.sourceBooruFor(item).name);

  bool shouldFavouriteOnSnatch(BooruItem item) =>
      SX.favouriteOnSnatch.valueForBooru(booruHandler.sourceBooruFor(item).name);

  void _updateSelectedIndices() {
    _selectedIndices.update(selected);
  }

  /// Whether to save page position during tab backup.
  RxBool savePageEnabled = SX.defaultSavePageEnabled.value.obs;

  /// Whether page restore has already been applied for this tab in this session.
  bool pageRestored = true;
  int? pendingRestorePage;

  BooruItem? itemWithKey(Key? key) {
    return booruHandler.filteredFetched.firstWhereOrNull((item) => item.key == key);
  }

  Future<bool?> toggleItemFavourite(
    int itemIndex, {
    bool? forcedValue,
    bool skipSnatching = false,
  }) async {
    final BooruItem item = booruHandler.filteredFetched[itemIndex];
    if (item.isFavourite.value != null) {
      if (item.tagsList.isEmpty || item.mediaType.value.isNeedToLoadItem) {
        // try to update the item before favouriting, do nothing on fail
        if (!booruHandler.hasLoadItemSupport) {
          return item.isFavourite.value;
        }

        final res = await booruHandler.loadItem(
          item: item,
          withCapcthaCheck: true,
        );
        if (res.failed ||
            res.item == null ||
            res.item!.tagsList.isEmpty ||
            res.item!.mediaType.value.isNeedToLoadItem) {
          return item.isFavourite.value;
        }
      }

      if (forcedValue == null) {
        await ServiceHandler.vibrate();
      }

      final bool newValue = forcedValue ?? (item.isFavourite.value == true ? false : true);
      item.isFavourite.value = newValue;

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      if (!skipSnatching && shouldSnatchOnFavourite(item) && newValue && item.isSnatched.value != true) {
        await SnatchHandler.instance.queue(
          [item],
          booruHandler.booru,
          SX.snatchCooldown.value,
          false,
          sourceFor: booruHandler.sourceBooruFor,
          useSourceCooldown: true,
        );
      }
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // update filtered items list in case user has favourites filter enabled
        await Future.delayed(const Duration(milliseconds: 200));
        booruHandler.refilterAll();
      });
    }
    return item.isFavourite.value;
  }

  Future<void> updateFavForMultipleItems(
    List<BooruItem> items, {
    required bool newValue,
    bool skipSnatching = false,
  }) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (!skipSnatching && newValue) {
      await SnatchHandler.instance.queue(
        items.where((item) => item.isSnatched.value != true && shouldSnatchOnFavourite(item)).toList(),
        booruHandler.booru,
        SX.snatchCooldown.value,
        false,
        sourceFor: booruHandler.sourceBooruFor,
        useSourceCooldown: true,
      );
    }

    for (final BooruItem item in items) {
      item.isFavourite.value = newValue;
    }

    await settingsHandler.dbHandler.updateMultipleBooruItems(
      items,
      BooruUpdateMode.local,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // update filtered items list in case user has favourites filter enabled
      await Future.delayed(const Duration(milliseconds: 200));
      booruHandler.refilterAll();
    });
  }

  @override
  String toString() {
    return 'tags: $tags selectedBooru: $selectedBooru booruHandler: $booruHandler';
  }
}

class TabBackup {
  TabBackup({
    required this.tags,
    required this.booru,
    this.secondaryBoorus = const [],
    this.selected = false,
    this.pageNum,
    this.savePageEnabled = false,
    this.groupId,
  });
  final String tags;
  final String booru;
  final List<String> secondaryBoorus;
  final bool selected;
  final int? pageNum;
  final bool savePageEnabled;
  final String? groupId;
  static const _unchangedGroup = Object();

  Map<String, dynamic> toJson() {
    return {
      't': tags,
      'b': booru,
      if (secondaryBoorus.isNotEmpty) 'sb': secondaryBoorus,
      if (selected) 's': selected, // only true matters, don't include on false
      if (pageNum != null) 'p': pageNum,
      if (savePageEnabled) 'sp': savePageEnabled,
      if (groupId != null) 'g': groupId,
    };
  }

  static TabBackup? fromJson(Map<String, dynamic> json) {
    try {
      return TabBackup(
        tags: json['t'] as String,
        booru: json['b'] as String,
        secondaryBoorus: (json['sb'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
        selected: (json['s'] as bool?) ?? false,
        pageNum: json['p'] as int?,
        savePageEnabled: (json['sp'] as bool?) ?? false,
        groupId: json['g'] as String?,
      );
    } catch (_) {
      try {
        return TabBackup(
          tags: json['t'] as String,
          booru: json['b'] as String,
        );
      } catch (e, s) {
        Logger.Inst().log(
          'Invalid tab backup',
          'TabBackup',
          'fromJson',
          LogTypes.exception,
          s: s,
        );
        return null;
      }
    }
  }

  static List<TabBackup> fromJsonList(String json) {
    final jsonList = jsonDecode(json);

    if (jsonList is! List) {
      return [];
    }

    final backups = <TabBackup>[];
    for (final entry in jsonList) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      try {
        final backup = fromJson(entry);
        if (backup != null) {
          backups.add(backup);
        }
      } catch (_) {
        // Invalid entries should not prevent otherwise valid tabs from being
        // restored or merged.
      }
    }
    return backups;
  }

  TabBackup copyWith({
    String? tags,
    String? booru,
    List<String>? secondaryBoorus,
    bool? selected,
    int? pageNum,
    bool? savePageEnabled,
    Object? groupId = _unchangedGroup,
  }) {
    return TabBackup(
      tags: tags ?? this.tags,
      booru: booru ?? this.booru,
      secondaryBoorus: secondaryBoorus ?? this.secondaryBoorus,
      selected: selected ?? this.selected,
      pageNum: pageNum ?? this.pageNum,
      savePageEnabled: savePageEnabled ?? this.savePageEnabled,
      groupId: identical(groupId, _unchangedGroup) ? this.groupId : groupId as String?,
    );
  }
}

enum HasTabWithTagResult {
  onlyTag,
  onlyTagDifferentBooru,
  containsTag,
  noTag,
  ;

  bool get isOnlyTag => this == HasTabWithTagResult.onlyTag;
  bool get isOnlyTagDifferentBooru => this == HasTabWithTagResult.onlyTagDifferentBooru;
  bool get isContainsTag => this == HasTabWithTagResult.containsTag;
  bool get isNoTag => this == HasTabWithTagResult.noTag;
  bool get hasTagInAnyForm =>
      this == HasTabWithTagResult.onlyTag ||
      this == HasTabWithTagResult.onlyTagDifferentBooru ||
      this == HasTabWithTagResult.containsTag;

  String? locName(BuildContext context) => switch (this) {
    .onlyTag => context.loc.tagView.tabsWithOnlyTag,
    .onlyTagDifferentBooru => context.loc.tagView.tabsWithOnlyTagDifferentBooru,
    .containsTag => context.loc.tagView.tabsContainingTag,
    _ => null,
  };

  Color? color(BuildContext context) => switch (this) {
    onlyTag => Theme.of(context).colorScheme.onSurface,
    onlyTagDifferentBooru => Colors.yellow,
    containsTag => Colors.blue,
    _ => null,
  };
}

enum TabAddMode {
  prev,
  next,
  end,
  ;

  String locName(BuildContext context) {
    switch (this) {
      case prev:
        return context.loc.tabs.addModePrevTab;
      case next:
        return context.loc.tabs.addModeNextTab;
      case end:
        return context.loc.tabs.addModeListEnd;
    }
  }
}

enum SearchReaction {
  uoh,
  ;

  int get limit => switch (this) {
    uoh => 5,
  };
}
