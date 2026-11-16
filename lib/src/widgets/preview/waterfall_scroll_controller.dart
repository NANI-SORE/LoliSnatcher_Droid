import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:scroll_to_index/scroll_to_index.dart';

class WaterfallScrollController extends SimpleAutoScrollController {
  WaterfallScrollController({
    required super.viewportBoundaryGetter,
    super.initialScrollOffset,
  }) : super(
         beginGetter: (rect) => rect.top,
         endGetter: (rect) => rect.bottom,
       );

  static final _restoreZoneKey = Object();
  _ScrollRestore? _restore;

  /// Guards every animation made by scroll_to_index, including its later passes.
  Future<void> restoreItem(
    int index, {
    required bool Function() isCurrent,
  }) async {
    cancelItemRestore();
    final restore = _ScrollRestore(isCurrent);
    _restore = restore;
    try {
      await runZoned(
        () =>
            scrollToIndex(index, duration: const Duration(milliseconds: 10), preferPosition: AutoScrollPosition.begin),
        zoneValues: {_restoreZoneKey: restore},
      );
    } finally {
      if (identical(_restore, restore)) _restore = null;
    }
  }

  void cancelItemRestore() {
    final restore = _restore;
    if (restore == null) return;
    restore.cancelled = true;
    _restore = null;
    if (hasClients) (position as _WaterfallScrollPosition).goIdle();
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    final restore = Zone.current[_restoreZoneKey] as _ScrollRestore?;
    if (restore != null && (restore.cancelled || !restore.isCurrent() || !hasClients)) {
      return Future.value();
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  // Scrollbar track clicks and page buttons use driven scrolling, while
  // scrollToIndex marks its restoration animations with isAutoScrolling.
  bool get isPaging => hasClients && !isAutoScrolling && (position as _WaterfallScrollPosition).isDrivenScrolling;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) {
    return _WaterfallScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _ScrollRestore {
  _ScrollRestore(this.isCurrent);

  final bool Function() isCurrent;
  bool cancelled = false;
}

class _WaterfallScrollPosition extends ScrollPositionWithSingleContext {
  _WaterfallScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  bool get isDrivenScrolling => activity is DrivenScrollActivity;
}
