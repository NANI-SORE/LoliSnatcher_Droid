import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

abstract interface class FilterRepository {
  Future<TagFilterConfiguration> load();
  Future<void> save(TagFilterConfiguration configuration);
  Future<TagFilterConfiguration> decode(String content);
  Future<void> replaceFromString(String content);
  Future<String> export();
}

enum FilterRecovery { temporary, backup, partial }

class JsonFilterRepository implements FilterRepository {
  JsonFilterRepository(this.directoryPath);

  static const int _isolateCodecThreshold = 256 * 1024;

  final String directoryPath;
  Future<void> _pendingWrites = Future.value();
  FilterRecovery? recovery;

  File _fileNamed(String name) => File.fromUri(Directory(directoryPath).uri.resolve(name));

  File get file => _fileNamed('filters.json');
  File get backupFile => _fileNamed('filters.json.bak');
  File get temporaryFile => _fileNamed('filters.json.tmp');

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<TagFilterConfiguration> load() => _enqueue(_loadNow);

  Future<TagFilterConfiguration> _loadNow() async {
    String? damagedPrimary;
    if (await file.exists()) {
      try {
        damagedPrimary = await file.readAsString();
        return await _decode(damagedPrimary, skipUnreadableRules: false);
      } catch (error, stackTrace) {
        _logRecovery('Primary filter configuration is damaged: $error', stackTrace);
      }
    }
    // A fully flushed first save has no backup yet. A pending replacement can
    // also be newer than the backup if the process stopped during rotation.
    for (final candidate in [temporaryFile, backupFile]) {
      if (!await candidate.exists()) continue;
      TagFilterConfiguration configuration;
      try {
        configuration = await _decode(await candidate.readAsString(), skipUnreadableRules: false);
      } catch (error, stackTrace) {
        _logRecovery('Cannot recover ${candidate.path}: $error', stackTrace);
        continue;
      }
      if (await file.exists()) await _preserveDamaged(file);
      if (await temporaryFile.exists() && candidate.path != temporaryFile.path) {
        await _preserveDamaged(temporaryFile);
      }
      await Directory(directoryPath).create(recursive: true);
      await temporaryFile.writeAsString(await _encode(configuration), flush: true);
      if (await file.exists()) await file.delete();
      await temporaryFile.rename(file.path);
      recovery = candidate.path == backupFile.path ? FilterRecovery.backup : FilterRecovery.temporary;
      return configuration;
    }
    if (damagedPrimary != null) {
      await _preserveDamaged(file);
      try {
        final readable = await decode(damagedPrimary);
        recovery = FilterRecovery.partial;
        return readable;
      } catch (error, stackTrace) {
        _logRecovery('No readable filter configuration: $error', stackTrace);
      }
      recovery = FilterRecovery.partial;
    } else if (await file.exists() || await temporaryFile.exists() || await backupFile.exists()) {
      // Preserve unparseable recovery files before a later save reuses them.
      if (await file.exists()) await _preserveDamaged(file);
      if (await temporaryFile.exists()) await _preserveDamaged(temporaryFile);
      if (await backupFile.exists()) await _preserveDamaged(backupFile);
      recovery = FilterRecovery.partial;
    }
    return const TagFilterConfiguration();
  }

  Future<void> _preserveDamaged(File source) async {
    final preserved = _fileNamed('filters.json.damaged-${DateTime.now().microsecondsSinceEpoch}');
    await source.copy(preserved.path);
  }

  void _logRecovery(String message, StackTrace stackTrace) => Logger.Inst().log(
    message,
    'JsonFilterRepository',
    'recover',
    LogTypes.exception,
    s: stackTrace,
  );

  @override
  Future<TagFilterConfiguration> decode(String content) => _decode(content, skipUnreadableRules: true);

  Future<TagFilterConfiguration> _decode(String content, {required bool skipUnreadableRules}) async {
    final decoded = content.length >= _isolateCodecThreshold
        ? await Isolate.run<dynamic>(() => jsonDecode(content))
        : jsonDecode(content);
    if (decoded is! Map) throw const FormatException('Filter configuration must be an object');
    final json = Map<String, dynamic>.from(decoded);
    final schemaVersion = json['schemaVersion'] as int? ?? 1;
    if (schemaVersion != 1) throw FormatException('Unsupported filter schema version: $schemaVersion');
    if (json['rules'] != null && json['rules'] is! List) {
      throw const FormatException('Filter rules must be a list');
    }

    final rules = <TagFilterRule>[];
    final ruleIds = <String>{};
    for (final entry in json['rules'] as List? ?? const []) {
      try {
        if (entry is! Map) throw const FormatException('Rule must be an object');
        final rule = TagFilterRule.fromJson(Map<String, dynamic>.from(entry));
        if (!ruleIds.add(rule.id)) throw FormatException('Duplicate filter rule id: ${rule.id}');
        rules.add(rule);
      } catch (error, stackTrace) {
        if (!skipUnreadableRules) rethrow;
        Logger.Inst().log(
          'Skipping unreadable filter rule: $error',
          'JsonFilterRepository',
          'decode',
          LogTypes.exception,
          s: stackTrace,
        );
      }
    }

    return TagFilterConfiguration(
      schemaVersion: schemaVersion,
      legacyImportVersion: json['legacyImportVersion'] as int? ?? 0,
      rules: List.unmodifiable(rules),
      hideAsBlur: HideAsBlurState.fromJson(
        json['hideAsBlur'] is Map ? Map<String, dynamic>.from(json['hideAsBlur'] as Map) : null,
      ),
    );
  }

  @override
  Future<String> export() async => _encode(await load());

  @override
  Future<void> replaceFromString(String content) async {
    // Restore and sync are all-or-nothing. Normal startup loading remains
    // tolerant so one damaged record cannot hide every otherwise valid rule.
    final configuration = await _decode(content, skipUnreadableRules: false);
    await save(configuration);
  }

  @override
  Future<void> save(TagFilterConfiguration configuration) => _enqueue(() => _saveNow(configuration));

  Future<void> _saveNow(TagFilterConfiguration configuration) async {
    if (configuration.schemaVersion != 1) {
      throw FormatException('Unsupported filter schema version: ${configuration.schemaVersion}');
    }
    final ids = <String>{};
    for (final rule in configuration.rules) {
      if (!ids.add(rule.id)) throw FormatException('Duplicate filter rule id: ${rule.id}');
    }
    await Directory(directoryPath).create(recursive: true);
    await temporaryFile.writeAsString(await _encode(configuration), flush: true);

    var movedPrimary = false;
    try {
      if (await file.exists()) {
        var validPrimary = false;
        try {
          await _decode(await file.readAsString(), skipUnreadableRules: false);
          validPrimary = true;
        } catch (_) {
          await _preserveDamaged(file);
        }
        if (validPrimary) {
          if (await backupFile.exists()) await backupFile.delete();
          await file.rename(backupFile.path);
          movedPrimary = true;
        } else {
          await file.delete();
        }
      }
      await temporaryFile.rename(file.path);
    } catch (_) {
      if (!await file.exists() && movedPrimary && await backupFile.exists()) {
        await backupFile.copy(file.path);
      }
      rethrow;
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } catch (error, stackTrace) {
        _logRecovery('Cannot remove temporary filter file: $error', stackTrace);
      }
    }
  }

  Future<String> _encode(TagFilterConfiguration configuration) {
    final json = configuration.toJson();
    if (configuration.rules.length < 1000) return Future.value(jsonEncode(json));
    return Isolate.run(() => jsonEncode(json));
  }
}
