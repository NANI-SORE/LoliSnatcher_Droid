import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
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
          _WaterfallSelectionButtons(
            animation: animation,
            showSearchBar: showSearchBar,
          ),
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

class _WaterfallSelectionButtons extends StatelessWidget {
  const _WaterfallSelectionButtons({
    required this.animation,
    required this.showSearchBar,
  });

  final Animation<double> animation;
  final bool showSearchBar;

  double get animValue => animation.value;
  double get reverseAnimValue => 1 - animValue;

  void selectAll(SearchHandler searchHandler) {
    searchHandler.currentTab.selected.assignAll(searchHandler.currentFetched);
  }

  void deselectAll(SearchHandler searchHandler) {
    searchHandler.currentTab.selected.clear();
  }

  @override
  Widget build(BuildContext context) {
    final searchHandler = SearchHandler.instance;
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Obx(() {
      final int selectedCount = searchHandler.currentSelected.length;
      final bool hasFetched = searchHandler.currentFetched.isNotEmpty;
      final bool hasSelected = selectedCount > 0;

      if (!hasFetched && !hasSelected) {
        return const SizedBox.shrink();
      }

      return AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              0,
              showSearchBar ? (MainSearchBar.height + bottomPadding) * animValue : bottomPadding * animValue,
            ),
            child: IgnorePointer(
              ignoring: animValue > 0.95,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: reverseAnimValue,
                child: child,
              ),
            ),
          );
        },
        child: Padding(
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
                    message: context.loc.selectAll,
                    child: IconButton(
                      icon: const Icon(Icons.select_all),
                      onPressed: hasFetched ? () => selectAll(searchHandler) : null,
                    ),
                  ),
                  Tooltip(
                    message: context.loc.settings.downloads.clearSelected,
                    child: IconButton(
                      icon: const Icon(Icons.deselect),
                      onPressed: hasSelected ? () => deselectAll(searchHandler) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
