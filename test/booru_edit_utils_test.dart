import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_form_controller.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_utils.dart';

void main() {
  group('booru edit URL helpers', () {
    test('normalizes schemes, trailing slashes, and hosts', () {
      expect(normalizeBooruUrl(' example.com/// '), 'https://example.com');
      expect(normalizeBooruUrl('http://example.com/'), 'http://example.com');
      expect(normalizeBooruUrl('HTTPS://Example.com/'), 'https://Example.com');
      expect(normalizedBooruHost('https://www.e926.net/posts'), 'e926.net');
      expect(canonicalBooruUrl('HTTPS://WWW.Example.com:443/posts/'), 'https://example.com/posts');
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
    expect(
      findBooruEditConflict(
        existingBoorus: existing,
        original: null,
        candidate: Booru('peer', BooruType.Gelbooru, '', 'https://new.example', ''),
      ),
      BooruEditConflict.name,
    );
    expect(
      findBooruEditConflict(
        existingBoorus: existing,
        original: null,
        candidate: Booru('Another', BooruType.Gelbooru, '', 'HTTPS://WWW.TWO.EXAMPLE:443/', ''),
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
      trustInitialConnection: false,
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

  test('existing drafts trust only unchanged connection fields', () {
    final controller = BooruEditFormController(
      Booru('Example', BooruType.Gelbooru, '', 'https://example.com', 'tag'),
      trustInitialConnection: true,
    );
    addTearDown(controller.dispose);

    expect(controller.hasCurrentSuccessfulTest, isTrue);
    controller.name.text = 'Renamed';
    controller.defaultTags.text = 'another_tag';
    expect(controller.hasCurrentSuccessfulTest, isTrue);

    controller.url.text = 'https://changed.example';
    controller.invalidateTestResult();
    expect(controller.hasCurrentSuccessfulTest, isFalse);
  });

  test('stale asynchronous test signatures are rejected', () {
    final controller = BooruEditFormController(
      Booru('', BooruType.Autodetect, '', 'https://example.com', ''),
      trustInitialConnection: false,
    );
    addTearDown(controller.dispose);

    final testedSignature = controller.testSignature();
    controller.apiKey.text = 'changed while testing';

    expect(
      controller.markTestSuccessfulIfCurrent(BooruType.Gelbooru, testedSignature),
      isFalse,
    );
    expect(controller.hasCurrentSuccessfulTest, isFalse);
  });

  test('booru editor mode is explicit for blank, imported, and existing configs', () {
    final imported = Booru('Imported', BooruType.Gelbooru, '', 'https://example.com', '');

    expect(BooruEdit.add().mode, BooruEditMode.add);
    expect(BooruEdit.add(initialBooru: imported).mode, BooruEditMode.add);
    expect(BooruEdit.edit(imported).mode, BooruEditMode.edit);
    expect(BooruEdit.edit(Booru('New', BooruType.Gelbooru, '', 'https://example.com', '')).mode, BooruEditMode.edit);
  });
}
