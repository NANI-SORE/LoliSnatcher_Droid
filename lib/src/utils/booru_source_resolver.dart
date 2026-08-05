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
    for (final booru in SettingsHandler.instance.booruList) {
      if (booru.type?.isFavouritesOrDownloads == true) continue;
      final booruHost = Uri.tryParse(booru.baseURL ?? '')?.host;
      final postMatches =
          itemPostHost?.isNotEmpty == true &&
          booruHost?.isNotEmpty == true &&
          (itemPostHost == booruHost ||
              switch (booru.type) {
                BooruType.IdolSankaku => IdolSankakuHandler.knownUrls.contains(itemPostHost),
                BooruType.Sankaku => SankakuHandler.knownPostUrls.contains(itemPostHost),
                _ => false,
              });
      final fileMatches =
          itemFileHost?.isNotEmpty == true && booruHost?.isNotEmpty == true && itemFileHost == booruHost;
      if (postMatches || fileMatches) return booru;
    }
    return null;
  }
}
