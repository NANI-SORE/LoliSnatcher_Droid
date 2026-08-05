import 'package:lolisnatcher/src/data/booru_item.dart';

const _escapedAsterisk = '\u0000';
const _escapedHyphen = '\u0001';

enum TagFilterQueryErrorCode {
  empty,
  loneNegation,
  unterminatedQuote,
  danglingEscape,
  invalidRating,
  invalidScore,
}

class TagFilterQueryError {
  const TagFilterQueryError(this.code, this.message);

  final TagFilterQueryErrorCode code;
  final String message;
}

class TagFilterQueryParseResult {
  const TagFilterQueryParseResult.success(this.query) : error = null;
  const TagFilterQueryParseResult.failure(this.error) : query = null;

  final TagFilterQuery? query;
  final TagFilterQueryError? error;
  bool get isValid => query != null;
}

class TagFilterQueryMatch {
  const TagFilterQueryMatch({required this.matches, this.matchedTags = const {}});

  final bool matches;
  final Set<String> matchedTags;
}

class TagFilterQuery {
  const TagFilterQuery._(this.raw, this.conditions);

  final String raw;
  final List<TagFilterCondition> conditions;

  Iterable<String> get positiveExactTags => conditions
      .whereType<TagCondition>()
      .where((condition) => !condition.negated && !condition.hasWildcard)
      .map((condition) => condition.pattern);

  Iterable<String> get positiveWildcardPrefixes => conditions
      .whereType<TagCondition>()
      .where((condition) => !condition.negated && condition.hasWildcard && condition.literalPrefix.isNotEmpty)
      .map((condition) => condition.literalPrefix);

  Iterable<String> get positiveWildcardSuffixes => conditions
      .whereType<TagCondition>()
      .where((condition) => !condition.negated && condition.hasWildcard && condition.literalSuffix.isNotEmpty)
      .map((condition) => condition.literalSuffix);

  Iterable<String> get positiveRatings => conditions
      .whereType<RatingCondition>()
      .where((condition) => !condition.negated)
      .map((condition) => condition.rating);

