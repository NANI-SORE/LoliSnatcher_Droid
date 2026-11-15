/// Returns the signed scroll step for a dragged pointer near a viewport edge.
///
/// The middle of the viewport returns zero. Inside either edge zone, speed
/// increases quadratically from zero at the zone boundary to [maximumStep] at
/// the viewport edge. Positions outside the viewport stay capped at that speed
/// until the pointer re-enters the viewport.
double tabDragAutoScrollDelta({
  required double pointerY,
  required double viewportHeight,
  double edgeExtent = 72,
  double maximumStep = 18,
}) {
  if (viewportHeight <= 0 || edgeExtent <= 0 || maximumStep <= 0) {
    return 0;
  }

  final halfViewport = viewportHeight / 2;
  final effectiveEdgeExtent = edgeExtent < halfViewport ? edgeExtent : halfViewport;

  if (pointerY < effectiveEdgeExtent) {
    final depth = ((effectiveEdgeExtent - pointerY) / effectiveEdgeExtent).clamp(0.0, 1.0);
    return -maximumStep * depth * depth;
  }

  final bottomEdgeStart = viewportHeight - effectiveEdgeExtent;
  if (pointerY > bottomEdgeStart) {
    final depth = ((pointerY - bottomEdgeStart) / effectiveEdgeExtent).clamp(0.0, 1.0);
    return maximumStep * depth * depth;
  }

  return 0;
}
