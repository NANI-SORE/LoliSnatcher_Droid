import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';

enum BooruEditConflict { duplicate, name, url }

String normalizeBooruUrl(String input) {
  var normalized = input.trim();
  if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
    normalized = 'https://$normalized';
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String normalizedBooruHost(String input) {
  final normalized = input.trim().contains('://') ? input.trim() : 'https://${input.trim()}';
  return Uri.tryParse(normalized)?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '') ?? '';
}

BooruType? knownBooruTypeForHost(String host) {
  return _knownBooruTypes[host];
}

String booruApiUrlFor(String url) {
  if (IdolSankakuHandler.knownUrls.any(url.contains)) {
    return 'https://iapi.sankakucomplex.com';
  }
  if (SankakuHandler.knownUrls.any(url.contains)) {
    return 'https://sankakuapi.com';
  }
  return url;
}

String booruFaviconUrlFor(String url) {
  if (url.contains('agn.ph')) {
    return 'https://agn.ph/skin/Retro/favicon.ico';
  }
  if (url.contains('rule34.us')) {
    return 'https://rule34.us/favicon.png';
  }
  if ([...SankakuHandler.knownUrls, ...IdolSankakuHandler.knownUrls, 'sankakuapi.com'].any(url.contains)) {
    return 'https://sankaku.app/images/favicon-32x32.png';
  }
  return '$url/favicon.ico';
}

BooruEditConflict? findBooruEditConflict({
  required Iterable<Booru> existingBoorus,
  required Booru original,
  required Booru candidate,
}) {
  var skippedOriginal = false;
  for (final existing in existingBoorus) {
    final isOriginal =
        original.name != 'New' &&
        !skippedOriginal &&
        (identical(existing, original) || (existing.name == original.name && existing.baseURL == original.baseURL));
    if (isOriginal) {
      skippedOriginal = true;
      continue;
    }

    final sameName = existing.name == candidate.name;
    final sameUrl = existing.baseURL == candidate.baseURL;
    if (sameName && sameUrl) return BooruEditConflict.duplicate;
    if (sameName) return BooruEditConflict.name;
    if (sameUrl) return BooruEditConflict.url;
  }
  return null;
}

const _knownBooruTypes = <String, BooruType>{
  'agn.ph': BooruType.AGNPH,
  'bleachbooru.org': BooruType.Danbooru,
  'booru.allthefallen.moe': BooruType.Danbooru,
  'chan.sankakucomplex.com': BooruType.Sankaku,
  'danbooru.donmai.us': BooruType.Danbooru,
  'derpibooru.org': BooruType.Philomena,
  'e621.net': BooruType.e621,
  'e926.net': BooruType.e621,
  'furbooru.org': BooruType.Philomena,
  'furry.booru.org': BooruType.Gelbooru,
  'gelbooru.com': BooruType.Gelbooru,
  'idol.sankakucomplex.com': BooruType.IdolSankaku,
  'inkbunny.net': BooruType.InkBunny,
  'konachan.com': BooruType.Moebooru,
  'konachan.net': BooruType.Moebooru,
  'lolibooru.moe': BooruType.Moebooru,
  'manebooru.art': BooruType.BooruOnRails,
  'nyanpals.com': BooruType.NyanPals,
  'ponybooru.org': BooruType.Philomena,
  'rainbooru.org': BooruType.Rainbooru,
  'realbooru.com': BooruType.Realbooru,
  'rule34.paheal.net': BooruType.Shimmie,
  'rule34.us': BooruType.R34US,
  'rule34.world': BooruType.World,
  'rule34.xxx': BooruType.Gelbooru,
  'rule34.xyz': BooruType.World,
  'rule34hentai.net': BooruType.R34Hentai,
  'rule34vault.com': BooruType.World,
  'safebooru.donmai.us': BooruType.Danbooru,
  'safebooru.org': BooruType.Gelbooru,
  'sankaku.app': BooruType.Sankaku,
  'sankakucomplex.com': BooruType.Sankaku,
  'sonohara.donmai.us': BooruType.Danbooru,
  'tantabus.ai': BooruType.Philomena,
  'tbib.org': BooruType.Gelbooru,
  'twibooru.org': BooruType.BooruOnRails,
  'wildcritters.ws': BooruType.WildCritters,
  'xbooru.com': BooruType.GelbooruV1,
  'yande.re': BooruType.Moebooru,
};
