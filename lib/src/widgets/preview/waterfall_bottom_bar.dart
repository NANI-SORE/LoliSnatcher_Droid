import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/dd_controller.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_bar.dart';
import 'package:lolisnatcher/src/widgets/preview/waterfall_error_buttons.dart';

// all the scroll stuff is just experiments,

// current implementation listens to MainAppBar visibility changes
// and shows/hides bottom bar as soon as it reaches starting height/leaves screen

class WaterfallBottomBar extends StatefulWidget {
  const WaterfallBottomBar({super.key});

  @override
  WaterfallBottomBarState createState() => WaterfallBottomBarState();
}

class WaterfallBottomBarState extends State<WaterfallBottomBar> with TickerProviderStateMixin {
  final SearchHandler searchHandler = SearchHandler.instance;
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late final AnimationController animationController;
  late final Animation<double> animation;

  double get animValue => animation.value;
  double get reverseAnimValue => 1 - animValue;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    animation = animationController.drive(
      Tween<double>(
        begin: 0,
        end: 1,
      ).chain(CurveTween(curve: Curves.ease)),
    );
  }

  void show() {
    if (animationController.status != AnimationStatus.reverse) {
      animationController.reverse();
    }
  }

  void hide() {
    if (animationController.status != AnimationStatus.forward) {
      animationController.forward();
    }
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    final bool showSearchBar = settingsHandler.showBottomSearchbar;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _WaterfallSelectionButtons(),
          // loading/error text, retry button (goes down with scroll, maybe shrinks to a small version for better fullscreen experience?)
          // + grid scroll buttons on the side (fixed vertical position, if present - change width of loading/error text)
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final double buttonPadding = showSearchBar
                  ? ((MediaQuery.sizeOf(context).width * 0.07) + kMinInteractiveDimension) * reverseAnimValue
                  : 0;

              return Transform.translate(
                offset: Offset(
                  0,
                  showSearchBar ? (MainSearchBar.height + bottomPadding) * animValue : bottomPadding,
                ),
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 100),
                  padding: EdgeInsets.only(
                    left: (settingsHandler.scrollGridButtonsPosition.isLeft ? buttonPadding : 0) + 10,
                    right: (settingsHandler.scrollGridButtonsPosition.isRight ? buttonPadding : 0) + 10,
                  ),
                  child: child,
                ),
              );
            },
            child: WaterfallErrorButtons(
              animation: animation,
              showSearchBar: showSearchBar,
            ),
          ),
          if (showSearchBar)
            // search bar (goes out of screen with scroll)
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return AnimatedSize(
                  duration: const Duration(milliseconds: 100),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: (12 + bottomPadding) * reverseAnimValue,
                    ),
                    child: Transform.translate(
                      offset: Offset(0, (MainSearchBar.height + bottomPadding) * 2 * animValue),
                      child: child,
                    ),
                  ),
                );
              },
              child: Container(
                height: MainSearchBar.height,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: const MainSearchBarWithActions('bottom'),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaterfallSelectionButtons extends StatefulWidget {
  const _WaterfallSelectionButtons();

  @override
  State<_WaterfallSelectionButtons> createState() => _WaterfallSelectionButtonsState();
}

class _WaterfallSelectionButtonsState extends State<_WaterfallSelectionButtons> {
  final DownloadsDrawerController downloadsController = DownloadsDrawerController();

  @override
  void dispose() {
    downloadsController.dispose();
    super.dispose();
  }

  void selectAll(SearchHandler searchHandler) {
    searchHandler.currentTab.selected.assignAll(searchHandler.currentFetched);
  }

  void deselectAll(SearchHandler searchHandler) {
    searchHandler.currentTab.selected.clear();
  }

  void showOverflowDialog(
    BuildContext context, {
    required int selectedCount,
    required int downloadsSelectedCount,
    required int favSelectedCount,
    required int unfavSelectedCount,
    required bool hasDownloadsSelected,
    required bool hasFavsSelected,
    required bool isAllSelectedFavs,
    required bool canCompareSelected,
    required bool canRefreshSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final width = MediaQuery.sizeOf(sheetContext).width;
        final maxSheetWidth = width < 720 ? width : (width * 0.62).clamp(480.0, 680.0);

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxSheetWidth),
            child: SettingsBottomSheet(
              title: Text('${context.loc.galleryButtons.select} (${selectedCount.toFormattedString()})'),
              contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              contentItems: [
                SettingsButton(
                  name: context.loc.settings.downloads.invertSelection,
                  icon: const Icon(Icons.flip_to_back),
                  action: () {
                    Navigator.of(sheetContext).pop();
                    downloadsController.invertSelection();
                  },
                  drawTopBorder: !canCompareSelected,
                ),
                SettingsButton(
                  name: context.loc.settings.downloads.copySelected,
                  icon: const Icon(Icons.copy),
                  action: () {
                    Navigator.of(sheetContext).pop();
                    downloadsController.showCopySelectedDialog(context);
                  },
                ),
                if (canCompareSelected)
                  SettingsButton(
                    name: context.loc.settings.downloads.compareSelected,
                    icon: const Icon(Icons.compare),
                    action: () {
                      Navigator.of(sheetContext).pop();
                      downloadsController.compareSelected(context);
                    },
                    drawTopBorder: true,
                  ),
                SettingsButton(
                  name: context.loc.settings.downloads.hideSelected,
                  icon: const Icon(Icons.visibility_off_outlined),
                  action: () {
                    Navigator.of(sheetContext).pop();
                    downloadsController.hideSelected();
                  },
                ),
                if (canRefreshSelected)
                  SettingsButton(
                    name: context.loc.settings.downloads.refreshSelectedMetadata,
                    icon: const Icon(Icons.refresh),
                    action: () {
                      Navigator.of(sheetContext).pop();
                      downloadsController.refreshSelectedMetadata(context);
                    },
                  ),
                if (hasDownloadsSelected)
                  SettingsButton(
                    name:
                        '${context.loc.settings.downloads.removeSnatchedStatusFromSelected} (${downloadsSelectedCount.toFormattedString()})',
                    icon: const Icon(Icons.file_download_off_outlined),
                    action: () {
                      Navigator.of(sheetContext).pop();
                      downloadsController.removeSnatchedStatusFromSelected();
                    },
                  ),
                if (!isAllSelectedFavs)
                  SettingsButton(
                    name:
                        '${context.loc.settings.downloads.favouriteSelected} (${unfavSelectedCount.toFormattedString()})',
                    icon: const Icon(Icons.favorite, color: Colors.red),
                    action: () {
                      Navigator.of(sheetContext).pop();
                      downloadsController.favouriteSelected();
                    },
                  ),
                if (hasFavsSelected)
                  SettingsButton(
                    name:
                        '${context.loc.settings.downloads.unfavouriteSelected} (${favSelectedCount.toFormattedString()})',
                    icon: const Icon(Icons.favorite_border),
                    action: () {
                      Navigator.of(sheetContext).pop();
                      downloadsController.unfavouriteSelected();
                    },
                    drawBottomBorder: false,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;

    return Obx(() {
      final selected = searchHandler.currentSelected;
      final int selectedCount = selected.length;
      final bool hasFetched = searchHandler.currentFetched.isNotEmpty;
      final bool hasSelected = selectedCount > 0;

      final bool controlsBlocked = searchHandler.selectionControlsBlocked.value;
      final int favSelectedCount = selected.where((item) => item.isFavourite.value == true).length;
      final int unfavSelectedCount = selected.where((item) => item.isFavourite.value == false).length;
      final bool hasFavsSelected = favSelectedCount > 0;
      final bool isAllSelectedFavs = selectedCount == favSelectedCount;
      final int downloadsSelectedCount = selected.where((item) => item.isSnatched.value == true).length;
      final bool hasDownloadsSelected = downloadsSelectedCount > 0;
      final bool canCompareSelected =
          selectedCount == 2 && selected.every((item) => item.mediaType.value.isImageOrAnimation);
      final bool canRefreshSelected = searchHandler.currentBooru.type?.isFavouritesOrDownloads == true;

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _selectionControlsTransition,
        child: hasSelected
            ? Padding(
                key: const ValueKey('selection-controls-visible'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message:
                              '${context.loc.settings.downloads.snatchSelected} (${selectedCount.toFormattedString()})',
                          child: GestureDetector(
                            onLongPress: controlsBlocked
                                ? null
                                : () => downloadsController.onStartSnatching(context, true),
                            child: IconButton(
                              icon: const Icon(Icons.download_sharp),
                              onPressed: controlsBlocked
                                  ? null
                                  : () => downloadsController.onStartSnatching(context, false),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: '${context.loc.galleryButtons.share} (${selectedCount.toFormattedString()})',
                          child: GestureDetector(
                            onLongPress: controlsBlocked
                                ? null
                                : () => downloadsController.onShareSelectedLongPress(context),
                            child: IconButton(
                              icon: const Icon(Icons.share),
                              onPressed: controlsBlocked ? null : () => downloadsController.onShareSelected(context),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: context.loc.selectAll,
                          child: IconButton(
                            icon: const Icon(Icons.select_all),
                            onPressed: hasFetched && !controlsBlocked ? () => selectAll(searchHandler) : null,
                          ),
                        ),
                        Tooltip(
                          message: context.loc.settings.downloads.clearSelected,
                          child: IconButton(
                            icon: const Icon(Icons.deselect),
                            onPressed: !controlsBlocked ? () => deselectAll(searchHandler) : null,
                          ),
                        ),
                        Tooltip(
                          message: context.loc.searchBar.more,
                          child: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: controlsBlocked
                                ? null
                                : () => showOverflowDialog(
                                    context,
                                    selectedCount: selectedCount,
                                    downloadsSelectedCount: downloadsSelectedCount,
                                    favSelectedCount: favSelectedCount,
                                    unfavSelectedCount: unfavSelectedCount,
                                    hasDownloadsSelected: hasDownloadsSelected,
                                    hasFavsSelected: hasFavsSelected,
                                    isAllSelectedFavs: isAllSelectedFavs,
                                    canCompareSelected: canCompareSelected,
                                    canRefreshSelected: canRefreshSelected,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('selection-controls-hidden')),
      );
    });
  }

  Widget _selectionControlsTransition(Widget child, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}
