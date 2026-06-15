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
  // current tab index
  RxInt index = 0.obs;
  RxnString tabId = RxnString(null);

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

    // Add new tab depending on the add mode
    final SearchTab newTab = SearchTab(
      booru,
      secondaryBoorus,
      searchText,
    );
    newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
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
        tabs.add(newTab);
        newIndex = total - 1;
        break;
    }

    // record search query to db
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    if (searchText != '' && SX.searchHistoryEnabled.value) {
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

      final String defaultText = currentBooru.defTags?.isNotEmpty == true ? currentBooru.defTags! : SX.defTags.value;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
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

      final String defaultText = currentBooru.defTags?.isNotEmpty == true ? currentBooru.defTags! : SX.defTags.value;
      searchTextController.text = defaultText;

      final SearchTab newTab = SearchTab(currentBooru, null, defaultText);
      newTab.savePageEnabled.value = SX.defaultSavePageEnabled.value;
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

    // move tab
    final SearchTab tab = tabs[fromIndex];
    tabs.removeAt(fromIndex);
    tabs.insert(toIndex, tab);

    // check how index changed and jump to correct tab
    if (fromIndex == currentIndex) {
      // if the current tab is moved, change the current tab index
      changeTabIndex(toIndex);
    } else if (toIndex == currentIndex) {
      // if moved into the place of the current tab, bump index of current tab
      changeTabIndex(toIndex + 1);
    } else if (fromIndex < currentIndex && toIndex > currentIndex) {
      // if tab was before current tab and is moved after current tab, current tab is -1
      changeTabIndex(currentIndex - 1);
    } else if (fromIndex > currentIndex && toIndex < currentIndex) {
      // if tab was after current tab and is moved before current tab, current tab is +1
      changeTabIndex(currentIndex + 1);
    }
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
    _scrollStream?.sink.add(notification);

    scrollOffset.value = gridScrollController.offset;
    currentTab.scrollPosition = gridScrollController.offset;

    if (!_scrollPageUpdateScheduled) {
      _scrollPageUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPageUpdateScheduled = false;
        _updateCurrentScrollPage();
      });
    }
  }

  void _updateCurrentScrollPage() {
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
      final RenderObject? renderObj = entry.value.context.findRenderObject();
      if (renderObj is! RenderBox || !renderObj.hasSize) continue;

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
    if (!ignoreSameIndexCheck && newIndex != currentIndex) {
      index.value = newIndex;
      tabId.value = tabs[newIndex].id;
      Tools.forceClearMemoryCache(withLive: true);
    }

    // Sync current booru context to the settings registry for per-booru overrides
    SettingsRegistry.instance.setCurrentBooru(currentTab.selectedBooru.value.name);

    // set search text (even if index didn't change)
    searchTextController.text = currentTab.tags;

    /// Get state from (new) current tab (current page, is end of search, did stop on error)
    pageNum.value = currentBooruHandler.pageNum;
    isLastPage.value = currentBooruHandler.locked;
    errorString.value = currentBooruHandler.errorString;
    currentScrollPage.value = 0;

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
      final startId = tabs[currentIndex].id;
      await runSearch();
      tabId.value = tabs[currentIndex].id;
      if (startId == currentTabId && errorString.value.isEmpty && _pendingPageRestores.containsKey(newIndex)) {
        unawaited(tryRestoreTabPage(newIndex));
      }
    } else {
      tabId.value = tabs[currentIndex].id;
      if (errorString.value.isEmpty && _pendingPageRestores.containsKey(newIndex)) {
        unawaited(tryRestoreTabPage(newIndex));
      }
    }

    // print('changed index from $oldIndex to $newIndex');
  }

  // recreate current tab with custom starting page number
  Future<void> changeCurrentTabPageNumber(int newPageNum) async {
    final SearchTab newTab = SearchTab(
      currentBooru,
      currentSecondaryBoorus.value,
      currentTab.tags,
    );
    newTab.booruHandler.pageNum = newPageNum;
    pageNum.value = newPageNum;
    newTab.savePageEnabled.value = tabs[currentIndex].savePageEnabled.value;
    tabs[currentIndex] = newTab;

    await changeTabIndex(currentIndex, ignoreSameIndexCheck: true);
  }

  HasTabWithTagResult hasTabWithTag(String tag, {Booru? customBooru}) {
    tag = tag.toLowerCase().trim();
    final Booru targetBooru = customBooru ?? currentBooru;

    final onlyTagMatches = tabs.where((tab) => tab.tags.toLowerCase().trim() == tag);
    if (onlyTagMatches.isNotEmpty) {
      if (onlyTagMatches.any((tab) => tab.selectedBooru.value == targetBooru)) {
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
      if (parts.length == 1 && parts[0] == tag && tab.selectedBooru.value == currentBooru) {
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
      if (parts.length == 1 && parts[0] == tag && tab.selectedBooru.value != currentBooru) {
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
  SearchTab get currentTab => tabs[currentIndex];
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
    for (final tab in tabs) {
      if (booruName != null && tab.selectedBooru.value.name != booruName) {
        continue;
      }
      tab
        ..pageRestored = true
        ..scrollPage = null;
    }
  }

  // runs search on current tab
  Future<void> searchAction(String text, Booru? newBooru) async {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    // Remove extra spaces
    text = text.trim();

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
        newBooru ?? currentBooru,
        currentSecondaryBoorus.value,
        text,
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

    // Notify about ratings change on gelbooru and danbooru
    if (text.contains('rating:safe')) {
      final bool isOnBooruWhereRatingsChanged =
          (booru.type?.isGelbooru == true && booru.baseURL!.contains('gelbooru.com')) ||
          (booru.type?.isDanbooru == true && booru.baseURL!.contains('danbooru.donmai.us'));
      if (isOnBooruWhereRatingsChanged) {
        await FlashElements.showSnackbar(
          duration: null,
          title: Text(
            context.loc.searchHandler.ratingsChanged,
            style: const TextStyle(fontSize: 20),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.loc.searchHandler.ratingsChangedMessage(booruType: booru.type?.name ?? ''),
                style: const TextStyle(fontSize: 16),
              ),
              const Text(''),
              Text(
                context.loc.searchHandler.appFixedRatingAutomatically,
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          leadingIcon: Icons.warning_amber,
          leadingIconColor: Colors.yellow,
          sideColor: Colors.red,
        );
      }
    }
  }

  //

  // add secondary boorus and run search
  void mergeAction(List<Booru>? secondaryBoorus) {
    final SettingsHandler settingsHandler = SettingsHandler.instance;

    final bool canAddSecondary = secondaryBoorus != null && settingsHandler.booruList.length > 1;
    final List<Booru>? secondary = canAddSecondary ? secondaryBoorus : null;

    final SearchTab newTab = SearchTab(currentBooru, secondary, currentTab.tags);
    newTab.savePageEnabled.value = tabs[currentIndex].savePageEnabled.value;
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

    // fetch new items, but get results from booruHandler and not search itself
    await currentBooruHandler.search(currentTab.tags, null);
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
      unawaited(currentBooruHandler.searchCount(currentTab.tags));
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
    isRunningAutoSearch.value = false;
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
      await changeTabIndex(newIndex);
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
        await changeTabIndex(0);
      }
      searchTextController.text = defaultText;
    }
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

        // Track page restore for this tab
        if (tabBackup.pageNum != null && tabBackup.pageNum! > -1) {
          _pendingPageRestores[restoredTabs.length - 1] = tabBackup.pageNum!;
          restoredTabs.last.pageRestored = newTab.selectedBooru.value.name == null;
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
      await changeTabIndex(newSelectedIndex);
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
        await changeTabIndex(0);
      }
    }
    return;
  }

  void mergeTabsNew(String tabStr) {
    final List<TabBackup> tabBackups = TabBackup.fromJsonList(tabStr);
    final List<SearchTab> restoredTabs = [];
    for (final tabBackup in tabBackups) {
      final newTab = parseTabFromBackup(tabBackup);

      // add only if there are not already the same tab in the list and booru is available on this device
      if (newTab.selectedBooru.value.name != null &&
          tabs.any(
            (tab) =>
                tab.selectedBooru.value.name == newTab.selectedBooru.value.name &&
                tab.secondaryBoorus.value?.map((t) => t.name).toList() ==
                    newTab.secondaryBoorus.value?.map((t) => t.name).toList() &&
                tab.tags == newTab.tags,
          )) {
        restoredTabs.add(newTab);
      }
    }

    tabs.addAll(restoredTabs);

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

  String? generateBackupJson() {
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // if there are only one tab - check that its not with default booru and tags
    // if there are more than 1 tab or check return false - start backup
    final int tabIndex = currentIndex;
    final bool onlyDefaultTab =
        tabs.length == 1 && tabs[0].booruHandler.booru.name == SX.prefBooru.value && tabs[0].tags == SX.defTags.value;
    if (!onlyDefaultTab && settingsHandler.booruList.isNotEmpty) {
      final List<String> dump = tabs.map((tab) {
        final String tags = tab.tags;
        final String booruName = tab.selectedBooru.value.name ?? 'unknown';
        final List<String> secondaryBoorusNames =
            tab.secondaryBoorus.value?.map((b) => b.name ?? 'unknown').toList() ?? [];
        final bool selected = tab == tabs[tabIndex];

        // Save page number only if enabled for this tab
        final int? savedPageNum = tab.savePageEnabled.value ? (_getTabCurrentPage(tab) ?? tab.scrollPage) : null;

        return jsonEncode(
          TabBackup(
            tags: tags,
            booru: booruName,
            secondaryBoorus: secondaryBoorusNames,
            selected: selected,
            pageNum: savedPageNum,
            savePageEnabled: tab.savePageEnabled.value,
          ).toJson(),
        );
      }).toList();

      return '[${dump.join(',')}]';
    } else {
      return null;
    }
  }

  /// Gets the current page for a specific tab based on its scroll position
  int? _getTabCurrentPage(SearchTab tab) {
    if (tab == currentTab && currentScrollPage.value > -1) {
      if (tab.pageRestored == false) {
        // keep backup page number while page restore is in progress
        return null;
      }
      return currentScrollPage.value;
    }
    if (tab.booruHandler.filteredFetched.isNotEmpty) {
      return tab.scrollPage;
    }
    return null;
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

    final tab = SearchTab(
      selectedBooru,
      secondaryBoorus.isEmpty ? null : secondaryBoorus,
      backup.tags,
    );
    tab.savePageEnabled.value = backup.savePageEnabled;
    tab.scrollPage = backup.pageNum;
    return tab;
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
      if (result == null || result.startsWith('[')) {
        await restoreTabsNew(result);
      } else {
        // ignore: deprecated_member_use_from_same_package
        await restoreTabsLegacy(result);
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
        await changeTabIndex(0);
      }
    }

    // allow backup only after restoring to avoid long operations (i.e. database fixes) delaying restore and therefore causing backup to run before tabs were restored
    canBackup.value = true;
  }

  void mergeTabs(String tabStr) {
    if (tabStr.startsWith('[')) {
      mergeTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      mergeTabsLegacy(tabStr);
    }
  }

  void replaceTabs(String tabStr) {
    if (tabStr.startsWith('[')) {
      replaceTabsNew(tabStr);
    } else {
      // ignore: deprecated_member_use_from_same_package
      replaceTabsLegacy(tabStr);
    }
  }

  Future<void> backupTabs() async {
    if (!canBackup.value) {
      return;
    }

    final String? backupString = generateBackupJson();
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    // print('backupString: $backupString');
    if (backupString != null) {
      await settingsHandler.dbHandler.addTabRestore(backupString);
    } else {
      await settingsHandler.dbHandler.clearTabRestore();
    }

    lastBackupTime = DateTime.now();
  }

  // --- Page restore logic ---

  /// Map of tab index -> saved page number for pending page restores.
  final Map<int, int> _pendingPageRestores = {};

  /// Attempts to restore the page for the given tab index.
  /// Called when a tab is switched to for the first time after restore.
  Future<void> tryRestoreTabPage(int tabIndex) async {
    final SearchTab tab = tabs[tabIndex];
    if (tab.pageRestored || isRunningAutoSearch.value) return;

    final int? savedPage = _pendingPageRestores[tabIndex];
    if (savedPage == null || savedPage <= 2) {
      tab.pageRestored = true;
      return;
    }

    final SettingsHandler settingsHandler = SettingsHandler.instance;
    TabPageRestoreMode mode = SX.tabPageRestoreMode.value;
    int delay = 200;

    if (mode.isIgnore) {
      tab.pageRestored = true;
      _pendingPageRestores.remove(tabIndex);
      return;
    }

    // force scroll page to saved page whild dialog is running to avoid losing page when backup is written in background
    final tempPage = tab.scrollPage;
    tab.scrollPage = savedPage;

    final context = NavigationHandler.instance.navContext;
    if (mode.isAsk) {
      final res = await showDialog<TabRestoreDialogResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TabRestoreDialog(
          pageNum: savedPage,
          tab: tab,
        ),
      );

      if (res == null) {
        // Dialog dismissed - don't mark as restored, ask again on next switch
        // Should not actually happen, because we block barrier dismiss and back button on dialog, but added just in case
        tab.pageRestored = true;
        return;
      }

      if (res.rememberChoice) {
        SX.tabPageRestoreMode.state.value = res.selectedMode;
        await settingsHandler.saveSettings(restate: false);
      }
      mode = res.selectedMode;
      delay = res.delay;

      if (mode.isIgnore) {
        tab.pageRestored = true;
        _pendingPageRestores.remove(tabIndex);
        tab.scrollPage = tempPage;
        return;
      }
    } else {
      FlashElements.showSnackbar(
        context: context,
        title: Text('${context.loc.searchHandler.restoringPage}: $savedPage'),
        content: Text('${context.loc.searchHandler.pageRestoreMode} ${mode.locName}'),
      );
    }

    tab.pageRestored = true;
    _pendingPageRestores.remove(tabIndex);

    if (mode.isFetchMultiplePages) {
      tab.scrollPage = tempPage;
    }

    await executePageRestore(
      tab,
      savedPage - 1,
      mode,
      customDelay: mode.isFetchMultiplePages ? delay : null,
    );
  }

  RxBool isRunningAutoSearch = false.obs;

  /// Executes the page restore for a tab with the given mode.
  Future<void> executePageRestore(
    SearchTab tab,
    int targetPage,
    TabPageRestoreMode mode, {
    int? customDelay,
  }) async {
    try {
      if (mode.isFetchOnlyPage) {
        // Jump to target page directly
        await changeCurrentTabPageNumber(targetPage);
      } else if (mode.isFetchMultiplePages) {
        if (isRunningAutoSearch.value) return;
        isRunningAutoSearch.value = true;

        bool isError = false;

        // Fetch pages sequentially until we reach the target page
        while (isRunningAutoSearch.value && tab.booruHandler.pageNum < targetPage && !tab.booruHandler.locked) {
          tab.booruHandler.pageNum++;
          pageNum.value = tab.booruHandler.pageNum;
          isLoading.value = true;

          await tab.booruHandler.search(tab.tags, null);
          if (errorString.value.isNotEmpty) {
            isError = true;
            break;
          }

          await Future.delayed(Duration(milliseconds: max(customDelay ?? 200, 200)));
          isLoading.value = false;
        }

        if (isError) {
          isRunningAutoSearch.value = false;
          return;
        }

        if (isRunningAutoSearch.value && mode.isFetchAndScroll) {
          // Scroll to first item of target page
          final int targetIndex = tab.booruHandler.filteredFetched.indexWhere(
            (item) => item.fetchedPage == targetPage,
          );
          if (targetIndex >= 0) {
            await Future.delayed(const Duration(milliseconds: 200));
            if (gridScrollController.hasClients) {
              await gridScrollController.scrollToIndex(
                targetIndex,
                duration: const Duration(milliseconds: 10),
                preferPosition: AutoScrollPosition.begin,
              );
              // Small jump to align with same page from backup
              gridScrollController.jumpTo(
                gridScrollController.position.pixels + 10,
              );
            }
          }
        }

        isRunningAutoSearch.value = false;
      }
    } catch (_) {
      isRunningAutoSearch.value = false;
    }
  }
}