  TagFilterQueryMatch match(BooruItem item, {Set<String>? normalizedTags}) {
    final tags =
        normalizedTags ??
        item.tagsList.map((tag) => tag.fullString.trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet();
    final matchedTags = <String>{};

    for (final condition in conditions) {
      final result = condition.evaluate(item, tags);
      if (!result.matches) {
        return const TagFilterQueryMatch(matches: false);
      }
      if (!condition.negated) {
        matchedTags.addAll(result.matchedTags);
      }
    }
    return TagFilterQueryMatch(matches: true, matchedTags: matchedTags);
  }

  static TagFilterQueryParseResult parse(String input) {
    if (input.trim().isEmpty) {
      return const TagFilterQueryParseResult.failure(
        TagFilterQueryError(TagFilterQueryErrorCode.empty, 'Query cannot be empty'),
      );
    }

    final tokenResult = _tokenize(input);
    if (tokenResult.error != null) {
      return TagFilterQueryParseResult.failure(tokenResult.error);
    }
    if (tokenResult.tokens.isEmpty || tokenResult.tokens.every((token) => token.trim().isEmpty)) {
      return const TagFilterQueryParseResult.failure(
        TagFilterQueryError(TagFilterQueryErrorCode.empty, 'Query cannot be empty'),
      );
    }

    final conditions = <TagFilterCondition>[];
    for (final rawToken in tokenResult.tokens) {
      var token = rawToken;
      final negated = token.startsWith('-');
      if (negated) token = token.substring(1);
      if (token.isEmpty) {
        return const TagFilterQueryParseResult.failure(
          TagFilterQueryError(TagFilterQueryErrorCode.loneNegation, 'Negation must be followed by a condition'),
        );
      }

      final lower = token.toLowerCase();
      if (lower.startsWith('rating:')) {
        final value = lower.substring('rating:'.length).replaceAll(_escapedAsterisk, '*');
        final rating = switch (value) {
          'safe' || 's' => 'safe',
          'general' || 'g' => 'general',
          'sensitive' => 'sensitive',
          'questionable' || 'q' => 'questionable',
          'explicit' || 'e' => 'explicit',
          _ => null,
        };
        if (rating == null) {
          return const TagFilterQueryParseResult.failure(
            TagFilterQueryError(
              TagFilterQueryErrorCode.invalidRating,
              'Rating must be safe, general, sensitive, questionable, or explicit',
            ),
          );
        }
        conditions.add(RatingCondition(rating: rating, negated: negated));
        continue;
      }

      if (lower.startsWith('score:')) {
        final value = lower.substring('score:'.length).replaceAll(_escapedAsterisk, '*');
        final match = RegExp(r'^(>=|<=|=|>|<)(-?\d+)$').firstMatch(value);
        if (match == null) {
          return const TagFilterQueryParseResult.failure(
            TagFilterQueryError(TagFilterQueryErrorCode.invalidScore, 'Score requires an operator and an integer'),
          );
        }
        final threshold = int.tryParse(match.group(2)!);
        if (threshold == null) {
          return const TagFilterQueryParseResult.failure(
            TagFilterQueryError(TagFilterQueryErrorCode.invalidScore, 'Score integer is out of range'),
          );
        }
        conditions.add(
          ScoreCondition(
            operator: ScoreOperator.fromSymbol(match.group(1)!),
            threshold: threshold,
            negated: negated,
          ),
        );
        continue;
      }

      conditions.add(TagCondition.fromToken(token, negated: negated));
    }

    return TagFilterQueryParseResult.success(TagFilterQuery._(input, List.unmodifiable(conditions)));
  }

  /// Splits a query into raw condition strings without removing quotes or
  /// escapes. This is used by editors that need to round-trip valid syntax.
  static List<String> splitRawConditions(String input) {
    final conditions = <String>[];
    int? start;
    var inQuotes = false;
    var escaping = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (start == null && char.trim().isNotEmpty) start = index;
      if (start == null) continue;
      if (escaping) {
        escaping = false;
      } else if (char == r'\') {
        escaping = true;
      } else if (char == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && char.trim().isEmpty) {
        conditions.add(input.substring(start, index));
        start = null;
      }
    }
    if (start != null) conditions.add(input.substring(start));
    return conditions;
  }

  static String escapeExactTag(String tag) {
    var escaped = tag.replaceAll(r'\', r'\\').replaceAll('*', r'\*').replaceAll('"', r'\"');
    if (escaped.startsWith('-')) escaped = r'\-' + escaped.substring(1);
    if (escaped.contains(RegExp(r'\s'))) {
      escaped = '"$escaped"';
    }
    return escaped;
  }
}

class _TokenizeResult {
  const _TokenizeResult(this.tokens, this.error);
  final List<String> tokens;
  final TagFilterQueryError? error;
}

_TokenizeResult _tokenize(String input) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  var escaping = false;

  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(switch (char) {
        '*' => _escapedAsterisk,
        '-' => _escapedHyphen,
        _ => char,
      });
      escaping = false;
      continue;
    }
    if (char == r'\') {
      escaping = true;
      continue;
    }
    if (char == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && char.trim().isEmpty) {
      flush();
      continue;
    }
    buffer.write(char);
  }

  if (escaping) {
    return const _TokenizeResult(
      [],
      TagFilterQueryError(TagFilterQueryErrorCode.danglingEscape, 'Query ends with an incomplete escape'),
    );
  }
  if (inQuotes) {
    return const _TokenizeResult(
      [],
      TagFilterQueryError(TagFilterQueryErrorCode.unterminatedQuote, 'Query contains an unterminated quote'),
    );
  }
  flush();
  return _TokenizeResult(tokens, null);
}

class ConditionMatch {
  const ConditionMatch(this.matches, [this.matchedTags = const {}]);
  final bool matches;
  final Set<String> matchedTags;
}

abstract class TagFilterCondition {
  const TagFilterCondition({required this.negated});
  final bool negated;
  ConditionMatch evaluate(BooruItem item, Set<String> tags);
}

