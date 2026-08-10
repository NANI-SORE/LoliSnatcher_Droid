import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

void main() {
  late SearchHandler searchHandler;

  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    searchHandler = SearchHandler.register();
  });

  tearDown(() {
    searchHandler
      ..tabs.clear()
      ..index.value = 0
      ..tabId.value = null;
  });

  tearDownAll(SearchHandler.unregister);

  test('removed booru tabs are rebuilt with the preferred booru and a matching handler', () {
    final removed = Booru('Removed', BooruType.Gelbooru, '', 'https://removed.example', '');
    final preferred = Booru('Preferred', BooruType.Danbooru, '', 'https://preferred.example', '');
    searchHandler.tabs.add(SearchTab(removed, [preferred], 'tag'));

    final replaced = searchHandler.replaceBooruInTabs(
      removed,
      preferred,
      refreshCurrent: false,
    );

    expect(replaced, 1);
    expect(searchHandler.currentBooru, same(preferred));
    expect(searchHandler.currentBooruHandler.booru, same(preferred));
    expect(searchHandler.currentSecondaryBoorus.value, isNull);
    expect(searchHandler.currentTab.tags, 'tag');
  });

  test('removed secondary boorus are dropped without changing the selected booru', () {
    final selected = Booru('Selected', BooruType.Gelbooru, '', 'https://selected.example', '');
    final removed = Booru('Removed', BooruType.Danbooru, '', 'https://removed.example', '');
    final secondary = Booru('Secondary', BooruType.e621, '', 'https://secondary.example', '');
    searchHandler.tabs.add(SearchTab(selected, [removed, secondary], 'tag'));

    searchHandler.replaceBooruInTabs(
      removed,
      selected,
      refreshCurrent: false,
    );

    expect(searchHandler.currentBooru, same(selected));
    expect(searchHandler.currentSecondaryBoorus.value, [secondary]);
  });
}
