import 'package:lolisnatcher/src/data/booru.dart';

/// Danbooru distinguishes general and sensitive; other sources use s for safe.
String? normalizeBooruRating(String? rating, {Booru? booru}) => switch (rating?.trim().toLowerCase()) {
  'g' => 'general',
  's' => booru?.type?.isDanbooru == true ? 'sensitive' : 'safe',
  'q' => 'questionable',
  'e' => 'explicit',
  final value => value,
};
