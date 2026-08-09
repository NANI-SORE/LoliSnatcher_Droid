import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_group_header.dart';

/// Single tab pill width on the desktop strip. Used for layout and scroll
/// distance estimates.
const double _desktopTabWidth = 250;

/// Desktop strip item: either an ungrouped tab, or a group (which may render
/// as a collapsed pill or as an expanded capsule containing its tabs).
sealed class _DesktopItem {
  const _DesktopItem();
}

class _DesktopTabItem extends _DesktopItem {
  const _DesktopTabItem(this.tab, {this.group});
  final SearchTab tab;
  final TabGroup? group;
}

class _DesktopGroupHeaderItem extends _DesktopItem {
  const _DesktopGroupHeaderItem(this.group, this.tabCount);
  final TabGroup group;
  final int tabCount;
}

class DesktopTabs extends StatefulWidget {
  const DesktopTabs({super.key});

  @override
  State<DesktopTabs> createState() => _DesktopTabsState();
}

class _DesktopTabsState extends State<DesktopTabs> {
  final SearchHandler searchHandler = SearchHandler.instance;
  final AutoScrollController scrollController = AutoScrollController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToTab(searchHandler.currentIndex);
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> jumpToTab(int index) async {
    if (!scrollController.hasClients || index < 0 || index >= searchHandler.tabs.length) return;
    final tab = searchHandler.tabs[index];
    final group = searchHandler.groupOf(tab);
    final collapsedGroupId = group?.collapsed.value == true ? group?.id : null;
    final items = _buildItems();
    final itemIndex = items.indexWhere(
      (item) => switch (item) {
        _DesktopTabItem(tab: final itemTab) => identical(itemTab, tab),
        _DesktopGroupHeaderItem(group: final itemGroup) => collapsedGroupId != null && itemGroup.id == collapsedGroupId,
      },
    );
    if (itemIndex < 0) return;
    final max = scrollController.position.maxScrollExtent;
    if (max == 0) return;
    scrollController.jumpTo(itemIndex * (max / items.length));
    await Future.delayed(const Duration(milliseconds: 50));
    await scrollController.scrollToIndex(
      itemIndex,
      preferPosition: AutoScrollPosition.begin,
      duration: const Duration(milliseconds: 50),
    );
  }

