import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:get/get.dart' hide ContextExt;
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/long_press_repeater.dart';
import 'package:lolisnatcher/src/widgets/preview/grid_builder.dart';
import 'package:lolisnatcher/src/widgets/preview/page_indicator.dart';
import 'package:lolisnatcher/src/widgets/preview/shimmer_builder.dart';
import 'package:lolisnatcher/src/widgets/preview/staggered_builder.dart';
import 'package:lolisnatcher/src/widgets/preview/thumbnail_drag_select.dart';
import 'package:lolisnatcher/src/widgets/preview/waterfall_bottom_bar.dart';
import 'package:lolisnatcher/src/widgets/preview/waterfall_scroll_controller.dart';
import 'package:lolisnatcher/src/widgets/root/main_appbar.dart';

class WaterfallView extends StatefulWidget {
  const WaterfallView({super.key});

  @override
  State<WaterfallView> createState() => _WaterfallViewState();
}

class _WaterfallViewState extends State<WaterfallView> with RouteAware {
  static const int _floatingBarsDirectionDebounceMs = 120;

  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;
  final NavigationHandler navigationHandler = NavigationHandler.instance;

  StreamSubscription? volumeListener;
  bool scrollDone = true;

  Orientation currentOrientation = Orientation.portrait;
  // Nested viewers replace ViewerHandler.current, so retain the page shown by
  // the root gallery for scroll restoration while they are open.
  int? _rootViewerIndex;

  bool isStaggered = false;

  bool get isMobile => SX.appMode.value.isMobile;

  final ValueNotifier<bool> isActive = ValueNotifier(true);
  ScrollDirection _lastFloatingBarsDirection = ScrollDirection.idle;
  ScrollDirection _pendingFloatingBarsDirection = ScrollDirection.idle;
  int _lastFloatingBarsDirectionChangedAt = 0;

  Timer? viewedItemCleanupTimer;
  int viewedItemCleanupCount = 0;
  final Set<BooruItem> viewedItems = {};

  final ThumbnailDragSelectController dragSelectController = ThumbnailDragSelectController();
  final GlobalKey dragSelectViewportKey = GlobalKey(debugLabel: 'drag-select-viewport');
  Timer? dragAutoScrollTimer;
  Timer? dragControlsUnblockTimer;
  Offset? latestDragGlobalPosition;
  bool isDragSelecting = false;
  double dragAutoScrollDelta = 0;
  int? dragAnchorIndex;
  int? dragCurrentHitIndex;
  bool? dragSelectAdds;
  final List<BooruItem> dragInitialSelectedItems = [];
  final Set<BooruItem> dragInitialSelectedSet = Set<BooruItem>.identity();
  final Set<BooruItem> dragCurrentRangeItems = Set<BooruItem>.identity();
  final Map<int, Offset> pinchPointerPositions = {};
  bool isPinchResizing = false;
  double pinchStartDistance = 0;
  int pinchStartColumns = 0;
  int pinchLastColumns = 0;
  _GridResizeAnchor? pinchResizeAnchor;
  bool pinchStepApplied = false;

