import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/pages/settings/backup_feedback.dart';
import 'package:lolisnatcher/src/pages/settings/backup_theme.dart';
import 'package:lolisnatcher/src/pages/settings/language_page.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class BackupRecoveryApp extends StatelessWidget {
  const BackupRecoveryApp({
    required this.onRetry,
    required this.error,
    super.key,
  });

  final Future<void> Function() onRetry;
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
    darkTheme: ThemeData(colorSchemeSeed: Colors.deepPurple, brightness: Brightness.dark),
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleExt.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: BackupRecoveryFailurePage(onRetry: onRetry, initialError: error),
  );
}

class BackupRecoveryFailurePage extends StatefulWidget {
  const BackupRecoveryFailurePage({required this.onRetry, this.initialError, super.key});
  final Future<void> Function() onRetry;
  final Object? initialError;

  @override
  State<BackupRecoveryFailurePage> createState() => _BackupRecoveryFailurePageState();
}

class _BackupRecoveryFailurePageState extends State<BackupRecoveryFailurePage> {
  bool retrying = false;
  Object? retryError;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    final error = retryError ?? widget.initialError;
    return BackupControlsTheme(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restore, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      t.recoveryFailedTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(t.recoveryFailedMessage),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(backupFailureMessage(context, error)),
                      ),
                      BackupErrorDetails(details: error.toString()),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: retrying
                          ? null
                          : () async {
                              setState(() {
                                retrying = true;
                                retryError = null;
                              });
                              try {
                                await widget.onRetry();
                              } catch (error, stack) {
                                if (mounted) setState(() => retryError = error);
                                Logger.Inst().log(
                                  error,
                                  'BackupRecoveryFailurePage',
                                  'retry',
                                  LogTypes.exception,
                                  s: stack,
                                );
                              } finally {
                                if (mounted) setState(() => retrying = false);
                              }
                            },
                      child: retrying
                          ? Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                Text(t.recovering),
                              ],
                            )
                          : Text(t.retryRecovery),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
