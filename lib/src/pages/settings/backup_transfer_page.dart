import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/auto_backup_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_import_compat_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/pages/settings/backup_feedback.dart';
import 'package:lolisnatcher/src/pages/settings/backup_theme.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

import 'package:lolisnatcher/src/pages/settings/advanced_backup_page.dart';
import 'package:lolisnatcher/src/pages/settings/backup_import_dialog.dart';
import 'package:lolisnatcher/src/pages/settings/backup_transfer_widgets.dart';
import 'package:lolisnatcher/src/pages/settings/receive_data_page.dart';
import 'package:lolisnatcher/src/pages/settings/send_data_page.dart';

class BackupTransferPage extends StatefulWidget {
  const BackupTransferPage({super.key});

  @override
  State<BackupTransferPage> createState() => _BackupTransferPageState();
}

class _BackupTransferPageState extends State<BackupTransferPage> {
  final packageService = BackupPackageService();
  final importService = BackupImportCompatService();
  final autoBackupService = AutoBackupService();
  late final defaultBackupDirectory = autoBackupService.defaultBackupDirectory();
  AutoBackupConfig autoConfig = AutoBackupConfig.defaults;
  final operation = BackupOperationController();
  bool get busy => operation.busy;

  @override
  void initState() {
    super.initState();
    operation.addListener(_onOperationChanged);
    unawaited(_loadAutoConfig());
  }

