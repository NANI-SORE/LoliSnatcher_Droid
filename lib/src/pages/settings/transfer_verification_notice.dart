import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:lolisnatcher/gen/strings.g.dart';

class TransferVerificationNotice extends StatelessWidget {
  const TransferVerificationNotice({required this.phrase, super.key});

  final String phrase;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    final emojis = phrase.split(' ');
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.verificationPhrase, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                textDirection: TextDirection.ltr,
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, emoji) in emojis.indexed)
                    Semantics(
                      sortKey: OrdinalSortKey(index.toDouble()),
                      label: '${index + 1}: $emoji',
                      excludeSemantics: true,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              emoji,
                              textDirection: TextDirection.ltr,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text('${index + 1}', style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(t.compareVerificationPhrase),
            ],
          ),
        ),
      ),
    );
  }
}