class SearchTab {
  SearchTab(
    Booru selectedBooru,
    List<Booru>? secondaryBoorus,
    this.tags,
  ) {
    this.selectedBooru = selectedBooru.obs;
    this.secondaryBoorus = Rxn<List<Booru>?>(secondaryBoorus);

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
  String tags = '';

  late final Rx<Booru> selectedBooru;
  late final Rxn<List<Booru>?> secondaryBoorus;
  late final BooruHandler booruHandler;

  double scrollPosition = 0;
  int? scrollPage;
  RxList<BooruItem> selected = RxList<BooruItem>.from([]);
  final OrderedSelectionIndex<BooruItem> _selectedIndices = OrderedSelectionIndex();

  int? selectedIndexOf(BooruItem item) => _selectedIndices.indexOf(item);

  bool get hasSelectedItems => _selectedIndices.isNotEmpty;

  void _updateSelectedIndices() {
    _selectedIndices.update(selected);
  }

  /// Whether to save page position during tab backup.
  RxBool savePageEnabled = true.obs;

  /// Whether page restore has already been applied for this tab in this session.
  bool pageRestored = true;

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
      if (!skipSnatching && SX.snatchOnFavourite.value && newValue && item.isSnatched.value != true) {
        SnatchHandler.instance.queue(
          [item],
          booruHandler.booru,
          SX.snatchCooldown.value,
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
    if (!skipSnatching && SX.snatchOnFavourite.value && newValue) {
      SnatchHandler.instance.queue(
        items.where((e) => e.isSnatched.value != true).toList(),
        booruHandler.booru,
        SX.snatchCooldown.value,
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
  });
  final String tags;
  final String booru;
  final List<String> secondaryBoorus;
  final bool selected;
  final int? pageNum;
  final bool savePageEnabled;

  Map<String, dynamic> toJson() {
    return {
      't': tags,
      'b': booru,
      if (secondaryBoorus.isNotEmpty) 'sb': secondaryBoorus,
      if (selected) 's': selected, // only true matters, don't include on false
      if (pageNum != null) 'p': pageNum,
      if (savePageEnabled) 'sp': savePageEnabled,
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
        throw Exception('Invalid tab backup: $json');
      }
    }
  }

  static List<TabBackup> fromJsonList(String json) {
    final jsonList = jsonDecode(json);

    if (jsonList is! List) {
      return [];
    }

    return jsonList.map((e) => fromJson(e as Map<String, dynamic>)).where((e) => e != null).cast<TabBackup>().toList();
  }

  TabBackup copyWith({
    String? tags,
    String? booru,
    List<String>? secondaryBoorus,
    bool? selected,
    int? pageNum,
    bool? savePageEnabled,
  }) {
    return TabBackup(
      tags: tags ?? this.tags,
      booru: booru ?? this.booru,
      secondaryBoorus: secondaryBoorus ?? this.secondaryBoorus,
      selected: selected ?? this.selected,
      pageNum: pageNum ?? this.pageNum,
      savePageEnabled: savePageEnabled ?? this.savePageEnabled,
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