  void _onOperationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    operation.removeListener(_onOperationChanged);
    operation.dispose();
    super.dispose();
  }

  Future<void> _loadAutoConfig() async {
    autoConfig = await autoBackupService.loadConfig();
    if (mounted) setState(() {});
  }

  Future<void> _exportAll() async {
    await _runBusy(() async {
      final path = await packageService.exportPackageFileWithPicker(
        entryIds: BackupEntryRegistry.instance.fullBackupEntries.map((entry) => entry.id).toList(),
      );
      if (path != null && mounted) {
        operation.source = path;
        _snack(context.loc.settings.backupAndTransfer.backupExported, false);
      }
    });
  }

  Future<void> _importAny() async {
    await _runBusy(() async {
      await packageService.withPickedBackup((name, file) async {
        operation.source = name;
        final preview = await importService.inspectNamedPreview(name, file);
        final entries = preview.entries;
        final size = TransferFormatters.bytes(await file.length());
        if (!mounted) return;
        final options = await showBackupImportDialog(
          context,
          entries,
          sourceName: '$name · $size',
          createdAt: preview.createdAt,
        );
        if (options == null) return;
        final imported = await importService.importNamedFile(name, file, options: operation.track(options));
        if (mounted) _snack(context.loc.settings.backupAndTransfer.importedEntries(count: imported.length), false);
      });
    });
  }

  Future<void> _backupNow() async {
    await _runBusy(() async {
      autoConfig = await autoBackupService.runNow(autoConfig);
      operation.source = autoConfig.location.isNotEmpty ? autoConfig.location : (await defaultBackupDirectory).path;
      if (mounted) _snack(context.loc.settings.backupAndTransfer.autoBackupCreated, false);
    });
  }

  Future<void> _resetAutoBackupConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => BackupControlsTheme(
        child: AlertDialog(
          icon: const Icon(Icons.settings_backup_restore),
          title: Text(context.loc.reset),
          scrollable: true,
          content: Text(context.loc.settings.backupAndTransfer.resetAutoBackupHint),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.loc.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.loc.reset)),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _runBusy(() async {
      await autoBackupService.resetConfig();
      autoConfig = await autoBackupService.loadConfig();
      if (mounted) _snack(context.loc.reset, false);
    });
  }

  Future<void> _retryUpdateBackup() => _runBusy(() async {
    try {
      await autoBackupService.retryAfterUpdateBackup();
      if (mounted) _snack(context.loc.settings.backupAndTransfer.autoBackupCreated, false);
    } finally {
      await _loadAutoConfig();
    }
  });

  Future<void> _chooseAutoLocation() async {
    try {
      final path = Platform.isAndroid
          ? await ServiceHandler.getSAFDirectoryAccess()
          : Platform.isIOS
          ? await ServiceHandler.chooseIosBackupDirectory()
          : await FilePicker.getDirectoryPath(
              dialogTitle: context.loc.settings.backupAndTransfer.autoBackupLocationDialogTitle,
            );
      if (path == null || path.isEmpty) return;
      autoConfig = autoConfig.copyWith(location: path);
      await _saveAutoConfig();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _snack(error.toString(), true);
    }
  }

  Future<void> _saveAutoConfig() async {
    try {
      await autoBackupService.saveConfig(autoConfig);
    } catch (error) {
      if (mounted) _snack(error.toString(), true);
      await _loadAutoConfig();
    }
  }

  Future<void> _runBusy(Future<void> Function() action) => operation.run(() async {
    try {
      await action();
    } finally {
      await _loadAutoConfig();
    }
  });

  void _snack(String message, bool isError) => operation.showMessage(message, isError: isError);

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: SettingsAppBar(
          title: t.title,
          leading: busy ? const IconButton(onPressed: null, icon: BackButtonIcon()) : null,
        ),
        body: Stack(
          children: [
            ExcludeFocus(
              excluding: busy,
              child: BackupPageBody(
                children: [
                  if (!busy) BackupOperationFeedback(operation: operation),
                  BackupSection(
                    title: t.backupData,
                    headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _ActionTile(
                        icon: Icons.save_alt,
                        title: t.exportBackupDialogTitle,
                        subtitle: t.exportBackupHint,
                        onTap: _exportAll,
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: Icons.restore,
                        title: t.importBackupTitle,
                        subtitle: t.importBackupHint,
                        onTap: _importAny,
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: Icons.tune,
                        title: t.advancedExportImport,
                        subtitle: t.advancedBackupHint,
                        onTap: () => SettingsPageOpen(context: context, page: (_) => const AdvancedBackupPage()).open(),
                      ),
                    ],
                  ),
                  BackupSection(
                    title: t.transferData,
                    headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _ActionTile(
                        icon: Icons.upload_rounded,
                        title: t.sendDataTitle,
                        subtitle: t.sendHint,
                        onTap: () => SettingsPageOpen(context: context, page: (_) => const SendDataPage()).open(),
                      ),
                      const Divider(height: 1),
                      _ActionTile(
                        icon: Icons.download_rounded,
                        title: t.receiveDataTitle,
                        subtitle: t.receiveHint,
                        onTap: () => SettingsPageOpen(context: context, page: (_) => const ReceiveDataPage()).open(),
                      ),
                    ],
                  ),
                  BackupSection(
                    title: t.autoBackup,
                    headerPadding: const EdgeInsets.symmetric(horizontal: 16),
                    trailing: IconButton(
                      tooltip: context.loc.reset,
                      icon: const Icon(Icons.settings_backup_restore),
                      onPressed: busy ? null : _resetAutoBackupConfig,
                    ),
                    children: [
                      SwitchListTile(
                        title: Text(t.enableAutoBackup),
                        subtitle: Text(t.autoBackupScheduleHint),
                        value: autoConfig.enabled,
                        onChanged: (value) async {
                          setState(() => autoConfig = autoConfig.copyWith(enabled: value));
                          await _saveAutoConfig();
                        },
                      ),
                      SwitchListTile(
                        title: Text(t.backupAfterUpdates),
                        subtitle: Text(t.backupAfterUpdatesSubtitle),
                        value: autoConfig.backupOnUpdate,
                        onChanged: (value) async {
                          setState(() => autoConfig = autoConfig.copyWith(backupOnUpdate: value));
                          await _saveAutoConfig();
                        },
                      ),
                      const Divider(height: 24),
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(t.backupLocation),
                        subtitle: autoConfig.location.isNotEmpty
                            ? Text(autoConfig.location)
                            : FutureBuilder<Directory>(
                                future: defaultBackupDirectory,
                                builder: (context, snapshot) => Text(
                                  snapshot.hasData
                                      ? '${t.defaultBackupLocation}\n${snapshot.data!.path}'
                                      : t.defaultBackupLocation,
                                ),
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _chooseAutoLocation,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BackupDropdown<int>(
                              initialValue: autoConfig.frequencyDays,
                              key: ValueKey(('frequency', autoConfig.frequencyDays)),
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t.backupInterval,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                DropdownMenuItem(value: 1, child: Text(t.daily)),
                                DropdownMenuItem(value: 7, child: Text(t.weekly)),
                                DropdownMenuItem(value: 30, child: Text(t.monthly)),
                              ],
                              onChanged: !autoConfig.enabled
                                  ? null
                                  : (value) async {
                                      if (value == null) return;
                                      setState(() => autoConfig = autoConfig.copyWith(frequencyDays: value));
                                      await _saveAutoConfig();
                                    },
                            ),
                            const SizedBox(height: 20),
                            BackupDropdown<int>(
                              initialValue: autoConfig.maximumBackups,
                              key: ValueKey(('retention', autoConfig.maximumBackups)),
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t.maximumBackups,
                                helperText: t.maximumBackupsHint,
                                helperMaxLines: 5,
                                border: const OutlineInputBorder(),
                              ),
                              items: const [0, 3, 5, 10, 20]
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value == 0 ? t.backupCountUnlimited : t.backupCount(count: value)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() => autoConfig = autoConfig.copyWith(maximumBackups: value));
                                await _saveAutoConfig();
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              autoConfig.lastBackupAt == null
                                  ? t.lastBackupNever
                                  : t.lastBackup(date: backupDateTime(context, autoConfig.lastBackupAt!)),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: busy ? null : _backupNow,
                              icon: const Icon(Icons.backup_outlined),
                              label: Text(t.backupNow),
                            ),
                            if (autoConfig.lastBackupError != null) ...[
                              const SizedBox(height: 16),
                              BackupNotice(
                                message: t.lastBackupFailed,
                                isWarning: true,
                              ),
                              BackupErrorDetails(details: autoConfig.lastBackupError!),
                            ],
                            if (autoConfig.lastUpdateBackupError != null) ...[
                              const SizedBox(height: 16),
                              BackupNotice(
                                message: t.lastUpdateBackupFailed,
                                isWarning: true,
                              ),
                              BackupErrorDetails(details: autoConfig.lastUpdateBackupError!),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _retryUpdateBackup,
                                icon: const Icon(Icons.refresh),
                                label: Text(t.retryUpdateBackup),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              Positioned.fill(
                child: BackupBusyOverlay(
                  label: t.operationInProgress,
                  content: BackupOperationFeedback(operation: operation),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
      child: Icon(icon),
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
