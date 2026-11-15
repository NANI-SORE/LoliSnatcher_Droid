import 'package:flutter/material.dart';

/// Gives tab and group drags the same pointer tracking and scroll lifecycle.
class TabManagerDraggable<T extends Object> extends StatefulWidget {
  const TabManagerDraggable({
    required this.data,
    required this.child,
    required this.childWhenDragging,
    required this.feedback,
    required this.pointerPosition,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    super.key,
  });

  final T data;
  final Widget child;
  final Widget childWhenDragging;
  final Widget feedback;
  final ValueNotifier<Offset> pointerPosition;
  final void Function(Offset position, int? pointer) onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;

  @override
  State<TabManagerDraggable<T>> createState() => _TabManagerDraggableState<T>();
}

class _TabManagerDraggableState<T extends Object> extends State<TabManagerDraggable<T>> {
  int? _activePointer;

  void _handlePointerDown(PointerDownEvent event) => _activePointer ??= event.pointer;

  void _handlePointerFinished(PointerEvent event) {
    if (event.pointer == _activePointer) _activePointer = null;
  }

  Offset _captureDragStart(Draggable<Object> draggable, BuildContext context, Offset position) {
    widget.pointerPosition.value = position;
    return Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerFinished,
      onPointerCancel: _handlePointerFinished,
      child: LongPressDraggable<T>(
        data: widget.data,
        dragAnchorStrategy: _captureDragStart,
        rootOverlay: true,
        maxSimultaneousDrags: 1,
        feedback: widget.feedback,
        onDragStarted: () => widget.onDragStarted(widget.pointerPosition.value, _activePointer),
        onDragUpdate: (details) {
          widget.pointerPosition.value = details.globalPosition;
          widget.onDragUpdate(details.globalPosition);
        },
        onDragEnd: (_) {
          _activePointer = null;
          widget.onDragEnded();
        },
        childWhenDragging: widget.childWhenDragging,
        child: widget.child,
      ),
    );
  }
}
