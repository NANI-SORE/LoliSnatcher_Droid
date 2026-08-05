import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_editor.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_query_text.dart';

Future<void> showTagFilterDetailsSheet(BuildContext context, TagFilterEvaluation evaluation) {
  return showTagFilterMatchesSheet(context, evaluation.matches);
}

Future<void> showTagFilterMatchesSheet(
  BuildContext context,
  Iterable<TagFilterRuleMatch> matches, {
  String? title,
}) {
  final displayedMatches = matches.toList(growable: false);
  if (displayedMatches.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 700),
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      color: Theme.of(sheetContext).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title ?? sheetContext.loc.settings.itemFilters.matchingRules,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.65),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: displayedMatches.length,
                itemBuilder: (_, index) {
                  final match = displayedMatches[index];
                  final showQuery = match.rule.hasDistinctName;
                  return ListTile(
                    leading: Icon(_effectIcon(match.rule.effect)),
                    title: showQuery
                        ? MarqueeText(
                            text: match.rule.displayName,
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                            isExpanded: false,
                          )
                        : TagFilterQueryText(
                            query: match.rule.query,
                            matchedTags: match.matchedTags,
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showQuery)
                          TagFilterQueryText(
                            query: match.rule.query,
                            matchedTags: match.matchedTags,
                          ),
                        Text(_effectName(sheetContext, match.rule.effect)),
                      ],
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Future<void>.delayed(
                        Duration.zero,
                        () => showTagFilterEditorSheet(context, rule: match.rule),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

IconData _effectIcon(TagFilterEffect effect) => switch (effect) {
  TagFilterEffect.hide => Icons.visibility_off,
  TagFilterEffect.blur => Icons.blur_on,
  TagFilterEffect.mark => Icons.star,
};

String _effectName(BuildContext context, TagFilterEffect effect) => switch (effect) {
  TagFilterEffect.hide => context.loc.settings.itemFilters.hide,
  TagFilterEffect.blur => context.loc.settings.itemFilters.blur,
  TagFilterEffect.mark => context.loc.settings.itemFilters.mark,
};
