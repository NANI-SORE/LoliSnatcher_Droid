import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps app internals outside the Documents directory exposed through Files.
class IOSStorage {
  IOSStorage({required Directory support, required Directory cache, required Directory documents})
    : config = Directory(p.join(support.path, 'LoliSnatcher', 'config')),
      cachedFiles = Directory(p.join(cache.path, 'LoliSnatcher')),
      downloads = Directory(p.join(documents.path, 'Downloads')),
      backups = Directory(p.join(documents.path, 'Backups'));

  static Future<IOSStorage>? _initialization;

  final Directory config;
  final Directory cachedFiles;
  final Directory downloads;
  final Directory backups;

  static Future<IOSStorage> initialize() => _initialization ??= _initialize();

  static Future<IOSStorage> _initialize() async {
    try {
      final support = await getApplicationSupportDirectory();
      final cache = await getApplicationCacheDirectory();
      final documents = await getApplicationDocumentsDirectory();
      final storage = IOSStorage(
        support: support,
        cache: cache,
        documents: documents,
      );
      await storage.prepare();
      return storage;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> prepare() async {
    for (final directory in [config, cachedFiles, downloads, backups]) {
      await directory.create(recursive: true);
    }
  }
}
