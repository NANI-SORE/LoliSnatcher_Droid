import 'package:flutter/widgets.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_handler.dart';
import 'package:lolisnatcher/src/utils/booru_source_resolver.dart';

/// Keeps media filtering current, including items outside a fetched list.
class TagFilterEvaluationBuilder extends StatelessWidget {
  const TagFilterEvaluationBuilder({
    required this.item,
    required this.builder,
    this.handler,
    this.booru,
    super.key,
  });

  final BooruItem item;
  final BooruHandler? handler;
  final Booru? booru;
  final Widget Function(BuildContext context, TagFilterEvaluation evaluation) builder;

  @override
  Widget build(BuildContext context) {
    if (!GetIt.instance.isRegistered<TagFilterHandler>()) {
      return builder(context, const TagFilterEvaluation.empty());
    }

    final filters = TagFilterHandler.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([filters.revision, if (handler != null) handler!.filteredFetched]),
      builder: (context, _) {
        final TagFilterEvaluation evaluation;
        if (handler != null) {
          evaluation = handler!.filterEvaluationFor(item);
        } else {
          final source = booru == null || booru!.type?.isFavouritesOrDownloads == true
              ? BooruSourceResolver.resolve(item)
              : booru;
          evaluation = filters.evaluate(
            item,
            FilterContext(
              viewBooru: booru ?? source ?? Booru.unknown(),
              sourceBooru: source,
            ),
          );
        }
        return evaluation.isHidden ? const SizedBox.shrink() : builder(context, evaluation);
      },
    );
  }
}
