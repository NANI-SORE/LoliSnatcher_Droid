import 'dart:math';

class TabDragFeedbackGeometry {
  const TabDragFeedbackGeometry({
    required this.width,
    required this.left,
    required this.top,
  });

  final double width;
  final double left;
  final double top;
}

/// Places a drag preview near the pointer while keeping it inside the screen.
///
/// The preview grows near the horizontal center and shrinks near either edge.
/// It sits above the finger whenever possible, flipping below it near the top.
TabDragFeedbackGeometry calculateTabDragFeedbackGeometry({
  required double pointerX,
  required double pointerY,
  required double viewportWidth,
  required double viewportHeight,
  required double previewHeight,
  double leftMargin = 12,
  double topMargin = 12,
  double rightMargin = 12,
  double bottomMargin = 12,
  double fingerGap = 20,
  double minimumWidth = 160,
  double maximumWidth = 360,
}) {
  final rightEdge = max(leftMargin, viewportWidth - rightMargin);
  final maximumUsableWidth = max(
    0,
    min(maximumWidth, rightEdge - leftMargin),
  ).toDouble();
  final minimumUsableWidth = min(minimumWidth, maximumUsableWidth);
  final distanceToNearestEdge = min(
    max(0, pointerX - leftMargin),
    max(0, rightEdge - pointerX),
  ).toDouble();
  final width = (distanceToNearestEdge * 2).clamp(
    minimumUsableWidth,
    maximumUsableWidth,
  );

  final latestLeft = max(leftMargin, rightEdge - width);
  final left = (pointerX - width / 2).clamp(leftMargin, latestLeft);

  final bottomEdge = max(topMargin, viewportHeight - bottomMargin);
  final latestTop = max(topMargin, bottomEdge - previewHeight);
  final fitsAbove = pointerY - fingerGap - previewHeight >= topMargin;
  final preferredTop = fitsAbove ? pointerY - fingerGap - previewHeight : pointerY + fingerGap;
  final top = preferredTop.clamp(topMargin, latestTop);

  return TabDragFeedbackGeometry(
    width: width,
    left: left,
    top: top,
  );
}
