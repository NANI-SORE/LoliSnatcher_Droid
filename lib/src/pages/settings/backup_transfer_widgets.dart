import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';

/// Gives category lists room on desktop while keeping narrow screens scrollable.
class BackupSelectionDialog extends StatelessWidget {
  const BackupSelectionDialog({
    required this.icon,
    required this.title,
    required this.content,
    required this.actions,
    this.warning,
    super.key,
  });

  final Widget icon;
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final Widget? warning;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: icon,
    title: title,
    constraints: const BoxConstraints(maxWidth: 720),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    scrollable: true,
    content: SizedBox(width: 720, child: content),
    actions: warning == null
        ? actions
        : [
            SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: warning),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions,
                  ),
                ],
              ),
            ),
          ],
  );
}

/// Keeps settings readable both on a phone and inside the desktop settings dialog.
class BackupPageBody extends StatelessWidget {
  const BackupPageBody({required this.children, this.fullWidth = false, this.controller, super.key});
  final List<Widget> children;
  final bool fullWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fullWidth ? double.infinity : 720),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.symmetric(horizontal: fullWidth ? 0 : 16, vertical: 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: children,
        ),
      ),
    ),
  );
}

class BackupSection extends StatelessWidget {
  const BackupSection({
    required this.title,
    required this.children,
    this.trailing,
    this.allowHeaderWrap = true,
    this.headerPadding = EdgeInsets.zero,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool allowHeaderWrap;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: headerPadding.add(const EdgeInsets.only(bottom: 10)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final label = Text(title, style: Theme.of(context).textTheme.titleMedium);
              if (trailing == null) return label;
              if (allowHeaderWrap && (constraints.maxWidth < 420 || MediaQuery.textScalerOf(context).scale(14) > 20)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label,
                    Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: label),
                  trailing!,
                ],
              );
            },
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ],
    ),
  );
}

class BackupNotice extends StatelessWidget {
  const BackupNotice({required this.message, this.isWarning = false, this.icon = Icons.info_outline, super.key});
  final String message;
  final bool isWarning;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = isWarning ? colors.onErrorContainer : colors.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isWarning ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isWarning ? Icons.warning_amber_rounded : icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }
}

