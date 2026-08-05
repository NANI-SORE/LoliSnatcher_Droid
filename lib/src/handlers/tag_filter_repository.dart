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

class JsonFilterRepository implements FilterRepository {
  JsonFilterRepository(this.directoryPath);

  static const int _isolateCodecThreshold = 256 * 1024;

  final String directoryPath;
  Future<void> _pendingWrites = Future.value();

  File _fileNamed(String name) => File.fromUri(Directory(directoryPath).uri.resolve(name));

  File get file => _fileNamed('filters.json');
  File get backupFile => _fileNamed('filters.json.bak');
  File get temporaryFile => _fileNamed('filters.json.tmp');

  @override
  Future<TagFilterConfiguration> load() async {
    await _pendingWrites;
    return _loadNow();
  }

  Future<TagFilterConfiguration> _loadNow() async {
    if (await file.exists()) {
      try {
        return await decode(await file.readAsString());
      } catch (error, stackTrace) {
        Logger.Inst().log(
          'Failed to load filters.json: $error',
          'JsonFilterRepository',
          'load',
          LogTypes.exception,
          s: stackTrace,
        );
      }
    }

    if (await backupFile.exists()) {
      try {
        final configuration = await decode(await backupFile.readAsString());
        await Directory(directoryPath).create(recursive: true);
        await temporaryFile.writeAsString(await _encode(configuration), flush: true);
        if (await file.exists()) await file.delete();
        await temporaryFile.rename(file.path);
        return configuration;
      } catch (error, stackTrace) {
        Logger.Inst().log(
          'Failed to recover filters.json.bak: $error',
          'JsonFilterRepository',
          'load',
          LogTypes.exception,
          s: stackTrace,
        );
      }
    }
    return const TagFilterConfiguration();
  }

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
  Future<void> save(TagFilterConfiguration configuration) {
    final completer = Completer<void>();
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        await _saveNow(configuration);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

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
      if (await backupFile.exists()) await backupFile.delete();
      if (await file.exists()) {
        await file.rename(backupFile.path);
        movedPrimary = true;
      }
      await temporaryFile.rename(file.path);
    } catch (_) {
      if (!await file.exists() && movedPrimary && await backupFile.exists()) {
        await backupFile.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temporaryFile.exists()) await temporaryFile.delete();
    }
  }

  Future<String> _encode(TagFilterConfiguration configuration) {
    final json = configuration.toJson();
    if (configuration.rules.length < 1000) return Future.value(jsonEncode(json));
    return Isolate.run(() => jsonEncode(json));
  }
}
