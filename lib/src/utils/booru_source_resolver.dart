import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_identity.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class BooruSourceResolver {
  BooruSourceResolver._();

  static Booru? resolve(BooruItem item, {Iterable<Booru>? sources}) {
    final candidates = (sources ?? SettingsHandler.instance.booruList)
        .where(
          (booru) => booru.type != null && booru.type?.isFavouritesOrDownloads != true && booru.type != BooruType.Merge,
        )
        .toList();
    final identity = item.sourceIdentity;
    if (identity != null) {
      // A removed source must not silently turn into a different installation.
      return _unique(candidates.where(identity.matches));
    }
    final post = Uri.tryParse(item.postURL);
    final postMatches = _urlMatches(post, candidates);
    if (postMatches.isNotEmpty) return _unique(postMatches);

    final aliases = candidates.where((booru) {
      final base = Uri.tryParse(booru.baseURL ?? '');
      if (post == null || base == null || post.port != base.port || post.scheme != base.scheme) return false;
      return switch (booru.type) {
        BooruType.IdolSankaku =>
          IdolSankakuHandler.knownUrls.contains(base.host) && IdolSankakuHandler.knownUrls.contains(post.host),
        BooruType.Sankaku =>
          [...SankakuHandler.knownUrls, 'sankakuapi.com'].contains(base.host) &&
              SankakuHandler.knownPostUrls.contains(post.host),
        _ => false,
      };
    }).toList();
    if (aliases.isNotEmpty) return _unique(aliases);
    return _unique(_urlMatches(Uri.tryParse(item.fileURL), candidates));
  }

  static List<Booru> _urlMatches(Uri? url, List<Booru> sources) {
    if (url == null || url.host.isEmpty) return [];
    var longestPath = -1;
    final matches = <Booru>[];
    for (final source in sources) {
      final base = Uri.tryParse(BooruIdentity.normalizeBaseUrl(source.baseURL) ?? '');
      if (base == null || base.host != url.host || base.scheme != url.scheme || base.port != url.port) continue;
      final path = base.path;
      if (url.path != path && !url.path.startsWith('$path/')) continue;
      if (path.length > longestPath) {
        matches.clear();
        longestPath = path.length;
      }
      if (path.length == longestPath) matches.add(source);
    }
    return matches;
  }

  static Booru? _unique(Iterable<Booru> matches) {
    final candidates = matches.toList();
    if (candidates.length == 1) return candidates.single;
    return null;
  }
}
