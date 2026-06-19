import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/server_favorites/server_favorite_models.dart';
import 'package:lolisnatcher/src/handlers/server_favorite_adapter.dart';

void main() {
  group('server favorite adapters', () {
    test('maps capabilities by booru type', () {
      const factory = ServerFavoriteAdapterFactory();

      final danbooru = factory.adapterFor(
        Booru.withKey('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', '', 'key', 'login'),
      );
      final gelbooru = factory.adapterFor(
        Booru.withKey('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', '', 'pass_hash', '123'),
      );
      final rule34 = factory.adapterFor(
        Booru.withKey('rule34', BooruType.Gelbooru, '', 'https://rule34.xxx', '', 'key', '123'),
      );
      final idol = factory.adapterFor(
        Booru.withKey('idol', BooruType.IdolSankaku, '', 'https://idol.sankakucomplex.com', '', 'pass', 'login'),
      );

      expect(danbooru?.capabilities.canAdd, true);
      expect(gelbooru?.capabilities.canRemove, true);
      expect(rule34?.capabilities.canFetch, true);
      expect(rule34?.capabilities.canAdd, false);
      expect(idol?.capabilities.canFetch, true);
      expect(idol?.capabilities.canAdd, false);
    });

    test('extracts server ids from common post urls', () {
      const factory = ServerFavoriteAdapterFactory();

      final danbooru = factory.adapterFor(Booru('danbooru', BooruType.Danbooru, '', 'https://danbooru.donmai.us', ''));
      final gelbooru = factory.adapterFor(Booru('gelbooru', BooruType.Gelbooru, '', 'https://gelbooru.com', ''));
      final sankaku = factory.adapterFor(Booru('sankaku', BooruType.Sankaku, '', 'https://chan.sankakucomplex.com', ''));
      final rule34 = factory.adapterFor(Booru('rule34', BooruType.Gelbooru, '', 'https://rule34.xxx', ''));

      expect(danbooru?.serverIdFromUrl('https://danbooru.donmai.us/posts/123?q=x'), '123');
      expect(gelbooru?.serverIdFromUrl('https://gelbooru.com/index.php?page=post&s=view&id=456'), '456');
      expect(sankaku?.serverIdFromUrl('https://chan.sankakucomplex.com/post/show/789'), '789');
      expect(rule34?.serverIdFromUrl('https://rule34.xxx/index.php?page=post&s=view&id=321'), '321');
    });
  });

  group('server favorites diff', () {
    test('calculates mode actions', () {
      final local = {
        '1': _item('1'),
        '2': _item('2'),
      };
      final server = {
        '2': _item('2'),
        '3': _item('3'),
      };
      final diff = ServerFavoritesDiff(localById: local, serverById: server);

      final importPreview = ServerFavoritesSyncPreview(diff: diff, mode: ServerFavoriteSyncMode.importServer);
      final mergePreview = ServerFavoritesSyncPreview(diff: diff, mode: ServerFavoriteSyncMode.twoWayMerge);
      final mirrorServerPreview = ServerFavoritesSyncPreview(diff: diff, mode: ServerFavoriteSyncMode.mirrorServerToLocal);
      final mirrorLocalPreview = ServerFavoritesSyncPreview(diff: diff, mode: ServerFavoriteSyncMode.mirrorLocalToServer);

      expect(importPreview.addLocal, 1);
      expect(importPreview.addServer, 0);
      expect(mergePreview.addLocal, 1);
      expect(mergePreview.addServer, 1);
      expect(mirrorServerPreview.removeLocal, 1);
      expect(mirrorLocalPreview.removeServer, 1);
      expect(mirrorLocalPreview.mode.isDestructive, true);
    });
  });

  test('BooruItem.fromDBRow derives missing serverId from postURL', () {
    final item = BooruItem.fromDBRow(
      {
        'fileURL': 'https://img.example/1.jpg',
        'sampleURL': 'https://img.example/1.jpg',
        'thumbnailURL': 'https://img.example/1.jpg',
        'postURL': 'https://rule34.xxx/index.php?page=post&s=view&id=987',
        'isFavourite': 1,
        'isSnatched': 0,
        'serverId': null,
      },
      const [],
    );

    expect(item.serverId, '987');
  });
}

BooruItem _item(String id) {
  final item = BooruItem(
    fileURL: 'https://example.com/$id.jpg',
    sampleURL: 'https://example.com/$id.jpg',
    thumbnailURL: 'https://example.com/$id.jpg',
    tagsList: const [],
    postURL: 'https://example.com/posts/$id',
    serverId: id,
  );
  item.isFavourite.value = true;
  item.isSnatched.value = false;
  return item;
}
