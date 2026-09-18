import 'package:flutter/material.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';

/// A local restore previews categories and makes database replacement explicit.
Future<BackupImportOptions?> showBackupImportDialog(
  BuildContext context,
  List<BackupEntryId> entries, {
  Set<BackupEntryId>? restrictedTo,
}) {
  final registry = BackupEntryRegistry.instance;
  final available = entries.where((id) => restrictedTo == null || restrictedTo.contains(id)).toList();
  final selected = available.toSet();
  var tabsMode = BackupTabsMode.merge;
  var tagsMode = BackupTagsMode.preferTypeIfNone;
  return showDialog<BackupImportOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final t = context.loc.settings.backupAndTransfer;
        return AlertDialog(
          title: Text(t.importBackupTitle),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.selectedImportOnly),
                  for (final id in available)
                    CheckboxListTile(
                      title: Text(registry.byId(id).title()),
                      value: selected.contains(id),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    ),
                  if (selected.contains(BackupEntryId.database))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(t.databaseReplacementWarning),
                    ),
                  if (selected.contains(BackupEntryId.tabs))
                    DropdownButtonFormField<BackupTabsMode>(
                      initialValue: tabsMode,
                      decoration: InputDecoration(labelText: t.entryTabsTitle),
                      items: [
                        DropdownMenuItem(value: BackupTabsMode.merge, child: Text(context.loc.settings.sync.merge)),
                        DropdownMenuItem(value: BackupTabsMode.replace, child: Text(context.loc.settings.sync.replace)),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() => tabsMode = value);
                      },
                    ),
                  if (selected.contains(BackupEntryId.tags))
                    SwitchListTile(
                      title: Text(context.loc.settings.sync.overwrite),
                      subtitle: Text(context.loc.settings.sync.tagsSyncModePreferTypeIfNone),
                      value: tagsMode == BackupTagsMode.overwrite,
                      onChanged: (value) =>
                          update(() => tagsMode = value ? BackupTagsMode.overwrite : BackupTagsMode.preferTypeIfNone),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.loc.cancel)),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      BackupImportOptions(
                        allowedEntryIds: selected,
                        rejectUnexpectedEntries: false,
                        tabsMode: tabsMode,
                        tagsMode: tagsMode,
                      ),
                    ),
              child: Text(t.import),
            ),
          ],
        );
      },
    ),
  );
}
