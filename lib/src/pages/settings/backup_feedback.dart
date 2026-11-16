import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/pages/settings/backup_theme.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/services/local_network_permission.dart';

String backupFailureMessage(BuildContext context, Object error, {bool transfer = false}) {
  final t = context.loc.settings.backupAndTransfer;
  if (error is LocalNetworkPermissionDenied) return context.loc.permissions.localNetworkRequired;
  if (error is BackupRestoreFailure) return t.restoreFailedRecovered;
  final text = error.toString().toLowerCase();
  if (text.contains('protocol') ||
      text.contains('протокол') ||
      text.contains('unsupported secure transfer handshake') ||
      text.contains(t.unsupportedTransferProtocol.toLowerCase())) {
    return t.updateBothDevices;
  }
  if (error is FileSystemException || text.contains('storage access') || text.contains('filesystemexception')) {
    return t.storageFailure;
  }
  if (error is SocketException ||
      error is TimeoutException ||
      text.contains('socketexception') ||
      text.contains('timeoutexception')) {
    return t.connectionFailure;
  }
  if (text.contains('declined') || text.contains('отклон')) return t.transferDeclined;
  if (error is FormatException || text.contains('formatexception')) {
    return transfer ? t.invalidTransferData : t.invalidBackupShort;
  }
  return t.operationFailed;
}

String backupDateTime(BuildContext context, DateTime value) {
  final localizations = MaterialLocalizations.of(context);
  final date = value.toLocal();
  return '${localizations.formatCompactDate(date)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

String backupImportPhaseTitle(BuildContext context, BackupImportPhase? phase) {
  final t = context.loc.settings.backupAndTransfer;
  return switch (phase) {
    BackupImportPhase.extracting => t.importExtracting,
    BackupImportPhase.verifying => t.verifyingTransfer,
    BackupImportPhase.validating => t.importValidating,
    BackupImportPhase.rechecking => t.importRechecking,
    BackupImportPhase.preparingDatabase => t.importPreparingDatabase,
    BackupImportPhase.cleaningUp => t.importCleaningUp,
    BackupImportPhase.refreshing => t.importRefreshing,
    BackupImportPhase.snapshotting => t.importSnapshotting,
    BackupImportPhase.rollingBack => t.importRollingBack,
    BackupImportPhase.importing || null => t.importingPackage,
  };
}

class BackupErrorDetails extends StatelessWidget {
  const BackupErrorDetails({required this.details, super.key});
  final String details;

  @override
  Widget build(BuildContext context) => BackupControlsTheme(
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.loc.settings.backupAndTransfer.details),
      children: [
        Align(alignment: AlignmentDirectional.centerStart, child: SelectableText(details)),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: details)),
            icon: const Icon(Icons.copy),
            label: Text(context.loc.copy),
          ),
        ),
      ],
    ),
  );
}

class BackupOperationController extends ChangeNotifier {
  bool busy = false;
  Object? error;
  String? message;
  String? source;
  BackupImportProgress? progress;
  DateTime? startedAt;
  DateTime? updatedAt;
  Timer? _heartbeat;
  final _uiThrottle = Stopwatch();
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void showMessage(String text, {bool isError = false}) {
    if (isError) {
      error = text;
      message = null;
      if (!busy) source = null;
    } else {
      error = null;
      message = text;
    }
    _notify();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    message = null;
    source = null;
    progress = null;
    updatedAt = null;
    startedAt = DateTime.now();
    _uiThrottle.start();
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    _notify();
    try {
      await action();
    } catch (failure) {
      error = failure;
    } finally {
      _heartbeat?.cancel();
      busy = false;
      _notify();
    }
  }

  BackupImportOptions track(BackupImportOptions options) => options.withProgress((value) {
    final changed = progress?.phase != value.phase || progress?.entryId != value.entryId;
    progress = value;
    updatedAt = DateTime.now();
    if (changed || _uiThrottle.elapsedMilliseconds >= 250) {
      _uiThrottle.reset();
      _notify();
    }
  });

  void clear() {
    if (busy) return;
    error = null;
    message = null;
    source = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    super.dispose();
  }
}

class BackupOperationFeedback extends StatelessWidget {
  const BackupOperationFeedback({required this.operation, super.key});
  final BackupOperationController operation;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    final progress = operation.progress;
    final busy = operation.busy;
    final error = operation.error;
    if (!busy && error == null && operation.message == null) return const SizedBox.shrink();
    final title = error != null
        ? backupFailureMessage(context, error)
        : busy
        ? progress == null
              ? t.operationInProgress
              : backupImportPhaseTitle(context, progress.phase)
        : operation.message!;
    final total = progress?.totalItems;
    return BackupControlsTheme(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(liveRegion: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              if (operation.source case final source?) ...[
                const SizedBox(height: 8),
                SelectableText(source),
              ],
              if (busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total != null && total > 0 ? ((progress?.processedItems ?? 0) / total).clamp(0.0, 1.0) : null,
                  semanticsLabel: title,
                ),
                if (progress?.entryId case final entryId?) ...[
                  const SizedBox(height: 8),
                  Text(BackupEntryRegistry.instance.byId(entryId).title()),
                ],
                if (progress?.processedItems case final count?) ...[
                  const SizedBox(height: 8),
                  Text(
                    total == null
                        ? t.importRecordsProcessed(count: count)
                        : t.importRecordsTotal(count: count, total: total),
                  ),
                ],
                const SizedBox(height: 8),
                Text('${t.elapsed}: ${TransferFormatters.duration(DateTime.now().difference(operation.startedAt!))}'),
                if (operation.updatedAt case final updatedAt? when DateTime.now().difference(updatedAt).inSeconds >= 10)
                  Text(
                    t.importLastProgress(elapsed: TransferFormatters.duration(DateTime.now().difference(updatedAt))),
                  ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  Text(t.finishRestoreFirst, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
              if (error != null) BackupErrorDetails(details: error.toString()),
              if (!busy)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(onPressed: operation.clear, child: Text(t.done)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
