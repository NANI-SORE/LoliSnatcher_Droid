import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:lolisnatcher/src/handlers/service_handler.dart';

// Routine media cache eviction must not touch this directory. Shares own its
// cleanup, including files retained for receivers after the native sheet closes.
class ShareStaging {
  ShareStaging._(this.directory);

  static const folderName = 'share_staging';
  static const retention = Duration(hours: 24);
  static final _activePaths = <String>{};
  final Directory directory;

  static Future<ShareStaging> create() async {
    final cacheRoot = await ServiceHandler.getCacheDir();
    if (cacheRoot.isEmpty) throw const FileSystemException('Cache directory unavailable');
    final root = Directory(p.join(cacheRoot, folderName));
    await root.create(recursive: true);
    final cutoff = DateTime.now().subtract(retention);
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || _activePaths.contains(entry.path)) continue;
      try {
        final marker = File(p.join(entry.path, 'retained'));
        final modified = await marker.exists() ? await marker.lastModified() : (await entry.stat()).modified;
        if (modified.isBefore(cutoff)) await entry.delete(recursive: true);
      } catch (_) {
        // A stale staging directory can be collected by the next share.
      }
    }
    final directory = await root.createTemp('share_');
    _activePaths.add(directory.path);
    return ShareStaging._(directory);
  }

  String pathFor(int index, String fileName) => p.join(directory.path, '${index}_${p.basename(fileName)}');

  Future<void> release({required bool handedOff}) async {
    try {
      if (handedOff) {
        await File(p.join(directory.path, 'retained')).writeAsString('');
      } else {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Cleanup must not mask the share result.
    } finally {
      _activePaths.remove(directory.path);
    }
  }
}