class BackupBusyOverlay extends StatelessWidget {
  const BackupBusyOverlay({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ModalBarrier(dismissible: false, color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.35)),
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Semantics(liveRegion: true, child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Groups only the supplied database categories, without changing selection rules.
class BackupEntryTree extends StatelessWidget {
  const BackupEntryTree({
    required this.entryIds,
    required this.entryBuilder,
    this.entryOptionsBuilder,
    this.sectionSpacing = 0,
    super.key,
  });

  final Iterable<BackupEntryId> entryIds;
  final Widget Function(BackupEntryDefinition entry) entryBuilder;
  final Widget? Function(BackupEntryDefinition entry)? entryOptionsBuilder;
  final double sectionSpacing;

  @override
  Widget build(BuildContext context) {
    final registry = BackupEntryRegistry.instance;
    final ids = entryIds.toSet();
    final childIds = BackupEntryRegistry.databaseChildIds.where(ids.contains).toList();
    final topLevelIds = ids
        .map((id) => registry.isDatabaseChild(id) ? BackupEntryRegistry.databaseParentId : id)
        .toSet();
    final database = registry.byId(BackupEntryRegistry.databaseParentId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in topLevelIds)
          Padding(
            padding: EdgeInsets.only(bottom: sectionSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ids.contains(id))
                  entryBuilder(registry.byId(id))
                else
                  ListTile(
                    leading: Icon(database.icon),
                    title: Text(context.loc.settings.database.title),
                  ),
                if (entryOptionsBuilder?.call(registry.byId(id)) case final Widget options)
                  Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), child: options),
                if (id == BackupEntryRegistry.databaseParentId)
                  for (final (index, childId) in childIds.indexed) ...[
                    _DatabaseTreeBranch(
                      key: ValueKey(childId),
                      isLast: index == childIds.length - 1,
                      child: entryBuilder(registry.byId(childId)),
                    ),
                    if (entryOptionsBuilder?.call(registry.byId(childId)) case final Widget options)
                      _DatabaseTreeBranch(
                        key: ValueKey((childId, 'options')),
                        isLast: index == childIds.length - 1,
                        showBranch: false,
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: options),
                      ),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DatabaseTreeBranch extends StatelessWidget {
  const _DatabaseTreeBranch({required this.isLast, required this.child, this.showBranch = true, super.key});

  final bool isLast;
  final Widget child;
  final bool showBranch;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.directional(
        textDirection: Directionality.of(context),
        start: 0,
        top: 0,
        bottom: 0,
        width: 40,
        child: CustomPaint(
          painter: _DatabaseTreePainter(
            color: Theme.of(context).colorScheme.outlineVariant,
            isLast: isLast,
            textDirection: Directionality.of(context),
            showBranch: showBranch,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(40, 6, 0, 6),
        child: child,
      ),
    ],
  );
}

class _DatabaseTreePainter extends CustomPainter {
  const _DatabaseTreePainter({
    required this.color,
    required this.isLast,
    required this.textDirection,
    required this.showBranch,
  });

  final Color color;
  final bool isLast;
  final TextDirection textDirection;
  final bool showBranch;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showBranch && isLast) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    final y = size.height / 2;
    final end = textDirection == TextDirection.rtl ? 0.0 : size.width;
    canvas.drawLine(Offset(x, 0), Offset(x, isLast ? y : size.height), paint);
    if (showBranch) canvas.drawLine(Offset(x, y), Offset(end, y), paint);
  }

  @override
  bool shouldRepaint(covariant _DatabaseTreePainter oldDelegate) =>
      color != oldDelegate.color ||
      isLast != oldDelegate.isLast ||
      textDirection != oldDelegate.textDirection ||
      showBranch != oldDelegate.showBranch;
}

class BackupEntryCheckbox extends StatelessWidget {
  const BackupEntryCheckbox({required this.entry, required this.selected, required this.onChanged, super.key});
  final BackupEntryDefinition entry;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    controlAffinity: ListTileControlAffinity.leading,
    secondary: Icon(entry.icon),
    title: Text(entry.title()),
    subtitle: Text(entry.description()),
    value: selected,
    onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
  );
}

/// Restore options are identical for files and received packages.
class BackupRestoreOptions extends StatelessWidget {
  const BackupRestoreOptions({
    required this.showTabs,
    required this.showTags,
    required this.tabsMode,
    required this.tagsMode,
    required this.onTabsModeChanged,
    required this.onTagsModeChanged,
    super.key,
  });
  final bool showTabs;
  final bool showTags;
  final BackupTabsMode tabsMode;
  final BackupTagsMode tagsMode;
  final ValueChanged<BackupTabsMode> onTabsModeChanged;
  final ValueChanged<BackupTagsMode> onTagsModeChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTabs) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<BackupTabsMode>(
            initialValue: tabsMode,
            isExpanded: true,
            decoration: InputDecoration(labelText: t.tabsImportMode, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: BackupTabsMode.merge, child: Text(context.loc.settings.sync.merge)),
              DropdownMenuItem(value: BackupTabsMode.replace, child: Text(context.loc.settings.sync.replace)),
            ],
            onChanged: (value) {
              if (value != null) onTabsModeChanged(value);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              tabsMode == BackupTabsMode.merge ? t.restoreTabsMergeHint : t.restoreTabsReplaceHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (showTags) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.overwriteTagTypes),
            subtitle: Text(
              tagsMode == BackupTagsMode.overwrite ? t.restoreTagsOverwriteHint : t.restoreTagsPreserveHint,
            ),
            value: tagsMode == BackupTagsMode.overwrite,
            onChanged: (value) => onTagsModeChanged(value ? BackupTagsMode.overwrite : BackupTagsMode.preferTypeIfNone),
          ),
        ],
      ],
    );
  }
}

