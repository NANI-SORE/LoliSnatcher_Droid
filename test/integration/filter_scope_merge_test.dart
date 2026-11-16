import 'package:lolisnatcher/src/widgets/preview/compare_image_source.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_network.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_repository.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Booru('Source', BooruType.Danbooru, '', 'https://source.example', '');
  final favourites = Booru('Favourites', BooruType.Favourites, '', '', '');
  var now = DateTime.utc(2026, 11, 16);

  TagFilterRule rule({
    TagFilterEffect effect = TagFilterEffect.hide,
    DateTime? disabledUntil,
    TagFilterScope scope = const TagFilterScope.global(),
  }) => TagFilterRule(
    id: 'rule',
    name: 'Rule',
    query: 'cat',
    effect: effect,
    scope: scope,
    enabled: true,
    createdAt: now,
    updatedAt: now,
    disabledUntil: disabledUntil,
  );
  BooruItem item() => BooruItem.fromMap({
    'fileURL': 'https://source.example/1.jpg',
    'sampleURL': '',
    'thumbnailURL': '',
    'postURL': 'https://source.example/posts/1',
    'tags': ['cat'],
    'serverId': '1',
  });
  RequestScope scope(TagFilterHandler filters) => RequestScope(
    client: Dio.new,
    cookies: (_) async => '',
    saveCookies: (_, _) async => true,
    filters: filters,
    settings: SettingsHandler.instance,
    headless: true,
  );

  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    SettingsHandler.register().booruList.addAll([source, favourites]);
  });
  tearDownAll(SettingsHandler.unregister);

  test('headless download filtering honors suspended-rule expiry without a UI timer', () async {
    now = DateTime.utc(2026, 11, 16);
    final filters = TagFilterHandler.fromConfiguration(
      TagFilterConfiguration(rules: [rule(disabledUntil: now.add(const Duration(minutes: 1)))]),
      clock: () => now,
    );
    final handler = _Handler(source);
    try {
      await scope(filters).run(() async {
        expect(handler.eligibleForDownload(item()), true);
        now = now.add(const Duration(minutes: 2));
        expect(handler.eligibleForDownload(item()), false);
      });
    } finally {
      filters.dispose();
    }
  });

  test('local-view scopes apply during headless discovery with original source context', () async {
    final filters = TagFilterHandler.fromConfiguration(
      TagFilterConfiguration(rules: [rule(scope: const TagFilterScope.view(BooruType.Favourites))]),
    );
    try {
      await scope(filters).run(() async {
        final handler = _Handler(source);
        expect(handler.eligibleForDownload(item()), true);
        expect(handler.eligibleForDownload(item(), traversal: favourites), false);
        expect(CompareImageSource.evaluationFor(item(), source, viewBooru: favourites).isHidden, true);
        final comparison = CompareImageSource(item(), source, widthLimit: 100, viewBooru: favourites);
        await comparison.load();
        expect(comparison.loaded, false);
        expect(comparison.stopReason?.name, 'hidden');
        comparison.dispose();
      });
    } finally {
      filters.dispose();
    }
  });

  test('hidden-item restore changes display only and preserves raw rule diagnostics and download filtering', () async {
    final filters = TagFilterHandler.fromConfiguration(TagFilterConfiguration(rules: [rule()]));
    try {
      await scope(filters).run(() async {
        final handler = _Handler(source);
        final hidden = item();
        handler.fetched.add(hidden);
        handler.filterFetched();
        expect(handler.filteredFetched, isEmpty);
        expect(handler.filterHiddenItems.keys, contains(hidden));
        handler.restoreFilteredItems([hidden]);
        expect(handler.filteredFetched, [hidden]);
        expect(handler.filterEvaluationFor(hidden).isHidden, false);
        expect(handler.rawFilterEvaluationFor(hidden).isHidden, true);
        expect(handler.filterEvaluationFor(hidden).matches, hasLength(1));
        expect(handler.eligibleForDownload(hidden), false);
      });
    } finally {
      filters.dispose();
    }
  });

  test('hiding as blur does not bypass download exclusion', () async {
    final filters = TagFilterHandler.fromConfiguration(
      TagFilterConfiguration(rules: [rule()], hideAsBlur: const HideAsBlurState(enabled: true)),
    );
    try {
      await scope(filters).run(() async {
        final handler = _Handler(source);
        expect(handler.filterEvaluationFor(item()).isBlurred, true);
        expect(handler.eligibleForDownload(item()), false);
      });
    } finally {
      filters.dispose();
    }
  });

  test('missing persisted headless filters stop discovery instead of silently allowing items', () async {
    await expectLater(DownloadConfiguration({}).filterEvaluator, throwsA(isA<DownloadBlocked>()));
    final filters = await DownloadConfiguration({'filters': const TagFilterConfiguration().toJson()}).filterEvaluator;
    expect(filters.rules, isEmpty);
    filters.dispose();
  });

  test('restore pauses rule publications and publishes one coherent state on completion', () async {
    final root = await Directory.systemTemp.createTemp('filter-restore-');
    final filters = TagFilterHandler(JsonFilterRepository(root.path));
    try {
      await filters.initialize();
      final watched = _ObservedHandler(source);
      final unwatch = filters.watchHandler(watched);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final before = watched.refilters;
      var publications = 0;
      filters.revision.addListener(() => publications++);
      await filters.suspendForRestore();
      await filters.replaceFromString(jsonEncode(TagFilterConfiguration(rules: [rule()]).toJson()));
      filters.handleAppResumed();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(watched.refilters, before);
      expect(publications, 0);
      filters.finishRestore();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(watched.refilters, before + 1);
      expect(publications, 1);
      unwatch();
    } finally {
      filters.dispose();
      await root.delete(recursive: true);
    }
  });
}

class _ObservedHandler extends BooruHandler {
  _ObservedHandler(Booru source) : super(source, 20);
  int refilters = 0;
  @override
  Future<void> refilterFetched({required bool Function() shouldCancel, bool forceRefresh = true}) async {
    if (!shouldCancel()) refilters++;
  }
}

class _Handler extends BooruHandler {
  _Handler(Booru source) : super(source, 20);
}
