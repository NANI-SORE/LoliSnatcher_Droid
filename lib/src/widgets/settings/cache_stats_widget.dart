import 'dart:isolate';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/image_writer_isolate.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Self-contained widget that displays cache statistics and clear buttons.
///
/// Shows per-folder cache sizes (total, favicons, thumbnails, samples, media, WebView)
/// computed in isolates, with buttons to clear individual folders or all cache.
class CacheStatsWidget extends StatefulWidget {
  const CacheStatsWidget({super.key});

  @override
  State<CacheStatsWidget> createState() => _CacheStatsWidgetState();
}

class _CacheStatsWidgetState extends State<CacheStatsWidget> {
  final ImageWriter imageWriter = ImageWriter();

  static const List<_CacheType> cacheTypes = [
    _CacheType(_CacheTypeEnum.total, null),
    _CacheType(_CacheTypeEnum.favicons, 'favicons'),
    _CacheType(_CacheTypeEnum.thumbnails, 'thumbnails'),
    _CacheType(_CacheTypeEnum.samples, 'samples'),
    _CacheType(_CacheTypeEnum.media, 'media'),
    _CacheType(_CacheTypeEnum.webView, 'WebView'),
  ];

  List<Map<String, dynamic>> cacheStats = [];
  Isolate? isolate;

  @override
  void initState() {
    super.initState();
    getCacheStats(null);
  }

  @override
  void dispose() {
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
    super.dispose();
  }

  Future<void> getCacheStats(String? folder) async {
    if (folder != null) {
      cacheStats.removeWhere((e) => e['type'] == folder || e['type'] == '' || e['type'] == null);
    } else {
      cacheStats = [];
    }

    final cacheTypesToGet = folder == null
        ? cacheTypes
        : cacheTypes.where((e) => e.folder == folder || e.folder == null).toList();

    for (final _CacheType type in cacheTypesToGet) {
      final ReceivePort receivePort = ReceivePort();
      isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

      receivePort.listen((dynamic data) async {
        if (mounted) {
          if (data is SendPort) {
            data.send({
              'path': await ServiceHandler.getCacheDir(),
              'type': type.folder,
            });
          } else {
            cacheStats.add(data);
            setState(() {});
          }
        }
      });
    }
  }

  static Future<void> _isolateEntry(dynamic d) async {
    final ReceivePort receivePort = ReceivePort();
    d.send(receivePort.sendPort);

    final config = await receivePort.first;
    d.send(await ImageWriterIsolate(config['path']).getCacheStat(config['type']));
  }

  Widget buildCacheButton(_CacheType type) {
    final Map<String, dynamic> stat = cacheStats.firstWhere(
      (stat) => stat['type'] == type.folder,
      orElse: () => {
        'type': 'loading',
        'totalSize': -1,
        'fileNum': -1,
      },
    );
    final String? folder = type.folder;
    final String label = type.type.locName;
    final String size = Tools.formatBytes(stat['totalSize']!, 2);
    final int fileCount = stat['fileNum'] ?? 0;
    final bool isEmpty = stat['fileNum'] == 0 || stat['totalSize'] == 0;
    final bool isLoading = stat['type'] == 'loading';
    final String text = isLoading
        ? context.loc.settings.cache.loading
        : (isEmpty
              ? context.loc.settings.cache.empty
              : (fileCount == 1
                    ? context.loc.settings.cache.inFileSingular(size: size)
                    : context.loc.settings.cache.inFilesPlural(size: size, count: fileCount)));

    final bool allowedToClear = folder != null && folder != 'favicons' && !isEmpty;

    return SettingsButton(
      name: '$label: $text',
      icon: isLoading ? const CircularProgressIndicator() : Icon(allowedToClear ? Icons.delete_forever : null),
      action: () async {
        if (allowedToClear) {
          FlashElements.showSnackbar(
            context: context,
            position: FlashPosition.top,
            duration: const Duration(seconds: 2),
            title: Text(
              context.loc.settings.cache.cacheCleared,
              style: const TextStyle(fontSize: 20),
            ),
            content: Text(
              context.loc.settings.cache.clearedCacheType(type: label),
              style: const TextStyle(fontSize: 16),
            ),
            leadingIcon: Icons.delete_forever,
            leadingIconColor: Colors.red,
            leadingIconSize: 40,
            sideColor: Colors.yellow,
          );
          await imageWriter.deleteCacheFolder(folder);
          await getCacheStats(folder);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...cacheTypes.map(buildCacheButton),
        SettingsButton(
          name: context.loc.settings.cache.clearAllCache,
          icon: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          action: () async {
            FlashElements.showSnackbar(
              context: context,
              position: FlashPosition.top,
              title: Text(
                context.loc.settings.cache.cacheCleared,
                style: const TextStyle(fontSize: 20),
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.settings.cache.clearedCacheCompletely,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    context.loc.settings.cache.appRestartRequired,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              leadingIcon: Icons.delete_forever,
              leadingIconColor: Colors.red,
              leadingIconSize: 40,
              sideColor: Colors.yellow,
            );
            await imageWriter.deleteCacheFolder('');
            await getCacheStats(null);
          },
          drawBottomBorder: false,
        ),
      ],
    );
  }
}

enum _CacheTypeEnum {
  total,
  favicons,
  thumbnails,
  samples,
  media,
  webView,
  ;

  String get locName {
    switch (this) {
      case total:
        return loc.settings.cache.cacheTypeTotal;
      case favicons:
        return loc.settings.cache.cacheTypeFavicons;
      case thumbnails:
        return loc.settings.cache.cacheTypeThumbnails;
      case samples:
        return loc.settings.cache.cacheTypeSamples;
      case media:
        return loc.settings.cache.cacheTypeMedia;
      case webView:
        return loc.settings.cache.cacheTypeWebView;
    }
  }
}

class _CacheType {
  const _CacheType(
    this.type,
    this.folder,
  );

  final _CacheTypeEnum type;
  final String? folder;
}
