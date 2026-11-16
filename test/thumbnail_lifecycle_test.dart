import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/preview_quality.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

void main() {
  final memory = ImageMemoryManager.instance;
  setUpAll(() {
    final settings = SettingsHandler.register();
    settings.blurImages = false;
    settings.gifsAsThumbnails = true;
    settings.thumbnailCache = true;
    settings.previewMode = PreviewQuality.thumbnail;
  });
  tearDownAll(SettingsHandler.unregister);

  for (final transition in ['viewer', 'pressure', 'remount']) {
    testWidgets('static thumbnail reuses decoded pixels after $transition', (tester) async {
      final url = 'https://fixture.invalid/lifecycle-${DateTime.now().microsecondsSinceEpoch}.png';
      late File fixture;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 80);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        fixture = (await ImageWriter().writeCacheFromBytes(url, bytes, 'thumbnails', fileNameExtras: ''))!;
      });
      final item = BooruItem(fileURL: url, sampleURL: url, thumbnailURL: url, tagsList: const [], postURL: '');
      final grid = MaterialApp(
        home: Center(
          child: SizedBox(width: 120, height: 80, child: Thumbnail(item: item, isStandalone: true, useHero: false)),
        ),
      );
      Future<void> waitForImage() async {
        await tester.pump(const Duration(milliseconds: 201));
        for (
          var i = 0;
          i < 100 && !tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image != null);
          i++
        ) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 10));
        }
      }

      final owner = Object();
      ui.Image? original;
      try {
        await tester.pumpWidget(grid);
        await waitForImage();
        original = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .singleWhere((w) => w.image != null)
            .image!
            .clone();
        if (transition == 'viewer') {
          memory.setImageViewerActive(owner, true);
        } else if (transition == 'pressure') {
          memory.handleMemoryPressure();
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(grid);
          await waitForImage();
        }
        await tester.pump();
        await tester.pump();
        expect(
          tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image?.isCloneOf(original!) == true),
          true,
        );
        memory.setImageViewerActive(owner, false);
        if (transition == 'pressure') await tester.pump(ImageMemoryManager.pressureCooldown);
        await tester.pump();
        await tester.pump();
        expect(
          tester.widgetList<RawImage>(find.byType(RawImage)).any((w) => w.image?.isCloneOf(original!) == true),
          true,
        );
      } finally {
        original?.dispose();
        memory.setImageViewerActive(owner, false);
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        await tester.pump(ImageMemoryManager.pressureCooldown);
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.runAsync(() => fixture.delete());
      }
    });
  }
}
