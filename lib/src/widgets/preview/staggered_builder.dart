import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:lolisnatcher/src/widgets/preview/page_indicator.dart';
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
  List<_StaggeredRowItem>? _cachedRowItems;

  @override
  Widget build(BuildContext context) {
    final int columnCount = context.isPortrait ? SX.portraitColumns.value : SX.landscapeColumns.value;
    SearchHandler.instance.currentColumnCount = columnCount;

    return ValueListenableBuilder(
      valueListenable: tab.booruHandler.filteredFetched,
      builder: (context, currentFetched, child) {
        if (SX.staggeredPageBoundaries.value) {
          return SliverLayoutBuilder(
            builder: (context, constraints) {
              final itemMaxWidth =
                  max(
                    0,
                    constraints.crossAxisExtent - (_crossAxisSpacing * (columnCount - 1)),
                  ) /
                  columnCount;
              final rowItems = _rowBoundedEntriesFor(
                currentFetched: currentFetched,
                columnCount: columnCount,
                itemMaxWidth: itemMaxWidth,
              );

              return _buildWaterfallSliver(
                columnCount: columnCount,
                itemCount: rowItems.length,
                itemBuilder: (context, entryIndex) {
                  final entry = rowItems[entryIndex];
                  return _buildItem(
                    context: context,
                    currentFetched: currentFetched,
                    index: entry.index,
                    dragHitHeight: entry.rowHeight,
                  );
                },
              );
            },
          );
        }

        return _buildWaterfallSliver(
          columnCount: columnCount,
          itemCount: currentFetched.length,
          itemBuilder: (context, index) => _buildItem(
            context: context,
            currentFetched: currentFetched,
            index: index,
          ),
        );
      },
    );
  }

  Widget _buildWaterfallSliver({
    required int columnCount,
    required int itemCount,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    return SliverWaterfallFlow(
      gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        mainAxisSpacing: _mainAxisSpacing,
        crossAxisSpacing: _crossAxisSpacing,
      ),
      delegate: SliverChildBuilderDelegate(
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false, // ThumbnailCardBuild has its own RepaintBoundary
        childCount: itemCount,
        itemBuilder,
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required List<BooruItem> currentFetched,
    required int index,
    double? dragHitHeight,
  }) {
    return LayoutBuilder(
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
          final bool isHighlighted = ViewerHandler.instance.current.value?.key == item.key;
          final controller = dragSelectController;

          final thumbnail = Stack(
            children: [
              ThumbnailCardBuild(
                index: index,
                item: item,
                handler: tab.booruHandler,
                scrollController: scrollController,
                isHighlighted: isHighlighted,
                selectable: true,
                selectedIndex: isSelected ? selectedIndex : null,
                onSelected: hasSelected ? onSelected : null,
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                onLongPress: controller == null ? onLongPress : null,
                onSecondaryTap: onSecondaryTap,
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

          final tile = SizedBox(
            height: possibleHeight,
            width: possibleWidth,
            child: thumbnail,
          );

          if (controller == null) {
            return tile;
          }

          return SizedBox(
            height: dragHitHeight ?? possibleHeight,
            width: possibleWidth,
            child: ThumbnailDragSelectRegistrant(
              controller: controller,
              index: index,
              item: item,
              child: tile,
            ),
          );
        });
      },
    );
  }

  List<_StaggeredRowItem> _buildRowBoundedEntries({
    required List<BooruItem> currentFetched,
    required int columnCount,
    required double itemMaxWidth,
  }) {
    if (currentFetched.isEmpty) {
      return const [];
    }

    final rowItems = <_StaggeredRowItem>[];
    final currentRow = <_StaggeredRowItem>[];

    void flushRow() {
      if (currentRow.isEmpty) {
        return;
      }

      final rowHeight = currentRow.map((item) => item.height).reduce(max);
      for (final item in currentRow) {
        rowItems.add(item.copyWith(rowHeight: rowHeight));
      }
      currentRow.clear();
    }

    for (var index = 0; index < currentFetched.length; index++) {
      final item = currentFetched[index];

      currentRow.add(
        _StaggeredRowItem(
          index: index,
          height: _itemHeight(item, itemMaxWidth),
          rowHeight: 0,
        ),
      );

      if (currentRow.length == columnCount) {
        flushRow();
      }
    }

    flushRow();
    return rowItems;
  }

  List<_StaggeredRowItem> _rowBoundedEntriesFor({
    required List<BooruItem> currentFetched,
    required int columnCount,
    required double itemMaxWidth,
  }) {
    final firstKey = currentFetched.firstOrNull?.key;
    final lastKey = currentFetched.lastOrNull?.key;
    final cachedRowItems = _cachedRowItems;
    if (cachedRowItems != null &&
        identical(_cachedFetched, currentFetched) &&
        _cachedLength == currentFetched.length &&
        _cachedFirstKey == firstKey &&
        _cachedLastKey == lastKey &&
        _cachedColumnCount == columnCount &&
        _cachedItemMaxWidth == itemMaxWidth) {
      return cachedRowItems;
    }

    final rowItems = _buildRowBoundedEntries(
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
    _cachedRowItems = rowItems;
    return rowItems;
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

class _StaggeredRowItem {
  const _StaggeredRowItem({
    required this.index,
    required this.height,
    required this.rowHeight,
  });

  final int index;
  final double height;
  final double rowHeight;

  _StaggeredRowItem copyWith({
    double? rowHeight,
  }) {
    return _StaggeredRowItem(
      index: index,
      height: height,
      rowHeight: rowHeight ?? this.rowHeight,
    );
  }
}