class BackupTransferProgress extends StatelessWidget {
  const BackupTransferProgress({
    required this.stats,
    required this.isReceiving,
    this.onCancel,
    this.onClearError,
    this.errorMessage,
    super.key,
  });
  final BackupTransferStats? stats;
  final bool isReceiving;
  final VoidCallback? onCancel;
  final VoidCallback? onClearError;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    final current = stats;
    final failed = current?.currentEntry == 'error';
    final complete = current?.isComplete == true;
    final importing = current?.currentEntry == 'importing';
    final importProgress = importing ? current?.importProgress : null;
    final importTotal = importProgress?.totalItems;
    final importRatio = importTotal != null && importTotal > 0
        ? ((importProgress?.processedItems ?? 0) / importTotal).clamp(0.0, 1.0)
        : null;
    final total = current?.totalBytes;
    final ratio = total != null && total > 0 ? ((current?.bytesTransferred ?? 0) / total).clamp(0.0, 1.0) : null;
    final String title;
    if (failed) {
      title = t.transferNotCompleted;
    } else if (complete) {
      title = t.transferComplete;
    } else if (importing) {
      title = switch (importProgress?.phase) {
        BackupImportPhase.extracting => t.importExtracting,
        BackupImportPhase.verifying => t.verifyingTransfer,
        BackupImportPhase.validating => t.importValidating,
        BackupImportPhase.rechecking => t.importRechecking,
        BackupImportPhase.preparingDatabase => t.importPreparingDatabase,
        BackupImportPhase.cleaningUp => t.importCleaningUp,
        BackupImportPhase.refreshing => t.importRefreshing,
        BackupImportPhase.importing || null => t.importingPackage,
      };
    } else if (current == null) {
      title = t.waitingForApproval;
    } else if (total == null) {
      title = t.preparingTransfer;
    } else if (ratio == 1) {
      title = isReceiving ? t.verifyingTransfer : t.waitingForImport;
    } else {
      title = isReceiving ? t.receiveDataTitle : t.sendDataTitle;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline
                        : complete
                        ? Icons.check_circle_outline
                        : Icons.sync,
                    color: failed ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                ],
              ),
              if (!complete) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: importing ? importRatio : (ratio == 1 ? null : ratio),
                  semanticsLabel: title,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
              if (importProgress != null && !complete) ...[
                if (importProgress.entryId case final entryId?) ...[
                  const SizedBox(height: 12),
                  Text(BackupEntryRegistry.instance.byId(entryId).title()),
                ],
                if (importProgress.processedItems case final count?) ...[
                  const SizedBox(height: 8),
                  Text(
                    importTotal == null
                        ? t.importRecordsProcessed(count: count)
                        : t.importRecordsTotal(count: count, total: importTotal),
                  ),
                ],
                const SizedBox(height: 8),
                Text('${t.elapsed}: ${TransferFormatters.duration(DateTime.now().difference(current!.startedAt))}'),
                if (current.importProgressUpdatedAt case final updatedAt?)
                  Text(
                    t.importLastProgress(elapsed: TransferFormatters.duration(DateTime.now().difference(updatedAt))),
                  ),
              ],
              if (current != null && !failed) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    TransferFormatters.bytes(current.bytesTransferred),
                    if (total != null) TransferFormatters.bytes(total),
                  ].join(' / '),
                ),
                if (!complete && !importing && ratio != 1) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text('${t.speed}: ${TransferFormatters.bytes(current.bytesPerSecond.round())}/s'),
                      Text(
                        '${t.elapsed}: ${TransferFormatters.duration(DateTime.now().difference(current.startedAt))}',
                      ),
                    ],
                  ),
                ],
              ],
              if (failed && errorMessage != null) ...[
                const SizedBox(height: 12),
                SelectableText(errorMessage!),
              ],
              if (failed && complete && onClearError != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: onClearError,
                    icon: const Icon(Icons.close),
                    label: Text(t.clearTransferError),
                  ),
                ),
              ],
              if (onCancel != null && !complete) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: Text(context.loc.cancel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BackupTransferActivity extends StatelessWidget {
  const BackupTransferActivity({required this.logs, required this.history, super.key});
  final List<BackupTransferLog> logs;
  final List<TransferHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (logs.isNotEmpty) ...[
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.notes),
              title: Text(t.logs),
              subtitle: Text(logs.first.message, maxLines: 2, overflow: TextOverflow.ellipsis),
              children: [
                for (final log in logs.take(100))
                  ListTile(
                    dense: true,
                    title: SelectableText(log.message),
                    subtitle: Text(TransferFormatters.time(log.createdAt)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: const Icon(Icons.history),
            title: Text(t.history),
            subtitle: history.isEmpty ? Text(t.noHistory) : null,
            children: [
              for (final entry in history.take(20))
                ListTile(
                  title: Text(entry.peerName.isEmpty ? entry.peerAddress : entry.peerName),
                  subtitle: Text(
                    [
                      entry.peerAddress,
                      TransferFormatters.dateTime(entry.createdAt),
                      entry.entryIds
                          .map(
                            (id) =>
                                BackupEntryRegistry.instance.entries
                                    .where((entry) => entry.id == id)
                                    .firstOrNull
                                    ?.title() ??
                                id.name,
                          )
                          .join(', '),
                    ].where((line) => line.isNotEmpty).join('\n'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
