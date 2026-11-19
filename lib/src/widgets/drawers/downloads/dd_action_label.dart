import 'package:flutter/material.dart';

class DDActionLabel extends StatelessWidget {
  const DDActionLabel({required this.icon, required this.label, this.count, super.key});
  final IconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      if (count != null) ...[
        const SizedBox(width: 12),
        Text('$count', style: Theme.of(context).textTheme.labelLarge),
      ],
    ],
  );
}

class DDStatusCount extends StatelessWidget {
  const DDStatusCount({required this.icon, required this.label, required this.count, super.key});
  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$label: $count',
    child: Semantics(
      label: '$label: $count',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text('$count', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
