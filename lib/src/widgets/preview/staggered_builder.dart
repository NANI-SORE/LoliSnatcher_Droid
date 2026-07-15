import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:waterfall_flow/waterfall_flow.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/page_indicator.dart';
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
  double? _cachedItemMaxHeight;
  List<_StaggeredRow>? _cachedRows;

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
              final itemMaxHeight = MediaQuery.sizeOf(context).height * 0.4;
              final rows = _rowBoundedEntriesFor(
                currentFetched: currentFetched,
                columnCount: columnCount,
                itemMaxWidth: itemMaxWidth,
                itemMaxHeight: itemMaxHeight,
              );

              return SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, rowIndex) => _buildRow(
                  context: context,
                  currentFetched: currentFetched,
                  row: rows[rowIndex],
                  itemMaxWidth: itemMaxWidth,
                  isLastRow: rowIndex == rows.length - 1,
                ),
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
            isFirstOfPage: index == 0 || currentFetched[index].fetchedPage != currentFetched[index - 1].fetchedPage,
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
    required bool isFirstOfPage,
    double? dragHitHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Obx(
          () {
            final BooruItem item = currentFetched[index];

            final double itemMaxWidth = constraints.maxWidth;
            final double itemMaxHeight = MediaQuery.sizeOf(context).height * 0.4;
            final double possibleWidth = itemMaxWidth;
            final double possibleHeight = _itemHeight(
              item: item,
              itemMaxWidth: itemMaxWidth,
              itemMaxHeight: itemMaxHeight,
            );

            return SizedBox(
              key: ValueKey(item.key),
              height: possibleHeight,
              width: possibleWidth,
              child: Obx(() {
                final bool hasSelected = tab.selected.isNotEmpty && tab.hasSelectedItems;
                final selectedIndex = tab.selectedIndexOf(item);
                final bool isSelected = selectedIndex != null;

                final controller = dragSelectController;
                final thumbnail = Obx(
                  () => ThumbnailCardBuild(
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
                  ),
                );
                final tile = Stack(
                  children: [
                    SizedBox(
                      height: possibleHeight,
                      width: possibleWidth,
                      child: thumbnail,
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
              }),
            );
          },
        );
      },
    );
  }

  Widget _buildRow({
    required BuildContext context,
    required List<BooruItem> currentFetched,
    required _StaggeredRow row,
    required double itemMaxWidth,
    required bool isLastRow,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLastRow ? 0 : _mainAxisSpacing),
      child: SizedBox(
        height: row.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var slot = 0; slot < row.items.length; slot++) ...[
              if (slot != 0) const SizedBox(width: _crossAxisSpacing),
              SizedBox(
                width: itemMaxWidth,
                child: _buildItem(
                  context: context,
                  currentFetched: currentFetched,
                  index: row.items[slot].index,
                  isFirstOfPage: row.items[slot].isFirstOfPage,
                  dragHitHeight: row.height,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_StaggeredRow> _buildRowBoundedEntries({
    required List<BooruItem> currentFetched,
    required int columnCount,
    required double itemMaxWidth,
    required double itemMaxHeight,
  }) {
    if (currentFetched.isEmpty) {
      return const [];
    }

    final rows = <_StaggeredRow>[];
    final currentRow = <_StaggeredRowItem>[];

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
      final isFirstOfPage = index == 0 || item.fetchedPage != currentFetched[index - 1].fetchedPage;

      currentRow.add(
        _StaggeredRowItem(
          index: index,
          isFirstOfPage: isFirstOfPage,
          height: _itemHeight(
            item: item,
            itemMaxWidth: itemMaxWidth,
            itemMaxHeight: itemMaxHeight,
          ),
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
    required double itemMaxHeight,
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
        _cachedItemMaxWidth == itemMaxWidth &&
        _cachedItemMaxHeight == itemMaxHeight) {
      return cachedRows;
    }

    final rows = _buildRowBoundedEntries(
      currentFetched: currentFetched,
      columnCount: columnCount,
      itemMaxWidth: itemMaxWidth,
      itemMaxHeight: itemMaxHeight,
    );
    _cachedFetched = currentFetched;
    _cachedLength = currentFetched.length;
    _cachedFirstKey = firstKey;
    _cachedLastKey = lastKey;
    _cachedColumnCount = columnCount;
    _cachedItemMaxWidth = itemMaxWidth;
    _cachedItemMaxHeight = itemMaxHeight;
    _cachedRows = rows;
    return rows;
  }

  double _itemHeight({
    required BooruItem item,
    required double itemMaxWidth,
    required double itemMaxHeight,
  }) {
    final widthData = item.fileWidth ?? item.sampleWidth ?? item.previewWidth;
    final heightData = item.fileHeight ?? item.sampleHeight ?? item.previewHeight;

    double possibleHeight = itemMaxWidth;
    final hasSizeData = heightData != null && widthData != null && widthData > 0 && heightData > 0;
    if (hasSizeData) {
      possibleHeight = itemMaxWidth * (heightData / widthData);
    }

    final itemMinHeight = min(150, itemMaxHeight);
    return possibleHeight.clamp(itemMinHeight, itemMaxHeight).toDouble();
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
