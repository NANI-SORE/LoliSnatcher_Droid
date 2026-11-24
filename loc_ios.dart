import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _baseLocale = 'en';

({String key, bool outdated}) _nativeKey(String raw, String source) {
  final match = RegExp(r'^([A-Za-z][A-Za-z0-9]*)(?:\(([^()]+)\))?$').firstMatch(raw);
  if (match == null) throw FormatException('Invalid native key: $source: $raw');
  final modifiers = match[2]?.split(',').map((modifier) => modifier.trim()).toSet() ?? <String>{};
  if (modifiers.difference({'ignoreUnused', 'ignoreMissing', 'OUTDATED'}).isNotEmpty) {
    throw FormatException('Native strings support only Slang analysis modifiers: $source: $raw');
  }
  return (key: match[1]!, outdated: modifiers.contains('OUTDATED'));
}

/// Generates Xcode's native permission catalog from the Slang JSON sources.
/// Returns false in check mode when the checked-in catalog needs regeneration.
Future<bool> buildIOSLocalizations({
  bool check = false,
  String sectionName = 'ios',
  String catalogName = 'InfoPlist',
  bool android = false,
}) async {
  final sourceKey = '$sectionName(ignoreUnused)';
  final translations = <String, Map<String, String>>{};
  final outdated = <String, Set<String>>{};
  final files = await Directory(p.join('assets', 'i18n')).list().where((entry) => entry is File).cast<File>().toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final localePattern = RegExp(r'^[a-z]{2,3}(?:[-_][A-Z][a-z]{3})?(?:[-_](?:[A-Z]{2}|[0-9]{3}))?$');
  for (final file in files) {
    if (p.extension(file.path) != '.json') continue;
    final locale = p.basenameWithoutExtension(file.path);
    // Slang's analysis files are not translation inputs.
    if (locale.startsWith('_')) continue;
    if (!localePattern.hasMatch(locale)) throw FormatException('Invalid translation locale: ${file.path}');
    final source = jsonDecode(await file.readAsString());
    if (source is! Map<String, dynamic>) throw FormatException('Expected a translation object: ${file.path}');
    final sections = source.entries.where((entry) => entry.key.split('(').first == sectionName).toList();
    if (sections.isEmpty) continue;
    if (sections.length != 1) throw FormatException('Duplicate $sectionName section: ${file.path}');
    final sectionInfo = _nativeKey(sections.single.key, file.path);
    final section = sections.single.value;
    if (section is! Map<String, dynamic>) throw FormatException('Expected $sourceKey object: ${file.path}');
    final values = <String, String>{};
    final outdatedKeys = <String>{};
    for (final entry in section.entries) {
      // Slang/ARB translator comments aren't native permission entries.
      if (entry.key.startsWith('@')) continue;
      final keyInfo = _nativeKey(entry.key, file.path);
      final key = keyInfo.key;
      final value = entry.value;
      if (values.containsKey(key)) throw FormatException('Duplicate native key: ${file.path}: $key');
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Native strings must be nonempty strings: ${file.path}: $key');
      }
      if (RegExp(r'\$(?:\{|[A-Za-z_])|@:\S').hasMatch(value)) {
        throw FormatException('Native strings cannot contain Slang interpolation or links: ${file.path}: $key');
      }
      values[key] = value;
      if (sectionInfo.outdated || keyInfo.outdated) outdatedKeys.add(key);
    }
    final languageTag = locale.replaceAll('_', '-');
    if (translations.containsKey(languageTag)) throw FormatException('Duplicate native locale: $languageTag');
    translations[languageTag] = values;
    outdated[languageTag] = outdatedKeys;
  }
  final base = translations[_baseLocale];
  if (base == null || base.isEmpty) throw FormatException('English $sectionName translations are required');
  for (final entry in translations.entries) {
    final extra = entry.value.keys.where((key) => !base.containsKey(key)).toList();
    if (extra.isNotEmpty) throw FormatException('Unknown native keys in ${entry.key}: ${extra.join(', ')}');
  }

  final keys = base.keys.toList()..sort();
  final locales = translations.keys.toList()..sort();
  final strings = <String, Object>{};
  for (final key in keys) {
    strings[key] = {
      'comment': 'Generated from assets/i18n/*.json ($sourceKey). Edit the JSON sources, then run loc_build.dart.',
      'extractionState': 'manual',
      'localizations': {
        for (final locale in locales)
          locale: {
            'stringUnit': {
              'state': !translations[locale]!.containsKey(key)
                  ? 'new'
                  : outdated[locale]!.contains(key)
                  ? 'needs_review'
                  : 'translated',
              'value': translations[locale]![key] ?? base[key]!,
            },
          },
      },
    };
  }
  final output =
      '${const JsonEncoder.withIndent('  ').convert({
        'sourceLanguage': _baseLocale,
        'strings': strings,
        'version': '1.0',
      })}\n';
  if (android) {
    for (final locale in locales) {
      final folder = locale == 'en'
          ? 'values'
          : locale == 'ru-RU'
          ? 'values-ru'
          : 'values-b+${locale.replaceAll('-', '+')}';
      final resource = File(p.join('android', 'app', 'src', 'main', 'res', folder, 'download_notifications.xml'));
      final xml = StringBuffer('<?xml version="1.0" encoding="utf-8"?>\n')
        ..writeln('<!-- Generated by loc_build.dart from assets/i18n/*.json. -->')
        ..writeln('<resources>');
      for (final key in keys) {
        final name = key.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
        final value = (translations[locale]![key] ?? base[key]!)
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"')
            .replaceAll("'", r"\'")
            .replaceAll('\n', r'\n');
        xml.writeln(
          '    <string name="download_notification_$name" formatted="false">"${htmlEscape.convert(value)}"</string>',
        );
      }
      xml.writeln('</resources>');
      await resource.parent.create(recursive: true);
      if (!await resource.exists() || await resource.readAsString() != xml.toString()) {
        await resource.writeAsString(xml.toString());
      }
    }
  }
  final catalog = File(p.join('ios', 'Runner', '$catalogName.xcstrings'));
  if (await catalog.exists() && await catalog.readAsString() == output) {
    stdout.writeln('$catalogName strings are up to date (${locales.join(', ')}).');
    return true;
  }
  if (check) {
    stderr.writeln('$catalogName strings are stale. Run dart run loc_build.dart --ios-only.');
    return false;
  }
  final temporary = File('${catalog.path}.$pid.tmp');
  try {
    await temporary.writeAsString(output, flush: true);
    await temporary.rename(catalog.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
  stdout.writeln('Generated ${catalog.path} (${locales.join(', ')}).');
  return true;
}
