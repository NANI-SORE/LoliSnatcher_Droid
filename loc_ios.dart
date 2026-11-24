import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'loc_native.dart';

Future<bool> buildIOSLocalizations({bool check = false}) async {
  final permissions = await _buildCatalog('ios', 'InfoPlist', check: check);
  final notifications = await _buildCatalog('downloadNotifications', 'DownloadNotifications', check: check);
  return permissions && notifications;
}

Future<bool> _buildCatalog(String sectionName, String catalogName, {required bool check}) async {
  final source = await readNativeLocalizations(sectionName);
  final sourceKey = source.sourceKey;
  final translations = source.translations;
  final outdated = source.outdated;
  final base = source.base;

  final keys = source.keys;
  final locales = source.locales;
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
        'sourceLanguage': nativeBaseLocale,
        'strings': strings,
        'version': '1.0',
      })}\n';
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
