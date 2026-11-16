import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:lolisnatcher/src/services/local_image_provider.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/services/image_metadata.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = ImageMemoryManager.instance;

  test('retained decode handle outlives viewer; final owner removes only its private file', () async {
    final root = await Directory.systemTemp.createTemp('owned-image-');
    final file = await File('${root.path}/image').writeAsString('source');
    final viewer = DownloadedImageFile(file, ownsFile: true, temporaryDirectory: root);
    final codec = viewer.retain();
    await viewer.dispose();
    expect(await file.exists(), true);
    expect(viewer.retain, throwsStateError);
    await codec.dispose();
    expect(await root.exists(), false);
    await viewer.dispose();
    await codec.dispose();
  });

  test('offline original survives all borrowed viewer and codec releases', () async {
    final root = await Directory.systemTemp.createTemp('borrowed-image-');
    try {
      final file = await File('${root.path}/original').writeAsString('user media');
      final viewer = DownloadedImageFile(file);
      final codec = viewer.retain();
      await viewer.dispose();
      await codec.dispose();
      expect(await file.readAsString(), 'user media');
    } finally {
      await root.delete(recursive: true);
    }
  });

  testWidgets('retained admission distinguishes permanent and temporary budget failures', (tester) async {
    expect(manager.retainedBytes, 0);
    expect(
      () => manager.reserveImage(ImageMemoryManager.maxRetainedBytes + 1),
      throwsA(isA<ImageMemoryException>().having((e) => e.isTransient, 'transient', false)),
    );
    final lease = manager.reserveImage(ImageMemoryManager.maxRetainedBytes);
    try {
      expect(
        () => manager.reserveImage(1),
        throwsA(isA<ImageMemoryException>().having((e) => e.isTransient, 'transient', true)),
      );
      expect(manager.underPressure.value, true);
    } finally {
      lease.release();
      lease.release();
      await tester.pump(ImageMemoryManager.pressureCooldown);
    }
    expect(manager.retainedBytes, 0);
    expect(manager.underPressure.value, false);
  });

  test('queued decode cancellation preserves serial execution and original request zone', () async {
    final gate = Completer<void>();
    final order = <int>[];
    final first = manager.runDecode(1, () async {
      order.add(1);
      await gate.future;
      order.add(2);
    });
    final token = CancelToken();
    final canceled = manager.runDecode(1, () async {
      fail('Canceled job ran');
    }, cancelToken: token);
    final rejected = expectLater(canceled, throwsA(isA<DioException>()));
    final zoneKey = Object();
    final last = runZoned(
      () => manager.runDecode(1, () async {
        order.add(3);
        return Zone.current[zoneKey];
      }),
      zoneValues: {zoneKey: 'source-specific transport'},
    );
    token.cancel();
    await rejected;
    expect(order, [1]);
    gate.complete();
    await first;
    expect(await last, 'source-specific transport');
    expect(order, [1, 2, 3]);
    expect(manager.queuedDecodeCount, 0);
  });

  test('oversized decode never starts native work', () async {
    await expectLater(
      manager.runDecode(ImageMemoryManager.maxTransientBytes + 1, () async {
        fail('Rejected decode ran');
      }),
      throwsA(isA<ImageMemoryException>()),
    );
  });

  testWidgets('saved PNG with AVIF filename uses actual encoding and bounded decode without deleting original', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('local-codec-');
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(const ui.Color(0xFF123456), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final source = await picture.toImage(40, 20);
        final encoded = (await source.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        source.dispose();
        picture.dispose();
        final file = await File('${root.path}/misleading.avif').writeAsBytes(encoded);
        final provider = SafeResizeImage(
          await localImageProvider(file),
          width: 10,
          height: 10,
          policy: ResizeImagePolicy.fit,
          allowUpscaling: false,
        );
        final stream = provider.resolve(ImageConfiguration.empty);
        final result = Completer<ImageInfo>();
        final listener = ImageStreamListener((info, _) => result.complete(info), onError: result.completeError);
        stream.addListener(listener);
        final info = await result.future.timeout(const Duration(seconds: 10));
        expect((info.image.width, info.image.height), (10, 5));
        info.dispose();
        stream.removeListener(listener);
        await provider.evict();
        expect(await file.readAsBytes(), encoded);
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  test('metadata blocks unsafe dimensions before decode for static, animated and AVIF media', () {
    ImageMetadata.checkDimensions(8000, 4000);
    for (final size in [(0, 1), (-1, 1), (32769, 1), (8001, 4000)]) {
      expect(() => ImageMetadata.checkDimensions(size.$1, size.$2), throwsA(isA<ImageMemoryException>()));
    }
    expect(
      () => ImageMetadata.checkDimensions(3000, 3000, pixelLimit: ImageMemoryManager.maxAnimatedSourcePixels),
      throwsA(isA<ImageMemoryException>()),
    );
    expect(
      () => ImageMetadata.checkDimensions(2001, 2000, pixelLimit: ImageMemoryManager.maxAvifSourcePixels),
      throwsA(isA<ImageMemoryException>()),
    );
  });
}
