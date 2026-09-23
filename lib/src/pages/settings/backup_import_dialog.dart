import 'package:flutter/material.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/backup_transfer_widgets.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';

/// A local restore previews categories and makes database replacement explicit.
Future<BackupImportOptions?> showBackupImportDialog(
  BuildContext context,
  List<BackupEntryId> entries, {
  Set<BackupEntryId>? restrictedTo,
}) {
  final available = entries.where((id) => restrictedTo == null || restrictedTo.contains(id)).toList();
  final registry = BackupEntryRegistry.instance;
  final selected = registry.normalizeSelection(available);
  var tabsMode = BackupTabsMode.merge;
  var tagsMode = BackupTagsMode.preferTypeIfNone;
  return showDialog<BackupImportOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        final t = context.loc.settings.backupAndTransfer;
        final fullDatabase = selected.contains(BackupEntryId.database);
        return BackupSelectionDialog(
          icon: const Icon(Icons.restore),
          title: Text(t.importBackupTitle),
          warning: fullDatabase ? BackupNotice(message: t.databaseReplacementWarning, isWarning: true) : null,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.selectedImportOnly),
              const SizedBox(height: 12),
              BackupEntryTree(
                entryIds: {...available, if (fullDatabase) ...BackupEntryRegistry.databaseChildIds},
                entryOptionsBuilder: (entry) {
                  if (!selected.contains(entry.id)) return null;
                  return switch (entry.id) {
                    BackupEntryId.tabs || BackupEntryId.tags => BackupRestoreOptions(
                      showTabs: entry.id == BackupEntryId.tabs,
                      showTags: entry.id == BackupEntryId.tags,
                      tabsMode: tabsMode,
                      tagsMode: tagsMode,
                      onTabsModeChanged: (value) => update(() => tabsMode = value),
                      onTagsModeChanged: (value) => update(() => tagsMode = value),
                    ),
                    _ => null,
                  };
                },
                entryBuilder: (entry) {
                  final includedInDatabase = fullDatabase && registry.isDatabaseChild(entry.id);
                  return BackupEntryCheckbox(
                    entry: entry,
                    selected: includedInDatabase || selected.contains(entry.id),
                    onChanged: includedInDatabase
                        ? null
                        : (value) => update(() {
                            if (value) {
                              selected.add(entry.id);
                            } else {
                              selected.remove(entry.id);
                            }
                            if (entry.id == BackupEntryId.database) {
                              selected.removeAll(BackupEntryRegistry.databaseChildIds);
                            }
                          }),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.loc.cancel)),
            FilledButton.icon(
              icon: const Icon(Icons.restore),
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
              label: Text(t.import),
            ),
          ],
        );
      },
    ),
  );
}
