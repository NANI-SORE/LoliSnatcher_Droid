import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/idol_sankaku_handler.dart';
import 'package:lolisnatcher/src/boorus/sankaku_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

class BooruSourceResolver {
  BooruSourceResolver._();

  static Booru? resolve(BooruItem item) {
    final itemFileHost = Uri.tryParse(item.fileURL)?.host;
    final itemPostHost = Uri.tryParse(item.postURL)?.host;
    final sources = SettingsHandler.instance.booruList.where((booru) => booru.type?.isFavouritesOrDownloads != true);

    // A post URL identifies its source more reliably than a media host,
    // which can also be a configured CDN or another booru's base URL.
    for (final booru in sources) {
      final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
      if (itemPostHost?.isNotEmpty == true &&
          booruHost?.isNotEmpty == true &&
          (itemPostHost == booruHost ||
              switch (booru.type) {
                BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                _ => false,
              })) {
        return booru;
      }
    }
    if (itemFileHost?.isNotEmpty == true) {
      for (final booru in sources) {
        final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
        if (booruHost?.isNotEmpty == true && itemFileHost == booruHost) return booru;
      }
    }
    return null;
  }
}
