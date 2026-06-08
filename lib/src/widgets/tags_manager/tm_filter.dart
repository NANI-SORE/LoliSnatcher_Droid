import 'package:lolisnatcher/src/data/tag.dart';

final RegExp _typeFilterPattern = RegExp(r'(?:^|\s)type:(\S+)', caseSensitive: false);
final RegExp _staleFilterPattern = RegExp(
  r'(?:^|\s)stale:(true|false|yes|y|no|n|1|0)',
  caseSensitive: false,
);

List<Tag> filterTagsByQuery(List<Tag> tags, String query) {
  final String trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return [...tags];
  }

  String textQuery = trimmedQuery;
  String? typeQuery;
  bool? staleQuery;

  final Match? typeMatch = _typeFilterPattern.firstMatch(textQuery);
  if (typeMatch != null) {
    typeQuery = typeMatch.group(1)!.toLowerCase();
    textQuery = textQuery.replaceRange(typeMatch.start, typeMatch.end, ' ');
  }

  final Match? staleMatch = _staleFilterPattern.firstMatch(textQuery);
  if (staleMatch != null) {
    staleQuery = switch (staleMatch.group(1)!.toLowerCase()) {
      'true' || 'yes' || 'y' || '1' => true,
      _ => false,
    };
    textQuery = textQuery.replaceRange(staleMatch.start, staleMatch.end, ' ');
  } else {
    final String normalizedQuery = textQuery.trim().toLowerCase();
    if (normalizedQuery == 'stale') {
      staleQuery = true;
      textQuery = '';
    } else if (normalizedQuery == 'notstale') {
      staleQuery = false;
      textQuery = '';
    }
  }

  final List<RegExp> textPatterns = textQuery
      .trim()
      .split(RegExp(r'\s+'))
      .where((entry) => entry.isNotEmpty)
      .map(_buildTextPattern)
      .toList();

  return tags.where((tag) {
    final bool matchesText = textPatterns.isEmpty || textPatterns.any((pattern) => pattern.hasMatch(tag.fullString));
    final bool matchesType =
        typeQuery == null ||
        tag.tagType.name.toLowerCase() == typeQuery ||
        (typeQuery.length == 1 && tag.tagType.name[0].toLowerCase() == typeQuery[0].toLowerCase()) ||
        tag.tagType.name.substring(0, 2).toLowerCase() == typeQuery.substring(0, 2).toLowerCase();
    final bool matchesStale = staleQuery == null || tag.isStale() == staleQuery;
    return matchesText && matchesType && matchesStale;
  }).toList();
}

RegExp _buildTextPattern(String query) {
  try {
    return RegExp(query, caseSensitive: false);
  } on FormatException {
    return RegExp(RegExp.escape(query), caseSensitive: false);
  }
}
