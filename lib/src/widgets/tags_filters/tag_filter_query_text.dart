import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/tag_filter_query.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';

class TagFilterQueryText extends StatelessWidget {
  const TagFilterQueryText({
    required this.query,
    this.prefix = '',
    this.matchedTags = const {},
    this.style,
    this.isExpanded = false,
    super.key,
  });

  final String query;
  final String prefix;
  final Set<String> matchedTags;
  final TextStyle? style;
  final bool isExpanded;

  List<({int start, int end})> _tokenRanges() {
    final ranges = <({int start, int end})>[];
    int? start;
    var inQuotes = false;
    var escaping = false;
    for (var index = 0; index < query.length; index++) {
      final char = query[index];
      if (start == null && char.trim().isNotEmpty) start = index;
      if (start == null) continue;
      if (escaping) {
        escaping = false;
      } else if (char == r'\') {
        escaping = true;
      } else if (char == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && char.trim().isEmpty) {
        ranges.add((start: start, end: index));
        start = null;
      }
    }
    if (start != null) ranges.add((start: start, end: query.length));
    return ranges;
  }

  Color? _tagColor(TagCondition condition) {
    if (condition.hasWildcard && condition.matcher != null) {
      for (final matchedTag in matchedTags) {
        if (condition.matcher!.hasMatch(matchedTag)) {
          return TagHandler.instance.getTag(matchedTag).getColour();
        }
      }
    }
    final lookupTag = condition.hasWildcard ? condition.literalPrefix : condition.pattern;
    if (lookupTag.isEmpty) return null;
    return TagHandler.instance.getTag(lookupTag).getColour();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = TagFilterQuery.parse(query).query;
    if (parsed == null) {
      return MarqueeText(text: '$prefix$query', style: style, isExpanded: isExpanded);
    }
    final ranges = _tokenRanges();
    if (ranges.length != parsed.conditions.length) {
      return MarqueeText(text: '$prefix$query', style: style, isExpanded: isExpanded);
    }

    final spans = <InlineSpan>[
      if (prefix.isNotEmpty) TextSpan(text: prefix),
    ];
    var cursor = 0;
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      if (range.start > cursor) spans.add(TextSpan(text: query.substring(cursor, range.start)));
      final condition = parsed.conditions[index];
      final color = condition is TagCondition ? _tagColor(condition) : Theme.of(context).colorScheme.secondary;
      spans.add(
        TextSpan(
          text: query.substring(range.start, range.end),
          style: TextStyle(color: color),
        ),
      );
      cursor = range.end;
    }
    if (cursor < query.length) spans.add(TextSpan(text: query.substring(cursor)));

    return MarqueeText.rich(
      textSpan: TextSpan(children: spans),
      style: style,
      isExpanded: isExpanded,
    );
  }
}
