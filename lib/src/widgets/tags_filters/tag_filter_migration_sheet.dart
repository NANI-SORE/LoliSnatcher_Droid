import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';

Future<bool?> showTagFilterMigrationSheet({
  required BuildContext context,
  required int migratedRuleCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) {
      return _TagFilterMigrationSheet(
        migratedRuleCount: migratedRuleCount,
      );
    },
  );
}

class _TagFilterMigrationSheet extends StatelessWidget {
  const _TagFilterMigrationSheet({
    required this.migratedRuleCount,
  });

  final int migratedRuleCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final loc = context.loc.settings.itemFilters;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.filter_alt_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  loc.migrationNoticeTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            loc.migrationNoticeMessage(count: migratedRuleCount),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: kMinInteractiveDimension,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.tune_rounded),
              label: Text(loc.openFilters),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: kMinInteractiveDimension,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.loc.later),
            ),
          ),
        ],
      ),
    );
  }
}
