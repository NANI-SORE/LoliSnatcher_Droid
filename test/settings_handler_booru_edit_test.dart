import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';

void main() {
  late SettingsHandler handler;
  late Directory configDirectory;
  late String originalPath;
  late String originalBoorusPath;

  setUpAll(() async {
    await LocaleSettings.instance.loadAllLocales();
    if (SettingsRegistry.instance.isEmpty) registerAllSettings();
    handler = SettingsHandler.register();
  });

  setUp(() async {
    configDirectory = await Directory.systemTemp.createTemp('lolisnatcher-booru-edit-');
    originalPath = handler.path;
    originalBoorusPath = handler.boorusPath;
    handler.path = '${configDirectory.path}${Platform.pathSeparator}';
    handler.boorusPath = '${handler.path}boorus${Platform.pathSeparator}';
    handler.booruList.clear();
  });

  tearDown(() async {
    SettingsRegistry.instance
      ..removeAllOverridesForBooru('Original', save: false)
      ..removeAllOverridesForBooru('Renamed', save: false);
    SX.prefBooru.state.setValue('', save: false);
    await handler.flushPendingSettingsSaves();
    handler
      ..booruList.clear()
      ..path = originalPath
      ..boorusPath = originalBoorusPath;
    await configDirectory.delete(recursive: true);
  });

  tearDownAll(SettingsHandler.unregister);

  test('replaceBooru migrates overrides and preferred booru after the new file is written', () async {
    final original = Booru('Original', BooruType.Gelbooru, '', 'https://old.example', '');
    final replacement = Booru('Renamed', BooruType.Gelbooru, '', 'https://new.example', '');
    handler.booruList.add(original);
    SX.enableDrawerMascot.state.setOverrideFor('Original', true, save: false);
    SX.prefBooru.state.setValue('Original', save: false);
    await handler.saveBooru(original, onlySave: true);

    expect(await handler.replaceBooru(original, replacement), isTrue);

    expect(await File('${handler.boorusPath}Original.json').exists(), isFalse);
    final replacementFile = File('${handler.boorusPath}Renamed.json');
    expect(await replacementFile.exists(), isTrue);
    expect(SX.prefBooru.value, 'Renamed');
    expect(SX.enableDrawerMascot.state.hasOverrideFor('Original'), isFalse);
    expect(SX.enableDrawerMascot.state.getOverrideFor('Renamed'), isTrue);

    final savedBooru = jsonDecode(await replacementFile.readAsString()) as Map<String, dynamic>;
    expect(savedBooru['settingOverrides'], isNotEmpty);
    final savedSettings = jsonDecode(await File('${handler.path}settings.json').readAsString()) as Map<String, dynamic>;
    expect(savedSettings['prefBooru'], 'Renamed');
  });

  test('replaceBooru restores the original file and overrides when preference persistence fails', () async {
    final original = Booru('Original', BooruType.Gelbooru, '', 'https://old.example', '');
    final replacement = Booru('Renamed', BooruType.Gelbooru, '', 'https://new.example', '');
    handler.booruList.add(original);
    SX.enableDrawerMascot.state.setOverrideFor('Original', true, save: false);
    SX.prefBooru.state.setValue('Original', save: false);
    await handler.saveBooru(original, onlySave: true);

    // A directory at the settings file path makes the preference write fail
    // after the replacement booru file has already been written.
    await Directory('${handler.path}settings.json').create();

    await expectLater(handler.replaceBooru(original, replacement), throwsA(isA<FileSystemException>()));

    expect(await File('${handler.boorusPath}Original.json').exists(), isTrue);
    expect(await File('${handler.boorusPath}Renamed.json').exists(), isFalse);
    expect(SX.prefBooru.value, 'Original');
    expect(SX.enableDrawerMascot.state.getOverrideFor('Original'), isTrue);
    expect(SX.enableDrawerMascot.state.hasOverrideFor('Renamed'), isFalse);
  });
}
