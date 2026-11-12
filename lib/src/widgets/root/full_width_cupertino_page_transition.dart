import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

const double _kMinFlingVelocity = 1; // Screen widths per second.
const Duration _kDroppedSwipePageAnimationDuration = Duration(milliseconds: 350);
const Duration _kCupertinoTransitionDuration = Duration(milliseconds: 500);

class FullWidthCupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const FullWidthCupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _kCupertinoTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final bool linearTransition = route.popGestureInProgress;

    if (route.fullscreenDialog) {
      return CupertinoFullscreenDialogTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: secondaryAnimation,
        linearTransition: linearTransition,
        child: child,
      );
    }

    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: linearTransition,
      child: _FullWidthCupertinoBackGestureDetector<T>(
        enabledCallback: () => route.popGestureEnabled,
        onStartPopGesture: () => _CupertinoBackGestureController<T>.start(route),
        child: child,
      ),
    );
  }
}

class _FullWidthCupertinoBackGestureDetector<T> extends StatefulWidget {
  const _FullWidthCupertinoBackGestureDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final Widget child;
  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_CupertinoBackGestureController<T>> onStartPopGesture;

  @override
  State<_FullWidthCupertinoBackGestureDetector<T>> createState() => _FullWidthCupertinoBackGestureDetectorState<T>();
}

class _FullWidthCupertinoBackGestureDetectorState<T> extends State<_FullWidthCupertinoBackGestureDetector<T>> {
  _CupertinoBackGestureController<T>? _backGestureController;
  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();

    if (_backGestureController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_backGestureController?.navigator.mounted ?? false) {
          _backGestureController?.navigator.didStopUserGesture();
        }
        _backGestureController = null;
      });
    }

    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    assert(mounted, 'The back gesture detector must be mounted before handling drag start.');
    assert(_backGestureController == null, 'A back gesture controller is already active.');
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted, 'The back gesture detector must be mounted before handling drag update.');
    assert(_backGestureController != null, 'A back gesture controller must exist before drag update.');
    _backGestureController!.dragUpdate(
      _convertToLogical(details.primaryDelta! / context.size!.width),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted, 'The back gesture detector must be mounted before handling drag end.');
    assert(_backGestureController != null, 'A back gesture controller must exist before drag end.');
    _backGestureController!.dragEnd(
      _convertToLogical(details.velocity.pixelsPerSecond.dx / context.size!.width),
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    assert(mounted, 'The back gesture detector must be mounted before handling drag cancel.');
    _backGestureController?.dragEnd(0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  double _convertToLogical(double value) {
    return switch (Directionality.of(context)) {
      TextDirection.rtl => -value,
      TextDirection.ltr => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context), 'Full-width Cupertino back gestures require Directionality.');
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: Listener(onPointerDown: _handlePointerDown, behavior: HitTestBehavior.translucent),
        ),
      ],
    );
  }
}

class _CupertinoBackGestureController<T> {
  _CupertinoBackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  factory _CupertinoBackGestureController.start(PageRoute<T> route) {
    assert(route.popGestureEnabled, 'A pop gesture can only start when the route allows it.');

    return _CupertinoBackGestureController<T>(
      navigator: route.navigator!,
      getIsCurrent: () => route.isCurrent,
      getIsActive: () => route.isActive,
      // ignore: invalid_use_of_protected_member
      controller: route.controller!,
    );
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsActive;
  final ValueGetter<bool> getIsCurrent;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.fastEaseInToSlowEaseOut;
    final bool isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      animateForward = getIsActive();
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      controller.animateTo(
        1,
        duration: _kDroppedSwipePageAnimationDuration,
        curve: animationCurve,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }

      if (controller.isAnimating) {
        controller.animateBack(
          0,
          duration: _kDroppedSwipePageAnimationDuration,
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
