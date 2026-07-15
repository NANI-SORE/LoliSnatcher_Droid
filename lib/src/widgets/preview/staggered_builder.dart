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
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

class StaggeredBuilder extends StatelessWidget {
  const StaggeredBuilder({
    required this.tab,
    required this.scrollController,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSelected,
    super.key,
  });

  final SearchTab tab;
  final AutoScrollController scrollController;
  final void Function(int)? onTap;
  final void Function(int)? onDoubleTap;
  final void Function(int)? onLongPress;
  final void Function(int)? onSecondaryTap;
  final void Function(int)? onSelected;

  @override
  Widget build(BuildContext context) {
    final int columnCount = context.isPortrait ? SX.portraitColumns.value : SX.landscapeColumns.value;
    SearchHandler.instance.currentColumnCount = columnCount;

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
              final BooruItem item = currentFetched[index];

              final bool isFirstOfPage = index == 0 || item.fetchedPage != currentFetched[index - 1].fetchedPage;

              final double itemMaxWidth = constraints.maxWidth;
              final double itemMaxHeight = itemMaxWidth * (16 / 9);

              final double? widthData = item.fileWidth;
              final double? heightData = item.fileHeight;

              final double possibleWidth = itemMaxWidth;
              double possibleHeight = itemMaxWidth;
              final bool hasSizeData = heightData != null && widthData != null;
              if (hasSizeData) {
                final double aspectRatio = widthData / heightData;
                possibleHeight = possibleWidth / aspectRatio;
              }
              // force to use minimum 100 px and max 60% of screen height
              possibleHeight = max(min(itemMaxHeight, possibleHeight), 100);

              return SizedBox(
                key: ValueKey(item.key),
                height: possibleHeight,
                width: possibleWidth,
                child: Obx(() {
                  final bool hasSelected = tab.selected.isNotEmpty && tab.hasSelectedItems;
                  final selectedIndex = tab.selectedIndexOf(item);
                  final bool isSelected = selectedIndex != null;

                  return Stack(
                    children: [
                      SizedBox(
                        height: possibleHeight,
                        width: possibleWidth,
                        child: Obx(
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
                            onLongPress: onLongPress,
                            onSecondaryTap: onSecondaryTap,
                          ),
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
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}
