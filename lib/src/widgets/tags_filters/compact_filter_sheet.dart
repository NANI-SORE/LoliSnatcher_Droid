import 'package:flutter/material.dart';

/// Shows a filter sheet with a shorter drag-handle strip than Flutter's
/// built-in 48-pixel minimum. The sheet body remains draggable.
Future<T?> showCompactFilterSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: backgroundColor,
  shape: shape,
  clipBehavior: clipBehavior,
  constraints: constraints,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: false,
  builder: (sheetContext) => Stack(
    alignment: Alignment.topCenter,
    children: [
      SizedBox(
        height: 24,
        child: Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: builder(sheetContext),
      ),
    ],
  ),
);
