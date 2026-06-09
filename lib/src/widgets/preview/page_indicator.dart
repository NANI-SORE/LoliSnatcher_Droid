import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/page_number_dialog.dart';

class GridPageIndicator extends StatelessWidget {
  const GridPageIndicator(
    this.page, {
    super.key,
  });

  final int page;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          Text(
            page.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Icon(
            Icons.insert_drive_file,
            size: 12,
          ),
        ],
      ),
    );
  }
}

class GridPageNumberOverlay extends StatefulWidget {
  const GridPageNumberOverlay({
    super.key,
  });

  @override
  State<GridPageNumberOverlay> createState() => _GridPageNumberOverlayState();
}

class _GridPageNumberOverlayState extends State<GridPageNumberOverlay> {
  final searchHandler = SearchHandler.instance;
  final settingsHandler = SettingsHandler.instance;

  Timer? overlayTimer;
  Worker? pageWorker;
  final RxBool showOverlay = false.obs;
  double pageProgress = 0;

  @override
  void initState() {
    super.initState();

    searchHandler.gridScrollController.addListener(_onPageChanged);

    pageWorker = ever(searchHandler.currentScrollPage, (_) => _onPageChanged());
  }

  void _onPageChanged() {
    if (settingsHandler.shitDevice) {
      if (pageProgress > 0 && mounted) {
        setState(() {
          pageProgress = 0;
        });
      }
    } else {
      final double nextProgress = _calculatePageProgress();
      if ((pageProgress - nextProgress).abs() > 0.001 && mounted) {
        setState(() {
          pageProgress = nextProgress;
        });
      }
    }

    showOverlay.value = true;
    overlayTimer?.cancel();
    overlayTimer = Timer(const Duration(milliseconds: 2500), () {
      showOverlay.value = false;
    });
  }

  double _calculatePageProgress() {
    final controller = searchHandler.gridScrollController;
    final currentFetched = searchHandler.currentFetched;
    final int page = searchHandler.currentScrollPage.value;

    if (!controller.hasClients || currentFetched.isEmpty || page < 0) {
      return 0;
    }

    final int pageStart = currentFetched.indexWhere((item) => item.fetchedPage == page);
    if (pageStart == -1) {
      return 0;
    }

    int pageEnd = pageStart;
    while (pageEnd < currentFetched.length && currentFetched[pageEnd].fetchedPage == page) {
      pageEnd++;
    }

    final double viewportHeight = controller.position.viewportDimension;
    final double viewportTop = controller.viewportBoundaryGetter().top;
    int? topItemIndex;
    double? topItemPosition;
    double topItemHeight = 1;

    for (final entry in controller.tagMap.entries) {
      final int index = entry.key;
      if (index < pageStart || index >= pageEnd) {
        continue;
      }

      final renderObject = entry.value.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }

      final double itemTop = renderObject.localToGlobal(Offset.zero).dy - viewportTop;
      final double itemBottom = itemTop + renderObject.size.height;
      if (itemBottom <= 0 || itemTop >= viewportHeight) {
        continue;
      }

      if (topItemPosition == null || itemTop < topItemPosition) {
        topItemIndex = index;
        topItemPosition = itemTop;
        topItemHeight = renderObject.size.height;
      }
    }

    if (topItemIndex == null || topItemPosition == null) {
      return pageProgress;
    }

    final double itemScrollProgress = (-topItemPosition / topItemHeight).clamp(0.0, 1.0);
    final int pageItemCount = pageEnd - pageStart;
    final double progressedItems = (topItemIndex - pageStart) + (itemScrollProgress * searchHandler.currentColumnCount);

    return (progressedItems / pageItemCount).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    overlayTimer?.cancel();
    pageWorker?.dispose();
    searchHandler.gridScrollController.removeListener(_onPageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final int page = searchHandler.currentScrollPage.value;
      final bool show = showOverlay.value && page > -1;

      return Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              enabled: !settingsHandler.shitDevice,
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.theme.colorScheme.surface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pageProgress,
                      child: ColoredBox(
                        color: context.theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: show
                        ? () => SettingsPageOpen(
                            context: context,
                            asBottomSheet: true,
                            page: (_) => const PageNumberDialog(),
                          ).open()
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(
                        spacing: 2,
                        children: [
                          Text(
                            page.toString(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const Icon(
                            Icons.insert_drive_file,
                            size: 14,
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 12,
                          ),
                        ],
                      ),
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
