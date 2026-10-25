import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'loc_ios.dart';

Future<void> main(List<String> args) async {
  const allowed = {'--watch', '--ios-only', '--check-ios'};
  if (args.any((arg) => !allowed.contains(arg)) || (args.contains('--check-ios') && args.length != 1)) {
    stderr.writeln('Usage: loc_build.dart [--watch] [--ios-only] | --check-ios');
    exitCode = 64;
    return;
  }
  if (args.contains('--check-ios')) {
    exitCode = await _buildIOS(check: true);
    return;
  }
  final iosOnly = args.contains('--ios-only');
  exitCode = await buildLocalizations(iosOnly: iosOnly);
  if (exitCode != 0 || !args.contains('--watch')) return;

  Timer? debounce;
  Future<void> pending = Future.value();
  void scheduleBuild(FileSystemEvent event) {
    if (p.extension(event.path) != '.json' && p.basename(event.path) != 'slang.yaml') return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      // Serialize generation, including edits received during a running build.
      pending = pending.then((_) async {
        exitCode = await buildLocalizations(iosOnly: iosOnly);
      });
    });
  }

  final sourceSubscription = Directory(p.join('assets', 'i18n')).watch(recursive: true).listen(scheduleBuild);
  // Windows supports watching directories, not individual files. Watching the
  // parent also survives editors replacing slang.yaml with an atomic rename.
  final configSubscription = Directory('.').watch().listen((event) {
    if (p.basename(event.path) == 'slang.yaml') scheduleBuild(event);
  });
  final stop = Completer<void>();
  final signalSubscription = ProcessSignal.sigint.watch().listen((_) {
    if (!stop.isCompleted) stop.complete();
  });
  stdout.writeln('Watching localization sources. Press Ctrl+C to stop.');
  try {
    await stop.future;
  } finally {
    debounce?.cancel();
    await sourceSubscription.cancel();
    await configSubscription.cancel();
    await signalSubscription.cancel();
    await pending;
  }
}

Future<int> _buildIOS({bool check = false}) async {
  try {
    return await buildIOSLocalizations(check: check) ? 0 : 1;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    return 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    return 74;
  }
}

Future<int> buildLocalizations({bool iosOnly = false}) async {
  if (iosOnly) return _buildIOS();
  final status = await runSlang([]);
  if (status != 0) return status;

  // Preserve the generated method's source language, including English fallback.
  final resolver = RegExp(r"PluralResolvers\.cardinal\('([^']+)'\)");
  var replacements = 0;
  for (final file in Directory(p.join('lib', 'gen')).listSync().whereType<File>()) {
    final filename = p.basename(file.path);
    if (!filename.startsWith('strings') || p.extension(file.path, 2) != '.g.dart') continue;
    final fileLocale = RegExp(r'^strings_(.+)\.g\.dart$').firstMatch(filename)?.group(1);
    final content = await file.readAsString();
    final output = content.replaceAllMapped(resolver, (match) {
      replacements++;
      final language = match[1]!;
      final sourceLocale = fileLocale != null && fileLocale.split('_').first == language ? fileLocale : language;
      return "LocalizationPluralRules.cardinal('$sourceLocale')";
    });
    if (output.contains('PluralResolvers.cardinal')) {
      stderr.writeln(
        'Unrecognized cardinal resolver syntax in ${file.path}. Check the Slang generator before using this output.',
      );
      return 65;
    }
    if (output != content) await file.writeAsString(output);
  }
  if (replacements == 0) {
    stderr.writeln('No generated cardinal resolver calls found. Check the Slang generator before using this output.');
    return 65;
  }
  stdout.writeln('Adapted $replacements cardinal resolver calls to Intl.');
  return _buildIOS();
}

Future<int> runSlang(List<String> arguments) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'slang', ...arguments],
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
