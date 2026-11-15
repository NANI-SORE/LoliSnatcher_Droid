import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';

/// Danbooru distinguishes general and sensitive; other sources use s for safe.
String? normalizeBooruRating(String? rating, {Booru? booru, BooruType? sourceType}) =>
    switch (rating?.trim().toLowerCase()) {
      'g' => 'general',
      's' =>
        (booru?.type ?? sourceType) == null
            ? null
            : (booru?.type ?? sourceType)!.isDanbooru
            ? 'sensitive'
            : 'safe',
      'q' => 'questionable',
      'e' => 'explicit',
      'safe' || 'general' || 'sensitive' || 'questionable' || 'explicit' => rating!.trim().toLowerCase(),
      _ => null,
    };