class TagCondition extends TagFilterCondition {
  TagCondition._({
    required this.pattern,
    required super.negated,
    required this.hasWildcard,
    required this.literalPrefix,
    required this.literalSuffix,
    this.matcher,
  });

  factory TagCondition.fromToken(String token, {required bool negated}) {
    final hasWildcard = token.contains('*');
    final pattern = token.replaceAll(_escapedAsterisk, '*').replaceAll(_escapedHyphen, '-').toLowerCase();
    final wildcardIndex = token.indexOf('*');
    final literalPrefix = wildcardIndex < 0
        ? ''
        : token
              .substring(0, wildcardIndex)
              .replaceAll(_escapedAsterisk, '*')
              .replaceAll(_escapedHyphen, '-')
              .toLowerCase();
    final lastWildcardIndex = token.lastIndexOf('*');
    final literalSuffix = lastWildcardIndex < 0
        ? ''
        : token
              .substring(lastWildcardIndex + 1)
              .replaceAll(_escapedAsterisk, '*')
              .replaceAll(_escapedHyphen, '-')
              .toLowerCase();
    RegExp? matcher;
    if (hasWildcard) {
      final source = token
          .split('*')
          .map(
            (part) => RegExp.escape(
              part.replaceAll(_escapedAsterisk, '*').replaceAll(_escapedHyphen, '-').toLowerCase(),
            ),
          )
          .join('.*');
      matcher = RegExp('^$source\$', caseSensitive: false, unicode: true);
    }
    return TagCondition._(
      pattern: pattern,
      negated: negated,
      hasWildcard: hasWildcard,
      literalPrefix: literalPrefix,
      literalSuffix: literalSuffix,
      matcher: matcher,
    );
  }

  final String pattern;
  final bool hasWildcard;
  final String literalPrefix;
  final String literalSuffix;
  final RegExp? matcher;

  @override
  ConditionMatch evaluate(BooruItem item, Set<String> tags) {
    if (!hasWildcard) {
      final matches = tags.contains(pattern);
      return ConditionMatch(negated ? !matches : matches, !negated && matches ? {pattern} : const {});
    }
    if (negated) {
      return ConditionMatch(!tags.any(matcher!.hasMatch));
    }
    Set<String>? matches;
    for (final tag in tags) {
      if (matcher!.hasMatch(tag)) (matches ??= <String>{}).add(tag);
    }
    return ConditionMatch(matches != null, matches ?? const {});
  }
}

class RatingCondition extends TagFilterCondition {
  const RatingCondition({required this.rating, required super.negated});
  final String rating;

  @override
  ConditionMatch evaluate(BooruItem item, Set<String> tags) {
    final raw = item.rating?.trim().toLowerCase();
    final normalized = switch (raw) {
      's' => 'safe',
      'q' => 'questionable',
      'e' => 'explicit',
      _ => raw,
    };
    final result = normalized == rating;
    return ConditionMatch(negated ? !result : result);
  }
}

enum ScoreOperator {
  equal,
  less,
  lessOrEqual,
  greater,
  greaterOrEqual;

  factory ScoreOperator.fromSymbol(String symbol) => switch (symbol) {
    '=' => equal,
    '<' => less,
    '<=' => lessOrEqual,
    '>' => greater,
    '>=' => greaterOrEqual,
    _ => throw ArgumentError.value(symbol),
  };

  bool compare(int value, int threshold) => switch (this) {
    equal => value == threshold,
    less => value < threshold,
    lessOrEqual => value <= threshold,
    greater => value > threshold,
    greaterOrEqual => value >= threshold,
  };
}

class ScoreCondition extends TagFilterCondition {
  const ScoreCondition({required this.operator, required this.threshold, required super.negated});
  final ScoreOperator operator;
  final int threshold;

  @override
  ConditionMatch evaluate(BooruItem item, Set<String> tags) {
    final score = int.tryParse(item.score?.trim() ?? '');
    final result = score != null && operator.compare(score, threshold);
    return ConditionMatch(negated ? !result : result);
  }
}
