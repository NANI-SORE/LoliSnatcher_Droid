import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

void main() {
  for (final shared in [false, true]) {
    testWidgets('animation ownership survives first-frame disposal, shared=$shared', (tester) async {
      late Directory root;
      late File file;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('animation-abandoned-');
        final encoder = img.GifEncoder()
          ..addFrame(img.fill(img.Image(width: 8, height: 8), color: img.ColorRgb8(255, 0, 0)))
          ..addFrame(img.fill(img.Image(width: 8, height: 8), color: img.ColorRgb8(0, 0, 255)));
        file = await File('${root.path}/animation.gif').writeAsBytes(encoder.finish()!);
      });
      final memory = ImageMemoryManager.instance;
      final retainedBefore = memory.retainedBytes;
      final token = CancelToken();
      final provider = CustomNetworkImage(file.uri.toString(), localFilePath: file.path, cancelToken: token);
      late ImageStream stream;
      ImageStream? second;
      final secondToken = CancelToken();
      var secondFrames = 0;
      final secondListener = ImageStreamListener((info, _) {
        secondFrames++;
        info.dispose();
      });
      var delivered = 0;
      final listener = ImageStreamListener((info, _) {
        delivered++;
        info.dispose();
      });
      try {
        await tester.runAsync(() async {
          stream = provider.resolve(ImageConfiguration.empty);
          stream.addListener(listener);
          if (shared) {
            second = CustomNetworkImage(
              file.uri.toString(),
              localFilePath: file.path,
              cancelToken: secondToken,
            ).resolve(ImageConfiguration.empty);
            second!.addListener(secondListener);
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        expect(memory.retainedBytes, greaterThan(retainedBefore));
        expect(delivered, 0, reason: 'The animation frame waits for the next Flutter frame');
        stream.removeListener(listener);
        token.cancel();
        await tester.pump();
        await tester.pump();
        if (shared) {
          expect(secondFrames, greaterThan(0));
          expect(PaintingBinding.instance.imageCache.statusForKey(provider).keepAlive, true);
          second!.removeListener(secondListener);
          secondToken.cancel();
          tester.binding.scheduleFrame();
          await tester.pump();
        }
        expect(PaintingBinding.instance.imageCache.statusForKey(provider).keepAlive, false);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(memory.retainedBytes, retainedBefore);
      } finally {
        stream.removeListener(listener);
        second?.removeListener(secondListener);
        secondToken.cancel();
        await provider.evict();
        await tester.runAsync(() => root.delete(recursive: true));
      }
    });
  }

  testWidgets('poster-only decode still identifies animated payload behind a PNG URL', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('animated-poster-');
      final encoder = img.GifEncoder()
        ..addFrame(img.fill(img.Image(width: 8, height: 8), color: img.ColorRgb8(255, 0, 0)))
        ..addFrame(img.fill(img.Image(width: 8, height: 8), color: img.ColorRgb8(0, 0, 255)));
      final file = await File('${root.path}/misleading.png').writeAsBytes(encoder.finish()!);
      final provider = CustomNetworkImage(file.uri.toString(), localFilePath: file.path, firstFrameOnly: true);
      final stream = provider.resolve(ImageConfiguration.empty);
      final result = Completer<ImageInfo>();
      final listener = ImageStreamListener((info, _) => result.complete(info), onError: result.completeError);
      stream.addListener(listener);
      try {
        final info = await result.future.timeout(const Duration(seconds: 10));
        info.dispose();
        expect(imageStreamIsAnimated(stream), true);
      } finally {
        stream.removeListener(listener);
        await provider.evict();
        await root.delete(recursive: true);
      }
    });
  });

  testWidgets('equal request headers share one decode; different credentials stay isolated', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('image-cache-identity-');
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 20);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      final file = await File('${root.path}/fixture.png').writeAsBytes(bytes);
      final providers = [
        CustomNetworkImage(
          'https://fixture.invalid/image.png',
          localFilePath: file.path,
          headers: Map<String, String>.of({'Authorization': 'fixture-a', 'Accept': 'image/*'}),
        ),
        CustomNetworkImage(
          'https://fixture.invalid/image.png',
          localFilePath: file.path,
          headers: Map<String, String>.of({'Accept': 'image/*', 'Authorization': 'fixture-a'}),
        ),
        CustomNetworkImage(
          'https://fixture.invalid/image.png',
          localFilePath: file.path,
          headers: Map<String, String>.of({'Authorization': 'fixture-b', 'Accept': 'image/*'}),
        ),
      ];
      final streams = providers.map((p) => p.resolve(ImageConfiguration.empty)).toList();
      final results = List.generate(3, (_) => Completer<ImageInfo>());
      final listeners = List.generate(
        3,
        (i) => ImageStreamListener((info, _) => results[i].complete(info), onError: results[i].completeError),
      );
      for (var i = 0; i < 3; i++) {
        streams[i].addListener(listeners[i]);
      }
      try {
        final images = await Future.wait(results.map((r) => r.future.timeout(const Duration(seconds: 10))));
        try {
          expect(imageStreamIsAnimated(streams.first), false);
          expect(
            images[0].image.isCloneOf(images[1].image),
            true,
            reason: 'Equivalent requests must share decoded pixels',
          );
          expect(
            images[0].image.isCloneOf(images[2].image),
            false,
            reason: 'Credentials remain part of the cache identity',
          );
        } finally {
          for (final info in images) {
            info.dispose();
          }
        }
      } finally {
        for (var i = 0; i < 3; i++) {
          streams[i].removeListener(listeners[i]);
          await providers[i].evict();
        }
        await root.delete(recursive: true);
      }
    });
  });
}
