import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/backup_import_dialog.dart';
import 'package:lolisnatcher/src/pages/settings/backup_transfer_widgets.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_file_naming.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_import_compat_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_package_service.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class AdvancedBackupPage extends StatefulWidget {
  const AdvancedBackupPage({super.key});

  @override
  State<AdvancedBackupPage> createState() => _AdvancedBackupPageState();
}

class _AdvancedBackupPageState extends State<AdvancedBackupPage> {
  final registry = BackupEntryRegistry.instance;
  final packageService = BackupPackageService();
  final compatService = BackupImportCompatService();
  bool busy = false;

  Future<void> _showActions(BackupEntryDefinition entry) async {
    if (busy) return;
    final available = await entry.isAvailable();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(entry.icon),
                  title: Text(entry.title(), style: Theme.of(context).textTheme.titleLarge),
                  subtitle: Text(entry.description()),
                ),
                const Divider(),
                if (available)
                  ListTile(
                    enabled: available,
                    leading: const Icon(Icons.save_as),
                    title: Text(context.loc.settings.backupAndTransfer.exportToFile),
                    onTap: () {
                      Navigator.of(context).pop();
                      _exportEntryFile(entry);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.file_open_rounded),
                  title: Text(context.loc.settings.backupAndTransfer.importFromFile),
                  onTap: () {
                    Navigator.of(context).pop();
                    _importEntryFile(entry);
                  },
                ),
                if (entry.supportsClipboard) ...[
                  if (available)
                    ListTile(
                      enabled: available,
                      leading: const Icon(Icons.content_copy),
                      title: Text(context.loc.settings.backupAndTransfer.exportToClipboard),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportClipboard(entry);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.content_paste),
                    title: Text(context.loc.settings.backupAndTransfer.importFromClipboard),
                    onTap: () {
                      Navigator.of(context).pop();
                      _importClipboard(entry);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportEntryFile(BackupEntryDefinition entry) async {
    await _runBusy(() async {
      final path = await packageService.exportPackageFileWithPicker(entryIds: [entry.id]);
      if (path != null && mounted) {
        _snack(context.loc.settings.backupAndTransfer.entryExported(entry: entry.title()), false);
      }
    });
  }

  Future<void> _importEntryFile(BackupEntryDefinition entry) async {
    await _runBusy(() async {
      await packageService.withPickedBackup((name, file) async {
        final isPackage = BackupFileNaming.isPackageFileName(name);
        final entries = isPackage ? await packageService.inspectPackageFile(file) : [entry.id];
        if (!entries.contains(entry.id)) {
          throw const FormatException('The backup does not contain the selected category');
        }
        if (!mounted) return;
        final options = await showBackupImportDialog(context, entries, restrictedTo: {entry.id});
        if (options == null) return;
        await compatService.importNamedFile(isPackage ? name : entry.fileName, file, options: options);
        if (mounted) _snack(context.loc.settings.backupAndTransfer.entryImported(entry: entry.title()), false);
      });
    });
  }

  Future<void> _exportClipboard(BackupEntryDefinition entry) async {
    await _runBusy(() async {
      final payload = await entry.exportEntry(const BackupExportOptions());
      await Clipboard.setData(ClipboardData(text: utf8.decode(payload.bytes)));
      if (mounted) _snack(context.loc.settings.backupAndTransfer.entryCopied(entry: entry.title()), false);
    });
  }

  Future<void> _importClipboard(BackupEntryDefinition entry) async {
    await _runBusy(() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      if (!mounted) return;
      final options = await showBackupImportDialog(context, [entry.id]);
      if (options == null) return;
      await compatService.importNamedBytes(entry.fileName, Uint8List.fromList(utf8.encode(text)), options: options);
      if (mounted) _snack(context.loc.settings.backupAndTransfer.entryImported(entry: entry.title()), false);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _snack(e.toString(), true);
    } finally {
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
        appBar: SettingsAppBar(title: context.loc.settings.backupAndTransfer.advancedExportImport),
        body: Stack(
          children: [
            BackupPageBody(
              children: [
                BackupNotice(message: context.loc.settings.backupAndTransfer.advancedBackupHint),
                const SizedBox(height: 24),
                BackupEntryTree(
                  entryIds: registry.entries.map((entry) => entry.id),
                  sectionSpacing: 12,
                  entryBuilder: (entry) => _AdvancedEntryTile(entry: entry, onTap: () => _showActions(entry)),
                ),
              ],
            ),
            if (busy)
              Positioned.fill(
                child: BackupBusyOverlay(label: context.loc.settings.backupAndTransfer.operationInProgress),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedEntryTile extends StatelessWidget {
  const _AdvancedEntryTile({required this.entry, required this.onTap});
  final BackupEntryDefinition entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = Theme.of(context).cardTheme.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Card(
      margin: EdgeInsets.zero,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<bool>(
        future: entry.isAvailable(),
        builder: (context, snapshot) => ListTile(
          shape: shape,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(entry.icon, color: Theme.of(context).colorScheme.primary),
          title: Text(entry.title()),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.description()),
              if (snapshot.hasData && !snapshot.data!)
                Text(
                  context.loc.settings.backupAndTransfer.exportUnavailable,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          trailing: const Icon(Icons.more_horiz),
          onTap: onTap,
        ),
      ),
    );
  }
}
