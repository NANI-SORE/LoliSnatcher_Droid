import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/services/image_region_decoder.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/image/region_image_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final memory = ImageMemoryManager.instance;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, Object> pixels(MethodCall call) {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final sample = args['sampleSize'] as int;
    final width = ((args['right'] as int) - (args['left'] as int) + sample - 1) ~/ sample;
    final height = ((args['bottom'] as int) - (args['top'] as int) + sample - 1) ~/ sample;
    return {
      'width': width,
      'height': height,
      'rowBytes': width * 4,
      'format': 'rgba8888',
      'bytes': Uint8List(width * height * 4),
    };
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('temporary detail failure retains the overview and retries only the missing tile', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('tile-retry-')))!;
    final file = (await tester.runAsync(() => File('${directory.path}/image').writeAsBytes([1, 2, 3])))!;
    final source = RegionImageSource(DownloadedImageFile(file), const Size(2048, 2048));
    final controller = PhotoViewController(initialScale: 1);
    final errors = <Object>[];
    var overviews = 0;
    var details = 0;
    var ready = false;
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (call) async {
      if (call.method == 'releaseImageRegionDecoder') return null;
      if (call.method != 'decodeImageRegion') throw MissingPluginException();
      final args = call.arguments as Map;
      if (args['right'] == 2048 && args['bottom'] == 2048 && args['left'] == 0 && args['top'] == 0) {
        overviews++;
      } else if (++details == 1) {
        throw PlatformException(code: 'IMAGE_MEMORY_LIMIT');
      }
      return pixels(call);
    });
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RegionImageView(
            source: source,
            controller: controller,
            viewport: const Size(400, 400),
            isViewed: true,
            onReady: () => ready = true,
            onPreviewReady: () {},
            onCoverageChanged: (_) {},
            onError: errors.add,
          ),
        ),
      );
      await settle(tester);
      expect(overviews, 1);
      expect(details, 1);
      expect(errors, isEmpty, reason: 'Temporary detail contention must not restart the viewer');
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(ready, true);
      expect(overviews, 1, reason: 'Already decoded overview must survive the retry');
      expect(details, greaterThan(1));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
      controller.dispose();
      await settle(tester);
      await tester.pump(ImageMemoryManager.pressureCooldown);
      messenger.setMockMethodCallHandler(ServiceHandler.platform, null);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
    expect(memory.retainedBytes, 0);
  });

  testWidgets('memory cooldown preserves one reusable decoder for the visible source', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('tile-session-')))!;
    final file = (await tester.runAsync(() => File('${directory.path}/image').writeAsBytes([1, 2, 3])))!;
    final retention = <bool>[];
    var closes = 0;
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (call) async {
      if (call.method == 'releaseImageRegionDecoder') {
        closes++;
        return null;
      }
      retention.add((call.arguments as Map)['retainDecoder'] == true);
      return pixels(call);
    });
    Future<void> decode() async {
      final result = await ImageRegionDecoder.instance.load(
        file,
        left: 0,
        top: 0,
        right: 32,
        bottom: 32,
        sampleSize: 1,
        cancelToken: CancelToken(),
        isForeground: () => true,
      );
      result.image.dispose();
      result.lease.release();
    }

    try {
      await tester.runAsync(decode);
      memory.handleMemoryPressure();
      await tester.runAsync(decode);
      await tester.runAsync(decode);
      expect(retention, [true, true, true]);
      expect(closes, 0, reason: 'Visible tiles must not reopen their source during every pressure-period decode');
    } finally {
      await tester.runAsync(() => ImageRegionDecoder.instance.release(file.path));
      await tester.pump(ImageMemoryManager.pressureCooldown);
      messenger.setMockMethodCallHandler(ServiceHandler.platform, null);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
    expect(closes, 1);
    expect(memory.retainedBytes, 0);
  });

  testWidgets('overview retries pause offscreen and resume without replacing the source', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('overview-retry-')))!;
    final file = (await tester.runAsync(() => File('${directory.path}/image').writeAsBytes([1, 2, 3])))!;
    final source = RegionImageSource(DownloadedImageFile(file), const Size(2048, 2048));
    final controller = PhotoViewController(initialScale: 1);
    var overviews = 0;
    var previewReady = false;
    var failOverview = true;
    final errors = <Object>[];
    messenger.setMockMethodCallHandler(ServiceHandler.platform, (call) async {
      if (call.method == 'releaseImageRegionDecoder') return null;
      final args = call.arguments as Map;
      if (args['right'] == 2048 && args['bottom'] == 2048 && args['left'] == 0 && args['top'] == 0) {
        overviews++;
        if (failOverview) throw PlatformException(code: 'IMAGE_MEMORY_LIMIT');
      }
      return pixels(call);
    });
    Widget view(bool viewed) => MaterialApp(
      home: RegionImageView(
        source: source,
        controller: controller,
        viewport: const Size(400, 400),
        isViewed: viewed,
        onReady: () {},
        onPreviewReady: () => previewReady = true,
        onCoverageChanged: (_) {},
        onError: errors.add,
      ),
    );
    try {
      await tester.pumpWidget(view(true));
      await settle(tester);
      expect(overviews, 1);
      await tester.pumpWidget(view(false));
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(overviews, 1, reason: 'Offscreen retry must not compete with the foreground viewer');
      failOverview = false;
      await tester.pumpWidget(view(true));
      await settle(tester);
      expect(overviews, 2);
      expect(previewReady, true);
      expect(errors, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
      controller.dispose();
      await settle(tester);
      await tester.pump(ImageMemoryManager.pressureCooldown);
      messenger.setMockMethodCallHandler(ServiceHandler.platform, null);
      await tester.runAsync(() => directory.delete(recursive: true));
    }
    expect(memory.retainedBytes, 0);
  });
}
