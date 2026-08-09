import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:lolisnatcher/src/widgets/dialogs/add_new_tab_dialog.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/root/main_appbar.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_booru_selector.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_drag_auto_scroll.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_drag_feedback_geometry.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_drop_position.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_filters_dialog.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_group_header.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_manager_scroll_metrics.dart';
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

enum _TabGroupChooserAction { create, ungroup }

class _TabGroupChooserSheet extends StatelessWidget {
  const _TabGroupChooserSheet({
    required this.groups,
    required this.currentGroupId,
    required this.showUngroupAction,
    required this.ungroupLabel,
  });

  final List<TabGroup> groups;
  final String? currentGroupId;
  final bool showUngroupAction;
  final String ungroupLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                context.loc.tabs.groups.chooseGroup,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final group in groups)
              ListTile(
                leading: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: group.color.value,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(group.name.value),
                trailing: currentGroupId == group.id ? const Icon(Icons.check, size: 20) : null,
                selected: currentGroupId == group.id,
                onTap: () => Navigator.of(context).pop(group.id),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text('${context.loc.tabs.groups.newGroup}…'),
              onTap: () => Navigator.of(context).pop(_TabGroupChooserAction.create),
            ),
            if (showUngroupAction)
              ListTile(
                leading: const Icon(Icons.folder_off),
                title: Text(ungroupLabel),
                onTap: () => Navigator.of(context).pop(_TabGroupChooserAction.ungroup),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabManagerStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TabManagerStickyHeaderDelegate({
    required this.extent,
    required this.backgroundColor,
    required this.child,
  });

  final double extent;
  final Color backgroundColor;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: backgroundColor,
      elevation: overlapsContent ? 2 : 0,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _TabManagerStickyHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent || backgroundColor != oldDelegate.backgroundColor || child != oldDelegate.child;
  }
}

class _TabDropPreview extends StatelessWidget {
  const _TabDropPreview({
    required this.active,
    required this.label,
    required this.color,
    required this.icon,
    required this.child,
    this.showLabel = true,
  });

  final bool active;
  final String label;
  final Color color;
  final IconData icon;
  final Widget child;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: active ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.72), width: 1.5),
                ),
                child: showLabel
                    ? Center(
                        child: Material(
                          color: scheme.inverseSurface.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 16, color: scheme.onInverseSurface.withValues(alpha: 0.95)),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onInverseSurface.withValues(alpha: 0.95),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdaptiveTabDraggable extends StatefulWidget {
  const _AdaptiveTabDraggable({
    required this.tab,
    required this.originalIndex,
    required this.child,
    required this.childWhenDragging,
    required this.pointerPosition,
    required this.dragResultLabel,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    super.key,
  });

  final SearchTab tab;
  final int originalIndex;
  final Widget child;
  final Widget childWhenDragging;
  final ValueNotifier<Offset> pointerPosition;
  final ValueListenable<String> dragResultLabel;
  final void Function(Offset globalPosition, int? pointer) onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;

  @override
  State<_AdaptiveTabDraggable> createState() => _AdaptiveTabDraggableState();
}

class _AdaptiveTabDraggableState extends State<_AdaptiveTabDraggable> {
  int? _activePointer;

  void _handlePointerDown(PointerDownEvent event) {
    _activePointer ??= event.pointer;
  }

  void _handlePointerFinished(PointerEvent event) {
    if (event.pointer == _activePointer) {
      _activePointer = null;
    }
  }

  void _updatePointer(Offset position) {
    if (widget.pointerPosition.value == position) return;
    widget.pointerPosition.value = position;
    widget.onDragUpdate(position);
  }

  void _startDrag() {
    widget.onDragStarted(widget.pointerPosition.value, _activePointer);
  }

  void _finishDrag() {
    _activePointer = null;
    widget.onDragEnded();
  }

  Offset _captureDragStart(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    widget.pointerPosition.value = position;
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerFinished,
      onPointerCancel: _handlePointerFinished,
      child: LongPressDraggable<SearchTab>(
        data: widget.tab,
        dragAnchorStrategy: _captureDragStart,
        rootOverlay: true,
        maxSimultaneousDrags: 1,
        feedback: _AdaptiveTabDragFeedback(
          tab: widget.tab,
          originalIndex: widget.originalIndex,
          pointerPosition: widget.pointerPosition,
          dragResultLabel: widget.dragResultLabel,
        ),
        onDragStarted: _startDrag,
        onDragUpdate: (details) => _updatePointer(details.globalPosition),
        onDragEnd: (_) => _finishDrag(),
        childWhenDragging: widget.childWhenDragging,
        child: widget.child,
      ),
    );
  }
}