  void onMouseScroll(double delta) {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.offset + (delta * 2));
    }
  }

  /// Build the ordered list of strip items from the master `tabs` list,
  /// preserving the contiguous-block invariant (§0.1): ungrouped tabs first,
  /// then a header and lazily-built tab items for each expanded group.
  List<_DesktopItem> _buildItems() {
    final tabs = searchHandler.tabs;
    final groups = searchHandler.tabGroups;
    final items = <_DesktopItem>[];

    final ungrouped = tabs.where((t) => t.groupId.value == null);
    for (final t in ungrouped) {
      items.add(_DesktopTabItem(t));
    }

    final byGroup = <String, List<SearchTab>>{
      for (final g in groups) g.id: <SearchTab>[],
    };
    for (final t in tabs) {
      final gid = t.groupId.value;
      if (gid != null && byGroup.containsKey(gid)) {
        byGroup[gid]!.add(t);
      }
    }
    for (final g in groups) {
      final groupedTabs = byGroup[g.id]!;
      items.add(_DesktopGroupHeaderItem(g, groupedTabs.length));
      if (!g.collapsed.value) {
        for (final tab in groupedTabs) {
          items.add(_DesktopTabItem(tab, group: g));
        }
      }
    }

    return items;
  }

  Widget _buildTabPill(SearchTab tab, {bool insideGroup = false, Color? groupColor}) {
    final isNotEmptyBooru = tab.selectedBooru.value.faviconURL != null;
    final totalCount = tab.booruHandler.totalCount.value;
    final totalCountText = (totalCount > 0) ? ' ($totalCount)' : '';
    final tagText = '${tab.tags.isEmpty ? context.loc.tabs.empty : tab.tags}$totalCountText';
    final isSelected = searchHandler.currentIndex == searchHandler.tabs.indexOf(tab);

    final borderColor = isSelected ? Colors.red : (insideGroup ? Colors.transparent : Colors.grey);

    final pill = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(5),
      ),
      width: double.maxFinite,
      child: Row(
        children: [
          if (groupColor != null) ...[
            const SizedBox(width: 4),
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: groupColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (isNotEmptyBooru) BooruFavicon(tab.selectedBooru.value) else const Icon(CupertinoIcons.question, size: 20),
          const SizedBox(width: 3),
          MarqueeText(
            key: ValueKey(tagText),
            text: tagText,
            style: TextStyle(
              fontSize: 16,
              color: tab.tags == '' ? Colors.grey : null,
            ),
          ),
          const SizedBox(width: 3),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              searchHandler.removeTabAt(tabIndex: searchHandler.tabs.indexOf(tab));
            },
            hoverColor: Theme.of(context).hoverColor,
            iconSize: 14,
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () {
        // Auto-expand group on switch (§5.2).
        final group = searchHandler.groupOf(tab);
        if (group != null && group.collapsed.value) {
          group.collapsed.value = false;
        }
        searchHandler.changeTabIndex(searchHandler.tabs.indexOf(tab));
      },
      onSecondaryTap: () => _showTabContextMenu(tab),
      onLongPress: () => _showTabContextMenu(tab),
      child: SizedBox(
        width: _desktopTabWidth,
        child: pill,
      ),
    );
  }

  Widget _buildGroupHeader(TabGroup group, int tabCount) {
    return Obx(() {
      final color = group.color.value;
      final name = group.name.value;
      final collapsed = group.collapsed.value;
      final scheme = Theme.of(context).colorScheme;

      return GestureDetector(
        onTap: () => searchHandler.toggleGroupCollapsed(group.id),
        onSecondaryTap: () => _showGroupContextMenu(group),
        onLongPress: () => _showGroupContextMenu(group),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: 0.2), scheme.surface),
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$tabCount',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showTabContextMenu(SearchTab tab) {
    final groups = searchHandler.tabGroups;
    final inGroupId = tab.groupId.value;

    showMenu<String>(
      context: context,
      position: _menuAnchor(),
      items: [
        if (groups.isNotEmpty) ...[
          PopupMenuItem<String>(
            value: '__add_to_group__',
            child: Text(context.loc.tabs.groups.addToGroup),
          ),
        ],
        PopupMenuItem<String>(
          value: '__new_group__',
          child: Text(context.loc.tabs.groups.newGroupFromTab),
        ),
        if (inGroupId != null)
          PopupMenuItem<String>(
            value: '__remove_from_group__',
            child: Text(context.loc.tabs.groups.removeFromGroup),
          ),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case '__add_to_group__':
          final groupId = await _showGroupChooser();
          if (groupId != null) {
            searchHandler.assignTabToGroup(tab, groupId);
          }
        case '__new_group__':
          final newId = await showCreateTabGroupDialog(context);
          if (newId != null) {
            searchHandler.assignTabToGroup(tab, newId);
          }
        case '__remove_from_group__':
          searchHandler.assignTabToGroup(tab, null);
      }
    });
  }

  void _showGroupContextMenu(TabGroup group) {
    showMenu<String>(
      context: context,
      position: _menuAnchor(),
      items: [
        PopupMenuItem<String>(value: 'edit', child: Text(context.loc.tabs.groups.renameRecolor)),
        PopupMenuItem<String>(
          value: 'collapse',
          child: Text(group.collapsed.value ? context.loc.tabs.groups.expand : context.loc.tabs.groups.collapse),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(context.loc.tabs.groups.deleteGroup, style: const TextStyle(color: Colors.red)),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'edit':
          showEditTabGroupDialog(context, group.id);
        case 'collapse':
          searchHandler.toggleGroupCollapsed(group.id);
        case 'delete':
          showDeleteTabGroupDialog(context, group.id);
      }
    });
  }

  Future<String?> _showGroupChooser() async {
    final groups = searchHandler.tabGroups;
    if (groups.isEmpty) return null;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(context.loc.tabs.groups.chooseGroup),
          children: [
            for (final g in groups)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(g.id),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: g.color.value,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(g.name.value)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  RelativeRect _menuAnchor() {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromCenter(
        center: overlay.size.center(Offset.zero),
        width: 1,
        height: 1,
      ),
      Offset.zero & overlay.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Obx(() {
        // Touch tabGroups so structural changes rebuild.
        searchHandler.tabGroups.length;
        final items = _buildItems();
        return Row(
          children: [
            Expanded(
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (PlatformExt.isDesktop && pointerSignal is PointerScrollEvent) {
                    onMouseScroll(pointerSignal.scrollDelta.dy);
                  }
                },
                child: ListView.builder(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return AutoScrollTag(
                      highlightColor: Colors.red,
                      key: ValueKey(_itemKey(item)),
                      controller: scrollController,
                      index: index,
                      child: switch (item) {
                        _DesktopTabItem(:final tab, :final group) => _buildTabPill(
                          tab,
                          insideGroup: group != null,
                          groupColor: group?.color.value,
                        ),
                        _DesktopGroupHeaderItem(:final group, :final tabCount) => _buildGroupHeader(group, tabCount),
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 3),
            IconButton(
              tooltip: context.loc.tabs.addNewTab,
              onPressed: () {
                // Use the current booru's defTags if set, otherwise the global
                // default from Boorus & Search settings.
                final booru = searchHandler.currentBooru;
                final query = (booru.defTags?.isNotEmpty == true) ? booru.defTags! : SettingsHandler.instance.defTags;
                searchHandler.addTabByString(query, switchToNew: true);
              },
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: context.loc.tabs.groups.newGroup,
              onPressed: () => showCreateTabGroupDialog(context),
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            const SizedBox(width: 3),
            PopupMenuButton<SearchTab>(
              onSelected: (SearchTab tab) {
                final group = searchHandler.groupOf(tab);
                if (group != null && group.collapsed.value) {
                  group.collapsed.value = false;
                }
                searchHandler.changeTabIndex(searchHandler.tabs.indexOf(tab));
              },
              itemBuilder: (BuildContext context) {
                return searchHandler.tabs.map((SearchTab choice) {
                  return PopupMenuItem<SearchTab>(
                    value: choice,
                    child: _buildTabPill(choice),
                  );
                }).toList();
              },
            ),
          ],
        );
      }),
    );
  }

  String _itemKey(_DesktopItem item) {
    return switch (item) {
      _DesktopTabItem(:final tab) => 'tab-${tab.id}',
      _DesktopGroupHeaderItem(:final group) => 'group-${group.id}',
    };
  }
}
