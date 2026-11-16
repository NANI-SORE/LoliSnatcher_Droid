import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.bytes, this.onRequest, {this.sources = const {}});
  final Uint8List bytes;
  final Map<String, Uint8List> sources;
  final VoidCallback onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest();
    final payload = sources[options.uri.path] ?? bytes;
    return ResponseBody.fromBytes(
      payload,
      200,
      headers: {
        HttpHeaders.contentTypeHeader: ['image/png'],
        HttpHeaders.contentLengthHeader: ['${payload.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final memory = ImageMemoryManager.instance;
  setUpAll(() {
    registerAllSettings();
    SettingsHandler.register().blurImages = false;
    SX.gifsAsThumbnails.state.setValue(true, save: false);
    SX.thumbnailCache.state.setValue(false, save: false);
  });
  tearDownAll(SettingsHandler.unregister);

  for (final animateThumbnails in [false, true]) {
    testWidgets('sample quality recovers with animations=$animateThumbnails', (tester) async {
      SX.gifsAsThumbnails.state.setValue(animateThumbnails, save: false);
      Future<Uint8List> png(int width, int height) async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(width, height);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        return bytes;
      }

      late Uint8List sample, thumbnail;
      await tester.runAsync(() async {
        sample = await png(320, 200);
        thumbnail = await png(40, 20);
      });
      final item = BooruItem(
        fileURL: 'https://fixture.invalid/original.png',
        sampleURL: 'https://fixture.invalid/sample-quality.png',
        thumbnailURL: 'https://fixture.invalid/thumbnail-quality.png',
        postURL: '',
        tagsList: const [],
      );
      final scope = RequestScope(
        client: () => Dio()
          ..httpClientAdapter = _FixtureAdapter(
            thumbnail,
            () {},
            sources: {
              '/sample-quality.png': sample,
            },
          ),
        cookies: (_) async => '',
        saveCookies: (_, _) async => true,
      );
      Future<void> drain() async {
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      try {
        await scope.run(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 320,
                  height: 200,
                  child: Thumbnail(
                    item: item,
                    filterEvaluation: const TagFilterEvaluation.empty(),
                    isStandalone: true,
                    useHero: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 201));
          await drain();
          final dynamic state = tester.state(
            find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ThumbnailImage'),
          );
          state.onError(const ImageMemoryException('Native decoder temporarily out of memory', isTransient: true));
          await drain();
          expect(memory.underPressure.value, true);
          expect(tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image?.width == 40), true);
          await tester.pump(ImageMemoryManager.pressureCooldown);
          await drain();
          expect(
            tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image?.width == 320),
            true,
            reason: 'A temporary fallback must not permanently lower the selected preview quality',
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        await tester.pump(ImageMemoryManager.pressureCooldown);
        SX.gifsAsThumbnails.state.setValue(true, save: false);
        tester.binding.scheduleFrame();
        await tester.pump();
      }
    });
  }

  for (final transition in ['viewer transitions', 'memory pressure cooldown', 'scroll away and back']) {
    final pressure = transition == 'memory pressure cooldown';
    final remount = transition == 'scroll away and back';
    testWidgets('static thumbnail reuses decoded pixels through $transition', (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 80);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
      });
      var requests = 0;
      final item = BooruItem(
        fileURL: 'https://fixture.invalid/lifecycle-${transition.hashCode}.png',
        sampleURL: '',
        thumbnailURL: 'https://fixture.invalid/lifecycle-${transition.hashCode}.png',
        tagsList: const [],
        postURL: '',
      );
      final owner = Object();
      final scope = RequestScope(
        client: () => Dio()..httpClientAdapter = _FixtureAdapter(bytes, () => requests++),
        cookies: (_) async => '',
        saveCookies: (_, _) async => true,
      );
      await scope.run(() async {
        final grid = MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              height: 80,
              child: Thumbnail(
                item: item,
                filterEvaluation: const TagFilterEvaluation.empty(),
                isStandalone: true,
                useHero: false,
                forceThumbnail: true,
              ),
            ),
          ),
        );
        await tester.pumpWidget(grid);
        await tester.pump(const Duration(milliseconds: 201));
        for (
          var i = 0;
          i < 100 && !tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image != null);
          i++
        ) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(seconds: 1));
        expect(requests, 1);
        final original = tester.widgetList<RawImage>(find.byType(RawImage)).singleWhere((w) => w.image != null).image!;
        final before = original.clone();
        try {
          if (remount) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(grid);
            await tester.pump(const Duration(milliseconds: 201));
            for (
              var i = 0;
              i < 100 && !tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image != null);
              i++
            ) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
              await tester.pump(const Duration(milliseconds: 10));
            }
          } else if (pressure) {
            memory.handleMemoryPressure();
          } else {
            memory.setImageViewerActive(owner, true);
          }
          await tester.pump();
          await tester.pump();
          final images = tester.widgetList<RawImage>(find.byType(RawImage)).where((w) => w.image != null);
          expect(images, isNotEmpty, reason: 'Already visible pixels must survive the transition');
          expect(images.single.image!.isCloneOf(before), true, reason: 'Static images must not be decoded again');
          if (pressure) {
            await tester.pump(ImageMemoryManager.pressureCooldown);
          } else {
            memory.setImageViewerActive(owner, false);
          }
          await tester.pump();
          await tester.pump();
          expect(
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .singleWhere((w) => w.image != null)
                .image!
                .isCloneOf(before),
            true,
          );
          expect(requests, 1);
        } finally {
          before.dispose();
          memory.setImageViewerActive(owner, false);
          await tester.pumpWidget(const SizedBox.shrink());
          PaintingBinding.instance.imageCache.clear();
          await tester.pump(ImageMemoryManager.pressureCooldown);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        }
      });
    });
  }
}