  @override
  void initState() {
    super.initState();

    // listen to current tab change to restore the scroll value
    searchHandler.index.addListener(tabIndexListener);

    searchHandler.tabId.addListener(tabIdListener);

    // listen to isLoading to select first loaded item for desktop
    searchHandler.isLoading.addListener(isLoadingListener);

    setVolumeListener();
    // reset the volume butons state
    ServiceHandler.setVolumeButtons(!SX.useVolumeButtonsForScroll.value);
    // tabChanged(0);
    // TODO reset the controller when appMode changes
    searchHandler.gridScrollController = WaterfallScrollController(
      initialScrollOffset: searchHandler.currentTabOrNull?.scrollPosition ?? 0,
      viewportBoundaryGetter: () => Rect.fromLTRB(
        0,
        isMobile ? (MediaQuery.paddingOf(context).top + kToolbarHeight + 4) : 0,
        0,
        MediaQuery.paddingOf(context).bottom,
      ),
    );

    isStaggered =
        SX.previewDisplay.value.isStaggered && (searchHandler.currentBooruHandlerOrNull?.hasSizeData ?? false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    NavigationHandler.instance.routeObserver.subscribe(
      this,
      ModalRoute.of(context)! as PageRoute,
    );
  }

  @override
  void didPushNext() {
    isActive.value = false;
  }

  @override
  void didPush() {
    isActive.value = true;
  }

  @override
  void didPopNext() {
    isActive.value = true;
  }

  void tabIdListener() {
    if (searchHandler.tabId.value != null) {
      tabIndexListener();
    }
  }

  void tabIndexListener() {
    // print('tabChanged: ${searchHandler.currentTabOrNull?.scrollPosition} ${searchHandler.gridScrollController.hasClients}');

    // postpone scroll updates until the current render is done, since this is called after the global restate after exiting settings
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final currentTab = searchHandler.currentTabOrNull;
      if (currentTab == null) {
        return;
      }

      // restore scroll position on tab change
      if (searchHandler.gridScrollController.hasClients) {
        searchHandler.gridScrollController.jumpTo(currentTab.scrollPosition);
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted || !searchHandler.gridScrollController.hasClients) return;
        // workaround to force update scrollPage
        searchHandler.gridScrollController.jumpTo(searchHandler.gridScrollController.position.pixels + 1);
      } else {
        // if (currentTab.scrollPosition != 0) {
        // TODO reset the controller when appMode changes
        searchHandler.gridScrollController = WaterfallScrollController(
          initialScrollOffset: currentTab.scrollPosition,
          viewportBoundaryGetter: () => Rect.fromLTRB(
            0,
            isMobile ? (MediaQuery.paddingOf(context).top + kToolbarHeight + 4) : 0,
            0,
            MediaQuery.paddingOf(context).bottom,
          ),
        );
      }

      _showFloatingBars();
    });

    // check if grid type changed when changing tab
    final bool newIsStaggered =
        SX.previewDisplay.value.isStaggered && (searchHandler.currentBooruHandlerOrNull?.hasSizeData ?? false);
    if (isStaggered != newIsStaggered) {
      isStaggered = newIsStaggered;
      setState(() {});
    }
  }

  void isLoadingListener() {
    if (!searchHandler.isLoading.value) {
      afterSearch();
    }
  }

  void setVolumeListener() {
    volumeListener?.cancel();
    volumeListener = searchHandler.volumeStream?.listen(volumeCallback);
  }

  Future<void> volumeCallback(String event) async {
    if (isActive.value) {
      int dir = 0;
      if (event == 'up') {
        dir = -1;
      } else if (event == 'down') {
        dir = 1;
      }

      if (dir != 0 && scrollDone == true) {
        scrollDone = false;
        final double offset = max(
          searchHandler.gridScrollController.offset + (SX.volumeButtonsScrollSpeed.value * dir),
          -20,
        );
        await searchHandler.gridScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        );
        scrollDone = true;
      }
    }
  }

  @override
  void dispose() {
    viewedItemCleanupTimer?.cancel();
    stopDragAutoScroll();
    dragControlsUnblockTimer?.cancel();
    searchHandler.selectionControlsBlocked.value = false;
    NavigationHandler.instance.routeObserver.unsubscribe(this);
    searchHandler.index.removeListener(tabIndexListener);
    searchHandler.tabId.removeListener(tabIdListener);
    searchHandler.isLoading.removeListener(isLoadingListener);
    volumeListener?.cancel();
    ServiceHandler.setVolumeButtons(true);
    super.dispose();
  }

  void jumpTo(int newIndex) {
    if (!searchHandler.gridScrollController.hasClients || newIndex == -1 || (isActive.value && isMobile)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (newIndex == 0) {
        searchHandler.gridScrollController.jumpTo(0);
      } else {
        searchHandler.gridScrollController.scrollToIndex(
          newIndex,
          duration: Duration(milliseconds: isMobile ? 10 : 100),
          preferPosition: AutoScrollPosition.begin,
        );
      }
    });
  }

  void afterSearch() {
    if (isMobile) {
      return;
    }

    final currentFetched = searchHandler.currentFetchedOrNull;
    if (viewerHandler.current.value == null &&
        currentFetched != null &&
        currentFetched.isNotEmpty &&
        currentFetched.length < (SX.limit.value + 1)) {
      viewerHandler.setCurrent(currentFetched.first);
    }
  }

  void syncFloatingBarsWithScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        !searchHandler.gridScrollController.hasClients) {
      return;
    }

    if (_isAtScrollStart(notification.metrics)) {
      _showFloatingBars();
      return;
    }

    final controller = searchHandler.gridScrollController;
    if (!isActive.value || controller.isAutoScrolling) {
      return;
    }

    // Driven user paging has an idle (or interrupted drag's stale) direction.
    // Only use its deltas; jumps, layout corrections and ballistic bounce-back
    // must not be interpreted as a new user direction.
    if (controller is WaterfallScrollController && controller.isPaging) {
      final delta = notification is ScrollUpdateNotification ? notification.scrollDelta : null;
      if (delta != null && delta != 0) {
        _updateFloatingBars(delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward, debounce: false);
      }
    } else {
      _updateFloatingBars(controller.position.userScrollDirection);
    }
  }

  void _updateFloatingBars(
    ScrollDirection direction, {
    bool debounce = true,
  }) {
    if (direction == ScrollDirection.idle) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final directionChanged = _lastFloatingBarsDirection != direction;
    if (debounce && directionChanged && now - _lastFloatingBarsDirectionChangedAt < _floatingBarsDirectionDebounceMs) {
      _pendingFloatingBarsDirection = direction;
      return;
    }

    _pendingFloatingBarsDirection = ScrollDirection.idle;
    _lastFloatingBarsDirection = direction;
    if (directionChanged) {
      _lastFloatingBarsDirectionChangedAt = now;
    }
    navigationHandler.floatingHeaderKey.currentState?.handleUserScrollDirection(direction);
  }

  bool _isAtScrollStart(ScrollMetrics metrics) {
    return metrics.pixels <= metrics.minScrollExtent + 0.5;
  }

  void _showFloatingBars() {
    _pendingFloatingBarsDirection = ScrollDirection.idle;
    if (_lastFloatingBarsDirection != ScrollDirection.forward) {
      _lastFloatingBarsDirectionChangedAt = DateTime.now().millisecondsSinceEpoch;
    }
    _lastFloatingBarsDirection = ScrollDirection.forward;
    navigationHandler.floatingHeaderKey.currentState?.show();
  }

  void settleFloatingBarsAfterScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return;
    }

    if (_isAtScrollStart(notification.metrics)) {
      _showFloatingBars();
      final controller = searchHandler.gridScrollController;
      // jumpTo emits scroll-end while already idle; show() has snapped it.
      if (!controller.hasClients || !controller.position.isScrollingNotifier.value) {
        return;
      }
    } else if (_pendingFloatingBarsDirection != ScrollDirection.idle) {
      // A short reversal may end before the debounce window expires.
      _updateFloatingBars(_pendingFloatingBarsDirection, debounce: false);
    }

    navigationHandler.floatingHeaderKey.currentState?.settleUserScrollDirection();
  }

  void viewerCallback() {
    // do cleanup after a delay to avoid animation stutter when leaving the viewer (especially when there are thousands of items)
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final item in viewedItems) {
        if (item.toggleQuality.value) {
          item.toggleQuality.value = false;
        }
      }
      viewedItems.clear();
    });
  }

  void onViewerPageChanged(int index) {
    _rootViewerIndex = index;

    final currentFetched = searchHandler.currentFetchedOrNull;
    if (currentFetched == null || index >= currentFetched.length) return;
    viewedItems.add(currentFetched[index]);
    if (isMobile) {
      jumpTo(index);
    } else {
      // don't auto scroll on viewed index change on desktop
      // call jumpTo only when viewed item is possibly out of view (i.e. selected by arrow keys)
    }
  }

  Future<void> onTap(int index) async {
    if (isMobile) {
      // protection from opening multiple viewers at once
      if (!isActive.value) {
        return;
      }

      viewedItemCleanupTimer?.cancel();
      viewedItemCleanupCount = 0;
      final currentFetched = searchHandler.currentFetchedOrNull;
      final currentTab = searchHandler.currentTabOrNull;
      if (currentFetched == null || currentTab == null || index >= currentFetched.length) return;

      viewedItems
        ..clear()
        ..add(currentFetched[index]);
      viewerHandler.setCurrent(currentFetched[index]);

      isActive.value = false;
      viewerHandler.showNotes.value = !SX.hideNotes.value;
      _rootViewerIndex = index;

      final viewerKey = GlobalKey(debugLabel: 'viewer-main');
      ViewerHandler.instance.addViewer(viewerKey);
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => GalleryViewPage(
            key: viewerKey,
            tab: currentTab,
            initialIndex: index,
            onPageChanged: onViewerPageChanged,
          ),
          opaque: false,
          transitionDuration: const Duration(milliseconds: 300),
          barrierColor: Colors.black26,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return const ZoomPageTransitionsBuilder().buildTransitions(
              MaterialPageRoute(
                builder: (_) => const SizedBox.shrink(),
              ), // is not used anywhere, but function requires it to get allowSnapshotting from it
              context,
              animation,
              secondaryAnimation,
              child,
            );
          },
        ),
      );

      _rootViewerIndex = null;
      viewerHandler.dropCurrent();

      viewedItemCleanupTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) {
          // workaround to forcefully clear the viewed item if it got set after we left the viewer (i.e. check after favouriting)
          if (viewerHandler.current.value != null) {
            viewerHandler.dropCurrent();
          }

          // run for 5s with 200ms interval
          if (viewedItemCleanupCount < 25) {
            viewedItemCleanupCount++;
          } else {
            viewedItemCleanupTimer?.cancel();
          }
        },
      );

      isActive.value = true;

      // reset notes to default state, defined in settings
      viewerHandler.showNotes.value = !SX.hideNotes.value;

      viewerCallback();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showFloatingBars();
      });
    } else {
      final currentFetched = searchHandler.currentFetchedOrNull;
      if (currentFetched == null || index >= currentFetched.length) return;
      viewerHandler.setCurrent(currentFetched[index]);
    }
  }

  Future<void> onDoubleTap(int index) async {
    await searchHandler.currentTabOrNull?.toggleItemFavourite(index);
  }

  Future<void> onLongPress(int index) async {
    final currentFetched = searchHandler.currentFetchedOrNull;
    final currentTab = searchHandler.currentTabOrNull;
    final currentSelected = searchHandler.currentSelectedOrNull;
    if (currentFetched == null || currentTab == null || currentSelected == null || index >= currentFetched.length) {
      return;
    }

    final BooruItem item = currentFetched[index];

    if (currentSelected.contains(item)) {
      currentTab.selected.remove(item);
    } else {
      currentTab.selected.add(item);
    }
  }

  Future<void> onDragSelectStart(LongPressStartDetails details) async {
    if (isPinchResizing || pinchPointerPositions.length >= 2) {
      return;
    }

    dragControlsUnblockTimer?.cancel();
    searchHandler.selectionControlsBlocked.value = true;
    isDragSelecting = true;
    latestDragGlobalPosition = details.globalPosition;
    dragAnchorIndex = null;
    dragCurrentHitIndex = null;
    dragSelectAdds = null;
    dragInitialSelectedItems
      ..clear()
      ..addAll(searchHandler.currentSelected);
    dragInitialSelectedSet
      ..clear()
      ..addAll(dragInitialSelectedItems);
    dragCurrentRangeItems.clear();

    final hit = dragSelectController.hitTest(
      details.globalPosition,
      lastIndex: searchHandler.currentFetched.length - 1,
    );
    if (hit == null) {
      endDragSelection();
      return;
    }

    dragAnchorIndex = hit.index;
    dragSelectAdds = !dragInitialSelectedSet.contains(hit.item);
    applyDragSelectionRange(hit.index);
    updateDragAutoScroll();
  }

  void onDragSelectMove(LongPressMoveUpdateDetails details) {
    if (!isDragSelecting) {
      return;
    }

    latestDragGlobalPosition = details.globalPosition;
    applyDragSelectionRangeAt(details.globalPosition);
    updateDragAutoScroll();
  }

  void applyDragSelectionRangeAt(Offset globalPosition) {
    final anchorIndex = dragAnchorIndex;
    if (anchorIndex == null) {
      return;
    }

    final hit = dragSelectController.hitTest(
      globalPosition,
      lastIndex: searchHandler.currentFetched.length - 1,
    );
    if (hit == null) {
      return;
    }

    applyDragSelectionRange(hit.index);
  }

  void applyDragSelectionRange(int hitIndex) {
    final anchorIndex = dragAnchorIndex;
    final selectAdds = dragSelectAdds;
    if (anchorIndex == null || selectAdds == null) {
      return;
    }
    if (dragCurrentHitIndex == hitIndex) {
      return;
    }

    final currentFetched = searchHandler.currentFetched;
    if (currentFetched.isEmpty) {
      return;
    }

    final startIndex = min(anchorIndex, hitIndex).clamp(0, currentFetched.length - 1);
    final endIndex = max(anchorIndex, hitIndex).clamp(0, currentFetched.length - 1);
    final nextRangeList = <BooruItem>[];
    final nextRangeItems = Set<BooruItem>.identity();

    if (hitIndex >= anchorIndex) {
      for (int i = startIndex; i <= endIndex; i++) {
        nextRangeList.add(currentFetched[i]);
      }
    } else {
      for (int i = endIndex; i >= startIndex; i--) {
        nextRangeList.add(currentFetched[i]);
      }
    }

    nextRangeItems.addAll(nextRangeList);

    final selectedAfterDrag = <BooruItem>[];
    final selectedAfterDragSet = Set<BooruItem>.identity();

    if (selectAdds) {
      for (final item in dragInitialSelectedItems) {
        if (selectedAfterDragSet.add(item)) {
          selectedAfterDrag.add(item);
        }
      }

      for (final item in nextRangeList) {
        if (!dragInitialSelectedSet.contains(item) && selectedAfterDragSet.add(item)) {
          selectedAfterDrag.add(item);
        }
      }
    } else {
      for (final item in dragInitialSelectedItems) {
        if (!nextRangeItems.contains(item) && selectedAfterDragSet.add(item)) {
          selectedAfterDrag.add(item);
        }
      }
    }

    searchHandler.currentTab.selected.assignAll(selectedAfterDrag);
    dragCurrentHitIndex = hitIndex;
    dragCurrentRangeItems
      ..clear()
      ..addAll(nextRangeItems);
  }

  void updateDragAutoScroll() {
    final globalPosition = latestDragGlobalPosition;
    final viewportContext = dragSelectViewportKey.currentContext;
    if (!isDragSelecting || globalPosition == null || viewportContext == null) {
      stopDragAutoScroll();
      return;
    }

    final renderObject = viewportContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || !searchHandler.gridScrollController.hasClients) {
      stopDragAutoScroll();
      return;
    }

    final localPosition = renderObject.globalToLocal(globalPosition);
    final double edgeSize = min(220, max(128, renderObject.size.height * 0.18));
    const double maxDelta = 24;

    if (localPosition.dy < edgeSize) {
      dragAutoScrollDelta = -maxDelta * ((edgeSize - localPosition.dy) / edgeSize).clamp(0, 1);
    } else if (localPosition.dy > renderObject.size.height - edgeSize) {
      dragAutoScrollDelta =
          maxDelta * ((localPosition.dy - (renderObject.size.height - edgeSize)) / edgeSize).clamp(0, 1);
    } else {
      dragAutoScrollDelta = 0;
    }

    if (dragAutoScrollDelta == 0) {
      stopDragAutoScroll();
      return;
    }

    dragAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => dragAutoScrollTick(),
    );
  }

  void dragAutoScrollTick() {
    final globalPosition = latestDragGlobalPosition;
    if (!isDragSelecting ||
        globalPosition == null ||
        dragAutoScrollDelta == 0 ||
        !searchHandler.gridScrollController.hasClients) {
      stopDragAutoScroll();
      return;
    }

    final scrollController = searchHandler.gridScrollController;
    final position = scrollController.position;
    final nextOffset = (scrollController.offset + dragAutoScrollDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (nextOffset == scrollController.offset) {
      stopDragAutoScroll();
      return;
    }

    scrollController.jumpTo(nextOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDragSelecting && latestDragGlobalPosition != null) {
        applyDragSelectionRangeAt(latestDragGlobalPosition!);
        updateDragAutoScroll();
      }
    });
  }

  void stopDragAutoScroll() {
    dragAutoScrollTimer?.cancel();
    dragAutoScrollTimer = null;
    dragAutoScrollDelta = 0;
  }

  void endDragSelection() {
    isDragSelecting = false;
    latestDragGlobalPosition = null;
    dragAnchorIndex = null;
    dragCurrentHitIndex = null;
    dragSelectAdds = null;
    dragInitialSelectedItems.clear();
    dragInitialSelectedSet.clear();
    dragCurrentRangeItems.clear();
    stopDragAutoScroll();
    dragControlsUnblockTimer?.cancel();
    dragControlsUnblockTimer = Timer(const Duration(milliseconds: 450), () {
      searchHandler.selectionControlsBlocked.value = false;
    });
  }

  void onGridPointerDown(PointerDownEvent event) {
    pinchPointerPositions[event.pointer] = event.position;
    if (pinchPointerPositions.length >= 2 && !isPinchResizing && !isDragSelecting) {
      startPinchResize();
    }
  }

  void onGridPointerMove(PointerMoveEvent event) {
    if (!pinchPointerPositions.containsKey(event.pointer)) {
      return;
    }

    pinchPointerPositions[event.pointer] = event.position;
    if (!isPinchResizing) {
      return;
    }

    updatePinchResize();
  }

  void onGridPointerUp(PointerUpEvent event) {
    pinchPointerPositions.remove(event.pointer);
    if (isPinchResizing && pinchPointerPositions.length < 2) {
      endPinchResize();
    }
  }

  void onGridPointerCancel(PointerCancelEvent event) {
    pinchPointerPositions.remove(event.pointer);
    if (isPinchResizing && pinchPointerPositions.length < 2) {
      endPinchResize();
    }
  }

  void startPinchResize() {
    final points = _pinchPoints();
    if (points == null || searchHandler.currentFetched.isEmpty || !searchHandler.gridScrollController.hasClients) {
      return;
    }

    final distance = (points.$1 - points.$2).distance;
    if (distance <= 0) {
      return;
    }

    final state = _activeColumnState();
    isPinchResizing = true;
    pinchStartDistance = distance;
    pinchStartColumns = state.value;
    pinchLastColumns = pinchStartColumns;
    pinchStepApplied = false;
    pinchResizeAnchor = captureGridResizeAnchor(_pinchFocalPoint(points));
    setState(() {});
  }

  void updatePinchResize() {
    if (pinchStepApplied) {
      return;
    }

    final points = _pinchPoints();
    if (points == null || pinchStartDistance <= 0) {
      return;
    }

    final distance = (points.$1 - points.$2).distance;
    if (distance <= 0) {
      return;
    }

    final scale = distance / pinchStartDistance;
    if (scale > 0.96 && scale < 1.04) {
      return;
    }

    final state = _activeColumnState();
    final nextColumns = _validatedColumnCount(state, pinchStartColumns + (scale > 1 ? -1 : 1));
    if (nextColumns == pinchLastColumns) {
      return;
    }

    pinchResizeAnchor = captureGridResizeAnchor(_pinchFocalPoint(points)) ?? pinchResizeAnchor;
    pinchLastColumns = nextColumns;
    pinchStepApplied = true;
    unawaited(ServiceHandler.vibrate());
    persistColumnCount(state, nextColumns);
    if (mounted) {
      setState(() {});
    }
    preserveGridResizeAnchor();
  }

  void endPinchResize() {
    isPinchResizing = false;
    pinchStartDistance = 0;
    pinchStartColumns = 0;
    pinchLastColumns = 0;
    pinchStepApplied = false;
    preserveGridResizeAnchor();
    pinchResizeAnchor = null;
    if (mounted) {
      setState(() {});
    }
  }

  (Offset, Offset)? _pinchPoints() {
    if (pinchPointerPositions.length < 2) {
      return null;
    }

    final entries = pinchPointerPositions.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return (entries[0].value, entries[1].value);
  }

  Offset _pinchFocalPoint((Offset, Offset) points) {
    return Offset(
      (points.$1.dx + points.$2.dx) / 2,
      (points.$1.dy + points.$2.dy) / 2,
    );
  }

  SettingState<int> _activeColumnState() {
    return context.isPortrait ? SX.portraitColumns.state : SX.landscapeColumns.state;
  }

  int _validatedColumnCount(SettingState<int> state, int value) {
    return state.def.validate?.call(value) ?? value;
  }

  void persistColumnCount(SettingState<int> state, int value) {
    final booruName = SettingsRegistry.instance.currentBooruName;
    if (booruName != null && state.hasOverrideFor(booruName)) {
      state.setOverrideFor(booruName, value, debounceSave: true);
    } else {
      state.setValue(value, debounceSave: true);
    }
  }

  _GridResizeAnchor? captureGridResizeAnchor(Offset focalGlobalPosition) {
    final controller = searchHandler.gridScrollController;
    if (!controller.hasClients || controller.tagMap.isEmpty) {
      return null;
    }

    final viewportTop = controller.viewportBoundaryGetter().top;
    final viewportHeight = controller.position.viewportDimension;
    int? closestIndex;
    double? closestDistance;
    double? closestTop;

    for (final entry in controller.tagMap.entries) {
      final index = entry.key;
      if (index < 0 || index >= searchHandler.currentFetched.length) {
        continue;
      }

      final renderObject = entry.value.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      final rect = topLeft & renderObject.size;
      final itemTop = topLeft.dy - viewportTop;
      final itemBottom = itemTop + renderObject.size.height;
      if (itemBottom <= 0 || itemTop >= viewportHeight) {
        continue;
      }

      final distance = (rect.center - focalGlobalPosition).distance;
      if (closestDistance == null || distance < closestDistance) {
        closestIndex = index;
        closestDistance = distance;
        closestTop = itemTop;
      }
    }

    if (closestIndex == null || closestTop == null) {
      return null;
    }

    return _GridResizeAnchor(
      index: closestIndex,
      itemTop: closestTop,
    );
  }

  void preserveGridResizeAnchor({bool animate = false}) {
    final anchor = pinchResizeAnchor;
    if (anchor == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !searchHandler.gridScrollController.hasClients) {
        return;
      }

      final controller = searchHandler.gridScrollController;
      final tag = controller.tagMap[anchor.index];
      final renderObject = tag?.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        controller.scrollToIndex(
          anchor.index,
          duration: Duration(milliseconds: animate ? 120 : 10),
          preferPosition: AutoScrollPosition.begin,
        );
        return;
      }

      final viewportTop = controller.viewportBoundaryGetter().top;
      final currentTop = renderObject.localToGlobal(Offset.zero).dy - viewportTop;
      final delta = currentTop - anchor.itemTop;
      if (delta.abs() < 0.5) {
        return;
      }

      final position = controller.position;
      final nextOffset = (controller.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (nextOffset == controller.offset) {
        return;
      }

      if (animate) {
        unawaited(
          controller.animateTo(
            nextOffset,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          ),
        );
      } else {
        controller.jumpTo(nextOffset);
      }
    });
  }

  Future<void> onSecondaryTap(int index, BuildContext context) async {
    final currentFetched = searchHandler.currentFetchedOrNull;
    if (currentFetched == null || index >= currentFetched.length) return;
    final BooruItem item = currentFetched[index];
    await ClipboardUtils.copyImageToClipboard(item);
  }

  @override
  Widget build(BuildContext context) {
    // check if grid type changed when rebuilding the widget (must happen only on start and when saving settings)
    final bool newIsStaggered =
        SX.previewDisplay.value.isStaggered && (searchHandler.currentBooruHandlerOrNull?.hasSizeData ?? false);
    if (isStaggered != newIsStaggered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        isStaggered = newIsStaggered;
        setState(() {});
      });
    }

    final bool changedOrientation = context.orientation != currentOrientation;
    if (changedOrientation && !isActive.value) {
      // try to keep the scroll position at currently viewed item when screen orientation changes
      currentOrientation = context.orientation;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentFetched = searchHandler.currentFetchedOrNull;
        if (currentFetched == null) return;

        final rootViewerIndex = _rootViewerIndex;
        final itemIndex = rootViewerIndex != null && rootViewerIndex >= 0 && rootViewerIndex < currentFetched.length
            ? rootViewerIndex
            : currentFetched.indexWhere(
                (item) => item.key == viewerHandler.current.value?.key,
              );
        if (itemIndex != -1) {
          searchHandler.gridScrollController.scrollToIndex(
            itemIndex,
            duration: Duration(milliseconds: isMobile ? 10 : 100),
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        NotificationListener<ScrollNotification>(
          child: RefreshIndicator(
            triggerMode: RefreshIndicatorTriggerMode.anywhere,
            displacement: 40,
            edgeOffset: MediaQuery.paddingOf(context).top + MainAppBar.height,
            strokeWidth: 4,
            color: Theme.of(context).colorScheme.secondary,
            onRefresh: () => searchHandler.searchAction(
              searchHandler.currentTabOrNull?.tags ?? '',
              null,
            ),
            child: Stack(
              children: [
                ValueListenableBuilder(
                  valueListenable: isActive,
                  builder: (context, isActive, child) {
                    return ShimmerWrap(
                      enabled: isActive && !SX.shitDevice.value,
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  child: Obx(() {
                    final currentFetched = searchHandler.currentFetchedOrNull;
                    final currentTab = searchHandler.currentTabOrNull;
                    final bool isLoadingAndNoItems = searchHandler.isLoading.value && (currentFetched?.isEmpty ?? true);

                    if (isLoadingAndNoItems) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        // reset scroll position if in loading state
                        searchHandler.gridScrollController.jumpTo(0);
                      });
                    }

                    // If loading just finished but content doesn't fill the viewport,
                    // the NotificationListener won't fire (no scroll possible), so trigger next page here with a small delay.
                    if (!searchHandler.isLoading.value && (currentFetched?.isNotEmpty ?? false)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (searchHandler.gridScrollController.hasClients && !searchHandler.isLoading.value) {
                          final pos = searchHandler.gridScrollController.position;
                          final bool screenNotFilled = pos.extentBefore == 0 && pos.extentAfter == 0;
                          if (screenNotFilled) {
                            await Future.delayed(const Duration(milliseconds: 500));
                            unawaited(searchHandler.runSearch());
                          }
                        }
                      });
                    }

                    return Scrollbar(
                      controller: searchHandler.gridScrollController,
                      interactive: true,
                      thickness: 8,
                      thumbVisibility: true,
                      scrollbarOrientation: SX.handSide.value.isLeft
                          ? ScrollbarOrientation.left
                          : ScrollbarOrientation.right,
                      child: Listener(
                        onPointerDown: onGridPointerDown,
                        onPointerMove: onGridPointerMove,
                        onPointerUp: onGridPointerUp,
                        onPointerCancel: onGridPointerCancel,
                        child: GestureDetector(
                          key: dragSelectViewportKey,
                          behavior: HitTestBehavior.translucent,
                          onLongPressStart: isPinchResizing ? null : onDragSelectStart,
                          onLongPressMoveUpdate: isPinchResizing ? null : onDragSelectMove,
                          onLongPressEnd: isPinchResizing ? null : (_) => endDragSelection(),
                          onLongPressCancel: isPinchResizing ? null : endDragSelection,
                          child: CustomScrollView(
                            key: ValueKey('CustomScrollView-${searchHandler.currentTabId}'),
                            controller: searchHandler.gridScrollController,
                            physics: isPinchResizing || isLoadingAndNoItems
                                ? const NeverScrollableScrollPhysics()
                                : AlwaysScrollableScrollPhysics(
                                    parent: ScrollConfiguration.of(context).getScrollPhysics(context),
                                  ),
                            shrinkWrap: false,
                            scrollCacheExtent: SX.shitDevice.value ? const .viewport(0.5) : const .viewport(1),
                            slivers: [
                              const MainAppBar(),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(10, 16, 10, 180),
                                sliver: Builder(
                                  builder: (context) {
                                    if (isLoadingAndNoItems) {
                                      if (SX.shitDevice.value) {
                                        return const SliverToBoxAdapter(
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      }

                                      return const ThumbnailsShimmerList();
                                    }

                                    if (currentTab == null) {
                                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                                    }

                                    if (isStaggered) {
                                      return Obx(
                                        () => StaggeredBuilder(
                                          key: ValueKey('StaggeredBuilder-${searchHandler.currentTabId}'),
                                          tab: currentTab,
                                          scrollController: searchHandler.gridScrollController,
                                          onTap: onTap,
                                          onDoubleTap: onDoubleTap,
                                          onLongPress: onLongPress,
                                          onSecondaryTap: (i) => onSecondaryTap(i, context),
                                          onSelected: onLongPress,
                                          dragSelectController: dragSelectController,
                                        ),
                                      );
                                    }

                                    return Obx(
                                      () => GridBuilder(
                                        key: ValueKey('GridBuilder-${searchHandler.currentTabId}'),
                                        tab: searchHandler.currentTab,
                                        scrollController: searchHandler.gridScrollController,
                                        onTap: onTap,
                                        onDoubleTap: onDoubleTap,
                                        onLongPress: onLongPress,
                                        onSecondaryTap: (i) => onSecondaryTap(i, context),
                                        onSelected: onLongPress,
                                        dragSelectController: dragSelectController,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                Positioned(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 120,
                  right: SX.scrollGridButtonsPosition.value.isRight ? MediaQuery.sizeOf(context).width * 0.07 : null,
                  left: SX.scrollGridButtonsPosition.value.isLeft ? MediaQuery.sizeOf(context).width * 0.07 : null,
                  child: Obx(() {
                    final bool isLoadingAndNoItems =
                        searchHandler.isLoading.value && (searchHandler.currentFetchedOrNull?.isEmpty ?? true);

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child:
                          (isLoadingAndNoItems ||
                              SX.scrollGridButtonsPosition.value.isDisabled ||
                              SX.appMode.value.isDesktop == true)
                          ? const SizedBox.shrink()
                          : const WaterfallScrollButtons(),
                    );
                  }),
                ),
              ],
            ),
          ),
          onNotification: (notif) {
            if (notif.depth != 0 || notif.metrics.axis != Axis.vertical) {
              return false;
            }
            if (notif is ScrollStartNotification) {
              navigationHandler.floatingHeaderKey.currentState?.handleScrollStart();
            }
            if (notif is ScrollUpdateNotification || notif is OverscrollNotification) {
              syncFloatingBarsWithScroll(notif);
              searchHandler.sendToScrollStream(notif);

              // print('SCROLL NOTIFICATION');
              // print(searchHandler.gridScrollController.position.maxScrollExtent);
              // print(notif.metrics); // pixels before viewport, in viewport, after viewport

              final bool isNotAtStart = notif.metrics.pixels > 0;
              final bool isAtOrNearEdge =
                  notif.metrics.atEdge ||
                  notif.metrics.pixels >
                      (notif.metrics.maxScrollExtent -
                          (notif.metrics.extentInside *
                              2)); // trigger new page when at edge or scroll position is less than 2 viewports
              final bool isScreenFilled =
                  notif.metrics.extentBefore != 0 ||
                  notif.metrics.extentAfter != 0; // for cases when first page doesn't fill the screen

              if (!searchHandler.isLoading.value) {
                if (!isScreenFilled || (isNotAtStart && isAtOrNearEdge)) {
                  searchHandler.runSearch();
                }
              }
            }
            if (notif is ScrollEndNotification) {
              settleFloatingBarsAfterScroll(notif);
              searchHandler.sendToScrollStream(notif);
            }
            return true;
          },
        ),
        Positioned(
          top: isMobile ? (MediaQuery.paddingOf(context).top + kToolbarHeight + 12) : 12,
          right: 12,
          child: GridPageNumberOverlay(
            key: ValueKey(
              // recreate when controller is recreated
              'gridController${searchHandler.gridScrollController.hashCode}',
            ),
          ),
        ),
        //
        RepaintBoundary(
          child: WaterfallBottomBar(
            key: navigationHandler.bottomBarKey,
          ),
        ),
      ],
    );
  }
}

class _GridResizeAnchor {
  const _GridResizeAnchor({
    required this.index,
    required this.itemTop,
  });

  final int index;
  final double itemTop;
}

class WaterfallScrollButtons extends StatelessWidget {
  const WaterfallScrollButtons({super.key});

  Future<void> pageScroll(bool forward) async {
    final scrollController = SearchHandler.instance.gridScrollController;

    if (scrollController.hasClients && scrollController.position.hasContentDimensions) {
      double nextOffset = 0;
      final double viewportHeight = scrollController.position.viewportDimension;
      final double leftTillClosestEdge = max(
        0,
        min(
          scrollController.position.maxScrollExtent - scrollController.offset,
          scrollController.offset,
        ),
      );
      final bool closestEdgeIsTop =
          scrollController.offset < scrollController.position.maxScrollExtent - scrollController.offset;
      if (leftTillClosestEdge < viewportHeight / 2 &&
          ((forward && !closestEdgeIsTop) || (!forward && closestEdgeIsTop))) {
        nextOffset = (forward ? 1 : -1) * (leftTillClosestEdge * 1.2);
      } else {
        nextOffset = (scrollController.position.viewportDimension * 0.9) * (forward ? 1 : -1);
      }

      await scrollController.animateTo(
        scrollController.offset + nextOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.33),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            LongPressRepeater(
              onStart: () async => pageScroll(false),
              startDelay: 300,
              child: InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                onTap: () => pageScroll(false),
                child: SizedBox(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                  child: Icon(
                    Icons.arrow_upward,
                    size: 30,
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            LongPressRepeater(
              onStart: () async => pageScroll(true),
              startDelay: 300,
              child: InkWell(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                onTap: () => pageScroll(true),
                child: SizedBox(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                  child: Icon(
                    Icons.arrow_downward,
                    size: 30,
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
