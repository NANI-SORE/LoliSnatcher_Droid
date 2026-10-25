import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class BackupRestoreJournal {
  BackupRestoreJournal(Directory configuration) : configuration = Directory(p.normalize(configuration.absolute.path));

  static const directoryName = '.backup-restore-recovery';
  static const _fixedFiles = {'settings.json', 'tags.json', 'tabs.json', 'store.db'};
  static const _databaseSuffixes = ['-wal', '-shm', '-journal'];
  final Directory configuration;

  Directory get _directory => Directory(p.join(configuration.path, directoryName));
  File get _manifest => File(p.join(_directory.path, 'journal.json'));

  Future<void> prepare({Future<void> Function(File destination)? snapshotDatabase}) async {
    await configuration.create(recursive: true);
    if (await FileSystemEntity.type(_directory.path, followLinks: false) != FileSystemEntityType.notFound) {
      throw StateError('An unfinished backup restore must be recovered first');
    }
    await _directory.create();
    await _writeManifest({'version': 1, 'phase': 'preparing'});
    final paths = <String>[..._fixedFiles];
    final profiles = Directory(p.join(configuration.path, 'boorus'));
    await _rejectLink(profiles.path);
    if (await profiles.exists()) {
      await for (final entity in profiles.list(followLinks: false)) {
        if (entity is File && p.extension(entity.path).toLowerCase() == '.json') {
          paths.add(p.posix.join('boorus', p.basename(entity.path)));
        }
      }
    }
    final files = <Map<String, Object?>>[];
    for (final path in paths) {
      final source = await _target(path);
      final exists = await source.exists();
      final record = <String, Object?>{'path': path, 'exists': exists};
      if (exists) {
        final snapshot = File(p.join(_directory.path, 'original-${files.length}'));
        if (path == 'store.db') {
          if (snapshotDatabase == null) throw StateError('Database snapshot support is required');
          await snapshotDatabase(snapshot);
        } else {
          await source.copy(snapshot.path);
        }
        final handle = await snapshot.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        record.addAll({
          'snapshot': p.basename(snapshot.path),
          'size': await snapshot.length(),
          'sha256': (await sha256.bind(snapshot.openRead()).first).toString(),
        });
      }
      files.add(record);
    }
    // No application mutation is allowed until every original is durable.
    await _writeManifest({'version': 1, 'phase': 'prepared', 'files': files});
  }

  Future<void> commit() async {
    final data = await _readManifest();
    if (data['phase'] != 'prepared') throw StateError('No prepared restore to commit');
    await _writeManifest({...data, 'phase': 'committed'});
    // The commit is authoritative even when a temporary lock delays cleanup.
    await _cleanupFinished();
  }

  Future<bool> recover({Future<void> Function()? beforeRestore}) async {
    final type = await FileSystemEntity.type(_directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    if (type != FileSystemEntityType.directory) throw const FormatException('Invalid recovery directory');
    if (!await _manifest.exists()) {
      final remaining = await _directory.list(followLinks: false).toList();
      if (remaining.isEmpty ||
          (remaining.length == 1 &&
              remaining.single is File &&
              p.basename(remaining.single.path) == 'journal.json.tmp')) {
        // No snapshots exist: the first preparing manifest was never installed.
        await _cleanupFinished();
        return false;
      }
      throw const FormatException('Missing restore recovery journal');
    }
    final data = await _readManifest();
    if (data['phase'] == 'preparing' || data['phase'] == 'committed' || data['phase'] == 'rolledBack') {
      await _cleanupFinished();
      return false;
    }
    if (data['phase'] != 'prepared' || data['files'] is! List) {
      throw const FormatException('Invalid restore recovery phase');
    }
    final records = <Map<String, dynamic>>[];
    final paths = <String>{};
    final snapshots = <String>{};
    // Validate the entire recovery set before changing any live file.
    for (final raw in data['files'] as List) {
      if (raw is! Map<String, dynamic> || raw['path'] is! String || raw['exists'] is! bool) {
        throw const FormatException('Invalid recovery file record');
      }
      final path = raw['path'] as String;
      final target = await _target(path);
      final temporary = File('${target.path}.restore-tmp');
      await _rejectLink(temporary.path);
      final temporaryType = await FileSystemEntity.type(temporary.path, followLinks: false);
      if (temporaryType != FileSystemEntityType.file && temporaryType != FileSystemEntityType.notFound) {
        throw const FormatException('Invalid recovery temporary file');
      }
      if (!paths.add(path.toLowerCase())) throw const FormatException('Duplicate recovery file');
      if (raw['exists'] == true) {
        final name = raw['snapshot'];
        if (name is! String ||
            !RegExp(r'^original-[0-9]+$').hasMatch(name) ||
            !snapshots.add(name) ||
            raw['size'] is! int ||
            (raw['size'] as int) < 0 ||
            raw['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'] as String)) {
          throw const FormatException('Invalid recovery snapshot metadata');
        }
        final file = File(p.join(_directory.path, name));
        await _rejectLink(file.path);
        if (!await file.exists() ||
            await file.length() != raw['size'] ||
            (await sha256.bind(file.openRead()).first).toString() != raw['sha256']) {
          throw const FormatException('Recovery snapshot is missing or corrupt');
        }
      }
      records.add(raw);
    }
    if (!paths.containsAll(_fixedFiles)) throw const FormatException('Incomplete recovery journal');
    final profiles = Directory(p.join(configuration.path, 'boorus'));
    await _checkProfilesDirectory();
    for (final suffix in _databaseSuffixes) {
      await _target('store.db$suffix', allowSidecar: true);
    }
    await beforeRestore?.call();
    for (final suffix in _databaseSuffixes) {
      await _deleteFile(await _target('store.db$suffix', allowSidecar: true));
    }
    if (await profiles.exists()) {
      await for (final entity in profiles.list(followLinks: false)) {
        if (entity is File &&
            p.extension(entity.path).toLowerCase() == '.json' &&
            !paths.contains(p.posix.join('boorus', p.basename(entity.path)).toLowerCase())) {
          await entity.delete();
        }
      }
    }
    for (final record in records) {
      final target = await _target(record['path'] as String);
      if (record['exists'] == false) {
        await _deleteFile(target);
        continue;
      }
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.restore-tmp');
      await _rejectLink(temporary.path);
      // Copy rather than move: originals survive another interrupted rollback.
      await File(p.join(_directory.path, record['snapshot'] as String)).copy(temporary.path);
      final handle = await temporary.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temporary.rename(target.path);
    }
    await _writeManifest({...data, 'phase': 'rolledBack'});
    await _cleanupFinished();
    return true;
  }

  Future<void> _cleanupFinished() async {
    // Rename the whole directory before deleting its files. A crash partway
    // through cleanup must never leave an active journal missing snapshots.
    final cleanup = Directory(p.join(configuration.path, '$directoryName-cleanup'));
    try {
      final type = await FileSystemEntity.type(cleanup.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await cleanup.delete(recursive: true);
      } else if (type != FileSystemEntityType.notFound) {
        throw const FileSystemException('Invalid restore cleanup directory');
      }
      await _directory.rename(cleanup.path);
      await cleanup.delete(recursive: true);
    } on FileSystemException {
      // A terminal manifest, or a renamed cleanup directory, remains safe.
    }
  }

  Future<File> _target(String relative, {bool allowSidecar = false}) async {
    final segments = p.posix.split(relative);
    final profile =
        segments.length == 2 &&
        segments.first == 'boorus' &&
        segments.last != '.' &&
        segments.last != '..' &&
        !segments.last.contains(r'\') &&
        !segments.last.contains(':') &&
        p.posix.extension(segments.last).toLowerCase() == '.json';
    if (!_fixedFiles.contains(relative) &&
        !profile &&
        !(allowSidecar && _databaseSuffixes.any((suffix) => relative == 'store.db$suffix'))) {
      throw const FormatException('Unsafe recovery path');
    }
    final path = p.normalize(p.joinAll([configuration.path, ...segments]));
    if (!p.isWithin(configuration.path, path)) throw const FormatException('Recovery path escapes configuration');
    await _checkProfilesDirectory();
    await _rejectLink(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file && type != FileSystemEntityType.notFound) {
      throw const FormatException('Recovery file target has an invalid type');
    }
    return File(path);
  }

  Future<void> _rejectLink(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link) throw const FormatException('Recovery paths cannot be symbolic links');
  }

  Future<void> _checkProfilesDirectory() async {
    final type = await FileSystemEntity.type(p.join(configuration.path, 'boorus'), followLinks: false);
    if (type != FileSystemEntityType.directory && type != FileSystemEntityType.notFound) {
      throw const FormatException('Invalid recovery profiles directory');
    }
  }

  Future<void> _deleteFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<Map<String, dynamic>> _readManifest() async {
    await _rejectLink(_manifest.path);
    if (await _manifest.length() > 4 * 1024 * 1024) throw const FormatException('Recovery journal is too large');
    final data = jsonDecode(await _manifest.readAsString());
    if (data is! Map<String, dynamic> || data['version'] != 1) {
      throw const FormatException('Unsupported recovery journal');
    }
    return data;
  }

  Future<void> _writeManifest(Map<String, Object?> data) async {
    final temporary = File(p.join(_directory.path, 'journal.json.tmp'));
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(_manifest.path);
  }
}
