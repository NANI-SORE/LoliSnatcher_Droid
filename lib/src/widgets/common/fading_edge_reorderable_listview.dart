import 'package:flutter/material.dart';

// Updated version of fading_edge_scrollview package

/// Flutter widget for displaying fading edge at start/end of scroll views
class FadingEdgeScrollView extends StatefulWidget {
  const FadingEdgeScrollView._internal({
    required this.child,
    required this.scrollController,
    required this.reverse,
    required this.scrollDirection,
    required this.gradientFractionOnStart,
    required this.gradientFractionOnEnd,
    super.key,
  }) : assert(
         gradientFractionOnStart >= 0 && gradientFractionOnStart <= 1,
         'gradientFractionOnStart must be between 0 and 1',
       ),
       assert(
         gradientFractionOnEnd >= 0 && gradientFractionOnEnd <= 1,
         'gradientFractionOnEnd must be between 0 and 1',
       );

  static Widget from({
    required Widget child,
    Key? key,
    double gradientFractionOnStart = 0.1,
    double gradientFractionOnEnd = 0.1,
  }) {
    final scrollable = _scrollableFrom(child);
    if (scrollable == null) {
      return child;
    }

    return FadingEdgeScrollView._internal(
      key: key,
      scrollController: scrollable.controller,
      scrollDirection: scrollable.scrollDirection,
      reverse: scrollable.reverse,
      gradientFractionOnStart: gradientFractionOnStart,
      gradientFractionOnEnd: gradientFractionOnEnd,
      child: child,
    );
  }

  /// child widget
  final Widget child;

  /// scroll controller of child widget
  ///
  /// Look for more documentation at [ScrollView.scrollController]
  final ScrollController scrollController;

  /// Whether the scroll view scrolls in the reading direction.
  ///
  /// Look for more documentation at [ScrollView.reverse]
  final bool reverse;

  /// The axis along which child view scrolls
  ///
  /// Look for more documentation at [ScrollView.scrollDirection]
  final Axis scrollDirection;

  /// what part of screen on start half should be covered by fading edge gradient
  /// [gradientFractionOnStart] must be 0 <= [gradientFractionOnStart] <= 1
  /// 0 means no gradient,
  /// 1 means gradients on start half of widget fully covers it
  final double gradientFractionOnStart;

  /// what part of screen on end half should be covered by fading edge gradient
  /// [gradientFractionOnEnd] must be 0 <= [gradientFractionOnEnd] <= 1
  /// 0 means no gradient,
  /// 1 means gradients on start half of widget fully covers it
  final double gradientFractionOnEnd;

  @override
  FadingEdgeScrollViewState createState() => FadingEdgeScrollViewState();
}

({ScrollController controller, Axis scrollDirection, bool reverse})? _scrollableFrom(Widget child) {
  switch (child) {
    case ScrollView(:final controller?, :final scrollDirection, :final reverse):
      return (controller: controller, scrollDirection: scrollDirection, reverse: reverse);
    case SingleChildScrollView(:final controller?, :final scrollDirection, :final reverse):
      return (controller: controller, scrollDirection: scrollDirection, reverse: reverse);
    case PageView(:final controller?, :final scrollDirection, :final reverse):
      return (controller: controller, scrollDirection: scrollDirection, reverse: reverse);
    case AnimatedList(:final controller?, :final scrollDirection, :final reverse):
      return (controller: controller, scrollDirection: scrollDirection, reverse: reverse);
    case ListWheelScrollView(:final controller?):
      return (controller: controller, scrollDirection: Axis.vertical, reverse: false);
    case ReorderableListView(:final scrollController?, :final scrollDirection, :final reverse):
      return (controller: scrollController, scrollDirection: scrollDirection, reverse: reverse);
    default:
      return null;
  }
}

class FadingEdgeScrollViewState extends State<FadingEdgeScrollView> with WidgetsBindingObserver {
  late ScrollController _controller;
  _ScrollState _scrollState = _ScrollState.notScrollable;
  int lastScrollViewListLength = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.scrollController;
    _controller.addListener(_updateScrollState);

    WidgetsBinding.instance.addObserver(this);
  }

  bool get _controllerIsReady => _controller.hasClients && _controller.positions.last.hasContentDimensions;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    _controller.removeListener(_updateScrollState);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Add the shading or remove it when the screen resize (web/desktop) or mobile is rotated
    _updateScrollState();
  }

  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (bounds) => _createShaderGradient().createShader(
      bounds.shift(Offset(-bounds.left, -bounds.top)),
      textDirection: Directionality.of(context),
    ),
    blendMode: BlendMode.dstIn,
    // Catching ScrollMetricsNotifications from the Scrollable child.
    // This way we get notified if the size of the underlying list changes.
    // We then re-evaluate if Gradient should be shown.
    child: NotificationListener<ScrollMetricsNotification>(
      child: widget.child,
      onNotification: (_) {
        _updateScrollState();
        // Enable notification to still bubble up.
        return false;
      },
    ),
  );

  Gradient _createShaderGradient() => LinearGradient(
    begin: _gradientStart,
    end: _gradientEnd,
    stops: [
      0,
      widget.gradientFractionOnStart * 0.5,
      1 - widget.gradientFractionOnEnd * 0.5,
      1,
    ],
    colors: _getColors(
      widget.gradientFractionOnStart > 0 && _scrollState.isShowGradientAtStart,
      widget.gradientFractionOnEnd > 0 && _scrollState.isShowGradientAtEnd,
    ),
  );

  AlignmentGeometry get _gradientStart => widget.scrollDirection == Axis.vertical ? _verticalStart : _horizontalStart;

  AlignmentGeometry get _gradientEnd => widget.scrollDirection == Axis.vertical ? _verticalEnd : _horizontalEnd;

  Alignment get _verticalStart => widget.reverse ? Alignment.bottomCenter : Alignment.topCenter;

  Alignment get _verticalEnd => widget.reverse ? Alignment.topCenter : Alignment.bottomCenter;

  AlignmentDirectional get _horizontalStart =>
      widget.reverse ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart;

  AlignmentDirectional get _horizontalEnd =>
      widget.reverse ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd;

  List<Color> _getColors(bool showGradientAtStart, bool showGradientAtEnd) => [
    if (showGradientAtStart) Colors.transparent else Colors.white,
    Colors.white,
    Colors.white,
    if (showGradientAtEnd) Colors.transparent else Colors.white,
  ];

  void _updateScrollState() {
    if (!_controllerIsReady) {
      return;
    }

    final offset = _controller.positions.last.pixels;
    final minOffset = _controller.positions.last.minScrollExtent;
    final maxOffset = _controller.positions.last.maxScrollExtent;

    final isScrolledToEnd = offset >= maxOffset;
    final isScrolledToStart = offset <= minOffset;

    final scrollState = switch ((isScrolledToStart, isScrolledToEnd)) {
      (true, true) => _ScrollState.notScrollable,
      (true, false) => _ScrollState.scrollableAtStart,
      (false, true) => _ScrollState.scrollableAtEnd,
      (false, false) => _ScrollState.scrollableInTheMiddle,
    };

    if (_scrollState != scrollState) {
      setState(() {
        _scrollState = scrollState;
      });
    }
  }
}

enum _ScrollState {
  notScrollable,
  scrollableAtStart,
  scrollableAtEnd,
  scrollableInTheMiddle;

  bool get isShowGradientAtStart => this == _ScrollState.scrollableAtEnd || this == _ScrollState.scrollableInTheMiddle;

  bool get isShowGradientAtEnd => this == _ScrollState.scrollableAtStart || this == _ScrollState.scrollableInTheMiddle;
}
