import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';

class ThumbnailDragSelectHit {
  const ThumbnailDragSelectHit({
    required this.index,
    required this.item,
  });

  final int index;
  final BooruItem item;
}

class ThumbnailDragSelectController {
  final Set<_ThumbnailDragSelectRegistrantState> _registrants = {};

  void _register(_ThumbnailDragSelectRegistrantState registrant) {
    _registrants.add(registrant);
  }

  void _unregister(_ThumbnailDragSelectRegistrantState registrant) {
    _registrants.remove(registrant);
  }

  ThumbnailDragSelectHit? hitTest(
    Offset globalPosition, {
    int? lastIndex,
  }) {
    final registrants = _visibleRegistrants();
    final exactHit = _hitTestRegistrants(globalPosition, registrants);
    if (exactHit != null) {
      return exactHit;
    }

    if (lastIndex != null) {
      return _hitTestTrailingLastRowSpace(globalPosition, registrants, lastIndex);
    }

    return null;
  }

  List<({int index, BooruItem item, Rect rect})> _visibleRegistrants() {
    final visible = <({int index, BooruItem item, Rect rect})>[];

    for (final registrant in _registrants) {
      if (!registrant.mounted) {
        continue;
      }

      final renderObject = registrant.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      visible.add((
        index: registrant.widget.index,
        item: registrant.widget.item,
        rect: topLeft & renderObject.size,
      ));
    }

    return visible;
  }

  ThumbnailDragSelectHit? _hitTestRegistrants(
    Offset globalPosition,
    List<({int index, BooruItem item, Rect rect})> registrants,
  ) {
    ({int index, BooruItem item, Rect rect})? bestRegistrant;
    double? bestArea;

    for (final registrant in registrants) {
      final rect = registrant.rect;
      if (!rect.contains(globalPosition)) {
        continue;
      }

      final area = rect.width * rect.height;
      if (bestArea == null || area < bestArea) {
        bestRegistrant = registrant;
        bestArea = area;
      }
    }

    if (bestRegistrant == null) {
      return null;
    }

    return ThumbnailDragSelectHit(
      index: bestRegistrant.index,
      item: bestRegistrant.item,
    );
  }

  ThumbnailDragSelectHit? _hitTestTrailingLastRowSpace(
    Offset globalPosition,
    List<({int index, BooruItem item, Rect rect})> registrants,
    int lastIndex,
  ) {
    final rowCandidates = registrants
        .where(
          (registrant) => globalPosition.dy >= registrant.rect.top && globalPosition.dy <= registrant.rect.bottom,
        )
        .toList();

    if (rowCandidates.isEmpty) {
      return null;
    }

    rowCandidates.sort((a, b) => a.index.compareTo(b.index));
    final lastRowItem = rowCandidates.last;
    if (lastRowItem.index != lastIndex || globalPosition.dx < lastRowItem.rect.right) {
      return null;
    }

    return ThumbnailDragSelectHit(
      index: lastRowItem.index,
      item: lastRowItem.item,
    );
  }
}

class ThumbnailDragSelectRegistrant extends StatefulWidget {
  const ThumbnailDragSelectRegistrant({
    required this.controller,
    required this.index,
    required this.item,
    required this.child,
    super.key,
  });

  final ThumbnailDragSelectController controller;
  final int index;
  final BooruItem item;
  final Widget child;

  @override
  State<ThumbnailDragSelectRegistrant> createState() => _ThumbnailDragSelectRegistrantState();
}

class _ThumbnailDragSelectRegistrantState extends State<ThumbnailDragSelectRegistrant> {
  @override
  void initState() {
    super.initState();
    widget.controller._register(this);
  }

  @override
  void didUpdateWidget(covariant ThumbnailDragSelectRegistrant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._unregister(this);
      widget.controller._register(this);
    }
  }

  @override
  void dispose() {
    widget.controller._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
