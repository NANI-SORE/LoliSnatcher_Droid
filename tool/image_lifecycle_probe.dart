// Local, synthetic-image Android probe. Does not load or save user settings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';

const stress = bool.fromEnvironment('IMAGE_PROBE_STRESS');

Future<Uint8List> fixture(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < height; y += 100) {
    for (var x = 0; x < width; x += 100) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 100, 100),
        Paint()..color = ((x + y) ~/ 100).isEven ? Colors.blue : Colors.amber,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<void> main() => RequestScope(
  client: Dio.new,
  cookies: (_) async => '',
  saveCookies: (_, _) async => true,
).run(runProbe);

Future<void> runProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAllSettings();
  SettingsHandler.register().blurImages = false;
  SX.gifsAsThumbnails.state.setValue(true, save: false);
  SX.thumbnailCache.state.setValue(false, save: false);
  SX.mediaCache.state.setValue(false, save: false);
  SX.preloadHeight.state.setValue(0, save: false);
  final thumbnail = await fixture(320, 200);
  final full = await fixture(6000, 4000);
  final encoder = img.GifEncoder()
    ..addFrame(img.fill(img.Image(width: 320, height: 200), color: img.ColorRgb8(255, 0, 0)))
    ..addFrame(img.fill(img.Image(width: 320, height: 200), color: img.ColorRgb8(0, 0, 255)));
  final animation = encoder.finish()!;
  final requests = <String, int>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    requests.update(path, (n) => n + 1, ifAbsent: () => 1);
    request.response.headers.contentType = ContentType('image', 'png');
    final index = int.tryParse(RegExp(r'\d+').firstMatch(path)?.group(0) ?? '') ?? 1;
    request.response.add(
      path.startsWith('/full')
          ? full
          : stress && index % 5 == 0
          ? animation
          : thumbnail,
    );
    await request.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}';
  runApp(
    TranslationProvider(
      child: MaterialApp(
        home: _Probe(url: url, requests: requests),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.url, required this.requests});
  final String url;
  final Map<String, int> requests;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final viewerKey = GlobalKey<ImageViewerState>();
  final frames = <ui.FrameTiming>[];
  final scroll = ScrollController();
  late final items = List.generate(
    60,
    (i) => BooruItem(
      fileURL: '${widget.url}/full-$i.png',
      sampleURL: '${widget.url}/full-$i.png',
      thumbnailURL: '${widget.url}/thumb-$i.png',
      tagsList: const [],
      postURL: '',
      fileWidth: 6000,
      fileHeight: 4000,
      previewWidth: 320,
      previewHeight: 200,
    ),
  );
  late final booru = Booru('Synthetic fixture', BooruType.Danbooru, '', widget.url, '');
  bool showViewer = false;
  String phase = 'warmup';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(frames.addAll);
    unawaited(run());
  }

  void report(String phase) {
    final times = frames.map((f) => (f.buildDuration + f.rasterDuration).inMicroseconds / 1000).toList()..sort();
    final memory = ImageMemoryManager.instance;
    print(
      'IMAGE_PROBE ${jsonEncode({
        'phase': phase,
        'requests': widget.requests.values.fold(0, (a, b) => a + b),
        'thumbnailRequests': widget.requests.entries.where((e) => e.key.startsWith('/thumb')).fold(0, (a, b) => a + b.value),
        'frames': times.length,
        'over32ms': times.where((t) => t > 32).length,
        'p95ms': times.isEmpty ? 0 : times[((times.length - 1) * .95).round()],
        'maxMs': times.isEmpty ? 0 : times.last,
        'retained': memory.retainedBytes,
        'rss': ProcessInfo.currentRss,
        'pressure': memory.underPressure.value,
        'rejections': memory.rejectedCount,
        'queuedDecodes': memory.queuedDecodeCount,
        'queuedDownloads': memory.queuedDownloadCount,
        'loaded': viewerKey.currentState?.isLoaded.value,
        'tiled': viewerKey.currentState?.isTiled,
        'stopped': viewerKey.currentState?.stopReason.value?.name,
        'stopDetails': viewerKey.currentState?.stopDetails.value,
      })}',
    );
    frames.clear();
  }

  Future<void> run() async {
    await Future<void>.delayed(const Duration(seconds: 6));
    report('initial-grid');
    for (var i = 0; i < 3; i++) {
      setState(() {
        phase = 'viewer-$i';
        showViewer = true;
      });
      await Future<void>.delayed(const Duration(seconds: 5));
      report(phase);
      final state = viewerKey.currentState;
      state?.viewController.scale = 1.0;
      for (var step = 0; step < 12; step++) {
        state?.viewController.position = Offset(-step * 80, step * 40);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      report('zoom-$i');
      setState(() {
        phase = 'grid-$i';
        showViewer = false;
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      report(phase);
    }
    ImageMemoryManager.instance.handleMemoryPressure();
    setState(() => phase = 'pressure');
    await Future<void>.delayed(const Duration(seconds: 3));
    report(phase);
    await Future<void>.delayed(ImageMemoryManager.pressureCooldown);
    report('pressure-recovered');
    await scroll.animateTo(1200, duration: const Duration(seconds: 2), curve: Curves.linear);
    await scroll.animateTo(0, duration: const Duration(seconds: 2), curve: Curves.linear);
    await Future<void>.delayed(const Duration(seconds: 3));
    report('scroll-return');
    if (stress) {
      setState(() {
        phase = 'pressure-viewer';
        showViewer = true;
      });
      await Future<void>.delayed(const Duration(seconds: 5));
      ImageMemoryManager.instance.handleMemoryPressure();
      viewerKey.currentState?.viewController.scale = 1.0;
      await Future<void>.delayed(const Duration(seconds: 5));
      report('pressure-viewer');
      for (var i = 0; i < 12; i++) {
        setState(() => showViewer = !showViewer);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      setState(() => showViewer = false);
      await Future<void>.delayed(ImageMemoryManager.pressureCooldown);
      report('rapid-disposal-recovered');
      setState(() => phase = 'disposed');
      await Future<void>.delayed(const Duration(seconds: 1));
      PaintingBinding.instance.imageCache.clear();
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(const Duration(seconds: 2));
      report('all-disposed');
    }
    setState(() => phase = 'done');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(frames.addAll);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Image probe: $phase')),
    body: Stack(
      children: [
        if (phase != 'disposed' && phase != 'done')
          GridView.builder(
            controller: scroll,
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.6),
            itemBuilder: (_, i) => Thumbnail(
              key: ValueKey(i),
              item: items[i],
              filterEvaluation: const TagFilterEvaluation.empty(),
              isStandalone: true,
              useHero: false,
              forceThumbnail: true,
            ),
          ),
        if (showViewer)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: ImageViewer(
                items.first,
                key: viewerKey,
                booru: booru,
                isViewed: true,
                isStandalone: true,
                fullQuality: true,
              ),
            ),
          ),
      ],
    ),
  );
}
