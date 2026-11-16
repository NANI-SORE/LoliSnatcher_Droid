import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/utils/booru_source_resolver.dart';
import 'package:lolisnatcher/src/utils/ordered_selection_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final first = Booru('First', BooruType.Danbooru, '', 'https://host.example/a', '');
  final second = Booru('Second', BooruType.Danbooru, '', 'https://host.example/b', '');
  late SearchHandler search;
  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    search = SearchHandler.register();
  });
  tearDown(() {
    search.tabs.clear();
    SX.limit.state.loadDefaultValue();
    SX.limit.state.removeOverrideFor('Second');
  });
  tearDownAll(SearchHandler.unregister);

  test('source limit changes invalidate pending pages only for affected grouped tabs', () {
    final sourceTab = SearchTab(first, null, 'a', groupId: 'group')..pendingRestorePage = 7;
    final mergedTab = SearchTab(first, [second], 'b', groupId: 'group')..pendingRestorePage = 9;
    search.tabs.addAll([sourceTab, mergedTab]);
    SX.limit.state.setOverrideFor('Second', SX.limit.valueForBooru('Second') + 1);
    search.invalidateSavedPages(booruName: 'Second');
    expect(sourceTab.hasValidPageCoordinates, true);
    expect(sourceTab.pendingRestorePage, 7);
    expect(mergedTab.hasValidPageCoordinates, false);
    expect(mergedTab.pendingRestorePage, isNull);
    expect(mergedTab.groupId.value, 'group');
  });

  test('selection index survives mutable item metadata and preserves order across replacement', () {
    final a = _item('https://host.example/a/posts/1');
    final b = _item('https://host.example/a/posts/2');
    final index = OrderedSelectionIndex<BooruItem>()..update([b, a]);
    a.savedFileName = 'actual.avif';
    a.isSnatched.value = true;
    a.serverId = 'new-server-id';
    expect(index.indexOf(b), 0);
    expect(index.indexOf(a), 1);
    expect(index.indexOf(_item(a.postURL)), isNull);
    index.update([a]);
    expect(index.indexOf(b), isNull);
    expect(index.indexOf(a), 0);
  });

  test('offline and download discovery resolve exact origin, longest path and valid preferred account', () {
    final root = Booru('Root', BooruType.Danbooru, '', 'https://host.example', '');
    final account = Booru('Account', BooruType.Danbooru, '', first.baseURL, '');
    final otherPort = Booru('Port', BooruType.Danbooru, '', 'https://host.example:8443/a', '');
    expect(
      BooruSourceResolver.resolve(_item('https://host.example/a/posts/1'), sources: [root, first, second]),
      same(first),
    );
    expect(BooruSourceResolver.resolve(_item('https://host.example/abc/posts/1'), sources: [root, first]), same(root));
    expect(
      BooruSourceResolver.resolve(_item('https://host.example:8443/a/posts/1'), sources: [first, otherPort]),
      same(otherPort),
    );
    final post = _item('https://host.example/a/posts/1');
    expect(BooruSourceResolver.resolve(post, sources: [first, account]), isNull);
    expect(BooruSourceResolver.resolve(post, sources: [first, account], preferred: account), same(account));
    expect(BooruSourceResolver.resolve(post, sources: [first, account], preferred: second), isNull);
  });
}

BooruItem _item(String post) => BooruItem(
  fileURL: 'https://cdn.example/image.jpg',
  sampleURL: '',
  thumbnailURL: '',
  postURL: post,
  tagsList: const [],
);