class _AdaptiveTabDragFeedback extends StatelessWidget {
  const _AdaptiveTabDragFeedback({
    required this.tab,
    required this.originalIndex,
    required this.pointerPosition,
    required this.dragResultLabel,
  });

  static const double _cardHeight = 56;
  static const double _tooltipHeight = 28;
  static const double _tooltipGap = 4;
  static const double _height = _tooltipHeight + _tooltipGap + _cardHeight;

  final SearchTab tab;
  final int originalIndex;
  final ValueListenable<Offset> pointerPosition;
  final ValueListenable<String> dragResultLabel;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    final card = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TabRow(tab: tab, withFavicon: true),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '#${(originalIndex + 1).toFormattedString()}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<Offset>(
      valueListenable: pointerPosition,
      child: card,
      builder: (context, pointer, child) {
        final geometry = calculateTabDragFeedbackGeometry(
          pointerX: pointer.dx,
          pointerY: pointer.dy,
          viewportWidth: mediaQuery.size.width,
          viewportHeight: mediaQuery.size.height,
          previewHeight: _height,
          leftMargin: max(12, padding.left + 8),
          topMargin: max(12, padding.top + 8),
          rightMargin: max(12, padding.right + 8),
          bottomMargin: max(12, padding.bottom + 8),
        );

        return Transform.translate(
          offset: Offset(
            geometry.left - pointer.dx,
            geometry.top - pointer.dy,
          ),
          child: SizedBox(
            width: geometry.width,
            height: _height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: _tooltipHeight,
                  child: ValueListenableBuilder<String>(
                    valueListenable: dragResultLabel,
                    builder: (context, label, _) {
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 100),
                        opacity: label.isEmpty ? 0 : 1,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            elevation: 2,
                            color: Theme.of(context).colorScheme.inverseSurface.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: _tooltipGap),
                SizedBox(
                  height: _cardHeight,
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
  bool showGroupedTabs = true;
  bool selectMode = false;
  bool showScrollbarContext = false;
  bool isScrollbarContextHeld = false;
  int scrollbarContextIndex = 0;
  Timer? scrollbarContextTimer;
  // Scroll ticks update only the floating context label. Rebuilding this page
  // would regroup every tab on every drag event.
  final ValueNotifier<int> _scrollbarContextRevision = ValueNotifier<int>(0);
  final GlobalKey _dragViewportKey = GlobalKey();
  final ValueNotifier<Offset> _dragFeedbackPointerPosition = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<String> _dragResultLabel = ValueNotifier<String>('');
  final Object _ungroupedDropTargetToken = Object();
  late final PointerRoute _dragGlobalPointerRoute = _handleGlobalDragPointerEvent;
  Timer? _dragAutoScrollTimer;
  Offset? _dragPointerPosition;
  int? _dragPointerId;
  bool _dragGlobalPointerRouteRegistered = false;
  Object? _activeDropTargetToken;
  TabManagerScrollMetrics _scrollMetrics = TabManagerScrollMetrics.empty;
  List<TabGroup?> _scrollMetricGroups = const [];
  List<int> _scrollMetricTabCounts = const [];

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

  void _updateScrollMetrics([List<({TabGroup? group, List<SearchTab> tabs})>? sections]) {
    if (!showGroupedTabs) {
      _scrollMetricGroups = const [];
      _scrollMetricTabCounts = const [];
      _scrollMetrics = TabManagerScrollMetrics.build(
        itemExtent: tabHeight,
        sections: [
          TabManagerSectionLayout(
            headerExtent: 0,
            tabCount: filteredTabs.length,
            collapsed: false,
          ),
        ],
      );
      return;
    }

    final currentSections = sections ?? visibleSections;
    _scrollMetricGroups = [for (final section in currentSections) section.group];
    _scrollMetricTabCounts = [for (final section in currentSections) section.tabs.length];
    _scrollMetrics = TabManagerScrollMetrics.build(
      itemExtent: tabHeight,
      sections: [
        for (final section in currentSections)
          TabManagerSectionLayout(
            headerExtent: section.group != null
                ? tabGroupHeaderHeight
                : searchHandler.tabGroups.isNotEmpty && (section.tabs.isNotEmpty || !isFilterActive)
                ? _ungroupedHeaderHeight
                : 0,
            tabCount: section.tabs.length,
            collapsed: section.group != null
                ? section.group!.collapsed.value
                : (searchHandler.tabGroups.isNotEmpty && searchHandler.ungroupedCollapsed.value),
          ),
      ],
    );
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
    _updateScrollMetrics();

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
    _dragAutoScrollTimer?.cancel();
    if (_dragGlobalPointerRouteRegistered) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_dragGlobalPointerRoute);
    }
    _scrollbarContextRevision.dispose();
    _dragFeedbackPointerPosition.dispose();
    _dragResultLabel.dispose();
    scrollController.dispose();
    filterTextController.dispose();
    super.dispose();
  }

  void updateScrollbarContext() {
    if (!scrollController.hasClients || filteredTabs.isEmpty) {
      return;
    }

    final int newIndex = _scrollMetrics
        .tabIndexForOffset(scrollController.offset)
        .clamp(
          0,
          filteredTabs.length - 1,
        );

    if (isScrollbarContextHeld) {
      scrollbarContextTimer?.cancel();
    } else {
      startScrollbarContextTimer();
    }

    showScrollbarContext = true;
    scrollbarContextIndex = newIndex;
    _scrollbarContextRevision.value++;
  }

  void startScrollbarContextTimer() {
    scrollbarContextTimer?.cancel();
    scrollbarContextTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !isScrollbarContextHeld) {
        showScrollbarContext = false;
        _scrollbarContextRevision.value++;
      }
    });
  }

  void holdScrollbarContext() {
    scrollbarContextTimer?.cancel();
    if (!isScrollbarContextHeld || !showScrollbarContext) {
      isScrollbarContextHeld = true;
      showScrollbarContext = true;
      _scrollbarContextRevision.value++;
    }
  }

  void releaseScrollbarContext() {
    if (!isScrollbarContextHeld) {
      return;
    }

    isScrollbarContextHeld = false;
    _scrollbarContextRevision.value++;
    startScrollbarContextTimer();
  }

  void _handleGlobalDragPointerEvent(PointerEvent event) {
    if (_dragPointerPosition == null || (_dragPointerId != null && event.pointer != _dragPointerId)) {
      return;
    }
    if (event is PointerMoveEvent) {
      _updateTabDrag(event.position);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _endTabDrag();
    }
  }

  void _startTabDrag(Offset globalPosition, int? pointer) {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
    _dragPointerPosition = globalPosition;
    _dragPointerId = pointer;
    if (!_dragGlobalPointerRouteRegistered) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_dragGlobalPointerRoute);
      _dragGlobalPointerRouteRegistered = true;
    }
    _activeDropTargetToken = null;
    if (_dragResultLabel.value.isNotEmpty) {
      _dragResultLabel.value = '';
    }
    _syncTabDragAutoScrollTimer();
  }

  void _updateTabDrag(Offset globalPosition) {
    if (_dragPointerPosition == globalPosition) return;
    if (_dragFeedbackPointerPosition.value != globalPosition) {
      _dragFeedbackPointerPosition.value = globalPosition;
    }
    _dragPointerPosition = globalPosition;
    _syncTabDragAutoScrollTimer();
  }

  void _endTabDrag() {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
    if (_dragGlobalPointerRouteRegistered) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_dragGlobalPointerRoute);
      _dragGlobalPointerRouteRegistered = false;
    }
    _dragPointerPosition = null;
    _dragPointerId = null;
    _activeDropTargetToken = null;
    if (_dragResultLabel.value.isNotEmpty) {
      _dragResultLabel.value = '';
    }
  }

  double _currentTabDragAutoScrollDelta() {
    final globalPosition = _dragPointerPosition;
    final viewportContext = _dragViewportKey.currentContext;
    if (globalPosition == null || viewportContext == null) {
      return 0;
    }

    final renderObject = viewportContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 0;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    return tabDragAutoScrollDelta(
      pointerY: localPosition.dy,
      viewportHeight: renderObject.size.height,
    );
  }

  void _syncTabDragAutoScrollTimer() {
    if (_currentTabDragAutoScrollDelta() == 0) {
      _dragAutoScrollTimer?.cancel();
      _dragAutoScrollTimer = null;
      return;
    }

    _dragAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 24),
      (_) => _autoScrollTabDrag(),
    );
  }

  void _autoScrollTabDrag() {
    final delta = _currentTabDragAutoScrollDelta();
    if (delta == 0) {
      _dragAutoScrollTimer?.cancel();
      _dragAutoScrollTimer = null;
      return;
    }
    if (!scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;
    if (!position.hasPixels || !position.hasContentDimensions || position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }

    final newOffset = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (newOffset != position.pixels) {
      scrollController.jumpTo(newOffset);
    }
  }

  void _showTabDropResult(Object targetToken, String label) {
    _activeDropTargetToken = targetToken;
    if (_dragResultLabel.value != label) {
      _dragResultLabel.value = label;
    }
  }

  void _clearTabDropResult(Object targetToken) {
    if (!identical(_activeDropTargetToken, targetToken)) return;
    _activeDropTargetToken = null;
    if (_dragResultLabel.value.isNotEmpty) {
      _dragResultLabel.value = '';
    }
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
    late final String tabTitle;

    if (sortingMode.isNone) {
      final int start = (index ~/ 10) * 10;
      final int end = min(start + 10, filteredTabs.length);
      tabTitle = '$start-$end';
    } else {
      final firstLetter = _firstTabLetter(tab);
      if (sortingMode.isAnyBooru) {
        final booruName = tab.selectedBooru.value.name?.trim() ?? '';
        tabTitle = booruName.isEmpty ? firstLetter : '$booruName | $firstLetter';
      } else {
        tabTitle = firstLetter;
      }
    }

    if (!showGroupedTabs || searchHandler.tabGroups.isEmpty || _scrollMetricGroups.isEmpty) {
      return tabTitle;
    }

    double scrollOffset = 0;
    if (scrollController.hasClients) {
      final position = scrollController.position;
      if (position.hasPixels) {
        scrollOffset = position.pixels;
      }
    }
    final sectionIndex = _scrollMetrics
        .sectionIndexForOffset(scrollOffset)
        .clamp(
          0,
          _scrollMetricGroups.length - 1,
        );
    final group = _scrollMetricGroups[sectionIndex];
    final groupTitle = group?.name.value.trim() ?? context.loc.tabs.groups.ungrouped;

    if (groupTitle.isEmpty) {
      return tabTitle;
    }
    return _scrollMetricTabCounts[sectionIndex] == 0 ? groupTitle : '$groupTitle | $tabTitle';
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
    _updateScrollMetrics();

    setState(() {});
  }

  /// Computes the scroll offset of the current tab in the sliver layout
  /// (§4.1). Walks each section in order, accumulating header heights and
  /// section heights, returning the offset to the current tab. Skips collapsed
  /// sections entirely. If the current tab is in a collapsed group, returns
  /// 0 (caller should auto-expand first).
  double _computeJumpOffset() {
    return currentTabIndex == -1
        ? 0
        : _scrollMetrics.offsetForTabIndex(
            currentTabIndex,
            keepHeaderVisible: true,
          );
  }

  static const double _ungroupedHeaderHeight = 44;

  Future<void> _moveToOffset(double requestedOffset, {required bool animated}) async {
    if (!scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;
    final double scrollOffset = requestedOffset.clamp(position.minScrollExtent, position.maxScrollExtent);
    final distance = (scrollController.offset - scrollOffset).abs();
    final shouldAnimate =
        animated &&
        shouldAnimateTabManagerScroll(
          distance: distance,
          viewportExtent: position.viewportDimension,
        );

    if (shouldAnimate) {
      await scrollController.animateTo(
        scrollOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      scrollController.jumpTo(scrollOffset);
    }
  }

  Future<void> jumpToCurrent({bool animated = false}) async {
    if (currentTabIndex == -1) {
      return;
    }
    await _moveToOffset(_computeJumpOffset(), animated: animated);
  }

  Future<void> _scrollToSection(int sectionIndex) async {
    final sections = visibleSections;
    _updateScrollMetrics(sections);
    await _moveToOffset(
      _scrollMetrics.offsetForSectionIndex(sectionIndex),
      animated: true,
    );
  }

  void scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpToCurrent(animated: true);
    });
  }

  void jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moveToOffset(0, animated: false);
    });
  }

  void scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moveToOffset(0, animated: true);
    });
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        _moveToOffset(scrollController.position.maxScrollExtent, animated: true);
      }
    });
  }

  void _toggleGroupedTabs() {
    setState(() {
      showGroupedTabs = !showGroupedTabs;
      _updateScrollMetrics();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _moveToOffset(currentTabIndex >= 0 ? _computeJumpOffset() : 0, animated: false);
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

  String _tabDropLabel(
    BuildContext context,
    SearchTab draggedTab,
    String? targetGroupId, {
    SearchTab? targetTab,
  }) {
    final groupName = targetGroupId == null
        ? context.loc.tabs.groups.ungrouped
        : searchHandler.groupById(targetGroupId)?.name.value.trim();
    final position = predictedTabDropPosition(
      tabGroupIds: [for (final tab in searchHandler.tabs) tab.groupId.value],
      draggedIndex: searchHandler.tabs.indexOf(draggedTab),
      targetGroupId: targetGroupId,
      targetIndex: targetTab == null ? null : searchHandler.tabs.indexOf(targetTab),
    );
    final positionLabel = context.loc.tabs.move.moveTo(
      formattedNumber: position.toFormattedString(),
    );

    return '${groupName?.isNotEmpty == true ? groupName : context.loc.tabs.groups.moveToGroup} • $positionLabel';
  }

  IconData _tabDropIcon(SearchTab draggedTab, String? targetGroupId) {
    if (draggedTab.groupId.value == targetGroupId) {
      return Icons.swap_vert;
    }
    return targetGroupId == null ? Icons.folder_off_outlined : Icons.drive_file_move_outline;
  }

  void _acceptTabDrop(
    SearchTab draggedTab,
    String? targetGroupId, {
    SearchTab? targetTab,
  }) {
    if (draggedTab.groupId.value != targetGroupId) {
      searchHandler.assignTabToGroup(
        draggedTab,
        targetGroupId,
        targetTab: targetTab,
      );
    } else if (targetTab != null && draggedTab != targetTab) {
      final fromIndex = searchHandler.tabs.indexOf(draggedTab);
      final toIndex = searchHandler.tabs.indexOf(targetTab);
      searchHandler.moveTab(fromIndex, toIndex);
    }
    getTabs();
  }

  Widget _buildTabDropTarget({
    required BuildContext context,
    required SearchTab targetTab,
    required Widget child,
  }) {
    final targetGroupId = targetTab.groupId.value;
    final targetColor = searchHandler.groupById(targetGroupId)?.color.value ?? Theme.of(context).colorScheme.primary;
    return DragTarget<SearchTab>(
      onWillAcceptWithDetails: (details) {
        final accepts = details.data != targetTab;
        if (accepts) {
          _showTabDropResult(
            targetTab,
            _tabDropLabel(
              context,
              details.data,
              targetGroupId,
              targetTab: targetTab,
            ),
          );
        }
        return accepts;
      },
      onMove: (details) {
        if (details.data == targetTab) return;
        _showTabDropResult(
          targetTab,
          _tabDropLabel(
            context,
            details.data,
            targetGroupId,
            targetTab: targetTab,
          ),
        );
      },
      onLeave: (_) => _clearTabDropResult(targetTab),
      onAcceptWithDetails: (details) {
        _clearTabDropResult(targetTab);
        _acceptTabDrop(
          details.data,
          targetGroupId,
          targetTab: targetTab,
        );
      },
      builder: (context, candidates, rejects) {
        final draggedTab = candidates.isEmpty ? null : candidates.first;
        return _TabDropPreview(
          active: draggedTab != null,
          label: draggedTab == null
              ? ''
              : _tabDropLabel(
                  context,
                  draggedTab,
                  targetGroupId,
                  targetTab: targetTab,
                ),
          color: targetColor,
          icon: draggedTab == null ? Icons.drive_file_move_outline : _tabDropIcon(draggedTab, targetGroupId),
          showLabel: false,
          child: child,
        );
      },
    );
  }

  Widget _buildSectionedManagerBody() {
    if (!showGroupedTabs) {
      return _buildFlatManagerBody();
    }

    final sections = visibleSections;
    _updateScrollMetrics(sections);
    final widgets = <Widget>[];
    final navigableSectionIndexes = <int>[
      for (var index = 0; index < sections.length; index++)
        if (sections[index].group != null ||
            (searchHandler.tabGroups.isNotEmpty && (sections[index].tabs.isNotEmpty || !isFilterActive)))
          index,
    ];

    for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      final group = section.group;
      final sectionTabs = section.tabs;
      final navigationIndex = navigableSectionIndexes.indexOf(sectionIndex);
      final onPreviousGroup = navigationIndex > 0
          ? () => _scrollToSection(navigableSectionIndexes[navigationIndex - 1])
          : null;
      final onNextGroup = navigationIndex >= 0 && navigationIndex + 1 < navigableSectionIndexes.length
          ? () => _scrollToSection(navigableSectionIndexes[navigationIndex + 1])
          : null;
      final sectionSlivers = <Widget>[];
      final scheme = Theme.of(context).colorScheme;
      final sectionBackground = group != null
          ? Color.alphaBlend(group.color.value.withValues(alpha: 0.06), scheme.surface)
          : searchHandler.tabGroups.isNotEmpty
          ? Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.035), scheme.surface)
          : Colors.transparent;

      // The header accepts tabs from other sections and whole-group drags.
      if (group != null) {
        sectionSlivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabManagerStickyHeaderDelegate(
              extent: tabGroupHeaderHeight,
              backgroundColor: sectionBackground,
              child: DragTarget<SearchTab>(
                onWillAcceptWithDetails: (details) {
                  final accepts = details.data.groupId.value != group.id;
                  if (accepts) {
                    _showTabDropResult(
                      group,
                      _tabDropLabel(context, details.data, group.id),
                    );
                  }
                  return accepts;
                },
                onMove: (details) {
                  if (details.data.groupId.value == group.id) return;
                  _showTabDropResult(
                    group,
                    _tabDropLabel(context, details.data, group.id),
                  );
                },
                onLeave: (_) => _clearTabDropResult(group),
                onAcceptWithDetails: (details) {
                  _clearTabDropResult(group);
                  _acceptTabDrop(details.data, group.id);
                },
                builder: (context, tabCandidates, tabRejects) {
                  final draggedTab = tabCandidates.isEmpty ? null : tabCandidates.first;
                  return _TabDropPreview(
                    active: draggedTab != null,
                    label: draggedTab != null
                        ? _tabDropLabel(
                            context,
                            draggedTab,
                            group.id,
                          )
                        : '',
                    color: group.color.value,
                    icon: draggedTab != null ? _tabDropIcon(draggedTab, group.id) : Icons.drive_file_move_outline,
                    showLabel: false,
                    child: DragTarget<TabGroup>(
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
                        final draggedGroup = hoveringGroup ? groupCandidates.first : null;
                        final targetGroupIndex = searchHandler.tabGroups.indexOf(group);
                        return _TabDropPreview(
                          active: hoveringGroup,
                          label: draggedGroup != null
                              ? '${draggedGroup.name.value} • ${context.loc.tabs.move.moveTo(
                                  formattedNumber: (targetGroupIndex + 1).toFormattedString(),
                                )}'
                              : '',
                          color: group.color.value,
                          icon: Icons.swap_vert,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: TabGroupHeader(
                              key: ValueKey('header-${group.id}'),
                              group: group,
                              tabsInGroupCount: sectionTabs.length,
                              onPreviousGroup: onPreviousGroup,
                              onNextGroup: onNextGroup,
                              onToggleCollapse: () {
                                searchHandler.toggleGroupCollapsed(group.id);
                                setState(() {});
                              },
                              onMenuTap: () async {
                                await showTabGroupActionsSheet(context, group.id);
                                if (mounted) getTabs();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      } else {
        // Ungrouped section: drop target for "remove from group" / "ungroup".
        // Keep an empty ungrouped header visible while groups exist so tabs can
        // always be dragged out of their current group.
        final showUngroupedHeader = searchHandler.tabGroups.isNotEmpty && (sectionTabs.isNotEmpty || !isFilterActive);
        final ungroupedDropTarget = DragTarget<SearchTab>(
          onWillAcceptWithDetails: (details) {
            final accepts = details.data.groupId.value != null;
            if (accepts) {
              _showTabDropResult(
                _ungroupedDropTargetToken,
                _tabDropLabel(context, details.data, null),
              );
            }
            return accepts;
          },
          onMove: (details) {
            if (details.data.groupId.value == null) return;
            _showTabDropResult(
              _ungroupedDropTargetToken,
              _tabDropLabel(context, details.data, null),
            );
          },
          onLeave: (_) => _clearTabDropResult(_ungroupedDropTargetToken),
          onAcceptWithDetails: (details) {
            _clearTabDropResult(_ungroupedDropTargetToken);
            _acceptTabDrop(details.data, null);
          },
          builder: (context, candidates, rejects) {
            final draggedTab = candidates.isEmpty ? null : candidates.first;
            if (showUngroupedHeader || draggedTab != null) {
              return _TabDropPreview(
                active: draggedTab != null,
                label: draggedTab != null ? _tabDropLabel(context, draggedTab, null) : '',
                color: scheme.primary,
                icon: Icons.folder_off_outlined,
                showLabel: false,
                child: showUngroupedHeader
                    ? TabGroupUngroupedHeader(
                        tabsInUngroupedCount: sectionTabs.length,
                        collapsed: searchHandler.ungroupedCollapsed.value,
                        onPreviousGroup: onPreviousGroup,
                        onNextGroup: onNextGroup,
                        onToggleCollapse: () {
                          searchHandler.toggleUngroupedCollapsed();
                          setState(() {});
                        },
                      )
                    : SizedBox(
                        height: 24,
                        child: Center(
                          child: Text(
                            draggedTab != null ? context.loc.tabs.groups.dropToUngroup : '',
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
        );
        sectionSlivers.add(
          showUngroupedHeader
              ? SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabManagerStickyHeaderDelegate(
                    extent: _ungroupedHeaderHeight,
                    backgroundColor: sectionBackground,
                    child: ungroupedDropTarget,
                  ),
                )
              : SliverToBoxAdapter(child: ungroupedDropTarget),
        );
      }

      // Tabs sliver (skipped if collapsed). The ungrouped section is only
      // collapsible when a group exists (its header is shown then).
      final isCollapsed = group != null
          ? group.collapsed.value
          : (searchHandler.tabGroups.isNotEmpty && searchHandler.ungroupedCollapsed.value);
      if (!isCollapsed && sectionTabs.isNotEmpty) {
        sectionSlivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverFixedExtentList.builder(
              key: ValueKey('sliver-${group?.id ?? '__ungrouped__'}'),
              itemExtent: tabHeight,
              itemCount: sectionTabs.length,
              itemBuilder: (context, localIndex) {
                final tab = sectionTabs[localIndex];
                return _buildTabRowWidget(context, localIndex, tab);
              },
            ),
          ),
        );
      }

      widgets.add(
        DecoratedSliver(
          key: ValueKey('section-${group?.id ?? '__ungrouped__'}'),
          decoration: BoxDecoration(
            color: sectionBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          sliver: SliverMainAxisGroup(slivers: sectionSlivers),
        ),
      );
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

  Widget _buildFlatManagerBody() {
    _updateScrollMetrics();
    return Scrollbar(
      controller: scrollController,
      thickness: 8,
      interactive: true,
      scrollbarOrientation: settingsHandler.handSide.value.isLeft
          ? ScrollbarOrientation.left
          : ScrollbarOrientation.right,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverFixedExtentList.builder(
              key: const ValueKey('sliver-flat'),
              itemExtent: tabHeight,
              itemCount: filteredTabs.length,
              itemBuilder: (context, index) {
                final tab = filteredTabs[index];
                return _buildTabRowWidget(context, index, tab);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
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
          if (searchHandler.tabGroups.isNotEmpty) ...[
            IconButton(
              iconSize: 30,
              icon: Icon(showGroupedTabs ? Icons.view_list_outlined : Icons.folder_copy_outlined),
              tooltip: showGroupedTabs ? context.loc.tabs.viewAsSingleList : context.loc.tabs.viewGrouped,
              onPressed: _toggleGroupedTabs,
            ),
            const SizedBox(width: 4),
          ],
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
    final bool dragEnabled = !selectMode && !isFilterActive && sortingMode.isNone;

    final item = TabManagerItem(
      tab: tab,
      index: localIndex,
      isFiltered: isFilterActive || !sortingMode.isNone,
      originalIndex: (isFilterActive || !sortingMode.isNone) ? tabSortData[tab]?.index : null,
      isCurrent: isCurrent,
      filterText: filterTextController.text,
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
    );

    final dropTarget = _buildTabDropTarget(
      context: context,
      targetTab: tab,
      child: item,
    );

    if (!dragEnabled) {
      return KeyedSubtree(
        key: ValueKey('item-${tab.id}'),
        child: dropTarget,
      );
    }

    return _AdaptiveTabDraggable(
      key: ValueKey('item-${tab.id}'),
      tab: tab,
      originalIndex: localIndex,
      childWhenDragging: Opacity(opacity: 0.35, child: item),
      pointerPosition: _dragFeedbackPointerPosition,
      dragResultLabel: _dragResultLabel,
      onDragStarted: _startTabDrag,
      onDragUpdate: _updateTabDrag,
      onDragEnded: _endTabDrag,
      child: dropTarget,
    );
  }

  /// Picks a group (or "Ungroup", or "New group") and assigns [tab] to it.
  Future<void> _showMoveTabToGroupChooser(SearchTab tab) async {
    final currentGroupId = tab.groupId.value;
    final selection = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _TabGroupChooserSheet(
        groups: List<TabGroup>.from(searchHandler.tabGroups),
        currentGroupId: currentGroupId,
        showUngroupAction: currentGroupId != null,
        ungroupLabel: context.loc.tabs.groups.removeFromGroup,
      ),
    );

    if (!mounted || selection == null) return;
    if (selection is String) {
      searchHandler.assignTabToGroup(tab, selection);
    } else if (selection == _TabGroupChooserAction.create) {
      final newId = await showCreateTabGroupDialog(context);
      if (newId != null) searchHandler.assignTabToGroup(tab, newId);
    } else if (selection == _TabGroupChooserAction.ungroup) {
      searchHandler.assignTabToGroup(tab, null);
    }
  }

  /// Like [_showMoveTabToGroupChooser] but for a batch of tabs (select-mode).
  Future<void> _showMoveTabsToGroupChooser(List<SearchTab> selectedTabsBatch) async {
    if (selectedTabsBatch.isEmpty) return;
    final selection = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _TabGroupChooserSheet(
        groups: List<TabGroup>.from(searchHandler.tabGroups),
        currentGroupId: null,
        showUngroupAction: true,
        ungroupLabel: context.loc.tabs.groups.ungroup,
      ),
    );

    if (!mounted || selection == null) return;
    String? targetGroupId;
    if (selection is String) {
      targetGroupId = selection;
    } else if (selection == _TabGroupChooserAction.create) {
      targetGroupId = await showCreateTabGroupDialog(context);
      if (targetGroupId == null) return;
    } else if (selection != _TabGroupChooserAction.ungroup) {
      return;
    }

    searchHandler.assignTabsToGroup(selectedTabsBatch, targetGroupId);
    selectedTabs.clear();
    selectMode = false;
    getTabs();
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
              leading: const Icon(Icons.touch_app_outlined),
              text: context.loc.tabs.groups.helpDragTabHandle,
            ),
            const SizedBox(height: 6),
            helpRow(
              leading: const Icon(Icons.touch_app_outlined),
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
                final double scrollLabelDragHeight = max(0, constraints.maxHeight - 40);

                return Stack(
                  key: _dragViewportKey,
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
                      ValueListenableBuilder<int>(
                        valueListenable: _scrollbarContextRevision,
                        builder: (context, _, _) {
                          double scrollProgress = 0;
                          if (scrollController.hasClients) {
                            final position = scrollController.position;
                            if (position.hasPixels && position.hasContentDimensions && position.maxScrollExtent > 0) {
                              scrollProgress = (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0);
                            }
                          }
                          final double scrollLabelTop = scrollLabelDragHeight * scrollProgress;

                          return AnimatedPositioned(
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
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: min(280, max(40, constraints.maxWidth - 48)),
                                          ),
                                          child: Text(
                                            scrollbarContextTitle(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (!selectMode)
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
                                SettingsPageOpen(
                                  context: context,
                                  asBottomSheet: true,
                                  page: (_) => const AddNewTabDialog(),
                                ).open();
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
