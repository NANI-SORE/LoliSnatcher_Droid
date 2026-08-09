import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
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
    if (customPage != null) {
      newTab.booruHandler.pageNum = customPage;
    }

    int newIndex = 0;
    switch (addMode) {
      case TabAddMode.prev:
        newIndex = currentIndex;
        tabs.insert(newIndex, newTab);
        break;
      case TabAddMode.next:
        newIndex = currentIndex + 1;
        tabs.insert(newIndex, newTab);
        break;
      case TabAddMode.end:
        // §0.1: ungrouped tab must land in the ungrouped block, before any
        // grouped tabs. With no groups, the list end is the ungrouped block end.
        if (tabGroups.isEmpty) {
          tabs.add(newTab);
          newIndex = total - 1;
        } else {
          int insertAt = tabs.length;
          for (int i = 0; i < tabs.length; i++) {
            if (tabs[i].groupId.value != null) {
              insertAt = i;
              break;
            }
          }
          tabs.insert(insertAt, newTab);
          newIndex = insertAt;
        }
        break;
    }

    // record search query to db
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (searchText != '' && settingsHandler.searchHistoryEnabled) {
      settingsHandler.dbHandler.updateSearchHistory(
        searchText,
        booru.type?.name,
        booru.name,
      );
    }

    // set to last tab if requested
    if (switchToNew) {
      changeTabIndex(newIndex);
    }
  }

  // remove tab (or current if not provided) index and set new index and search text values
  void removeTabAt({int tabIndex = -1}) {
    if (tabIndex == -1) {
      tabIndex = currentIndex;
    }

    if (total > 1) {
      if (tabIndex == currentIndex) {
        // if current tab is the one being removed
        if (currentIndex == total - 1) {
          // if current tab is the last one, switch to previous one
          changeTabIndex(currentIndex - 1);
          tabs.removeAt(currentIndex + 1);
        } else {
          // if current tab is not the last one, switch to next one
          changeTabIndex(currentIndex + 1, switchOnly: true);
          tabs.removeAt(currentIndex - 1);
          changeTabIndex(currentIndex - 1);
        }
      } else {
        // if current tab is not the one being removed
        if (tabIndex < currentIndex) {
          // if tab to be removed is before current tab
          changeTabIndex(currentIndex - 1, switchOnly: true);
        }
        tabs.removeAt(tabIndex);
        changeTabIndex(currentIndex);
      }
    } else {
      // if there is only one tab, reset to default tags
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

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      final String defaultText = currentBooru.defTags?.isNotEmpty == true
          ? currentBooru.defTags!
          : settingsHandler.defTags;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      tabs[0] = newTab;
      changeTabIndex(0);
    }
  }

  void removeTabs(List<SearchTab> tabsToRemove) {
    final curTab = currentTab;
    final totalTabs = total;

    for (final tab in tabsToRemove) {
      tabs.value.remove(tab);
    }

    if (totalTabs == tabsToRemove.length) {
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

      final SettingsHandler settingsHandler = SettingsHandler.instance;
      final String defaultText = currentBooru.defTags?.isNotEmpty == true
          ? currentBooru.defTags!
          : settingsHandler.defTags;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      tabs.value[0] = newTab;
      changeTabIndex(0);
    } else {
      final newIndex = tabs.value.indexWhere((t) => t.id == curTab.id);
      changeTabIndex(newIndex == -1 ? total - 1 : newIndex);
    }
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

    // Moving across group boundaries follows the same semantics as drag/drop:
    // adopt the destination group and land at the target tab's position.
    if (tab.groupId.value != targetTab.groupId.value) {
      assignTabToGroup(
        tab,
        targetTab.groupId.value,
        targetTab: targetTab,
      );
      return;
    }

    final SearchTab? currentTabRef = tabs.isNotEmpty ? tabs[currentIndex] : null;
    tabs.removeAt(fromIndex);
    tabs.insert(toIndex, tab);

    if (currentTabRef != null) {
      final newIndex = tabs.indexOf(currentTabRef);
      changeTabIndex(newIndex < 0 ? 0 : newIndex);
    }
    _scheduleTabsBackup();
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

      final SearchTab? currentTabRef = tabs.isNotEmpty ? tabs[currentIndex] : null;
      tabs.value = _normalizeTabsByGroup(tabs.value, tabGroups.value);
      if (currentTabRef != null) {
        final newIdx = tabs.indexOf(currentTabRef);
        changeTabIndex(newIdx < 0 ? 0 : newIdx);
      }

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
    if (tab.groupId.value == newGroupId) return;
    if (newGroupId != null && groupById(newGroupId) == null) return;

    tab.groupId.value = newGroupId;

    // Move the tab to the end of the source list before normalizing so that
    // _normalizeTabsByGroup appends it last to the destination bucket.
    final List<SearchTab> input = List<SearchTab>.from(tabs.value);
    input.remove(tab);
    input.add(tab);

    final SearchTab? currentTabRef = tabs.isNotEmpty ? tabs[currentIndex] : null;
    final normalizedTabs = _normalizeTabsByGroup(input, tabGroups.value);
    if (targetTab != null && targetTab != tab && targetTab.groupId.value == newGroupId) {
      final fromIndex = normalizedTabs.indexOf(tab);
      final toIndex = normalizedTabs.indexOf(targetTab);
      if (fromIndex >= 0 && toIndex >= 0 && fromIndex != toIndex) {
        normalizedTabs.removeAt(fromIndex);
        normalizedTabs.insert(toIndex, tab);
      }
    }

    tabs.value = normalizedTabs;
    if (currentTabRef != null) {
      final newIdx = tabs.indexOf(currentTabRef);
      changeTabIndex(newIdx < 0 ? 0 : newIdx);
    }
    _scheduleTabsBackup();
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

    final SearchTab? currentTabRef = tabs.isNotEmpty ? tabs[currentIndex] : null;
    tabs.value = _normalizeTabsByGroup(input, tabGroups.value);
    if (currentTabRef != null) {
      final newIdx = tabs.indexOf(currentTabRef);
      changeTabIndex(newIdx < 0 ? 0 : newIdx);
    }
    _scheduleTabsBackup();
  }

  /// Move a group from [fromIndex] to [toIndex] in [tabGroups] order. The
  /// contiguous block of tabs in that group moves with it (§2.4).
  void moveGroup(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || fromIndex >= tabGroups.length) return;
    if (toIndex < 0 || toIndex >= tabGroups.length) return;

    final SearchTab? currentTabRef = tabs.isNotEmpty ? tabs[currentIndex] : null;

    final group = tabGroups[fromIndex];
    tabGroups.removeAt(fromIndex);
    tabGroups.insert(toIndex, group);

    tabs.value = _normalizeTabsByGroup(tabs.value, tabGroups.value);

    if (currentTabRef != null) {
      final newIdx = tabs.indexOf(currentTabRef);
      changeTabIndex(newIdx < 0 ? 0 : newIdx);
    }

    _scheduleTabsBackup();
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
  // stream that will notify it's listeners about scroll events of the grid controller
  StreamController<ScrollNotification>? _scrollStream;
  Stream<ScrollNotification>? get scrollStream => _scrollStream?.stream;

  void sendToScrollStream(ScrollNotification notification) {
    _scrollStream?.sink.add(notification);

    scrollOffset.value = gridScrollController.offset;
    currentTab.scrollPosition = gridScrollController.offset;
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
  void changeTabIndex(
    int i, {
    bool switchOnly = false,
    bool ignoreSameIndexCheck = false,
  }) {
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
    if (!ignoreSameIndexCheck && newIndex != currentIndex) {
      index.value = newIndex;
      tabId.value = tabs[newIndex].id;
      Tools.forceClearMemoryCache(withLive: true);
    }

    // set search text (even if index didn't change)
    searchTextController.text = currentTab.tags;

    /// Get state from (new) current tab (current page, is end of search, did stop on error)
    pageNum.value = currentBooruHandler.pageNum;
    isLastPage.value = currentBooruHandler.locked;
    errorString.value = currentBooruHandler.errorString;

    if (switchOnly) {
      // only used when we need to switch tabs around, but don't trigger new search call (e.g. when removing tabs)
      return;
    }

    // reset search bool
    isLoading.value = false;

    // trigger first search OR just get old filteredFetched list
    final bool isNewSearch = currentFetched.isEmpty;
    // print('isNEW: $isNewSearch ${currentIndex}');
    // trigger search if there are items inside booruHandler
    if (isNewSearch) {
      runSearch().then((_) {
        tabId.value = tabs[currentIndex].id;
      });
    } else {
      tabId.value = tabs[currentIndex].id;
    }

    // print('changed index from $oldIndex to $newIndex');
  }

  // recreate current tab with custom starting page number
  void changeCurrentTabPageNumber(int newPageNum) {
    final SearchTab newTab = SearchTab(
      currentBooru,
      currentSecondaryBoorus.value,
      currentTab.tags,
      groupId: currentTab.groupId.value,
    );
    newTab.booruHandler.pageNum = newPageNum;
    pageNum.value = newPageNum;
    tabs[currentIndex] = newTab;

    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  RxBool isRunningAutoSearch = false.obs;
  // search on the current tab until we reach given page number or there is an error
  Future<void> searchCurrentTabUntilPageNumber(
    int newPageNum, {
    int? customDelay,
  }) async {
    if (isRunningAutoSearch.value) {
      return;
    }
    isRunningAutoSearch.value = true;

    if (newPageNum > pageNum.value) {
      int tempNum = pageNum.value;
      while (isRunningAutoSearch.value && tempNum < newPageNum) {
        if (!isLoading.value) {
          await runSearch();
          tempNum++;
          // print('search num $tempNum ${pageNum.value}');

          if (errorString.value.isNotEmpty) {
            break;
          }

          await Future.delayed(Duration(milliseconds: customDelay ?? 200));
        }
      }
    }

    isRunningAutoSearch.value = false;
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

  int get currentIndex => index.value;
  String? get currentTabId => tabId.value;
  int get total => tabs.length;
  bool get hasCurrentTab => tabs.isNotEmpty && currentIndex >= 0 && currentIndex < tabs.length;
  SearchTab? get currentTabOrNull => hasCurrentTab ? tabs[currentIndex] : null;
  BooruHandler? get currentBooruHandlerOrNull => currentTabOrNull?.booruHandler;
  Booru? get currentBooruOrNull => currentTabOrNull?.selectedBooru.value;
  Rxn<List<Booru>?>? get currentSecondaryBoorusOrNull => currentTabOrNull?.secondaryBoorus;
  RxList<BooruItem>? get currentSelectedOrNull => currentTabOrNull?.selected;
  RxList<BooruItem>? get currentFetchedOrNull => currentBooruHandlerOrNull?.filteredFetched;
  SearchTab get currentTab => tabs[currentIndex];
  BooruHandler get currentBooruHandler => currentTab.booruHandler;
  Booru get currentBooru => currentTab.selectedBooru.value;
  Rxn<List<Booru>?> get currentSecondaryBoorus => currentTab.secondaryBoorus;
  RxList<BooruItem> get currentSelected => currentTab.selected;
  RxList<BooruItem> get currentFetched => currentBooruHandler.filteredFetched;
  void filterCurrentFetched() {
    if (tabs.isNotEmpty) {
      currentBooruHandler.filterFetched();
    }
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
        tabs.add(newTab);
      }
    } else {
      final SearchTab newTab = SearchTab(
        targetBooru,
        currentSecondaryBoorus.value,
        text,
        groupId: currentTab.groupId.value,
      );
      tabs[currentIndex] = newTab;
    }

    unawaited(searchReactions(text, newBooru ?? currentBooru));

    // run search
    changeTabIndex(currentIndex, ignoreSameIndexCheck: true);

    // write to history
    if (text != '' && settingsHandler.searchHistoryEnabled) {
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

  // run search on current tab
  Future<void> runSearch() async {
    final startTabId = currentTab.id;
    // do nothing if reached the end or detected an error
    if (isLastPage.value || errorString.isNotEmpty) {
      return;
    }

    // if not last page - set loading state and increment page
    if (!currentBooruHandler.locked) {
      isLoading.value = true;
      currentBooruHandler.pageNum++;
      pageNum++;
    }

    final String requestTags = ContentPolicy.safeSearchTagsFor(currentBooru, currentTab.tags);

    // fetch new items, but get results from booruHandler and not search itself
    await currentBooruHandler.search(requestTags, null);
    // print('FINISHED SEARCH: ${booruhandler.filteredFetched.length}');

    // lock new loads if handler detected last page
    // (previous filteredFetched length == current length)
    if (currentBooruHandler.locked && !isLastPage.value) {
      isLastPage.value = true;
    }

    if (currentBooruHandler.errorString.isNotEmpty) {
      errorString.value = currentBooruHandler.errorString;
    }

    // request total image count if not already loaded
    if (currentBooruHandler.totalCount.value == 0) {
      unawaited(currentBooruHandler.searchCount(requestTags));
    }

    // check to avoid requests from old tab instances resetting loading state
    if (currentTab.id == startTabId) {
      // delay every new page load
      Future.delayed(const Duration(milliseconds: 200), () {
        isLoading.value = false;
      });
    }
    return;
  }

  // reset search to previous page and run again
  Future<void> retrySearch() async {
    currentBooruHandler.errorString = '';
    errorString.value = '';

    currentBooruHandler.locked = false;
    isLastPage.value = false;

    currentBooruHandler.pageNum--;
    pageNum--;
    await runSearch();
    return;
  }

  void reset() {
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
          findBooru = handleFavDlsNameChange(findBooru);
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
      changeTabIndex(newIndex);
    } else {
      Booru defaultBooru = Booru.unknown();
      // Set the default booru and tags at the start
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        tabs.add(newTab);
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
    return;
  }

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void mergeTabsLegacy(String tabStr) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<List<String>> splitInput = decodeBackupString(tabStr);
    final List<SearchTab> restoredGlobals = [];
    for (final List<String> booruAndTags in splitInput) {
      // check for parsing errors
      final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
      if (isEntryValid) {
        // find booru by name and create searchtab with given tags
        Booru findBooru = settingsHandler.booruList.firstWhere(
          (booru) => booru.name == booruAndTags[0],
          orElse: Booru.unknown,
        );
        findBooru = handleFavDlsNameChange(findBooru);
        if (findBooru.name != null) {
          final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
          // add only if there are not already the same tab in the list and booru is available on this device
          if (tabs.indexWhere(
                (tab) => tab.selectedBooru.value.name == newTab.selectedBooru.value.name && tab.tags == newTab.tags,
              ) ==
              -1) {
            restoredGlobals.add(newTab);
          }
        }
      }
    }
    tabs.addAll(restoredGlobals);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsMerged),
      content: Text(
        context.loc.searchHandler.addedTabsCount(count: restoredGlobals.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

  @Deprecated('Switched to new json format. Remove this after a few versions')
  void replaceTabsLegacy(String tabStr) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<List<String>> splitInput = decodeBackupString(tabStr);
    final List<SearchTab> restoredGlobals = [];
    int newIndex = 0;

    // reset current tab index to avoid exceptions when tab list length is different
    changeTabIndex(0, switchOnly: true);

    for (final List<String> booruAndTags in splitInput) {
      // check for parsing errors
      final bool isEntryValid = booruAndTags.length > 1 && booruAndTags[0].isNotEmpty;
      if (isEntryValid) {
        // find booru by name and create searchtab with given tags
        Booru findBooru = settingsHandler.booruList.firstWhere(
          (booru) => booru.name == booruAndTags[0],
          orElse: Booru.unknown,
        );
        findBooru = handleFavDlsNameChange(findBooru);
        if (findBooru.name != null) {
          final SearchTab newTab = SearchTab(findBooru, null, booruAndTags[1]);
          restoredGlobals.add(newTab);

          if (booruAndTags[2] == 'selected') {
            final int index = splitInput.indexWhere((si) => si == booruAndTags);
            newIndex = index;
          }
        }
      }
    }
    tabs.value = restoredGlobals;
    changeTabIndex(newIndex);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsReplaced),
      content: Text(
        context.loc.searchHandler.receivedTabsCount(count: restoredGlobals.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

  //

  Future<void> restoreTabsNew(String? result) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    final List<SearchTab> restoredTabs = [];

    bool foundBrokenItems = false;
    final List<TabBackup> brokenItems = [];
    int newSelectedIndex = 0;
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
        if (newSelectedIndex == 0 && tabBackup.selected) {
          final int index = tabBackups.indexWhere((tb) => tb == tabBackup);
          newSelectedIndex = index;
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
      changeTabIndex(newSelectedIndex);
    } else {
      Booru defaultBooru = Booru.unknown();
      if (settingsHandler.booruList.isNotEmpty) {
        defaultBooru = settingsHandler.booruList[0];
      }
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        tabs.add(
          SearchTab(defaultBooru, null, defaultText),
        );
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
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

  void mergeTabsNew(String tabStr) {
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabStr);
    final List<SearchTab> restoredTabs = [];
    final existingTabIdentities = tabs.map(_tabMergeIdentity).toSet();
    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);

      // add only if there are not already the same tab in the list and booru is available on this device
      if (newTab.selectedBooru.value.name != null && existingTabIdentities.add(_tabMergeIdentity(newTab))) {
        restoredTabs.add(newTab);
      }
    }

    tabs.addAll(restoredTabs);
    _scheduleTabsBackup();

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsMerged),
      content: Text(
        context.loc.searchHandler.addedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

  void replaceTabsNew(String tabStr) {
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabStr);
    final List<SearchTab> restoredTabs = [];
    int newSelectedIndex = 0;

    // reset current tab index to avoid exceptions when tab list length is different
    changeTabIndex(0, switchOnly: true);

    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);
      if (newTab.selectedBooru.value.name != null) {
        restoredTabs.add(newTab);

        if (newSelectedIndex == 0 && tabBackup.selected) {
          final int index = tabBackups.indexWhere((tb) => tb == tabBackup);
          newSelectedIndex = index;
        }
      }
    }
    tabs.value = restoredTabs;
    changeTabIndex(newSelectedIndex);

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsReplaced),
      content: Text(
        context.loc.searchHandler.receivedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

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
            : settingsHandler.defTags;
        if (defaultBooru.type != null) {
          tabs.add(SearchTab(defaultBooru, null, defaultText));
          changeTabIndex(0);
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
      changeTabIndex(newSelectedIndex < 0 ? 0 : newSelectedIndex);

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
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        tabs.add(SearchTab(defaultBooru, null, defaultText));
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
  }

  void mergeTabsV2(String tabStr) {
    final parsed = _parseEnvelope(tabStr);
    if (parsed.envelope == null) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsMerged),
        content: Text(context.loc.tabs.groups.backupImportFailed),
        sideColor: Colors.orange,
        leadingIcon: Icons.warning_amber,
      );
      return;
    }
    final envelope = parsed.envelope!;
    final List<dynamic> groupsJson = (envelope['groups'] as List<dynamic>?) ?? const [];
    final String tabsString = jsonEncode((envelope['tabs'] as List<dynamic>?) ?? const []);

    final List<TabGroup> importedGroups = TabGroup.fromJsonList(groupsJson);
    final Map<String, String> remapped = {};
    final Set<String> existingIds = tabGroups.map((g) => g.id).toSet();
    for (final g in importedGroups) {
      if (existingIds.contains(g.id)) {
        String newId;
        do {
          newId = uuid.v4();
        } while (existingIds.contains(newId));
        remapped[g.id] = newId;
        existingIds.add(newId);
      } else {
        existingIds.add(g.id);
      }
    }
    // Construct the (possibly remapped) groups before appending.
    final List<TabGroup> groupsToAppend = importedGroups
        .map(
          (g) => TabGroup(
            id: remapped[g.id] ?? g.id,
            name: g.name.value,
            color: g.color.value,
            collapsed: g.collapsed.value,
          ),
        )
        .toList();

    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabsString);
    final List<SearchTab> restoredTabs = [];
    final existingTabIdentities = tabs.map(_tabMergeIdentity).toSet();
    for (final tb in tabBackups) {
      final remappedGroupId = tb.groupId == null ? null : (remapped[tb.groupId] ?? tb.groupId);
      final remappedBackup = tb.copyWith(groupId: remappedGroupId);
      final newTab = parseTabFromBackup(remappedBackup);

      // skip if same tab already present (matches mergeTabsNew behavior)
      if (newTab.selectedBooru.value.name != null && existingTabIdentities.add(_tabMergeIdentity(newTab))) {
        restoredTabs.add(newTab);
      }
    }

    tabGroups.addAll(groupsToAppend);
    tabs.addAll(restoredTabs);
    tabs.value = _normalizeTabsByGroup(tabs.value, tabGroups.value);
    _scheduleTabsBackup();

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsMerged),
      content: Text(
        context.loc.searchHandler.addedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

  void replaceTabsV2(String tabStr) {
    final parsed = _parseEnvelope(tabStr);
    if (parsed.envelope == null) {
      final context = NavigationHandler.instance.navContext;
      FlashElements.showSnackbar(
        title: Text(context.loc.searchHandler.tabsReplaced),
        content: Text(context.loc.tabs.groups.backupImportFailed),
        sideColor: Colors.orange,
        leadingIcon: Icons.warning_amber,
      );
      return;
    }
    final envelope = parsed.envelope!;
    ungroupedCollapsed.value = (envelope['uc'] as bool?) ?? false;
    final List<dynamic> groupsJson = (envelope['groups'] as List<dynamic>?) ?? const [];
    final String tabsString = jsonEncode((envelope['tabs'] as List<dynamic>?) ?? const []);

    final List<TabGroup> importedGroups = TabGroup.fromJsonList(groupsJson);
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabsString);

    final List<SearchTab> restoredTabs = [];
    SearchTab? selectedTab;

    for (final tb in tabBackups) {
      final newTab = parseTabFromBackup(tb);
      if (newTab.selectedBooru.value.name != null) {
        restoredTabs.add(newTab);
        if (selectedTab == null && tb.selected) {
          selectedTab = newTab;
        }
      }
    }

    // The rest of the app assumes at least one tab exists. A valid V2
    // envelope with no usable tabs therefore falls back to the configured
    // default instead of installing an empty list.
    if (restoredTabs.isEmpty) {
      final settingsHandler = SettingsHandler.instance;
      final defaultBooru = settingsHandler.booruList.firstOrNull;
      if (defaultBooru == null || defaultBooru.type == null) {
        return;
      }
      final defaultText = defaultBooru.defTags?.isNotEmpty == true ? defaultBooru.defTags! : settingsHandler.defTags;
      final defaultTab = SearchTab(defaultBooru, null, defaultText);
      restoredTabs.add(defaultTab);
      selectedTab = defaultTab;
      importedGroups.clear();
      ungroupedCollapsed.value = false;
      searchTextController.text = defaultText;
    }

    // reset current tab index to avoid exceptions when list length differs
    changeTabIndex(0, switchOnly: true);

    // §3.6: groups before tabs.
    tabGroups.value = importedGroups;
    final List<SearchTab> normalized = _normalizeTabsByGroup(restoredTabs, importedGroups);
    tabs.value = normalized;
    changeTabIndex(selectedTab != null ? normalized.indexOf(selectedTab) : 0);
    _scheduleTabsBackup();

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.searchHandler.tabsReplaced),
      content: Text(
        context.loc.searchHandler.receivedTabsCount(count: restoredTabs.length),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.settings_backup_restore,
    );
  }

  String? generateBackupJson() {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // if there are only one tab - check that its not with default booru and tags
    // if there are more than 1 tab or check return false - start backup
    final int tabIndex = currentIndex;
    final bool onlyDefaultTab =
        tabs.length == 1 &&
        tabs[0].booruHandler.booru.name == settingsHandler.prefBooru &&
        tabs[0].tags == settingsHandler.defTags &&
        tabGroups.isEmpty;
    if (!onlyDefaultTab && settingsHandler.booruList.isNotEmpty) {
      final List<String> dump = tabs.map((tab) {
        final String tags = tab.tags;
        final String booruName = tab.selectedBooru.value.name ?? 'unknown';
        final List<String> secondaryBoorusNames =
            tab.secondaryBoorus.value?.map((b) => b.name ?? 'unknown').toList() ?? [];
        final bool selected = tab == tabs[tabIndex];

        return jsonEncode(
          TabBackup(
            tags: tags,
            booru: booruName,
            secondaryBoorus: secondaryBoorusNames,
            selected: selected,
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

  SearchTab parseTabFromBackup(TabBackup backup) {
    final booruList = SettingsHandler.instance.booruList;

    Booru selectedBooru = booruList.firstWhere(
      (b) => b.name == backup.booru,
      orElse: Booru.unknown,
    );
    selectedBooru = handleFavDlsNameChange(selectedBooru);
    List<Booru> secondaryBoorus = backup.secondaryBoorus
        .map(
          (b) => booruList.firstWhere(
            (booru) => booru.name == b,
            orElse: Booru.unknown,
          ),
        )
        .where((b) => b.name != null)
        .toList();
    secondaryBoorus = secondaryBoorus.map(handleFavDlsNameChange).where((b) => b.name != null).toList();

    return SearchTab(
      selectedBooru,
      secondaryBoorus.isEmpty ? null : secondaryBoorus,
      backup.tags,
      groupId: backup.groupId,
    );
  }

  Booru handleFavDlsNameChange(Booru booru) {
    if (booru.name != null) {
      return booru;
    }

    final booruList = SettingsHandler.instance.booruList;
    Booru tempBooru = Booru.unknown();
    // a workaround to fix favs/dls tabs not parsing/restoring correctly due to localized names
    for (final l in AppLocale.values) {
      tempBooru = booruList.firstWhere(
        (b) => b.name == l.translations['favourites'] || b.name == l.translations['downloads'],
        orElse: Booru.unknown,
      );
      if (tempBooru.name != null) {
        break;
      }
    }
    return tempBooru;
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
      final String defaultText = defaultBooru.defTags?.isNotEmpty == true
          ? defaultBooru.defTags!
          : settingsHandler.defTags;
      if (defaultBooru.type != null) {
        final SearchTab newTab = SearchTab(defaultBooru, null, defaultText);
        tabs.clear();
        tabs.add(newTab);
        changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }

    // allow backup only after restoring to avoid long operations (i.e. database fixes) delaying restore and therefore causing backup to run before tabs were restored
    canBackup.value = true;
  }

  void mergeTabs(String tabStr) {
    final String trimmed = tabStr.trimLeft();
    if (trimmed.startsWith('{')) {
      mergeTabsV2(tabStr);
    } else if (trimmed.startsWith('[')) {
      mergeTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      mergeTabsLegacy(tabStr);
    }
  }

  void replaceTabs(String tabStr) {
    final String trimmed = tabStr.trimLeft();
    if (trimmed.startsWith('{')) {
      replaceTabsV2(tabStr);
    } else if (trimmed.startsWith('[')) {
      replaceTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      replaceTabsLegacy(tabStr);
    }
  }

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
    final temp = BooruHandlerFactory().getBooruHandler(tempBooruList, null);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    selected.addListener(_updateSelectedIndices);
  }
  // unique id to use for booru controller
  final String id = uuid.v4();
  String tags;

  late final Rx<Booru> selectedBooru;
  late final Rxn<List<Booru>?> secondaryBoorus;
  late final BooruHandler booruHandler;
  // group membership; null = ungrouped
  late final RxnString groupId;

  TabGroup? get group => SearchHandler.instance.groupOf(this);

  double scrollPosition = 0;
  RxList<BooruItem> selected = RxList<BooruItem>.from([]);
  final OrderedSelectionIndex<BooruItem> _selectedIndices = OrderedSelectionIndex();

  int? selectedIndexOf(BooruItem item) => _selectedIndices.indexOf(item);

  bool get hasSelectedItems => _selectedIndices.isNotEmpty;

  void _updateSelectedIndices() {
    _selectedIndices.update(selected);
  }

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
      if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue && item.isSnatched.value != true) {
        SnatchHandler.instance.queue(
          [item],
          booruHandler.booru,
          settingsHandler.snatchCooldown,
          false,
        );
      }
      await settingsHandler.dbHandler.updateBooruItem(
        item,
        BooruUpdateMode.local,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // update filtered items list in case user has favourites filter enabled
        await Future.delayed(const Duration(milliseconds: 200));
        booruHandler.filterFetched();
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
    if (!skipSnatching && settingsHandler.snatchOnFavourite && newValue) {
      SnatchHandler.instance.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        booruHandler.booru,
        settingsHandler.snatchCooldown,
        false,
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
      booruHandler.filterFetched();
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
    this.groupId,
  });
  final String tags;
  final String booru;
  final List<String> secondaryBoorus;
  final bool selected;
  final String? groupId;

  Map<String, dynamic> toJson() {
    return {
      't': tags,
      'b': booru,
      if (secondaryBoorus.isNotEmpty) 'sb': secondaryBoorus,
      if (selected) 's': selected, // only true matters, don't include on false
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
    String? groupId,
  }) {
    return TabBackup(
      tags: tags ?? this.tags,
      booru: booru ?? this.booru,
      secondaryBoorus: secondaryBoorus ?? this.secondaryBoorus,
      selected: selected ?? this.selected,
      groupId: groupId ?? this.groupId,
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
