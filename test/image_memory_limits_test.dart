import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a valid static file over 64 MiB can reach dimension inspection', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('large-encoded-image-');
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(const ui.Color(0xFF123456), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(40, 20);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        final file = File('${root.path}/large.png');
        final output = await file.open(mode: FileMode.write);
        try {
          await output.writeFrom(bytes);
          // A PNG followed by padding exercises the real encoded-byte gate
          // without constructing a dangerously large decoded test bitmap.
          await output.setPosition(65 * 1024 * 1024 - 1);
          await output.writeByte(0);
        } finally {
          await output.close();
        }
        expect(await file.length(), greaterThan(64 * 1024 * 1024));
        expect(await NetworkImageLoader.inspectImageSize(file), const ui.Size(40, 20));
        final oversizedFile = File('${root.path}/oversized.png');
        final larger = await oversizedFile.open(mode: FileMode.write);
        try {
          await larger.writeFrom(bytes);
          await larger.setPosition(257 * 1024 * 1024 - 1);
          await larger.writeByte(0);
        } finally {
          await larger.close();
        }
        expect(await oversizedFile.length(), 257 * 1024 * 1024);
        await expectLater(NetworkImageLoader.inspectImageSize(oversizedFile), throwsA(isA<ImageMemoryException>()));
        expect(await oversizedFile.exists(), true, reason: 'Policy refusal must preserve the original file');
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
