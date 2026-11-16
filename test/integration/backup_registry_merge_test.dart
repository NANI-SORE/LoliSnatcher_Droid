import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    SettingsHandler.register();
    SearchHandler.register();
    TagHandler.register();
  });
  tearDownAll(() {
    TagHandler.unregister();
    SearchHandler.unregister();
    SettingsHandler.unregister();
  });

  test('full backups keep filters and presets when the main database replaces its child entries', () {
    expect(
      BackupEntryRegistry.instance.fullBackupEntries.map((entry) => entry.id),
      containsAll([BackupEntryId.filters, BackupEntryId.downloadPresets]),
    );
    expect(BackupEntryRegistry.databaseChildIds, isNot(contains(BackupEntryId.filters)));
    expect(BackupEntryRegistry.databaseChildIds, isNot(contains(BackupEntryId.downloadPresets)));
  });

  for (final entry in <String, Object>{
    'query': 42,
    'overwrite': 'yes',
    'quality': 'Unsafe',
    'amount': {},
    'delay': 'NaN',
    'sourceNames': [3],
  }.entries) {
    test('preset preflight rejects malformed ${entry.key} before mutation', () async {
      final payload = [
        {
          'id': 'preset',
          'name': 'Example',
          'payload': {entry.key: entry.value},
        },
      ];
      await expectLater(
        BackupEntryRegistry.instance.validateEntry(
          BackupEntryId.downloadPresets,
          bytes: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        ),
        throwsFormatException,
      );
    });
  }

  test('portable preset form accepts numeric strings from existing saved forms', () async {
    final payload = [
      {
        'id': 'preset',
        'name': 'Example',
        'payload': {
          'query': 'cat',
          'amount': '100',
          'delay': 1000,
          'startPage': '1',
          'quality': 'Sample',
          'overwrite': false,
          'sourceNames': ['Source'],
        },
      },
    ];
    await BackupEntryRegistry.instance.validateEntry(
      BackupEntryId.downloadPresets,
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
  });

  test('backup localization works through both typed and dynamic lookup in English and Russian', () async {
    for (final locale in [AppLocale.en, AppLocale.ruRu]) {
      final strings = await locale.build();
      expect(strings['settings.backupAndTransfer.title'], strings.settings.backupAndTransfer.title);
      expect(strings['init.backingUpDataAfterUpdate'], strings.init.backingUpDataAfterUpdate);
    }
  });
}
