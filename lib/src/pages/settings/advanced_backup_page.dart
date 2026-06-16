import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
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
    final available = await entry.isAvailable();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: Text(entry.title()),
                subtitle: Text(entry.description()),
              ),
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
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (file.name.toLowerCase().endsWith('.lsbackup')) {
        await compatService.importNamedBytes(file.name, bytes);
      } else {
        await entry.importEntry(bytes, const BackupImportOptions());
      }
      if (mounted) _snack(context.loc.settings.backupAndTransfer.entryImported(entry: entry.title()), false);
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
      await entry.importEntry(Uint8List.fromList(utf8.encode(text)), const BackupImportOptions());
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
    final topLevelEntries = registry.entries.where((entry) => !registry.isDatabaseChild(entry.id)).toList();
    return Scaffold(
      appBar: SettingsAppBar(title: context.loc.settings.backupAndTransfer.advancedExportImport),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              for (final entry in topLevelEntries) ...[
                _AdvancedEntryTile(
                  entry: entry,
                  onTap: () => _showActions(entry),
                ),
                if (entry.id == BackupEntryRegistry.databaseParentId)
                  for (final indexedEntry in BackupEntryRegistry.databaseChildIds.indexed)
                    _AdvancedEntryTile(
                      entry: registry.byId(indexedEntry.$2),
                      onTap: () => _showActions(registry.byId(indexedEntry.$2)),
                      isTreeChild: true,
                      isLastTreeChild: indexedEntry.$1 == BackupEntryRegistry.databaseChildIds.length - 1,
                    ),
              ],
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
    );
  }
}

class _AdvancedEntryTile extends StatelessWidget {
  const _AdvancedEntryTile({
    required this.entry,
    required this.onTap,
    this.isTreeChild = false,
    this.isLastTreeChild = false,
  });

  final BackupEntryDefinition entry;
  final VoidCallback onTap;
  final bool isTreeChild;
  final bool isLastTreeChild;

  @override
  Widget build(BuildContext context) {
    final tile = FutureBuilder<bool>(
      future: entry.isAvailable(),
      builder: (context, snapshot) {
        final available = snapshot.data ?? false;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(child: Icon(entry.icon)),
            title: Text(entry.title()),
            subtitle: Text(
              available
                  ? entry.description()
                  : '${entry.description()}\n${context.loc.settings.backupAndTransfer.unavailable}',
            ),
            isThreeLine: !available,
            trailing: const Icon(Icons.more_vert),
            onTap: onTap,
          ),
        );
      },
    );
    if (!isTreeChild) return tile;

    return Stack(
      children: [
        Positioned.directional(
          textDirection: Directionality.of(context),
          start: 0,
          top: 0,
          bottom: 0,
          width: 64,
          child: CustomPaint(
            painter: _AdvancedTreeBranchPainter(
              color: Theme.of(context).dividerColor,
              isLast: isLastTreeChild,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 64),
          child: tile,
        ),
      ],
    );
  }
}

class _AdvancedTreeBranchPainter extends CustomPainter {
  const _AdvancedTreeBranchPainter({required this.color, required this.isLast});

  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final x = size.width * 0.55;
    final y = size.height / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, isLast ? y : size.height), paint);
    canvas.drawLine(Offset(x, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _AdvancedTreeBranchPainter oldDelegate) {
    return color != oldDelegate.color || isLast != oldDelegate.isLast;
  }
}
