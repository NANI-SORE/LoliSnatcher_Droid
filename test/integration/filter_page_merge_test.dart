import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Booru('source', BooruType.Danbooru, '', 'https://source.example', '');

  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    SettingsHandler.register().booruList.add(source);
  });
  tearDownAll(SettingsHandler.unregister);

  test('JSON numeric server IDs coexist with offline saved filenames', () {
    final item = BooruItem.fromMap({
      'fileURL': 'https://source.example/42.jpg',
      'sampleURL': '',
      'thumbnailURL': '',
      'postURL': 'https://source.example/posts/42',
      'tagsList': <String>[],
      'serverId': 42,
      'savedFileName': 'saved-42.jpg',
    });
    expect(item.serverId, '42');
    expect(item.savedFileName, 'saved-42.jpg');
  });

  test('page completion evaluates each new item once and retains API coordinates', () async {
    final handler = _CountingHandler(source);
    final first = _item(1);
    final second = _item(2);
    handler.pageNum = 3;
    await handler.afterParseResponse([first]);
    expect(handler.sourceLookups, 1);
    handler.pageNum = 4;
    await handler.afterParseResponse([second]);
    expect(handler.sourceLookups, 2);
    expect(handler.filteredFetched, [first, second]);
    expect(handler.fetchedPageNumbers, {3, 4});
    expect([first.fetchedPage, second.fetchedPage], [3, 4]);
  });
}

BooruItem _item(int id) => BooruItem(
  fileURL: 'https://source.example/$id.jpg',
  sampleURL: '',
  thumbnailURL: '',
  postURL: 'https://source.example/posts/$id',
  tagsList: const [],
  serverId: '$id',
);

class _CountingHandler extends BooruHandler {
  _CountingHandler(Booru source) : super(source, 20);

  int sourceLookups = 0;

  @override
  Booru sourceBooruFor(BooruItem item) {
    sourceLookups++;
    return booru;
  }

  @override
  Future<void> populateTagHandler(List<BooruItem> items) async {}
}
