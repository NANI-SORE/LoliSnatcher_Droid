import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:get/get.dart';

import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/delete_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/common/loli_dropdown.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/root/main_appbar.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_filters_dialog.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_group_header.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_move_dialog.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_row.dart';

enum TabSortingMode {
  none,
  alphabet,
  alphabetReverse,
  booru,
  booruReverse,
  ;

  bool get isNone => this == TabSortingMode.none;
  bool get isAlphabet => this == TabSortingMode.alphabet;
  bool get isAlphabetReverse => this == TabSortingMode.alphabetReverse;
  bool get isBooru => this == TabSortingMode.booru;
  bool get isBooruReverse => this == TabSortingMode.booruReverse;

  bool get isAnyAlphabet => isAlphabet || isAlphabetReverse;
  bool get isAnyBooru => isBooru || isBooruReverse;
  bool get isAnyReverse => isAlphabetReverse || isBooruReverse;
}

/// Group filter for the tab manager. Sentinel-free: each variant is a distinct
/// type so filters never collide with a real group id.
@immutable
sealed class TabGroupFilter {
  const TabGroupFilter();
}

@immutable
class TabGroupFilterAll extends TabGroupFilter {
  const TabGroupFilterAll();

  @override
  bool operator ==(Object other) => other is TabGroupFilterAll;

  @override
  int get hashCode => 0;
}

@immutable
class TabGroupFilterUngrouped extends TabGroupFilter {
  const TabGroupFilterUngrouped();

  @override
  bool operator ==(Object other) => other is TabGroupFilterUngrouped;

  @override
  int get hashCode => 1;
}

@immutable
class TabGroupFilterSpecific extends TabGroupFilter {
  const TabGroupFilterSpecific(this.groupId);
  final String groupId;

  @override
  bool operator ==(Object other) => other is TabGroupFilterSpecific && other.groupId == groupId;

  @override
  int get hashCode => Object.hash('TabGroupFilterSpecific', groupId);
}

enum _DuplicateTabDeleteMode {
  keepFirst,
  keepLast,
}

class _DuplicateTabPreviewGroup {
  const _DuplicateTabPreviewGroup({
    required this.key,
    required this.title,
    required this.tabs,
  });

  final String key;
  final String title;
  final List<SearchTab> tabs;
}

class _TabSortData {
  const _TabSortData({
    required this.index,
    required this.tags,
    required this.booruName,
  });

  final int index;
  final String tags;
  final String booruName;
}

class TabSelector extends StatelessWidget {
  const TabSelector({
    this.withBorder = true,
    this.countOnTop = false,
    this.color,
    super.key,
  });

  final bool withBorder;
  final bool countOnTop;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    const double radius = 10;

    final SearchHandler searchHandler = SearchHandler.instance;
    final SettingsHandler settingsHandler = SettingsHandler.instance;
    return Obx(() {
      // no boorus
      if (settingsHandler.booruList.isEmpty) {
        return Center(
          child: Text(context.loc.tabs.addBoorusInSettings),
        );
      }

      // no tabs
      if (searchHandler.tabs.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }

      final currentTab = searchHandler.currentTabOrNull;
      if (currentTab == null) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      }
      final totalTabs = searchHandler.total;
      final currentTabIndex = searchHandler.currentIndex;

      final theme = Theme.of(context);
      final inputDecoration = theme.inputDecorationTheme;

      final EdgeInsetsGeometry margin = withBorder
          ? const EdgeInsets.fromLTRB(5, 8, 5, 8)
          : const EdgeInsets.fromLTRB(0, 16, 0, 0);
      const EdgeInsetsGeometry contentPadding = EdgeInsets.symmetric(horizontal: 16);

      final dropdown = LoliDropdown(
        value: currentTab.selectedBooru.value,
        onChanged: (Booru? newValue) {
          if (searchHandler.currentBooruOrNull != newValue) {
            // if not already selected
            searchHandler.searchAction(searchHandler.searchTextController.text, newValue);
          }
        },
        expandableByScroll: true,
        searchable: settingsHandler.booruList.length > 5,
        searchCheck: (searchText, item) =>
            (item.name?.toLowerCase().contains(searchText) ?? true) ||
            (item.type?.name.toLowerCase().contains(searchText) ?? true),
        items: settingsHandler.booruList,
        itemExtent: 54,
        itemBuilder: (item) {
          final bool isCurrent = currentTab.selectedBooru.value == item;

          if (item == null) {
            return const SizedBox.shrink();
          }

          return Container(
            padding: settingsHandler.appMode.value.isDesktop
                ? const EdgeInsets.all(5)
                : const EdgeInsets.only(left: 16, right: 16),
            height: 54,
            decoration: isCurrent
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  )
                : null,
            child: TabBooruSelectorItem(booru: item),
          );
        },
        selectedItemBuilder: (value) {
          if (value == null) {
            return Text(context.loc.tabs.selectABooru);
          }

          return TabBooruSelectorItem(booru: value);
        },
        labelText: context.loc.booru,
      );

