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
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

import 'package:lolisnatcher/src/pages/settings/advanced_backup_page.dart';
import 'package:lolisnatcher/src/pages/settings/backup_import_dialog.dart';
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
  AutoBackupConfig autoConfig = AutoBackupConfig.defaults;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAutoConfig());
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
      if (path != null && mounted) _snack(context.loc.settings.backupAndTransfer.backupExported, false);
    });
  }

  Future<void> _importAny() async {
    await _runBusy(() async {
      await packageService.withPickedBackup((name, file) async {
        final entries = await importService.inspectNamedFile(name, file);
        if (!mounted) return;
        final options = await showBackupImportDialog(context, entries);
        if (options == null) return;
        final imported = await importService.importNamedFile(name, file, options: options);
        if (mounted) _snack(context.loc.settings.backupAndTransfer.importedEntries(count: imported.length), false);
      });
    });
  }

  Future<void> _backupNow() async {
    await _runBusy(() async {
      autoConfig = await autoBackupService.runNow(autoConfig);
      if (mounted) _snack(context.loc.settings.backupAndTransfer.autoBackupCreated, false);
    });
  }

  Future<void> _resetAutoBackupConfig() async {
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
    final path = Platform.isAndroid
        ? await ServiceHandler.getSAFDirectoryAccess()
        : await FilePicker.getDirectoryPath(
            dialogTitle: context.loc.settings.backupAndTransfer.autoBackupLocationDialogTitle,
          );
    if (path == null || path.isEmpty) return;
    autoConfig = autoConfig.copyWith(location: path);
    await _saveAutoConfig();
    if (mounted) setState(() {});
  }

  Future<void> _saveAutoConfig() async {
    try {
      await autoBackupService.saveConfig(autoConfig);
    } catch (error) {
      if (mounted) _snack(error.toString(), true);
      await _loadAutoConfig();
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack(e.toString(), true);
    } finally {
      await _loadAutoConfig();
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String message, bool isError) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(isError ? context.loc.error : context.loc.settings.backupAndTransfer.done),
      content: Text(message),
      leadingIcon: isError ? Icons.error_outline : Icons.check_circle_outline,
      leadingIconColor: isError ? Colors.red : Colors.green,
      sideColor: isError ? Colors.red : Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: SettingsAppBar(title: context.loc.settings.backupAndTransfer.title),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SectionTitle(context.loc.settings.backupAndTransfer.transferData),
                Column(
                  spacing: 8,
                  children: [
                    _ActionTile(
                      icon: Icons.send,
                      title: context.loc.settings.backupAndTransfer.send,
                      onTap: () => SettingsPageOpen(context: context, page: (_) => const SendDataPage()).open(),
                    ),
                    _ActionTile(
                      icon: Icons.file_download_outlined,
                      title: context.loc.settings.backupAndTransfer.receive,
                      onTap: () => SettingsPageOpen(context: context, page: (_) => const ReceiveDataPage()).open(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionTitle(context.loc.settings.backupAndTransfer.backupData),
                Column(
                  spacing: 8,
                  children: [
                    _ActionTile(
                      icon: Icons.save_as,
                      title: context.loc.settings.backupAndTransfer.export,
                      onTap: _exportAll,
                    ),
                    _ActionTile(
                      icon: Icons.file_open_rounded,
                      title: context.loc.settings.backupAndTransfer.import,
                      onTap: _importAny,
                    ),
                    _ActionTile(
                      icon: Icons.tune,
                      title: context.loc.settings.backupAndTransfer.advancedExportImport,
                      onTap: () => SettingsPageOpen(context: context, page: (_) => const AdvancedBackupPage()).open(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionTitle(
                  context.loc.settings.backupAndTransfer.autoBackup,
                  trailing: IconButton(
                    tooltip: context.loc.reset,
                    icon: const Icon(Icons.restore),
                    onPressed: busy ? null : _resetAutoBackupConfig,
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text(context.loc.settings.backupAndTransfer.enableAutoBackup),
                        value: autoConfig.enabled,
                        onChanged: (value) async {
                          autoConfig = autoConfig.copyWith(enabled: value);
                          await _saveAutoConfig();
                          if (mounted) setState(() {});
                        },
                      ),
                      SwitchListTile(
                        title: Text(context.loc.settings.backupAndTransfer.backupAfterUpdates),
                        subtitle: Text(context.loc.settings.backupAndTransfer.backupAfterUpdatesSubtitle),
                        value: autoConfig.backupOnUpdate,
                        onChanged: (value) async {
                          autoConfig = autoConfig.copyWith(backupOnUpdate: value);
                          await _saveAutoConfig();
                          if (mounted) setState(() {});
                        },
                      ),
                      ListTile(
                        title: Text(context.loc.settings.backupAndTransfer.backupLocation),
                        subtitle: Text(
                          autoConfig.location.isEmpty
                              ? context.loc.settings.backupAndTransfer.backupLocationNotSelected
                              : autoConfig.location,
                        ),
                        trailing: FilledButton(
                          onPressed: _chooseAutoLocation,
                          child: Text(context.loc.settings.backupAndTransfer.change),
                        ),
                      ),
                      ListTile(
                        title: Text(context.loc.settings.backupAndTransfer.backupInterval),
                        trailing: DropdownButton<int>(
                          value: autoConfig.frequencyDays,
                          items: [
                            DropdownMenuItem(
                              value: 1,
                              child: Text(context.loc.settings.backupAndTransfer.daily),
                            ),
                            DropdownMenuItem(
                              value: 7,
                              child: Text(context.loc.settings.backupAndTransfer.weekly),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Text(context.loc.settings.backupAndTransfer.monthly),
                            ),
                          ],
                          onChanged: (value) async {
                            if (value == null) return;
                            autoConfig = autoConfig.copyWith(frequencyDays: value);
                            await _saveAutoConfig();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      ListTile(
                        title: Text(context.loc.settings.backupAndTransfer.maximumBackups),
                        trailing: DropdownButton<int>(
                          value: autoConfig.maximumBackups,
                          items:
                              const [
                                    0,
                                    3,
                                    5,
                                    10,
                                    20,
                                  ]
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(
                                        value == 0
                                            ? context.loc.settings.backupAndTransfer.backupCountUnlimited
                                            : context.loc.settings.backupAndTransfer.backupCount(count: value),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            autoConfig = autoConfig.copyWith(maximumBackups: value);
                            await _saveAutoConfig();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      ListTile(
                        title: Text(
                          autoConfig.lastBackupAt == null
                              ? context.loc.settings.backupAndTransfer.lastBackupNever
                              : context.loc.settings.backupAndTransfer.lastBackup(
                                  date: TransferFormatters.dateTime(autoConfig.lastBackupAt!),
                                ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 36),
                          child: Row(
                            children: [
                              SizedBox(
                                height: 36,
                                child: ElevatedButton(
                                  onPressed: autoConfig.location.isEmpty ? null : _backupNow,
                                  child: Text(context.loc.settings.backupAndTransfer.backupNow),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (autoConfig.lastBackupError != null)
                        ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(context.loc.settings.backupAndTransfer.lastBackupFailed),
                          subtitle: Text(autoConfig.lastBackupError!),
                        ),
                      if (autoConfig.lastUpdateBackupError != null)
                        ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(context.loc.settings.backupAndTransfer.lastUpdateBackupFailed),
                          subtitle: Text(autoConfig.lastUpdateBackupError!),
                          trailing: IconButton(
                            tooltip: context.loc.settings.backupAndTransfer.retryUpdateBackup,
                            icon: const Icon(Icons.refresh),
                            onPressed: busy ? null : _retryUpdateBackup,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 30,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
