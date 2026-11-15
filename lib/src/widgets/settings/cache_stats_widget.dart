import 'package:flutter/foundation.dart';
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
    _CacheType(_CacheTypeEnum.offlineMedia, 'offline_media'),
    _CacheType(_CacheTypeEnum.offlineThumbnails, 'offline_thumbnails'),
    _CacheType(_CacheTypeEnum.webView, 'WebView'),
  ];

  List<Map<String, dynamic>> cacheStats = [];
  int _statsGeneration = 0;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    getCacheStats();
  }

  @override
  void dispose() {
    _statsGeneration++;
    super.dispose();
  }

  Future<void> getCacheStats() async {
    if (!mounted) return;
    final generation = ++_statsGeneration;
    setState(() => cacheStats = []);
    try {
      final path = await ServiceHandler.getCacheDir();
      if (!mounted || generation != _statsGeneration) return;
      final stats = await compute(_readCacheStats, path);
      if (!mounted || generation != _statsGeneration) return;
      setState(() => cacheStats = stats);
    } catch (_) {
      if (mounted && generation == _statsGeneration) {
        FlashElements.showSnackbar(context: context, title: Text(context.loc.error));
      }
    }
  }

  static Future<List<Map<String, dynamic>>> _readCacheStats(String path) async {
    final writer = ImageWriterIsolate(path);
    final stats = <Map<String, dynamic>>[];
    for (final type in cacheTypes) {
      stats.add(await writer.getCacheStat(type.folder));
    }
    return stats;
  }

  Future<bool> _clearCache(String folder) async {
    if (_isClearing) return false;
    setState(() => _isClearing = true);
    final result = await imageWriter.deleteCacheFolder(folder);
    if (!mounted) return false;
    await getCacheStats();
    if (!mounted) return false;
    setState(() => _isClearing = false);
    if (result == false) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.error),
        content: Text(context.loc.settings.cache.errorExclamation),
      );
      return false;
    }
    return true;
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

    final bool allowedToClear = folder != null && folder != 'favicons' && !isEmpty && !isLoading && !_isClearing;

    return SettingsButton(
      name: '$label: $text',
      enabled: allowedToClear,
      icon: isLoading ? const CircularProgressIndicator() : Icon(allowedToClear ? Icons.delete_forever : null),
      action: () async {
        if (allowedToClear) {
          if (!await _clearCache(folder) || !mounted) return;
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
          enabled: !_isClearing,
          icon: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          action: () async {
            if (!await _clearCache('') || !mounted) return;
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
  offlineMedia,
  offlineThumbnails,
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
      case offlineMedia:
        return loc.settings.cache.cacheTypeOfflineMedia;
      case offlineThumbnails:
        return loc.settings.cache.cacheTypeOfflineThumbnails;
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