      return Padding(
        padding: margin,
        child: Obx(() {
          // §5.1: a thin colored bar at the top of the selector when the
          // current tab belongs to a group.
          final group = currentTab.group;
          final groupColor = group?.color.value;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (groupColor != null)
                Positioned(
                  bottom: 0,
                  left: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: groupColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: SizedBox(
                  height: MainAppBar.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned.fill(
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            InputDecorator(
                              decoration: InputDecoration(
                                label: Obx(() {
                                  final totalCount = currentTab.booruHandler.totalCount.value;

                                  return RichText(
                                    text: TextSpan(
                                      style: inputDecoration.labelStyle?.copyWith(
                                        color: color ?? inputDecoration.labelStyle?.color,
                                      ),
                                      children: [
                                        TextSpan(
                                          text:
                                              '${context.loc.tabs.tab} | ${(currentTabIndex + 1).toFormattedString()}/${totalTabs.toFormattedString()}',
                                        ),
                                        if (totalCount > 0 && countOnTop) ...[
                                          const TextSpan(text: ' | '),
                                          WidgetSpan(
                                            alignment: PlaceholderAlignment.middle,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                              child: Icon(
                                                Icons.image,
                                                size: inputDecoration.labelStyle?.fontSize ?? 12,
                                                color: color ?? inputDecoration.labelStyle?.color,
                                              ),
                                            ),
                                          ),
                                          TextSpan(
                                            text: totalCount.toFormattedString(),
                                          ),
                                        ],
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }),
                                labelStyle: inputDecoration.labelStyle?.copyWith(
                                  color: color ?? inputDecoration.labelStyle?.color,
                                ),
                                contentPadding: contentPadding,
                                border: inputDecoration.border?.copyWith(
                                  borderSide: BorderSide(
                                    color: withBorder
                                        ? (inputDecoration.border?.borderSide.color ?? Colors.transparent)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: inputDecoration.enabledBorder?.copyWith(
                                  borderSide: BorderSide(
                                    color: withBorder
                                        ? (inputDecoration.enabledBorder?.borderSide.color ?? Colors.transparent)
                                        : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: inputDecoration.focusedBorder?.copyWith(
                                  borderSide: BorderSide(
                                    color: withBorder
                                        ? (inputDecoration.focusedBorder?.borderSide.color ?? Colors.transparent)
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                            //
                            if (!countOnTop)
                              Positioned(
                                bottom: -8,
                                left: 16,
                                child: Obx(() {
                                  final totalCount = currentTab.booruHandler.totalCount.value;
                                  if (totalCount > 0) {
                                    final usedColor = (color ?? inputDecoration.labelStyle?.color)?.darken(0.2);
                                    return IgnorePointer(
                                      child: Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: Icon(
                                              Icons.image,
                                              size: 14,
                                              color: usedColor,
                                            ),
                                          ),
                                          //
                                          Text(
                                            totalCount.toFormattedString(),
                                            style: inputDecoration.labelStyle?.copyWith(
                                              fontSize: 12,
                                              color: usedColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return const SizedBox.shrink();
                                }),
                              ),
                          ],
                        ),
                      ),
                      //
                      Positioned.fill(
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: withBorder
                                    ? const BorderRadius.only(
                                        topLeft: Radius.circular(radius),
                                        bottomLeft: Radius.circular(radius),
                                      )
                                    : null,
                                onTap: () => dropdown.showDialog(context),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    left: 16,
                                    right: 16,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      BooruFavicon(currentTab.selectedBooru.value),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: color ?? theme.iconTheme.color,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            //
                            Container(
                              margin: const EdgeInsets.only(
                                top: 12,
                                bottom: 12,
                              ),
                              height: double.infinity,
                              width: 2,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            //
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: withBorder
                                      ? const BorderRadius.only(
                                          topRight: Radius.circular(radius),
                                          bottomRight: Radius.circular(radius),
                                        )
                                      : null,
                                  onTap: () {
                                    SettingsPageOpen(
                                      context: context,
                                      page: (_) => const TabManagerPage(),
                                    ).open();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              TabRow(
                                                tab: currentTab,
                                                color: color,
                                                withFavicon: false,
                                              ),
                                              MarqueeText(
                                                text: [
                                                  if (currentTab.booruHandler is MergebooruHandler)
                                                    (currentTab.booruHandler as MergebooruHandler).booruList[0].name ??
                                                        ''
                                                  else
                                                    currentTab.booruHandler.booru.name ?? '',
                                                  //
                                                  for (final booru in (currentTab.secondaryBoorus.value ?? <Booru>[]))
                                                    booru.name ?? '',
                                                ].join(', '),
                                                style: inputDecoration.labelStyle?.copyWith(
                                                  fontSize: 14,
                                                  color: color?.withValues(alpha: 0.75),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: color ?? theme.iconTheme.color,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      );
    });
  }
}

class TabManagerPage extends StatefulWidget {
  const TabManagerPage({super.key});

  @override
  State<TabManagerPage> createState() => _TabManagerPageState();
}

class _TabManagerPageState extends State<TabManagerPage> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  List<SearchTab> tabs = [], filteredTabs = [], selectedTabs = [];
  Map<SearchTab, _TabSortData> tabSortData = {};
  late final ScrollController scrollController;

  final TextEditingController filterTextController = TextEditingController();
  TabSortingMode sortingMode = TabSortingMode.none;
  bool? loadedFilter;
  Booru? booruFilter;
  TagType? tagTypeFilter;
  bool duplicateFilter = false, duplicateBooruFilter = true, emptyFilter = false;
  bool? isMultiBooruMode;
  TabGroupFilter groupFilter = const TabGroupFilterAll();
  bool selectMode = false;
  bool showScrollbarContext = false;
  bool isScrollbarContextHeld = false;
  int scrollbarContextIndex = 0;
  Timer? scrollbarContextTimer;

  static const double tabHeight = 72 + 8;

  int get totalTabs => searchHandler.total;
  int get totalFilteredTabs => filteredTabs.length;
  bool get isFilterActive => totalFilteredTabs != totalTabs || filterTextController.text.isNotEmpty || filtersCount > 0;
  int get currentTabIndex {
    final currentTab = searchHandler.currentTabOrNull;
    return currentTab == null ? -1 : filteredTabs.indexOf(currentTab);
  }

  /// Returns the visible tab manager sections in order:
  /// - First: ungrouped tabs (only when there are any in the filtered set).
  /// - Then: each group, in `tabGroups` order, that has at least one tab in
  ///   the filtered set (or always render headers — see code).
  ///
  /// Each entry is `(group?, tabs)` — `group == null` means ungrouped.
  List<({TabGroup? group, List<SearchTab> tabs})> get visibleSections {
    final ungrouped = filteredTabs.where((t) => t.groupId.value == null).toList();
    final byId = <String, List<SearchTab>>{
      for (final g in searchHandler.tabGroups) g.id: <SearchTab>[],
    };
    for (final t in filteredTabs) {
      final gid = t.groupId.value;
      if (gid != null && byId.containsKey(gid)) {
        byId[gid]!.add(t);
      }
    }
    return [
      (group: null, tabs: ungrouped),
      for (final g in searchHandler.tabGroups)
        if (byId[g.id]!.isNotEmpty || !isFilterActive) (group: g, tabs: byId[g.id]!),
    ];
  }

  int get filtersCount {
    int count = 0;
    if (loadedFilter != null) {
      count++;
    }
    if (booruFilter != null) {
      count++;
    }
    if (tagTypeFilter != null) {
      count++;
    }
    if (duplicateFilter) {
      count++;
    }
    if (isMultiBooruMode != null) {
      count++;
    }
    if (emptyFilter) {
      count++;
    }
    if (groupFilter is! TabGroupFilterAll) {
      count++;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    getTabs();

    // §4.5: Auto-expand the group containing the current tab so the user can
    // see their active tab when entering the manager.
    final currentTab = searchHandler.currentTabOrNull;
    final currentGroup = currentTab == null ? null : searchHandler.groupOf(currentTab);
    if (currentGroup != null && currentGroup.collapsed.value) {
      currentGroup.collapsed.value = false;
      // no backupTabs() — auto-expand is a UI preference, not user intent.
    } else if (currentTab != null && currentGroup == null && searchHandler.ungroupedCollapsed.value) {
      // current tab is ungrouped — auto-expand the ungrouped section too.
      searchHandler.ungroupedCollapsed.value = false;
    }

    scrollController = ScrollController(
      initialScrollOffset: _computeJumpOffset(),
    )..addListener(updateScrollbarContext);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await jumpToCurrent();
    });
  }

  @override
  void dispose() {
    scrollbarContextTimer?.cancel();
    scrollController.dispose();
    filterTextController.dispose();
    super.dispose();
  }

  void updateScrollbarContext() {
    if (!scrollController.hasClients || filteredTabs.isEmpty) {
      return;
    }

    final int newIndex = _scrollbarContextIndexForOffset(scrollController.offset);

    if (isScrollbarContextHeld) {
      scrollbarContextTimer?.cancel();
    } else {
      startScrollbarContextTimer();
    }

    if (!showScrollbarContext || scrollbarContextIndex != newIndex) {
      setState(() {
        showScrollbarContext = true;
        scrollbarContextIndex = newIndex;
      });
    }
  }

  void startScrollbarContextTimer() {
    scrollbarContextTimer?.cancel();
    scrollbarContextTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !isScrollbarContextHeld) {
        setState(() {
          showScrollbarContext = false;
        });
      }
    });
  }

  void holdScrollbarContext() {
    scrollbarContextTimer?.cancel();
    if (!isScrollbarContextHeld || !showScrollbarContext) {
      setState(() {
        isScrollbarContextHeld = true;
        showScrollbarContext = true;
      });
    }
  }

  void releaseScrollbarContext() {
    if (!isScrollbarContextHeld) {
      return;
    }

    setState(() {
      isScrollbarContextHeld = false;
    });
    startScrollbarContextTimer();
  }

  void dragScrollbarContext(double delta, double height) {
    if (!scrollController.hasClients || height <= 0) {
      return;
    }

    final position = scrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }

    final double offsetDelta = delta / height * position.maxScrollExtent;
    final double newOffset = (scrollController.offset + offsetDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    scrollController.jumpTo(newOffset);
  }

  int _scrollbarContextIndexForOffset(double scrollOffset) {
    double remainingOffset = max(0, scrollOffset);
    int lastVisibleIndex = 0;

    for (final section in visibleSections) {
      final tabsInSection = section.tabs;
      final bool hasUngroupedHeader =
          section.group == null && tabsInSection.isNotEmpty && searchHandler.tabGroups.isNotEmpty;
      final double headerHeight = section.group != null
          ? tabGroupHeaderHeight
          : hasUngroupedHeader
          ? _ungroupedHeaderHeight
          : 0;

      if (tabsInSection.isNotEmpty && remainingOffset < headerHeight) {
        return filteredTabs.indexOf(tabsInSection.first).clamp(0, filteredTabs.length - 1);
      }
      remainingOffset -= headerHeight;

      final bool isCollapsed = section.group != null
          ? section.group!.collapsed.value
          : (searchHandler.tabGroups.isNotEmpty && searchHandler.ungroupedCollapsed.value);
      if (isCollapsed || tabsInSection.isEmpty) {
        continue;
      }

      final double sectionHeight = tabsInSection.length * tabHeight;
      final int firstIndex = filteredTabs.indexOf(tabsInSection.first);
      if (remainingOffset < sectionHeight) {
        final int localIndex = (remainingOffset / tabHeight).floor().clamp(0, tabsInSection.length - 1);
        return (firstIndex + localIndex).clamp(0, filteredTabs.length - 1);
      }

      remainingOffset -= sectionHeight;
      lastVisibleIndex = firstIndex + tabsInSection.length - 1;
    }

    return lastVisibleIndex.clamp(0, filteredTabs.length - 1);
  }

  String _firstTabLetter(SearchTab tab) {
    final tagText = tab.tags.trim();
    if (tagText.isEmpty) {
      return context.loc.tabs.empty;
    }
    return tagText.characters.first.toUpperCase();
  }

  String scrollbarContextTitle() {
    if (filteredTabs.isEmpty) {
      return '';
    }

    final int index = scrollbarContextIndex.clamp(0, filteredTabs.length - 1);
    final tab = filteredTabs[index];

    if (sortingMode.isNone) {
      final int start = (index ~/ 10) * 10;
      final int end = min(start + 10, filteredTabs.length);
      return '$start-$end';
    }

    final firstLetter = _firstTabLetter(tab);
    if (sortingMode.isAnyBooru) {
      final booruName = tab.selectedBooru.value.name?.trim() ?? '';
      if (booruName.isEmpty) {
        return firstLetter;
      }
      return '$booruName | $firstLetter';
    }

    return firstLetter;
  }

  void getTabs() {
    tabs = searchHandler.tabs;
    tabSortData = {
      for (int i = 0; i < tabs.length; i++)
        tabs[i]: _TabSortData(
          index: i,
          tags: tabs[i].tags.toLowerCase().trim(),
          booruName: tabs[i].selectedBooru.value.name?.toLowerCase().trim() ?? '',
        ),
    };
    filteredTabs = tabs;
    filterTabs();

    setState(() {});
  }

  /// Computes the scroll offset of the current tab in the sliver layout
  /// (§4.1). Walks each section in order, accumulating header heights and
  /// section heights, returning the offset to the current tab. Skips collapsed
  /// sections entirely. If the current tab is in a collapsed group, returns
  /// 0 (caller should auto-expand first).
  double _computeJumpOffset() {
    if (currentTabIndex == -1) return 0;

    final SearchTab currentTab = searchHandler.currentTab;
    double offset = 0;

    final sections = visibleSections;
    for (final section in sections) {
      // ungrouped section uses a small header label (only if non-empty)
      if (section.group == null && section.tabs.isNotEmpty && searchHandler.tabGroups.isNotEmpty) {
        offset += _ungroupedHeaderHeight;
      } else if (section.group != null) {
        offset += tabGroupHeaderHeight;
      }

      final isCollapsed = section.group != null
          ? section.group!.collapsed.value
          : (searchHandler.tabGroups.isNotEmpty && searchHandler.ungroupedCollapsed.value);
      if (isCollapsed) {
        continue;
      }

      final localIndex = section.tabs.indexOf(currentTab);
      if (localIndex >= 0) {
        return offset + localIndex * tabHeight;
      }
      offset += section.tabs.length * tabHeight;
    }
    return offset;
  }

  static const double _ungroupedHeaderHeight = 28;

  Future<void> jumpToCurrent({bool animated = false}) async {
    if (scrollController.hasClients) {
      if (currentTabIndex == -1) {
        return;
      }

      final double maxScroll = scrollController.position.maxScrollExtent;
      double scrollOffset = _computeJumpOffset();
      if (scrollOffset > maxScroll) {
        scrollOffset = maxScroll;
      }
      if (scrollOffset < 0) {
        scrollOffset = 0;
      }

      if (animated) {
        await scrollController.animateTo(
          scrollOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        scrollController.jumpTo(scrollOffset);
      }
    }
  }

  void scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToCurrent(animated: true);
    });
  }

  void jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.jumpTo(0);
    });
  }

  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void filterTabs() {
    filteredTabs = [...tabs];

    // §4.6: filter by group
    switch (groupFilter) {
      case TabGroupFilterAll():
        break;
      case TabGroupFilterUngrouped():
        filteredTabs = filteredTabs.where((t) => t.groupId.value == null).toList();
      case TabGroupFilterSpecific(:final groupId):
        filteredTabs = filteredTabs.where((t) => t.groupId.value == groupId).toList();
    }

    if (booruFilter != null) {
      filteredTabs = filteredTabs.where((t) => t.selectedBooru.value == booruFilter).toList();
    }

    if (loadedFilter != null) {
      filteredTabs = filteredTabs
          .where(
            (t) => loadedFilter == true
                ? t.booruHandler.filteredFetched.isNotEmpty
                : t.booruHandler.filteredFetched.isEmpty,
          )
          .toList();
    }

    if (tagTypeFilter != null) {
      filteredTabs = filteredTabs.where((tab) {
        final List<String> tags = tab.tags.toLowerCase().trim().split(' ');
        for (final tag in tags) {
          if (tagHandler.getTag(tag).tagType == tagTypeFilter) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    if (isMultiBooruMode != null) {
      filteredTabs = filteredTabs
          .where(
            (tab) => isMultiBooruMode == false
                ? (tab.secondaryBoorus.value?.isEmpty ?? true)
                : tab.secondaryBoorus.value?.isNotEmpty == true,
          )
          .toList();
    }

    if (emptyFilter) {
      filteredTabs = filteredTabs.where((tab) => tab.tags.trim().isEmpty).toList();
    }

    if (filterTextController.text.isNotEmpty) {
      filteredTabs = filteredTabs.where((t) {
        final String filterText = filterTextController.text.toLowerCase().trim();
        return t.tags.toLowerCase().contains(filterText);
      }).toList();
    }

    if (duplicateFilter) {
      final Set<SearchTab> duplicateTabs = getDuplicateTabGroups(
        filteredTabs,
      ).values.expand<SearchTab>((tabs) => tabs).toSet();
      filteredTabs = searchHandler.tabs.where(duplicateTabs.contains).toList();
    }

    if (!sortingMode.isNone) {
      // §4.7: Sort within each group bucket (and within the ungrouped bucket)
      // — never across — to preserve the contiguous-block invariant.
      int compare(SearchTab a, SearchTab b) {
        final aData = tabSortData[a]!;
        final bData = tabSortData[b]!;

        if (sortingMode.isAnyBooru && aData.booruName != bData.booruName) {
          if (sortingMode.isAnyReverse) {
            return bData.booruName.compareTo(aData.booruName);
          } else {
            return aData.booruName.compareTo(bData.booruName);
          }
        }

        if (aData.tags != bData.tags) {
          if (sortingMode.isAnyReverse && !sortingMode.isAnyBooru) {
            return bData.tags.compareTo(aData.tags);
          } else {
            return aData.tags.compareTo(bData.tags);
          }
        }

        return aData.index.compareTo(bData.index);
      }

      // Bucket by group, sort each, concatenate in invariant order.
      final ungroupedBucket = <SearchTab>[];
      final byGroup = <String, List<SearchTab>>{
        for (final g in searchHandler.tabGroups) g.id: <SearchTab>[],
      };
      for (final t in filteredTabs) {
        final gid = t.groupId.value;
        if (gid != null && byGroup.containsKey(gid)) {
          byGroup[gid]!.add(t);
        } else {
          ungroupedBucket.add(t);
        }
      }
      ungroupedBucket.sort(compare);
      for (final list in byGroup.values) {
        list.sort(compare);
      }
      filteredTabs = [
        ...ungroupedBucket,
        for (final g in searchHandler.tabGroups) ...byGroup[g.id]!,
      ];
    }
  }

  Future<void> openFiltersDialog() async {
    final String? result = await SettingsPageOpen(
      context: context,
      asBottomSheet: true,
      page: (_) => TabManagerFiltersDialog(
        loadedFilter: loadedFilter,
        loadedFilterChanged: (bool? newValue) {
          loadedFilter = newValue;
        },
        booruFilter: booruFilter,
        booruFilterChanged: (Booru? newValue) {
          booruFilter = newValue;
        },
        tagTypeFilter: tagTypeFilter,
        tagTypeFilterChanged: (TagType? newValue) {
          tagTypeFilter = newValue;
        },
        duplicateFilter: duplicateFilter,
        duplicateFilterChanged: (bool newValue) {
          duplicateFilter = newValue;
          if (!duplicateFilter) {
            duplicateBooruFilter = true;
          }
        },
        duplicateBooruFilter: duplicateBooruFilter,
        duplicateBooruFilterChanged: (bool newValue) {
          duplicateBooruFilter = newValue;
        },
        isMultiBooruMode: isMultiBooruMode,
        isMultiBooruModeChanged: (bool? newValue) {
          isMultiBooruMode = newValue;
        },
        emptyFilter: emptyFilter,
        emptyFilterChanged: (bool newValue) {
          emptyFilter = newValue;
        },
        groupFilter: groupFilter,
        groupFilterChanged: (TabGroupFilter newValue) {
          groupFilter = newValue;
        },
      ),
    ).open();

    if (result == 'apply') {
      if (duplicateFilter) {
        sortingMode = TabSortingMode.alphabet;
      }
    }
    if (result == 'clear' ||
        (loadedFilter == null &&
            booruFilter == null &&
            tagTypeFilter == null &&
            duplicateFilter == false &&
            isMultiBooruMode == null &&
            emptyFilter == false &&
            groupFilter is TabGroupFilterAll)) {
      loadedFilter = null;
      booruFilter = null;
      tagTypeFilter = null;
      duplicateFilter = false;
      duplicateBooruFilter = true;
      isMultiBooruMode = null;
      emptyFilter = false;
      groupFilter = const TabGroupFilterAll();

      if (!sortingMode.isNone) {
        sortingMode = TabSortingMode.none;
      }
    }

    if (result != null) {
      getTabs();
      if (duplicateFilter) {
        await showDuplicateTabsDialog();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentTab = searchHandler.currentTabOrNull;
        if (currentTab != null && filteredTabs.contains(currentTab) && !duplicateFilter) {
          jumpToCurrent();
        } else {
          scrollToTop();
        }
      });
    }
  }

  Future<void> _onAddGroupTapped() async {
    final newId = await showCreateTabGroupDialog(context);
    if (newId != null) {
      getTabs();
    }
  }

  Map<String, List<SearchTab>> getDuplicateTabGroups(Iterable<SearchTab> tabsToCheck) {
    final Map<String, List<SearchTab>> duplicateGroups = {};

    for (final tab in tabsToCheck) {
      final String tags = tab.tags.toLowerCase().trim();
      final String key = duplicateBooruFilter ? '${tab.selectedBooru.value.name}+$tags' : tags;
      final List<SearchTab> group = duplicateGroups.putIfAbsent(key, () => []);
      group.add(tab);
    }

    duplicateGroups.removeWhere((_, tabs) => tabs.length < 2);

    return duplicateGroups;
  }

  List<_DuplicateTabPreviewGroup> getDuplicateTabPreviewGroups() {
    final duplicateGroups = getDuplicateTabGroups(filteredTabs);
    final List<_DuplicateTabPreviewGroup> previewGroups = [];

    for (final entry in duplicateGroups.entries) {
      final firstTab = entry.value.first;
      final String tags = firstTab.tags.trim().isEmpty ? context.loc.tabs.empty : firstTab.tags.trim();
      final String title = duplicateBooruFilter ? '${firstTab.selectedBooru.value.name ?? ''} | $tags' : tags;

      previewGroups.add(
        _DuplicateTabPreviewGroup(
          key: entry.key,
          title: title,
          tabs: searchHandler.tabs.where(entry.value.contains).toList(),
        ),
      );
    }

    return previewGroups;
  }

  Future<void> showDuplicateTabsDialog() async {
    final List<_DuplicateTabPreviewGroup> previewGroups = getDuplicateTabPreviewGroups();
    final int deleteCount = previewGroups.fold<int>(0, (count, group) => count + group.tabs.length - 1);

    if (deleteCount == 0) {
      return;
    }

    final List<SearchTab>? tabsToDelete = await showDialog<List<SearchTab>>(
      context: context,
      builder: (context) {
        return _DuplicateTabsDeleteDialog(
          previewGroups: previewGroups,
          searchHandler: searchHandler,
        );
      },
    );

    if (tabsToDelete == null || tabsToDelete.isEmpty) {
      return;
    }

    searchHandler.removeTabs(tabsToDelete);
    selectedTabs.removeWhere(tabsToDelete.contains);
    getTabs();

    if (filteredTabs.isEmpty) {
      duplicateFilter = false;
      duplicateBooruFilter = true;
      sortingMode = TabSortingMode.none;
      getTabs();
    }
  }

  Widget _buildSectionedManagerBody() {
    final sections = visibleSections;
    final widgets = <Widget>[];

    int globalOffset = 0;
    for (final section in sections) {
      final group = section.group;
      final sectionTabs = section.tabs;
      final sectionStart = globalOffset;

      // Section header (DragTarget for cross-group tab drag, §4.3, AND for
      // group reorder via TabGroup-typed Draggable on the header handle).
      if (group != null) {
        widgets.add(
          SliverToBoxAdapter(
            child: DragTarget<SearchTab>(
              onWillAcceptWithDetails: (details) => details.data.groupId.value != group.id,
              onAcceptWithDetails: (details) {
                searchHandler.assignTabToGroup(details.data, group.id);
                getTabs();
              },
              builder: (context, tabCandidates, tabRejects) {
                final hoveringTab = tabCandidates.isNotEmpty;
                return DragTarget<TabGroup>(
                  onWillAcceptWithDetails: (details) => details.data.id != group.id,
                  onAcceptWithDetails: (details) {
                    final fromIndex = searchHandler.tabGroups.indexWhere((g) => g.id == details.data.id);
                    final toIndex = searchHandler.tabGroups.indexWhere((g) => g.id == group.id);
                    if (fromIndex < 0 || toIndex < 0) return;
                    searchHandler.moveGroup(fromIndex, toIndex);
                    getTabs();
                  },
                  builder: (context, groupCandidates, groupRejects) {
                    final hoveringGroup = groupCandidates.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: hoveringTab
                            ? group.color.value.withValues(alpha: 0.18)
                            : hoveringGroup
                            ? group.color.value.withValues(alpha: 0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: hoveringGroup ? Border.all(color: group.color.value, width: 2) : null,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TabGroupHeader(
                        key: ValueKey('header-${group.id}'),
                        group: group,
                        tabsInGroupCount: sectionTabs.length,
                        onToggleCollapse: () {
                          searchHandler.toggleGroupCollapsed(group.id);
                          setState(() {});
                        },
                        onMenuTap: () async {
                          await showTabGroupActionsSheet(context, group.id);
                          if (mounted) getTabs();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      } else {
        // Ungrouped section: drop target for "remove from group" / "ungroup".
        // Only render the visible header when groups exist (otherwise the
        // ungrouped state is implicit). Always provide an invisible DragTarget
        // strip so dragging onto the ungrouped section's top works.
        final showUngroupedHeader = sectionTabs.isNotEmpty && searchHandler.tabGroups.isNotEmpty;
        widgets.add(
          SliverToBoxAdapter(
            child: DragTarget<SearchTab>(
              onWillAcceptWithDetails: (details) => details.data.groupId.value != null,
              onAcceptWithDetails: (details) {
                searchHandler.assignTabToGroup(details.data, null);
                getTabs();
              },
              builder: (context, candidates, rejects) {
                final hovering = candidates.isNotEmpty;
                final scheme = Theme.of(context).colorScheme;
                final overlay = hovering ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent;
                if (showUngroupedHeader || hovering) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    color: overlay,
                    child: showUngroupedHeader
                        ? TabGroupUngroupedHeader(
                            tabsInUngroupedCount: sectionTabs.length,
                            collapsed: searchHandler.ungroupedCollapsed.value,
                            onToggleCollapse: () {
                              searchHandler.toggleUngroupedCollapsed();
                              setState(() {});
                            },
                          )
                        : SizedBox(
                            height: 24,
                            child: Center(
                              child: Text(
                                hovering ? context.loc.tabs.groups.dropToUngroup : '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      }

      // Tabs sliver (skipped if collapsed). The ungrouped section is only
      // collapsible when a group exists (its header is shown then).
      final isCollapsed = group != null
          ? group.collapsed.value
          : (searchHandler.tabGroups.isNotEmpty && searchHandler.ungroupedCollapsed.value);
      if (!isCollapsed && sectionTabs.isNotEmpty) {
        widgets.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverReorderableList(
              key: ValueKey('sliver-${group?.id ?? '__ungrouped__'}'),
              itemCount: sectionTabs.length,
              itemBuilder: (context, localIndex) {
                final tab = sectionTabs[localIndex];
                return _buildTabRowWidget(context, localIndex, tab);
              },
              onReorderItem: (oldLocal, newLocal) {
                if (oldLocal == newLocal) return;
                // onReorderItem provides the post-removal newIndex directly;
                // translate to global by adding this section's start offset.
                final fromGlobal = searchHandler.tabs.indexOf(sectionTabs[oldLocal]);
                final toGlobal = sectionStart + newLocal;
                searchHandler.moveTab(fromGlobal, toGlobal);
                getTabs();
              },
            ),
          ),
        );
      }

      globalOffset += sectionTabs.length;
    }

    // Bottom spacer so the FAB doesn't clip the last row.
    widgets.add(
      SliverToBoxAdapter(
        child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
      ),
    );

    return Scrollbar(
      controller: scrollController,
      thickness: 8,
      interactive: true,
      scrollbarOrientation: settingsHandler.handSide.value.isLeft
          ? ScrollbarOrientation.left
          : ScrollbarOrientation.right,
      child: CustomScrollView(
        controller: scrollController,
        slivers: widgets,
      ),
    );
  }

  Widget filterBuild() {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      width: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: SettingsTextInput(
              title: context.loc.search,
              titleAsLabel: true,
              controller: filterTextController,
              inputType: TextInputType.text,
              clearable: true,
              pasteable: true,
              onlyInput: true,
              drawBottomBorder: false,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              // margin: const EdgeInsets.fromLTRB(2, 8, 2, 5),
              onChanged: (_) => getTabs(),
              enableIMEPersonalizedLearning: !settingsHandler.incognitoKeyboard,
            ),
          ),
          const SizedBox(width: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                iconSize: 30,
                onPressed: openFiltersDialog,
                icon: const Icon(Icons.filter_alt),
              ),
              if (filtersCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: openFiltersDialog,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Center(
                        child: Text(
                          filtersCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabRowWidget(BuildContext context, int localIndex, SearchTab tab) {
    final bool isCurrent = tab == searchHandler.currentTabOrNull;
    final bool isSelected = selectedTabs.contains(tab);
    final bool dragHandleEnabled = !selectMode && !isFilterActive && sortingMode.isNone;

    return ReorderableDelayedDragStartListener(
      key: ValueKey('item-${tab.id}'),
      index: localIndex,
      enabled: dragHandleEnabled,
      child: TabManagerItem(
        tab: tab,
        index: localIndex,
        isFiltered: isFilterActive || !sortingMode.isNone,
        originalIndex: (isFilterActive || !sortingMode.isNone) ? tabSortData[tab]?.index : null,
        isCurrent: isCurrent,
        filterText: filterTextController.text,
        leadingDragHandle: dragHandleEnabled
            ? Draggable<SearchTab>(
                data: tab,
                feedback: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 280,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: TabRow(tab: tab, withFavicon: true),
                    ),
                  ),
                ),
                childWhenDragging: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Tooltip(
                    message: context.loc.tabs.groups.dragToAGroup,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 22,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        onTap: selectMode
            ? () {
                if (isSelected || isCurrent) {
                  selectedTabs.removeWhere((item) => item == tab);
                } else {
                  selectedTabs.add(tab);
                }
                setState(() {});
              }
            : () {
                searchHandler.changeTabIndex(
                  tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab),
                );
                Navigator.of(context).pop();
              },
        optionsWidgetBuilder: selectMode
            ? (_, onTap) {
                if (isCurrent) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (bool? newValue) {
                      if (isSelected) {
                        selectedTabs.removeWhere((item) => item == tab);
                      } else {
                        selectedTabs.add(tab);
                      }
                      setState(() {});
                    },
                  ),
                );
              }
            : null,
        onOptionsTap: () {
          if (!selectMode) {
            showOptionsDialog(filteredTabs.indexOf(tab));
          }
        },
        onCloseTap: selectMode
            ? null
            : () {
                selectedTabs.remove(tab);
                searchHandler.removeTabAt(tabIndex: tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab));
                getTabs();
              },
      ),
    );
  }

  /// Picks a group (or "Ungroup", or "New group") and assigns [tab] to it.
  Future<void> _showMoveTabToGroupChooser(SearchTab tab) async {
    final groups = searchHandler.tabGroups;
    final currentGroupId = tab.groupId.value;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(context.loc.tabs.groups.chooseGroup),
          children: [
            for (final g in groups)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.of(context).pop();
                  searchHandler.assignTabToGroup(tab, g.id);
                },
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: g.color.value, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(g.name.value)),
                    if (currentGroupId == g.id) const Icon(Icons.check, size: 16),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () async {
                Navigator.of(context).pop();
                final newId = await showCreateTabGroupDialog(context);
                if (newId != null) searchHandler.assignTabToGroup(tab, newId);
              },
              child: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined),
                  const SizedBox(width: 12),
                  Text('${context.loc.tabs.groups.newGroup}…'),
                ],
              ),
            ),
            if (currentGroupId != null)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.of(context).pop();
                  searchHandler.assignTabToGroup(tab, null);
                },
                child: Row(
                  children: [
                    const Icon(Icons.folder_off),
                    const SizedBox(width: 12),
                    Text(context.loc.tabs.groups.removeFromGroup),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Like [_showMoveTabToGroupChooser] but for a batch of tabs (select-mode).
  Future<void> _showMoveTabsToGroupChooser(List<SearchTab> selectedTabsBatch) async {
    if (selectedTabsBatch.isEmpty) return;
    final groups = searchHandler.tabGroups;

    return showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(context.loc.tabs.groups.chooseGroup),
          children: [
            for (final g in groups)
              SimpleDialogOption(
                onPressed: () {
                  Navigator.of(context).pop();
                  searchHandler.assignTabsToGroup(selectedTabsBatch, g.id);
                  setState(() {
                    selectedTabs.clear();
                    selectMode = false;
                  });
                  getTabs();
                },
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: g.color.value, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(g.name.value)),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () async {
                Navigator.of(context).pop();
                final newId = await showCreateTabGroupDialog(context);
                if (newId != null) {
                  searchHandler.assignTabsToGroup(selectedTabsBatch, newId);
                  setState(() {
                    selectedTabs.clear();
                    selectMode = false;
                  });
                  getTabs();
                }
              },
              child: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined),
                  const SizedBox(width: 12),
                  Text('${context.loc.tabs.groups.newGroup}…'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                searchHandler.assignTabsToGroup(selectedTabsBatch, null);
                setState(() {
                  selectedTabs.clear();
                  selectMode = false;
                });
                getTabs();
              },
              child: Row(
                children: [
                  const Icon(Icons.folder_off),
                  const SizedBox(width: 12),
                  Text(context.loc.tabs.groups.ungroup),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void showOptionsDialog(int index) {
    final SearchTab tab = filteredTabs[index];
    final int originalIndex = tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab);

    final Widget optionsDialog = SettingsDialog(
      scrollable: false,
      contentItems: [
        TabManagerItem(
          tab: tab,
          index: index,
          isFiltered: isFilterActive || !sortingMode.isNone,
          originalIndex: (isFilterActive || !sortingMode.isNone) ? originalIndex : null,
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () async {
            await ClipboardUtils.copyTextToClipboard(tab.tags);

            Navigator.of(context).pop();
          },
          leading: const Icon(Icons.copy),
          title: Text(context.loc.tabs.copy),
        ),
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) => TabMoveDialog(
                row: TabManagerItem(
                  tab: tab,
                  index: tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab),
                  isFiltered: false,
                  originalIndex: null,
                ),
                index: tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab),
              ),
            );
            getTabs();
          },
          leading: const Icon(Icons.move_down_sharp),
          title: Text(context.loc.tabs.moveAction),
        ),
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () async {
            // Pop the options dialog first; group chooser is a separate dialog.
            Navigator.of(context).pop();
            await _showMoveTabToGroupChooser(tab);
            if (mounted) getTabs();
          },
          leading: Icon(
            tab.groupId.value == null ? Icons.create_new_folder_outlined : Icons.drive_file_move_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            tab.groupId.value == null ? context.loc.tabs.groups.addToGroup : context.loc.tabs.groups.moveToGroupAction,
          ),
        ),
        if (tab.groupId.value != null) ...[
          const SizedBox(height: 10),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(color: Theme.of(context).colorScheme.secondary),
            ),
            onTap: () {
              searchHandler.assignTabToGroup(tab, null);
              Navigator.of(context).pop();
              getTabs();
            },
            leading: const Icon(Icons.folder_off),
            title: Text(context.loc.tabs.groups.removeFromGroup),
          ),
        ],
        const SizedBox(height: 10),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () {
            selectedTabs.remove(tab);
            searchHandler.removeTabAt(tabIndex: tabSortData[tab]?.index ?? searchHandler.tabs.indexOf(tab));
            getTabs();
          },
          leading: const Icon(Icons.close, color: Colors.red),
          title: Text(context.loc.tabs.remove),
        ),
        const SizedBox(height: 20),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: Theme.of(context).colorScheme.secondary),
          ),
          onTap: () {
            Navigator.of(context).pop();
          },
          leading: const Icon(Icons.cancel_outlined),
          title: Text(context.loc.close),
        ),
        const SizedBox(height: 10),
      ],
    );

    showDialog(
      context: context,
      builder: (BuildContext context) => optionsDialog,
    );
  }

  void showDeleteDialog() {
    if (selectedTabs.isEmpty) {
      return;
    }

    // sort selected tabs in order of appearance in the list instead of order of selection
    selectedTabs.sort((a, b) => (tabSortData[a]?.index ?? -1).compareTo(tabSortData[b]?.index ?? -1));

    final Widget deleteDialog = SettingsDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.loc.tabs.deleteTabs),
          Text(
            context.loc.tabs.areYouSureDeleteTabs(count: selectedTabs.length),
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
      scrollable: false,
      content: Container(
        height: MediaQuery.sizeOf(context).height * 0.75,
        width: double.maxFinite,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.hardEdge,
        child: ListView.builder(
          clipBehavior: Clip.hardEdge,
          shrinkWrap: true,
          itemCount: selectedTabs.length,
          itemBuilder: (_, index) {
            final item = selectedTabs[index];

            final int itemIndex = tabSortData[item]?.index ?? searchHandler.tabs.indexOf(item);

            return TabManagerItem(
              tab: item,
              index: index,
              isFiltered: true,
              originalIndex: itemIndex,
            );
          },
        ),
      ),
      actionButtons: [
        const CancelButton(withIcon: true),
        DeleteButton(
          withIcon: true,
          action: () {
            searchHandler.removeTabs(selectedTabs);
            selectedTabs.clear();
            getTabs();
            Navigator.of(context).pop();
          },
        ),
      ],
    );

    showDialog(
      context: context,
      builder: (_) => deleteDialog,
    );
  }

  void showHelpDialog() {
    Widget helpText(String text, {TextStyle? style}) {
      return SizedBox(
        width: double.infinity,
        child: Text(
          text,
          softWrap: true,
          style: style,
        ),
      );
    }

    Widget helpRichText(List<InlineSpan> children) {
      return SizedBox(
        width: double.infinity,
        child: RichText(
          softWrap: true,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: children,
          ),
        ),
      );
    }

    Widget helpRow({
      required Widget leading,
      required String text,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(child: Text(text, softWrap: true)),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return SettingsDialog(
          title: Text(context.loc.tabs.tabsManager),
          contentItems: [
            helpText(context.loc.tabs.scrolling),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.subdirectory_arrow_left_outlined),
              text: context.loc.tabs.scrollToCurrent,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.arrow_circle_up),
              text: context.loc.tabs.scrollToTop,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.arrow_circle_down),
              text: context.loc.tabs.scrollToBottom,
            ),
            const Divider(),
            helpRow(
              leading: const Icon(Icons.filter_alt),
              text: context.loc.tabs.filterTabsByBooru,
            ),
            const Divider(),
            helpText(context.loc.tabs.sorting),
            const SizedBox(height: 6),
            helpRow(
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: TabSortingIcon(TabSortingMode.none, withBorder: true),
              ),
              text: context.loc.tabs.defaultTabsOrder,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: TabSortingIcon(TabSortingMode.alphabet, withBorder: true),
              ),
              text: context.loc.tabs.sortAlphabetically,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: TabSortingIcon(TabSortingMode.alphabetReverse, withBorder: true),
              ),
              text: context.loc.tabs.sortAlphabeticallyReversed,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: TabSortingIcon(TabSortingMode.booru, withBorder: true),
              ),
              text: context.loc.tabs.sortByBooruName,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: TabSortingIcon(TabSortingMode.booruReverse, withBorder: true),
              ),
              text: context.loc.tabs.sortByBooruNameReversed,
            ),
            const SizedBox(height: 6),
            helpText(context.loc.tabs.longPressSortToSave),
            const Divider(),
            helpText(context.loc.tabs.select),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.select_all),
              text: context.loc.tabs.toggleSelectMode,
            ),
            const SizedBox(height: 12),
            helpText(context.loc.tabs.onTheBottomOfPage),
            const SizedBox(height: 6),
            helpRow(
              leading: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.select_all),
                  Text(' / '),
                  Icon(Icons.border_clear),
                ],
              ),
              text: context.loc.tabs.selectDeselectAll,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.delete_forever),
              text: context.loc.tabs.deleteSelectedTabs,
            ),
            const Divider(),
            helpRow(
              leading: const Icon(Icons.expand),
              text: context.loc.tabs.longPressToMove,
            ),
            const Divider(),
            helpText(
              context.loc.tabs.groups.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.create_new_folder_outlined),
              text: context.loc.tabs.groups.helpTapNewGroup,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.drag_indicator),
              text: context.loc.tabs.groups.helpDragTabHandle,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.reorder),
              text: context.loc.tabs.groups.helpDragGroupHandle,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.expand_more),
              text: context.loc.tabs.groups.helpTapHeaderCollapse,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.more_vert),
              text: context.loc.tabs.groups.helpTapMoreVert,
            ),
            const SizedBox(height: 6),
            helpText(context.loc.tabs.groups.helpPrevNextInherits),
            const Divider(),
            helpText(context.loc.tabs.numbersInBottomRight),
            // TODO
            helpText(context.loc.tabs.firstNumberTabIndex),
            helpText(context.loc.tabs.secondNumberTabIndex),
            const Divider(),
            helpText(context.loc.tabs.specialFilters),
            helpText(context.loc.tabs.loadedFilter),
            helpText(context.loc.tabs.notLoadedFilter),
            helpRichText([
              TextSpan(text: context.loc.tabs.notLoadedItalic.replaceAll('italic', '')),
              const TextSpan(
                text: 'italic',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const TextSpan(text: ' text'),
            ]),
          ],
          actionButtons: const [
            CloseDialogButton(withIcon: true),
          ],
        );
      },
    );
  }

  /// Contextual app bar shown while in select mode. Surfaces the batch
  /// actions (add to group, delete) in the conventional top-bar location so
  /// they are discoverable regardless of the optional bottom action bar.
  PreferredSizeWidget _buildSelectionAppBar(BuildContext context) {
    final currentTab = searchHandler.currentTabOrNull;
    final filteredTabsMinusCurrent = [...filteredTabs];
    if (currentTab != null) {
      filteredTabsMinusCurrent.remove(currentTab);
    }
    final bool selectedAll = selectedTabs.isNotEmpty && selectedTabs.length == filteredTabsMinusCurrent.length;
    final bool hasSelected = selectedTabs.isNotEmpty;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: context.loc.tabs.toggleSelectMode,
        onPressed: () {
          setState(() {
            selectMode = false;
            selectedTabs.clear();
          });
        },
      ),
      title: Text(
        '${context.loc.tabs.select} ${selectedTabs.length.toFormattedString()}',
      ),
      actions: [
        IconButton(
          icon: Icon(selectedAll ? Icons.border_clear : Icons.select_all),
          tooltip: context.loc.tabs.selectDeselectAll,
          onPressed: () {
            setState(() {
              if (selectedAll) {
                selectedTabs.clear();
              } else {
                selectedTabs = [...filteredTabsMinusCurrent];
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: context.loc.tabs.groups.addToGroup,
          onPressed: hasSelected ? () => _showMoveTabsToGroupChooser(List<SearchTab>.from(selectedTabs)) : null,
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever),
          tooltip: context.loc.tabs.deleteSelectedTabs,
          onPressed: hasSelected ? showDeleteDialog : null,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: selectMode
          ? _buildSelectionAppBar(context)
          : AppBar(
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.tabs.tabsManager,
                    style: Theme.of(context).appBarTheme.titleTextStyle,
                  ),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                      children: [
                        if (isFilterActive) ...[
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(Icons.filter_alt, size: 16),
                          ),
                          TextSpan(text: '${totalFilteredTabs.toFormattedString()}/'),
                        ],
                        TextSpan(text: totalTabs.toFormattedString()),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: context.loc.tabs.selectMode,
                  onPressed: () {
                    setState(() {
                      selectMode = !selectMode;
                      selectedTabs.clear();
                    });
                  },
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPress: isFilterActive
                      ? null
                      : () async {
                          final currentTab = searchHandler.currentTabOrNull;
                          if (currentTab == null) {
                            return;
                          }

                          final res = await showDialog(
                            context: context,
                            builder: (context) {
                              return SettingsDialog(
                                title: Text(
                                  sortingMode.isNone ? context.loc.tabs.shuffleTabs : context.loc.tabs.sortMode,
                                ),
                                contentItems: [
                                  Text(
                                    sortingMode.isNone
                                        ? context.loc.tabs.shuffleTabsQuestion
                                        : context.loc.tabs.saveTabsInCurrentOrder,
                                  ),
                                  if (!sortingMode.isNone)
                                    Text(
                                      '${sortingMode.isAnyBooru ? context.loc.tabs.byBooru : ''} ${context.loc.tabs.alphabetically} ${sortingMode.isAnyReverse ? context.loc.tabs.reversed : ''}'
                                          .trim(),
                                    ),
                                ],
                                actionButtons: [
                                  const CancelButton(withIcon: true),
                                  ElevatedButton.icon(
                                    label: Text(sortingMode.isNone ? context.loc.tabs.shuffle : context.loc.tabs.sort),
                                    icon: TabSortingIcon(sortingMode),
                                    onPressed: () {
                                      Navigator.of(context).pop('allow');
                                    },
                                  ),
                                ],
                              );
                            },
                          );

                          if (res != 'allow') {
                            return;
                          }

                          if (sortingMode.isNone) {
                            // §0.7: shuffle within each group bucket, never across,
                            // to preserve the contiguous-block invariant.
                            final ungroupedBucket = filteredTabs.where((t) => t.groupId.value == null).toList()
                              ..shuffle();
                            final byGroup = <String, List<SearchTab>>{
                              for (final g in searchHandler.tabGroups) g.id: <SearchTab>[],
                            };
                            for (final t in filteredTabs) {
                              final gid = t.groupId.value;
                              if (gid != null && byGroup.containsKey(gid)) byGroup[gid]!.add(t);
                            }
                            for (final list in byGroup.values) {
                              list.shuffle();
                            }
                            filteredTabs = [
                              ...ungroupedBucket,
                              for (final g in searchHandler.tabGroups) ...byGroup[g.id]!,
                            ];

                            FlashElements.showSnackbar(
                              context: context,
                              duration: const Duration(seconds: 2),
                              title: Text(context.loc.tabs.tabRandomlyShuffled, style: const TextStyle(fontSize: 20)),
                              leadingIcon: Icons.sort_by_alpha,
                              sideColor: Colors.green,
                            );
                          } else {
                            FlashElements.showSnackbar(
                              context: context,
                              duration: const Duration(seconds: 2),
                              title: Text(context.loc.tabs.tabOrderSaved, style: const TextStyle(fontSize: 20)),
                              leadingIcon: Icons.sort,
                              sideColor: Colors.green,
                            );
                          }

                          final int newIndex = filteredTabs.indexOf(currentTab);
                          searchHandler.tabs.value = [...filteredTabs];
                          searchHandler.changeTabIndex(newIndex);

                          getTabs();
                        },
                  child: IconButton(
                    icon: TabSortingIcon(sortingMode),
                    tooltip: context.loc.tabs.sortMode,
                    onPressed: () {
                      switch (sortingMode) {
                        case TabSortingMode.none:
                          sortingMode = TabSortingMode.alphabet;
                          break;
                        case TabSortingMode.alphabet:
                          sortingMode = TabSortingMode.alphabetReverse;
                          break;
                        case TabSortingMode.alphabetReverse:
                          sortingMode = TabSortingMode.booru;
                          break;
                        case TabSortingMode.booru:
                          sortingMode = TabSortingMode.booruReverse;
                          break;
                        case TabSortingMode.booruReverse:
                          sortingMode = TabSortingMode.none;
                          break;
                      }
                      getTabs();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.help_center_outlined),
                  tooltip: context.loc.tabs.help,
                  onPressed: showHelpDialog,
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: Column(
        children: [
          filterBuild(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isScrollbarLeft = settingsHandler.handSide.value.isLeft;
                final double scrollProgress =
                    scrollController.hasClients && scrollController.position.maxScrollExtent > 0
                    ? (scrollController.offset / scrollController.position.maxScrollExtent).clamp(0.0, 1.0)
                    : 0;
                final double scrollLabelDragHeight = max(0, constraints.maxHeight - 40);
                final double scrollLabelTop = scrollLabelDragHeight * scrollProgress;

                return Stack(
                  children: [
                    Obx(() {
                      // Touch tabGroups so external mutations (e.g. backup
                      // restore) trigger a rebuild of the manager body.
                      searchHandler.tabGroups.length;
                      return _buildSectionedManagerBody();
                    }),
                    if (totalFilteredTabs == 0)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Kaomoji(
                              category: KaomojiCategory.indifference,
                              style: TextStyle(fontSize: 36),
                            ),
                            Text(
                              context.loc.tabs.noTabsFound,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ),
                      ),
                    if (totalFilteredTabs > 0)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOut,
                        top: scrollLabelTop,
                        left: isScrollbarLeft ? 16 : null,
                        right: isScrollbarLeft ? null : 16,
                        child: IgnorePointer(
                          ignoring: !showScrollbarContext && !isScrollbarContextHeld,
                          child: Listener(
                            onPointerDown: (_) => holdScrollbarContext(),
                            onPointerUp: (_) => releaseScrollbarContext(),
                            onPointerCancel: (_) => releaseScrollbarContext(),
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragStart: (_) => holdScrollbarContext(),
                              onVerticalDragUpdate: (details) {
                                holdScrollbarContext();
                                dragScrollbarContext(details.delta.dy, scrollLabelDragHeight);
                              },
                              onVerticalDragEnd: (_) => releaseScrollbarContext(),
                              onVerticalDragCancel: releaseScrollbarContext,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity: showScrollbarContext ? 1 : 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.66),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    child: Text(
                                      scrollbarContextTitle(),
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'tab_manager_new_tab_fab',
                            tooltip: context.loc.tabs.addNewTab,
                            onPressed: () {
                              // Use the current booru's defTags if set, otherwise the
                              // global default from Boorus & Search settings.
                              final booru = searchHandler.currentBooruOrNull;
                              final query = (booru?.defTags?.isNotEmpty == true)
                                  ? booru!.defTags!
                                  : settingsHandler.defTags;
                              searchHandler.addTabByString(query, switchToNew: true);
                              getTabs();
                            },
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 10),
                          FloatingActionButton.small(
                            heroTag: 'tab_manager_new_group_fab',
                            tooltip: context.loc.tabs.groups.newGroup,
                            onPressed: _onAddGroupTapped,
                            child: const Icon(Icons.create_new_folder_outlined),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Obx(() {
            if (!settingsHandler.tabManagerBottomBar.value) {
              return const SizedBox.shrink();
            }
            return Builder(
              builder: (context) {
                const double iconSize = 28;

                final toTopBtn = ElevatedButton(
                  onPressed: scrollToTop,
                  child: const Icon(
                    Icons.arrow_circle_up_rounded,
                    size: iconSize,
                  ),
                );

                final toCurrentBtn = ElevatedButton(
                  onPressed: currentTabIndex != -1 ? scrollToCurrent : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.subdirectory_arrow_left_outlined,
                        size: iconSize,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        (searchHandler.currentIndex + 1).toFormattedString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: currentTabIndex == -1 ? Colors.transparent : null,
                        ),
                      ),
                    ],
                  ),
                );

                final toBottomBtn = ElevatedButton(
                  onPressed: scrollToBottom,
                  child: const Icon(
                    Icons.arrow_circle_down_rounded,
                    size: iconSize,
                  ),
                );

                return Container(
                  margin: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    10 + MediaQuery.paddingOf(context).bottom,
                  ),
                  width: double.infinity,
                  child: Row(
                    children: [
                      if (settingsHandler.handSide.value.isLeft) ...[
                        toBottomBtn,
                        const SizedBox(width: 6),
                        toCurrentBtn,
                        const SizedBox(width: 6),
                        toTopBtn,
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(
                            Icons.close,
                            size: iconSize,
                          ),
                          label: AutoSizeText(
                            context.loc.close,
                            maxLines: 1,
                            overflowReplacement: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      if (settingsHandler.handSide.value.isRight) ...[
                        const SizedBox(width: 6),
                        toTopBtn,
                        const SizedBox(width: 6),
                        toCurrentBtn,
                        const SizedBox(width: 6),
                        toBottomBtn,
                      ],
                    ],
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class _DuplicateTabsDeleteDialog extends StatefulWidget {
  const _DuplicateTabsDeleteDialog({
    required this.previewGroups,
    required this.searchHandler,
  });

  final List<_DuplicateTabPreviewGroup> previewGroups;
  final SearchHandler searchHandler;

  @override
  State<_DuplicateTabsDeleteDialog> createState() => _DuplicateTabsDeleteDialogState();
}

class _DuplicateTabsDeleteDialogState extends State<_DuplicateTabsDeleteDialog> with SingleTickerProviderStateMixin {
  late final TabController tabController;
  late final ScrollController scrollController;
  late final TextEditingController searchController;
  late final Map<String, Set<SearchTab>> keptTabs;
  late final Map<SearchTab, int> tabIndexes;
  late final Map<String, ValueNotifier<int>> keptCountNotifiers;
  late final ValueNotifier<int> deleteCountNotifier;

  @override
  void initState() {
    super.initState();
    tabController = TabController(initialIndex: 1, length: 2, vsync: this);
    scrollController = ScrollController();
    searchController = TextEditingController();
    keptTabs = {};
    tabIndexes = {
      for (int index = 0; index < widget.searchHandler.tabs.length; index++) widget.searchHandler.tabs[index]: index,
    };
    keptCountNotifiers = {
      for (final group in widget.previewGroups) group.key: ValueNotifier<int>(0),
    };
    applyDeleteMode(_DuplicateTabDeleteMode.keepLast);
    deleteCountNotifier = ValueNotifier<int>(calculateDeleteCount());
  }

  @override
  void dispose() {
    tabController.dispose();
    scrollController.dispose();
    searchController.dispose();
    for (final notifier in keptCountNotifiers.values) {
      notifier.dispose();
    }
    deleteCountNotifier.dispose();
    super.dispose();
  }

  List<_DuplicateTabPreviewGroup> get visiblePreviewGroups {
    final filterText = searchController.text.toLowerCase().trim();

    if (filterText.isEmpty) {
      return widget.previewGroups;
    }

    return widget.previewGroups.where((group) {
      if (group.key.toLowerCase().contains(filterText)) {
        return true;
      }

      return group.tabs.any((tab) {
        final List<String> searchableText = [
          tab.tags,
          tab.selectedBooru.value.name ?? '',
          for (final booru in (tab.secondaryBoorus.value ?? [])) booru.name ?? '',
        ];

        return searchableText.any((text) => text.toLowerCase().contains(filterText));
      });
    }).toList();
  }

  void applyDeleteMode(_DuplicateTabDeleteMode mode) {
    for (final group in widget.previewGroups) {
      keptTabs[group.key] = {
        switch (mode) {
          _DuplicateTabDeleteMode.keepFirst => group.tabs.first,
          _DuplicateTabDeleteMode.keepLast => group.tabs.last,
        },
      };
      keptCountNotifiers[group.key]?.value = 1;
    }
  }

  void toggleKeptTab(_DuplicateTabPreviewGroup group, SearchTab tab) {
    final keptGroupTabs = keptTabs[group.key] ?? <SearchTab>{};

    if (keptGroupTabs.contains(tab)) {
      keptGroupTabs.remove(tab);
    } else {
      keptGroupTabs.add(tab);
    }
  }

  void toggleKeptGroup(_DuplicateTabPreviewGroup group) {
    final keptGroupTabs = keptTabs[group.key] ?? <SearchTab>{};
    final bool isAllKept = keptGroupTabs.length == group.tabs.length;

    keptTabs[group.key] = isAllKept ? <SearchTab>{} : group.tabs.toSet();
  }

  int calculateDeleteCount() {
    int result = 0;

    for (final group in widget.previewGroups) {
      result += group.tabs.length - (keptTabs[group.key]?.length ?? 0);
    }

    return result;
  }

  void updateDeleteCount() {
    deleteCountNotifier.value = calculateDeleteCount();
  }

  void updateKeptCount(_DuplicateTabPreviewGroup group) {
    keptCountNotifiers[group.key]?.value = keptTabs[group.key]?.length ?? 0;
  }

  List<SearchTab> get tabsToDelete {
    final List<SearchTab> result = [];

    for (final group in widget.previewGroups) {
      final keptGroupTabs = keptTabs[group.key] ?? <SearchTab>{};
      result.addAll(group.tabs.where((tab) => !keptGroupTabs.contains(tab)));
    }

    result.sort((a, b) => (tabIndexes[a] ?? -1).compareTo(tabIndexes[b] ?? -1));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDialog(
      title: Text(context.loc.tabs.deleteDuplicateTabs),
      scrollable: false,
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.loc.tabs.deleteDuplicateTabsQuestion),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: tabController,
              onTap: (index) {
                setState(() {
                  applyDeleteMode(
                    index == 0 ? _DuplicateTabDeleteMode.keepFirst : _DuplicateTabDeleteMode.keepLast,
                  );
                  updateDeleteCount();
                });
              },
              tabs: [
                Tab(
                  child: AutoSizeText(
                    context.loc.tabs.keepFirstDuplicateTabs,
                    maxLines: 1,
                    minFontSize: 10,
                  ),
                ),
                Tab(
                  child: AutoSizeText(
                    context.loc.tabs.keepLastDuplicateTabs,
                    maxLines: 1,
                    minFontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsTextInput(
              title: context.loc.search,
              titleAsLabel: true,
              controller: searchController,
              inputType: TextInputType.text,
              clearable: true,
              pasteable: true,
              onlyInput: true,
              drawBottomBorder: false,
              margin: EdgeInsets.zero,
              onChanged: (_) => setState(() {}),
              enableIMEPersonalizedLearning: !SettingsHandler.instance.incognitoKeyboard,
            ),
            Expanded(
              child: duplicateDeletePreviewList(),
            ),
          ],
        ),
      ),
      actionButtons: [
        ElevatedButton.icon(
          icon: const Icon(Icons.skip_next),
          label: Text(context.loc.tabs.skipDuplicateTabDelete),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ValueListenableBuilder<int>(
          valueListenable: deleteCountNotifier,
          builder: (_, deleteCount, _) {
            return DeleteButton(
              text: '${context.loc.delete} (${deleteCount.toFormattedString()})',
              withIcon: true,
              enabled: deleteCount > 0,
              action: () => Navigator.of(context).pop(tabsToDelete),
            );
          },
        ),
      ],
    );
  }

  Widget duplicateDeletePreviewList() {
    final previewGroups = visiblePreviewGroups;

    if (previewGroups.isEmpty) {
      return Center(
        child: Text(context.loc.tabs.noTabsFound),
      );
    }

    return Scrollbar(
      controller: scrollController,
      interactive: true,
      scrollbarOrientation: SettingsHandler.instance.handSide.value.isLeft
          ? ScrollbarOrientation.left
          : ScrollbarOrientation.right,
      child: ListView.builder(
        controller: scrollController,
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.only(top: 8),
        itemCount: previewGroups.length,
        itemBuilder: (_, groupIndex) {
          final group = previewGroups[groupIndex];
          final int originalGroupIndex = widget.previewGroups.indexOf(group);

          return StatefulBuilder(
            builder: (context, setGroupState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: keptCountNotifiers[group.key]!,
                    builder: (context, keptCount, _) {
                      final bool isAllKept = keptCount == group.tabs.length;

                      return Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AutoSizeText(
                                    group.title,
                                    maxLines: 1,
                                    minFontSize: 10,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelLarge,
                                  ),
                                  AutoSizeText(
                                    '#${(originalGroupIndex + 1).toFormattedString()} | ${keptCount.toFormattedString()}/${group.tabs.length.toFormattedString()}',
                                    maxLines: 1,
                                    minFontSize: 10,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.loc.tabs.selectDeselectAll,
                              onPressed: () {
                                setGroupState(() {
                                  toggleKeptGroup(group);
                                });
                                updateKeptCount(group);
                                updateDeleteCount();
                              },
                              icon: Icon(isAllKept ? Icons.border_clear : Icons.select_all),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  for (int index = 0; index < group.tabs.length; index++)
                    StatefulBuilder(
                      builder: (context, setRowState) {
                        final tab = group.tabs[index];
                        final isKept = keptTabs[group.key]?.contains(tab) ?? false;

                        void toggleTab() {
                          setRowState(() {
                            toggleKeptTab(group, tab);
                          });
                          updateKeptCount(group);
                          updateDeleteCount();
                        }

                        return Opacity(
                          opacity: isKept ? 1 : 0.5,
                          child: TabManagerItem(
                            tab: tab,
                            index: index,
                            isCurrent: tab == widget.searchHandler.currentTabOrNull,
                            isFiltered: true,
                            originalIndex: tabIndexes[tab] ?? -1,
                            onTap: toggleTab,
                            optionsWidgetBuilder: (_, onTap) {
                              return IconButton(
                                onPressed: onTap,
                                icon: Icon(
                                  isKept ? Icons.check_box : Icons.check_box_outline_blank,
                                ),
                              );
                            },
                            onOptionsTap: toggleTab,
                          ),
                        );
                      },
                    ),
                  if (groupIndex < previewGroups.length - 1) const Divider(height: 8),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class TabManagerItem extends StatelessWidget {
  const TabManagerItem({
    required this.tab,
    this.index,
    this.isCurrent = false,
    this.isFiltered = false,
    this.originalIndex,
    this.onTap,
    this.optionsWidgetBuilder,
    this.onOptionsTap,
    this.onCloseTap,
    this.filterText,
    this.leadingDragHandle,
    super.key,
  }) : assert(
         !isFiltered || (index != null && originalIndex != null),
         'originalIndex must be provided if isFiltered is true',
       );

  final SearchTab tab;
  final int? index;
  final bool isCurrent;
  final bool isFiltered;
  final int? originalIndex;
  final VoidCallback? onTap;
  final Widget Function(BuildContext, VoidCallback?)? optionsWidgetBuilder;
  final VoidCallback? onOptionsTap;
  final VoidCallback? onCloseTap;
  final String? filterText;
  // Optional drag handle widget rendered on the leading (left) edge for
  // cross-group drag (§4.3). Mirrors the placement of the group-reorder
  // handle on `TabGroupHeader`.
  final Widget? leadingDragHandle;

  @override
  Widget build(BuildContext context) {
    // print('tab selector item build $index');

    final BorderRadius radius = BorderRadius.circular(10);

    final subtitleStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).textTheme.bodySmall!.color,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 72,
        width: double.maxFinite,
        child: Material(
          color: Color.lerp(
            Theme.of(context).cardColor,
            Theme.of(context).brightness == Brightness.dark ? Colors.transparent : Colors.grey[200],
            0.66,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: isCurrent
                ? BorderSide(
                    color: Theme.of(context).colorScheme.secondary,
                    width: 2,
                  )
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 2,
                bottom: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        if (leadingDragHandle != null) ...[
                          leadingDragHandle!,
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: TabRow(
                            tab: tab,
                            filterText: filterText,
                          ),
                        ),
                        if (onOptionsTap != null) ...[
                          const SizedBox(width: 4),
                          optionsWidgetBuilder?.call(context, onOptionsTap) ??
                              IconButton(
                                onPressed: onOptionsTap,
                                icon: const Icon(CupertinoIcons.slider_horizontal_3),
                              ),
                        ],
                        if (onCloseTap != null) ...[
                          if (onOptionsTap == null) const SizedBox(width: 4) else const SizedBox(width: 8),
                          IconButton(
                            onPressed: onCloseTap,
                            icon: const Icon(
                              Icons.close,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: subtitleStyle.fontSize,
                            child: Builder(
                              builder: (context) {
                                final List<String> booruNames = [
                                  if (tab.booruHandler is MergebooruHandler)
                                    (tab.booruHandler as MergebooruHandler).booruList[0].name ?? ''
                                  else
                                    tab.booruHandler.booru.name ?? '',
                                  //
                                  for (final Booru booru in (tab.secondaryBoorus.value ?? [])) booru.name ?? '',
                                ];
                                final String booruNamesStr = booruNames.join(', ');

                                return MarqueeText(
                                  key: ValueKey(booruNamesStr),
                                  text: booruNamesStr.trim(),
                                  style: subtitleStyle.copyWith(
                                    height: 1,
                                  ),
                                  allowDownscale: false,
                                  isExpanded: false,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Obx(() {
                          final int totalCount = tab.booruHandler.totalCount.value;
                          return Row(
                            children: [
                              if (totalCount > 0) ...[
                                Icon(
                                  Icons.image,
                                  size: 16,
                                  color: subtitleStyle.color,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${totalCount.toFormattedString()} | ',
                                  style: subtitleStyle,
                                ),
                              ],
                              if (index != null)
                                Text(
                                  '#${(index! + 1).toFormattedString()}${originalIndex != null ? '|${(originalIndex! + 1).toFormattedString()}' : ''}',
                                  style: subtitleStyle,
                                ),
                            ],
                          );
                        }),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TabSortingIcon extends StatelessWidget {
  const TabSortingIcon(
    this.sortingMode, {
    this.withBorder = false,
    super.key,
  });

  final TabSortingMode sortingMode;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: withBorder ? const EdgeInsets.all(3) : null,
      decoration: BoxDecoration(
        borderRadius: withBorder ? BorderRadius.circular(10) : null,
        border: withBorder ? Border.all(color: Theme.of(context).colorScheme.secondary, width: 2) : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationX((sortingMode.isAnyReverse || sortingMode.isNone) ? 0 : pi),
            child: Icon(sortingMode.isNone ? Icons.sort_by_alpha : Icons.sort),
          ),
          if (sortingMode.isAnyBooru)
            Positioned(
              bottom: -10,
              child: Text(context.loc.tabs.byBooru, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
