import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/page_number_dialog.dart';

class PageItemRange {
  const PageItemRange(this.start, this.end);

  final int start;
  final int end;
}

class PageRangeIndex {
  final Map<int, PageItemRange> _ranges = {};
  int _processedLength = 0;
  BooruItem? _lastProcessedItem;
  List<BooruItem>? _items;
  int? _lastProcessedPage;
  int lastUpdateProcessedItems = 0;

  PageItemRange? operator [](int page) => _ranges[page];

  void clear() {
    _ranges.clear();
    _processedLength = 0;
    _lastProcessedItem = null;
    _items = null;
    _lastProcessedPage = null;
    lastUpdateProcessedItems = 0;
  }

  void update(List<BooruItem> items) {
    lastUpdateProcessedItems = 0;
    final bool canAppend =
        _processedLength < items.length &&
        (_processedLength == 0 ||
            (identical(items, _items) &&
                identical(items[_processedLength - 1], _lastProcessedItem) &&
                items[_processedLength - 1].fetchedPage == _lastProcessedPage));

    if (!canAppend) {
      _ranges.clear();
      _processedLength = 0;
      _lastProcessedItem = null;
    }

    for (int index = _processedLength; index < items.length; index++) {
      lastUpdateProcessedItems++;
      final int page = items[index].fetchedPage;
      if (page >= 0) {
        final previous = _ranges[page];
        _ranges[page] = PageItemRange(previous?.start ?? index, index + 1);
      }
    }

    _processedLength = items.length;
    _lastProcessedItem = items.isEmpty ? null : items.last;
    _items = items;
    _lastProcessedPage = _lastProcessedItem?.fetchedPage;
  }
}

class GridPageIndicator extends StatelessWidget {
  const GridPageIndicator(
    this.page, {
    required this.tab,
    super.key,
  });

  final int page;
  final SearchTab tab;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        enabled: !SX.shitDevice.value,
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.theme.colorScheme.surface.withValues(alpha: 0.5),
            border: Border.all(
              color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: .min,
            spacing: 1,
            children: [
              Text(
                tab.displayPage(page).toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(
                Icons.bookmark_border,
                size: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
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
  RxList<BooruItem>? observedItems;
  final RxBool showOverlay = false.obs;
  final PageRangeIndex pageRanges = PageRangeIndex();
  final RxDouble pageProgress = 0.0.obs;
  late final AutoScrollController _scrollController;
  int? _progressPage;

  @override
  void initState() {
    super.initState();

    _scrollController = searchHandler.gridScrollController;
    _scrollController.addListener(_onPageChanged);
    searchHandler.index.addListener(_observeCurrentItems);
    searchHandler.tabId.addListener(_observeCurrentItems);
    _observeCurrentItems();

    pageWorker = ever(searchHandler.currentScrollPage, (_) => _onPageChanged());
  }

  void _observeCurrentItems() {
    observedItems?.removeListener(_onItemsChanged);
    observedItems = searchHandler.currentFetchedOrNull;
    observedItems?.addListener(_onItemsChanged);
    pageRanges
      ..clear()
      ..update(observedItems?.value ?? const []);
    _progressPage = null;
    pageProgress.value = 0;
    showOverlay.value = false;
    overlayTimer?.cancel();
  }

  void _onItemsChanged() {
    pageRanges.update(observedItems?.value ?? const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onPageChanged();
    });
  }

  double _normalizeProgress(double value) {
    if (!value.isFinite || value <= 0) {
      return 0;
    }
    if (value >= 1) {
      return 1;
    }
    return value;
  }

  void _onPageChanged() {
    if (!mounted) return;
    if (searchHandler.currentTabOrNull == null || observedItems?.isNotEmpty != true) {
      showOverlay.value = false;
      pageProgress.value = 0;
      overlayTimer?.cancel();
      return;
    }
    final page = searchHandler.currentScrollPage.value;
    if (_progressPage != page) {
      _progressPage = page;
      pageProgress.value = 0;
    }
    if (SX.shitDevice.value) {
      if (pageProgress.value > 0 && mounted) {
        pageProgress.value = 0;
      }
    } else {
      final double nextProgress = _normalizeProgress(_calculatePageProgress());
      if ((pageProgress.value - nextProgress).abs() > 0.001 && mounted) {
        pageProgress.value = nextProgress;
      }
    }

    showOverlay.value = true;
    overlayTimer?.cancel();
    overlayTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) showOverlay.value = false;
    });
  }

  double _calculatePageProgress() {
    final controller = _scrollController;
    final currentFetched = searchHandler.currentFetchedOrNull;
    final int page = searchHandler.currentScrollPage.value;

    if (!controller.hasClients || currentFetched == null || currentFetched.isEmpty || page < 0 || SX.shitDevice.value) {
      return 0;
    }

    final pageRange = pageRanges[page];
    if (pageRange == null) {
      return 0;
    }

    final int pageStart = pageRange.start;
    final int pageEnd = pageRange.end;

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

      if (!entry.value.mounted) continue;
      final renderObject = entry.value.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
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

    if (topItemIndex == null || topItemPosition == null || topItemHeight <= precisionErrorTolerance) {
      if (pageEnd == currentFetched.length && controller.position.extentAfter <= precisionErrorTolerance) {
        return 1;
      }
      return _normalizeProgress(pageProgress.value);
    }

    final double itemScrollProgress = (-topItemPosition / topItemHeight).clamp(0.0, 1.0);
    final int pageItemCount = pageEnd - pageStart;
    final double progressedItems = max(
      0,
      (topItemIndex - pageStart) + (itemScrollProgress * searchHandler.currentColumnCount),
    );

    if (pageEnd == currentFetched.length) {
      final double remainingItems =
          (max(0, controller.position.extentAfter) / topItemHeight) * searchHandler.currentColumnCount;
      final double reachableItems = progressedItems + remainingItems;

      if (reachableItems <= precisionErrorTolerance) {
        return 1;
      }

      return _normalizeProgress(progressedItems / reachableItems);
    }

    return _normalizeProgress(progressedItems / pageItemCount);
  }

  @override
  void dispose() {
    overlayTimer?.cancel();
    pageWorker?.dispose();
    observedItems?.removeListener(_onItemsChanged);
    searchHandler.index.removeListener(_observeCurrentItems);
    searchHandler.tabId.removeListener(_observeCurrentItems);
    _scrollController.removeListener(_onPageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tab = searchHandler.currentTabOrNull;
      if (tab == null) return const SizedBox.shrink();
      final int page = searchHandler.currentScrollPage.value;
      final bool show = showOverlay.value && page >= tab.firstPage;

      return Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !show,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                enabled: !SX.shitDevice.value,
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
                      child: Obx(
                        () => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: pageProgress.value,
                          child: ColoredBox(
                            color: context.theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                          ),
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
                          mainAxisSize: .min,
                          spacing: 2,
                          crossAxisAlignment: .center,
                          children: [
                            Text(
                              tab.displayPage(page).toString(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Obx(
                              () => Icon(
                                tab.savePageEnabled.value ? Icons.bookmark : Icons.bookmark_border,
                                size: 16,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
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
        ),
      );
    });
  }
}
