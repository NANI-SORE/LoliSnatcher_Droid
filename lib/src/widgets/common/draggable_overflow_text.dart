import 'dart:async';

import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Text widget that renders normally when text fits and on overflow turns into combination of normal text and scrollable text
class DraggableOverflowText extends StatefulWidget {
  const DraggableOverflowText(
    this.text, {
    super.key,
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<DraggableOverflowText> createState() => _DraggableOverflowTextState();
}

class _DraggableOverflowTextState extends State<DraggableOverflowText> {
  bool _isInteracting = false;
  bool _isWaitingForScrollSettle = false;
  final ScrollController _scrollController = ScrollController();
  ScrollPosition? _scrollSettlePosition;
  VoidCallback? _scrollSettleListener;
  Timer? _idleResetTimer;

  void _setInteracting(bool value) {
    if (!mounted || _isInteracting == value) return;

    setState(() {
      _isInteracting = value;
    });
  }

  void _cancelIdleReset() {
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
  }

  void _onScrollActivity() {
    _cancelIdleReset();
    _setInteracting(true);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    if (delta == 0) return;

    _onScrollActivity();

    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (target != position.pixels) {
      position.jumpTo(target);
    }

    _onInteractionEnd();
  }

  void _scheduleIdleReset() {
    _cancelIdleReset();
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent || position.outOfRange) {
      return;
    }

    _idleResetTimer = Timer(const Duration(seconds: 10), () async {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      if (position.pixels <= position.minScrollExtent || position.outOfRange) {
        _onInteractionEnd();
        return;
      }

      _setInteracting(true);
      await _scrollController.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );

      if (mounted) {
        _onInteractionEnd(waitForBounce: false);
      }
    });
  }

  void _waitForScrollSettle() {
    if (_isWaitingForScrollSettle || !_scrollController.hasClients) return;

    _isWaitingForScrollSettle = true;
    final position = _scrollController.position;

    void listener() {
      if (position.isScrollingNotifier.value) return;

      _clearScrollSettleListener();
      _onInteractionEnd(waitForBounce: false);
    }

    _scrollSettlePosition = position;
    _scrollSettleListener = listener;
    position.isScrollingNotifier.addListener(listener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isWaitingForScrollSettle) {
        listener();
      }
    });
  }

  void _onInteractionEnd({bool waitForBounce = true}) {
    // If the user stops interacting and we are at the start, reset to ellipsis mode
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (waitForBounce && position.outOfRange) {
      _waitForScrollSettle();
      return;
    }

    if (position.pixels <= position.minScrollExtent) {
      _cancelIdleReset();
      _setInteracting(false);
    } else {
      _scheduleIdleReset();
    }
  }

  void _clearScrollSettleListener() {
    final listener = _scrollSettleListener;
    if (listener != null) {
      _scrollSettlePosition?.isScrollingNotifier.removeListener(listener);
    }
    _scrollSettlePosition = null;
    _scrollSettleListener = null;
    _isWaitingForScrollSettle = false;
  }

  @override
  void dispose() {
    _cancelIdleReset();
    _clearScrollSettleListener();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = widget.style ?? DefaultTextStyle.of(context).style;

        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final bool isOverflowing = textPainter.didExceedMaxLines;
        if (!isOverflowing) {
          return Text(widget.text, style: textStyle);
        }

        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (_) {
            _onScrollActivity();
          },
          onPointerUp: (_) => _onInteractionEnd(),
          onPointerCancel: (_) => _onInteractionEnd(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification ||
                  notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                _onScrollActivity();
              }

              if (notification is ScrollEndNotification) {
                _onInteractionEnd();
              }
              return false;
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Opacity(
                  opacity: _isInteracting ? 1 : 0,
                  child: FadingEdgeScrollView.fromSingleChildScrollView(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        widget.text,
                        style: textStyle,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
                //
                IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: _isInteracting ? 0.0 : 1.0,
                    child: Text(
                      widget.text,
                      style: textStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
