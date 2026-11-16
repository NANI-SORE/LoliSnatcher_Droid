import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_repository.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_restore_journal.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_json_array.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final envelope = <String, dynamic>{
    'v': 2,
    'uc': true,
    'groups': [
      {'id': 'group', 'n': 'Saved', 'c': '#FF123456', 'cl': true},
      {'id': 'empty', 'n': 'Empty group', 'c': '#FF654321'},
    ],
    'tabs': [
      {
        't': 'cat rating:safe',
        'b': 'Old',
        'sb': ['Second'],
        's': true,
        'p': 9,
        'sp': true,
        'g': 'group',
      },
    ],
  };

  test('grouped tabs retain empty groups, page, selection and collapse through source rename', () {
    final snapshot = TabBackupSnapshot.parse('\uFEFF ${jsonEncode(envelope)}');
    final result = jsonDecode(snapshot.encode(sourceNames: {'Old': 'New', 'Second': 'Other'})) as Map;
    expect(result['groups'], envelope['groups']);
    expect(result['uc'], true);
    expect(result['tabs'], [
      {
        't': 'cat rating:safe',
        'b': 'New',
        'sb': ['Other'],
        's': true,
        'p': 9,
        'sp': true,
        'g': 'group',
      },
    ]);
    expect(TabBackup.parseImport(jsonEncode(result)).single.groupId, 'group');
  });

  test('legacy and array backups remain portable', () {
    expect(TabBackupSnapshot.parse('Source|||query|||selected').tabs.single.selected, true);
    final parsed = TabBackupSnapshot.parse('[{"b":"Source","t":"query","p":4,"sp":true}]');
    expect(parsed.groups, isNull);
    expect(jsonDecode(parsed.encode()), isA<List>());
    expect(parsed.tabs.single.pageNum, 4);
  });

  for (final entry in <String, Object?>{
    's': 1,
    'sp': 'true',
    'p': -1,
    'sb': [1],
    'g': 7,
  }.entries) {
    test('strict tab preflight rejects malformed ${entry.key} without losing other fields', () {
      final raw = {'b': 'Source', 't': 'query', entry.key: entry.value};
      expect(() => TabBackup.parseImport(jsonEncode([raw])), throwsFormatException);
    });
  }
  test('unsupported group version and dangling membership are rejected', () {
    expect(() => TabBackupSnapshot.parse(jsonEncode({...envelope, 'v': 3})), throwsFormatException);
    expect(() => TabBackupSnapshot.parse(jsonEncode({...envelope, 'groups': []})), throwsFormatException);
  });

  group('crash recovery', () {
    late Directory root;
    late BackupRestoreJournal journal;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('merge-backup-');
      journal = BackupRestoreJournal(root);
    });
    tearDown(() async => root.delete(recursive: true));

    test('rollback restores filter primary, tmp, bak and removes newly imported presets', () async {
      for (final suffix in ['', '.tmp', '.bak']) {
        await File('${root.path}/filters.json$suffix').writeAsString('old$suffix');
      }
      await journal.prepare();
      for (final suffix in ['', '.tmp', '.bak']) {
        await File('${root.path}/filters.json$suffix').writeAsString('new');
      }
      await File('${root.path}/download_presets.json').writeAsString('[]');
      expect(await journal.recover(), true);
      for (final suffix in ['', '.tmp', '.bak']) {
        expect(await File('${root.path}/filters.json$suffix').readAsString(), 'old$suffix');
      }
      expect(await File('${root.path}/download_presets.json').exists(), false);
      expect(await journal.recover(), false);
    });

    test('old v1 recovery journals remain recoverable', () async {
      await File('${root.path}/settings.json').writeAsString('original');
      await journal.prepare();
      final file = File('${root.path}/${BackupRestoreJournal.directoryName}/journal.json');
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data['version'] = 1;
      (data['files'] as List).removeWhere(
        (dynamic row) => !['settings.json', 'tabs.json', 'tags.json', 'store.db'].contains(row['path']),
      );
      await file.writeAsString(jsonEncode(data));
      await File('${root.path}/settings.json').writeAsString('changed');
      expect(await journal.recover(), true);
      expect(await File('${root.path}/settings.json').readAsString(), 'original');
    });

    test('corrupt rollback snapshot is rejected before any live file is changed', () async {
      final original = File('${root.path}/settings.json');
      await original.writeAsString('old');
      await journal.prepare();
      await original.writeAsString('new');
      await File('${root.path}/${BackupRestoreJournal.directoryName}/original-0').writeAsString('corrupt');
      await expectLater(journal.recover(), throwsFormatException);
      expect(await original.readAsString(), 'new');
    });

    test('committed restore keeps imported state', () async {
      await journal.prepare();
      await File('${root.path}/filters.json').writeAsString('imported');
      await journal.commit();
      expect(await journal.recover(), false);
      expect(await File('${root.path}/filters.json').readAsString(), 'imported');
    });
  });

  test('streaming JSON import handles split UTF-8, escapes and nested values', () async {
    final rows = [
      {
        'name': 'Кот 🐈',
        'nested': [
          1,
          {'text': r'a]\\"b'},
        ],
      },
      {'id': 2},
    ];
    final bytes = utf8.encode(jsonEncode(rows));
    expect(await readBackupJsonArray(Stream.fromIterable(bytes.map((byte) => [byte]))).toList(), rows);
  });

  test('strict filter import rejects duplicate rules before replacing stored data', () async {
    final root = await Directory.systemTemp.createTemp('merge-filter-recovery-');
    try {
      final repo = JsonFilterRepository(root.path);
      await repo.replaceFromString('{"schemaVersion":1,"legacyImportVersion":2,"rules":[]}');
      final before = await repo.file.readAsString();
      await expectLater(repo.replaceFromString('{"schemaVersion":9,"rules":[]}'), throwsFormatException);
      expect(await repo.file.readAsString(), before);
      expect((await repo.load()).legacyImportVersion, 2);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
