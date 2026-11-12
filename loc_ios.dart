import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _sourceKey = 'ios(ignoreUnused)';
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
Future<bool> buildIOSLocalizations({bool check = false}) async {
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
    final sections = source.entries.where((entry) => entry.key.split('(').first == 'ios').toList();
    if (sections.isEmpty) continue;
    if (sections.length != 1) throw FormatException('Duplicate ios section: ${file.path}');
    final sectionInfo = _nativeKey(sections.single.key, file.path);
    final section = sections.single.value;
    if (section is! Map<String, dynamic>) throw FormatException('Expected $_sourceKey object: ${file.path}');
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
  if (base == null || base.isEmpty) throw const FormatException('English ios translations are required');
  for (final entry in translations.entries) {
    final extra = entry.value.keys.where((key) => !base.containsKey(key)).toList();
    if (extra.isNotEmpty) throw FormatException('Unknown native keys in ${entry.key}: ${extra.join(', ')}');
  }

  final keys = base.keys.toList()..sort();
  final locales = translations.keys.toList()..sort();
  final strings = <String, Object>{};
  for (final key in keys) {
    strings[key] = {
      'comment': 'Generated from assets/i18n/*.json ($_sourceKey). Edit the JSON sources, then run loc_build.dart.',
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
  final catalog = File(p.join('ios', 'Runner', 'InfoPlist.xcstrings'));
  if (await catalog.exists() && await catalog.readAsString() == output) {
    stdout.writeln('iOS native strings are up to date (${locales.join(', ')}).');
    return true;
  }
  if (check) {
    stderr.writeln('iOS native strings are stale. Run dart run loc_build.dart --ios-only.');
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
