import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/thumbnail_drag_select.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

class StaggeredBuilder extends StatefulWidget {
  const StaggeredBuilder({
    required this.tab,
    required this.scrollController,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSelected,
    this.dragSelectController,
    super.key,
  });

  final SearchTab tab;
  final AutoScrollController scrollController;
  final void Function(int)? onTap;
  final void Function(int)? onDoubleTap;
  final void Function(int)? onLongPress;
  final void Function(int)? onSecondaryTap;
  final void Function(int)? onSelected;
  final ThumbnailDragSelectController? dragSelectController;

  @override
  State<StaggeredBuilder> createState() => _StaggeredBuilderState();
}

class _StaggeredBuilderState extends State<StaggeredBuilder> {
  static const double _mainAxisSpacing = 4;
  static const double _crossAxisSpacing = 4;

  SearchTab get tab => widget.tab;
  AutoScrollController get scrollController => widget.scrollController;
  void Function(int)? get onTap => widget.onTap;
  void Function(int)? get onDoubleTap => widget.onDoubleTap;
  void Function(int)? get onLongPress => widget.onLongPress;
  void Function(int)? get onSecondaryTap => widget.onSecondaryTap;
  void Function(int)? get onSelected => widget.onSelected;
  ThumbnailDragSelectController? get dragSelectController => widget.dragSelectController;

  List<BooruItem>? _cachedFetched;
  Key? _cachedFirstKey;
  Key? _cachedLastKey;
  int? _cachedLength;
  int? _cachedColumnCount;
  double? _cachedItemMaxWidth;
  List<_StaggeredRow>? _cachedRows;

  @override
  Widget build(BuildContext context) {
    final int columnCount = context.isPortrait ? SX.portraitColumns.value : SX.landscapeColumns.value;

    return ValueListenableBuilder(
      valueListenable: tab.booruHandler.filteredFetched,
      builder: (context, currentFetched, child) => SliverWaterfallFlow(
        gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        delegate: SliverChildBuilderDelegate(
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false, // ThumbnailCardBuild has its own RepaintBoundary
          childCount: currentFetched.length,
          (context, index) => LayoutBuilder(
            builder: (context, constraints) {
              return Obx(() {
                final BooruItem item = currentFetched[index];

                final bool isFirstOfPage = index == 0 || item.fetchedPage != currentFetched[index - 1].fetchedPage;

                final double itemMaxWidth = constraints.maxWidth;
                final double possibleWidth = itemMaxWidth;
                final double possibleHeight = _itemHeight(item, itemMaxWidth);

                final bool hasSelected = tab.selected.isNotEmpty && tab.hasSelectedItems;
                final selectedIndex = tab.selectedIndexOf(item);
                final bool isSelected = selectedIndex != null;

                return Stack(
                  children: [
                    SizedBox(
                      height: possibleHeight,
                      width: possibleWidth,
                      child: Obx(
                        () {
                          final controller = dragSelectController;
                          final thumbnail = ThumbnailCardBuild(
                            index: index,
                            item: item,
                            handler: tab.booruHandler,
                            scrollController: scrollController,
                            isHighlighted: ViewerHandler.instance.current.value?.key == item.key,
                            selectable: true,
                            selectedIndex: isSelected ? selectedIndex : null,
                            onSelected: hasSelected ? onSelected : null,
                            onTap: onTap,
                            onDoubleTap: onDoubleTap,
                            onLongPress: controller == null ? onLongPress : null,
                            onSecondaryTap: onSecondaryTap,
                          );

                          if (controller == null) {
                            return thumbnail;
                          }

                          return ThumbnailDragSelectRegistrant(
                            controller: controller,
                            index: index,
                            item: item,
                            child: thumbnail,
                          );
                        },
                      ),
                    ),
                    if (isFirstOfPage && item.fetchedPage > -1)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: IgnorePointer(
                          child: GridPageIndicator(item.fetchedPage),
                        ),
                      ),
                  ],
                );
              });
            },
          ),
        ),
      ),
    );
  }

  List<_StaggeredRow> _buildRowBoundedEntries({
    required List<BooruItem> currentFetched,
    required int columnCount,
    required double itemMaxWidth,
  }) {
    if (currentFetched.isEmpty) {
      return const [];
    }

    final rows = <_StaggeredRow>[];
    final currentRow = <_StaggeredRowItem>[];
    var currentPage = currentFetched.first.fetchedPage;

    void flushRow() {
      if (currentRow.isEmpty) {
        return;
      }

      rows.add(
        _StaggeredRow(
          items: List.unmodifiable(currentRow),
          height: currentRow.map((item) => item.height).reduce(max),
        ),
      );
      currentRow.clear();
    }

    for (var index = 0; index < currentFetched.length; index++) {
      final item = currentFetched[index];
      final isFirstOfPage = index == 0 || item.fetchedPage != currentPage;
      if (isFirstOfPage && index != 0) {
        flushRow();
        currentPage = item.fetchedPage;
      }

      currentRow.add(
        _StaggeredRowItem(
          index: index,
          isFirstOfPage: isFirstOfPage,
          height: _itemHeight(item, itemMaxWidth),
        ),
      );

      if (currentRow.length == columnCount) {
        flushRow();
      }
    }

    flushRow();
    return rows;
  }

  List<_StaggeredRow> _rowBoundedEntriesFor({
    required List<BooruItem> currentFetched,
    required int columnCount,
    required double itemMaxWidth,
  }) {
    final firstKey = currentFetched.firstOrNull?.key;
    final lastKey = currentFetched.lastOrNull?.key;
    final cachedRows = _cachedRows;
    if (cachedRows != null &&
        identical(_cachedFetched, currentFetched) &&
        _cachedLength == currentFetched.length &&
        _cachedFirstKey == firstKey &&
        _cachedLastKey == lastKey &&
        _cachedColumnCount == columnCount &&
        _cachedItemMaxWidth == itemMaxWidth) {
      return cachedRows;
    }

    final rows = _buildRowBoundedEntries(
      currentFetched: currentFetched,
      columnCount: columnCount,
      itemMaxWidth: itemMaxWidth,
    );
    _cachedFetched = currentFetched;
    _cachedLength = currentFetched.length;
    _cachedFirstKey = firstKey;
    _cachedLastKey = lastKey;
    _cachedColumnCount = columnCount;
    _cachedItemMaxWidth = itemMaxWidth;
    _cachedRows = rows;
    return rows;
  }

  double _itemHeight(BooruItem item, double itemMaxWidth) {
    final double itemMaxHeight = itemMaxWidth * (16 / 9);

    final double? widthData = item.fileWidth;
    final double? heightData = item.fileHeight;

    double possibleHeight = itemMaxWidth;
    final bool hasSizeData = heightData != null && widthData != null;
    if (hasSizeData) {
      final double aspectRatio = widthData / heightData;
      possibleHeight = itemMaxWidth / aspectRatio;
    }
    // force to use minimum 100 px and max 60% of screen height
    return max(min(itemMaxHeight, possibleHeight), 100);
  }
}

class _StaggeredRow {
  const _StaggeredRow({
    required this.items,
    required this.height,
  });

  final List<_StaggeredRowItem> items;
  final double height;
}

class _StaggeredRowItem {
  const _StaggeredRowItem({
    required this.index,
    required this.isFirstOfPage,
    required this.height,
  });

  final int index;
  final bool isFirstOfPage;
  final double height;
}
