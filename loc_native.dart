import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const nativeBaseLocale = 'en';

class NativeLocalizations {
  const NativeLocalizations({required this.sourceKey, required this.translations, required this.outdated});

  final String sourceKey;
  final Map<String, Map<String, String>> translations;
  final Map<String, Set<String>> outdated;

  Map<String, String> get base => translations[nativeBaseLocale]!;
  List<String> get keys => base.keys.toList()..sort();
  List<String> get locales => translations.keys.toList()..sort();
}

({String key, bool outdated}) _nativeKey(String raw, String source) {
  final match = RegExp(r'^([A-Za-z][A-Za-z0-9]*)(?:\(([^()]+)\))?$').firstMatch(raw);
  if (match == null) throw FormatException('Invalid native key: $source: $raw');
  final modifiers = match[2]?.split(',').map((modifier) => modifier.trim()).toSet() ?? <String>{};
  if (modifiers.difference({'ignoreUnused', 'ignoreMissing', 'OUTDATED'}).isNotEmpty) {
    throw FormatException('Native strings support only Slang analysis modifiers: $source: $raw');
  }
  return (key: match[1]!, outdated: modifiers.contains('OUTDATED'));
}

Future<NativeLocalizations> readNativeLocalizations(String sectionName) async {
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
      // Slang/ARB translator comments aren't native string entries.
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
  final base = translations[nativeBaseLocale];
  if (base == null || base.isEmpty) throw FormatException('English $sectionName translations are required');
  for (final entry in translations.entries) {
    final extra = entry.value.keys.where((key) => !base.containsKey(key)).toList();
    if (extra.isNotEmpty) throw FormatException('Unknown native keys in ${entry.key}: ${extra.join(', ')}');
  }

  return NativeLocalizations(sourceKey: sourceKey, translations: translations, outdated: outdated);
}
