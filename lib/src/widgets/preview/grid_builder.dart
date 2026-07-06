import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/widgets/preview/thumbnail_drag_select.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

class GridBuilder extends StatelessWidget {
  const GridBuilder({
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
  Widget build(BuildContext context) {
    final previewDisplay = (SX.previewDisplay.value.isStaggered && !tab.booruHandler.hasSizeData)
        ? SX.previewDisplayFallback.value
        : SX.previewDisplay.value;

    final int columnCount = context.isPortrait ? SX.portraitColumns.value : SX.landscapeColumns.value;

    return ValueListenableBuilder(
      valueListenable: tab.booruHandler.filteredFetched,
      builder: (context, currentFetched, child) => SliverGrid.builder(
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false, // ThumbnailCardBuild has its own RepaintBoundary
        itemCount: currentFetched.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          childAspectRatio: previewDisplay.isSquare ? 1 : 9 / 16,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemBuilder: (BuildContext context, int index) {
          return GridTile(
            child: Obx(() {
              final BooruItem item = currentFetched[index];

              final bool hasSelected = tab.selected.isNotEmpty && tab.hasSelectedItems;
              final selectedIndex = tab.selectedIndexOf(item);
              final bool isSelected = selectedIndex != null;
              final bool isHighlighted = ViewerHandler.instance.current.value?.key == item.key;
              final controller = dragSelectController;

              final thumbnail = ThumbnailCardBuild(
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
            }),
          );
        },
      ),
    );
  }
}
