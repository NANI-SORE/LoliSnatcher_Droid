import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_form_controller.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_utils.dart';

void main() {
  group('booru edit URL helpers', () {
    test('normalizes schemes, trailing slashes, and hosts', () {
      expect(normalizeBooruUrl(' example.com/// '), 'https://example.com');
      expect(normalizeBooruUrl('http://example.com/'), 'http://example.com');
      expect(normalizedBooruHost('https://www.e926.net/posts'), 'e926.net');
    });

    test('maps known hosts and special endpoint URLs', () {
      expect(knownBooruTypeForHost('e926.net'), BooruType.e621);
      expect(knownBooruTypeForHost('idol.sankakucomplex.com'), BooruType.IdolSankaku);
      expect(knownBooruTypeForHost('unknown.example'), isNull);
      expect(booruApiUrlFor('https://chan.sankakucomplex.com'), 'https://sankakuapi.com');
      expect(booruFaviconUrlFor('https://rule34.us'), 'https://rule34.us/favicon.png');
    });
  });

  test('conflict detection excludes the edited booru and catches peers', () {
    final original = Booru('Original', BooruType.Gelbooru, '', 'https://one.example', '');
    final peer = Booru('Peer', BooruType.Danbooru, '', 'https://two.example', '');
    final existing = [original, peer];

    expect(
      findBooruEditConflict(existingBoorus: existing, original: original, candidate: original),
      isNull,
    );
    expect(
      findBooruEditConflict(
        existingBoorus: existing,
        original: original,
        candidate: Booru('Peer', BooruType.Gelbooru, '', 'https://new.example', ''),
      ),
      BooruEditConflict.name,
    );
    expect(
      findBooruEditConflict(
        existingBoorus: existing,
        original: original,
        candidate: Booru('New name', BooruType.Gelbooru, '', 'https://two.example', ''),
      ),
      BooruEditConflict.url,
    );
  });

  test('form controller owns draft values and invalidates stale tests', () {
    final controller = BooruEditFormController(
      Booru.withKey(
        'Example',
        BooruType.Gelbooru,
        'favicon',
        'https://example.com',
        'tag',
        'key',
        'user',
      ),
    );
    addTearDown(controller.dispose);

    expect(controller.toBooru().name, 'Example');
    controller.markTestSuccessful(BooruType.Gelbooru);
    expect(controller.hasCurrentSuccessfulTest, isTrue);

    controller.apiKey.text = 'changed';
    controller.invalidateTestResult();

    expect(controller.testedType, isNull);
    expect(controller.hasCurrentSuccessfulTest, isFalse);
  });
}
