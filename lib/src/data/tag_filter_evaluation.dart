import 'package:lolisnatcher/src/data/tag_filter.dart';

class TagFilterRuleMatch {
  const TagFilterRuleMatch({required this.rule, required this.matchedTags});
  final TagFilterRule rule;
  final Set<String> matchedTags;
}

class TagFilterEvaluation {
  const TagFilterEvaluation({
    this.effectiveEffect,
    this.primaryMatch,
    this.matches = const [],
    this.hideAsBlur = false,
  });

  const TagFilterEvaluation.empty() : this();

  final TagFilterEffect? effectiveEffect;
  final TagFilterRuleMatch? primaryMatch;
  final List<TagFilterRuleMatch> matches;
  final bool hideAsBlur;

  bool get isHidden => effectiveEffect == TagFilterEffect.hide;
  bool get isBlurred => effectiveEffect == TagFilterEffect.blur;
  bool get isMarked => matches.any((match) => match.rule.effect == TagFilterEffect.mark);

  Iterable<TagFilterRuleMatch> get blockingMatches {
    final effect = primaryMatch?.rule.effect;
    return effect == null ? const [] : matches.where((match) => match.rule.effect == effect);
  }

  String? get loadingFilterDetails {
    const visibleRuleLimit = 3;
    final blocking = blockingMatches.toList(growable: false);
    if (blocking.isEmpty) return null;
    final lines = blocking.take(visibleRuleLimit).map((match) {
      final rule = match.rule;
      return rule.hasDistinctName ? '${rule.displayName} — ${rule.query.trim()}' : rule.query.trim();
    }).toList();
    final hiddenCount = blocking.length - lines.length;
    if (hiddenCount > 0) lines.add('+$hiddenCount');
    return lines.join('\n');
  }

  List<TagFilterMarker?> get displayMarkers {
    return _markersFor(matches.where((match) => match.rule.effect == TagFilterEffect.mark));
  }

  List<TagFilterMarker?> get gridDisplayMarkers {
    return _markersFor(
      matches.where((match) => match.rule.effect == TagFilterEffect.mark && match.rule.showMarkerInGrid),
    );
  }

  List<TagFilterMarker?> _markersFor(Iterable<TagFilterRuleMatch> markerMatches) {
    final seen = <String>{};
    final result = <TagFilterMarker?>[];
    for (final match in markerMatches) {
      final marker = match.rule.marker;
      final key = TagFilterMarker.stableKeyFor(marker);
      if (seen.add(key)) result.add(marker);
    }
    return result;
  }
}
