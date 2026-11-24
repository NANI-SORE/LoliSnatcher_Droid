import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';

class DDEmptyState extends StatelessWidget {
  const DDEmptyState({required this.message, this.compact = false, super.key});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Kaomoji(
                  category: KaomojiCategory.indifference,
                  style: TextStyle(fontSize: compact ? 24 : 36, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: compact ? Theme.of(context).textTheme.bodyMedium : Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
