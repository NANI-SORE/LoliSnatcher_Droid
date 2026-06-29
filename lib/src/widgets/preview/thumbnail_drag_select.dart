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

  ThumbnailDragSelectHit? hitTest(Offset globalPosition) {
    _ThumbnailDragSelectRegistrantState? bestMatch;
    double? bestArea;

    for (final registrant in _registrants) {
      if (!registrant.mounted) {
        continue;
      }

      final renderObject = registrant.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      final rect = topLeft & renderObject.size;
      if (!rect.contains(globalPosition)) {
        continue;
      }

      final area = rect.width * rect.height;
      if (bestArea == null || area < bestArea) {
        bestMatch = registrant;
        bestArea = area;
      }
    }

    if (bestMatch == null) {
      return null;
    }

    return ThumbnailDragSelectHit(
      index: bestMatch.widget.index,
      item: bestMatch.widget.item,
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
