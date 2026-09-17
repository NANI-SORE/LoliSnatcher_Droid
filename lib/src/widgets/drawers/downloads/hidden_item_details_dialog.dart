import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/hidden_item_viewer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

typedef HiddenItemFilterMatch = ({String label, List<String> tags});

class HiddenItemDetailsDialog extends StatelessWidget {
  const HiddenItemDetailsDialog({
    required this.item,
    required this.booru,
    required this.matches,
    required this.onRestore,
    required this.forceUnblur,
    super.key,
  });

  final BooruItem item;
  final Booru booru;
  final List<HiddenItemFilterMatch> matches;
  final VoidCallback onRestore;
  final bool forceUnblur;

  Widget _preview(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: item.sampleAspectRatio ?? item.previewAspectRatio ?? item.fileAspectRatio ?? 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Thumbnail(
              item: item,
              booru: booru,
              isStandalone: true,
              useHero: false,
              forceUnblur: forceUnblur,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _details(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tags = item.tagsList.where((tag) => tag.fullString.trim().isNotEmpty).toList();
    final metadata = [
      item.fileExt?.toUpperCase() ?? '',
      if (item.fileWidth != null && item.fileHeight != null) '${item.fileWidth!.round()} × ${item.fileHeight!.round()}',
      if (item.fileSize != null) Tools.formatBytes(item.fileSize!, 2),
      if (item.rating?.isNotEmpty == true) '${context.loc.tagView.rating}: ${item.rating}',
    ].where((text) => text.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matches.isNotEmpty) ...[
          Text(context.loc.settings.downloads.hiddenMatchingFilters, style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          for (final match in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.filter_alt_outlined, size: 18, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(match.label, style: theme.textTheme.labelLarge)),
                        ],
                      ),
                      if (match.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText(match.tags.join(', '), style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (metadata.isNotEmpty || item.postURL.isNotEmpty) ...[
          Text(context.loc.tagView.details, style: theme.textTheme.titleSmall),
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final detail in metadata) _DetailPill(text: detail)],
            ),
          ],
          if (item.postURL.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              context.loc.tagView.postURL,
              style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            SelectableText(item.postURL, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
        ],
        if (tags.isNotEmpty) ...[
          Text('${context.loc.tags} (${tags.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags) _DetailPill(text: tag.fullString, color: tag.tagType.getColour()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final sourceName = booru.name?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sourceName?.isNotEmpty == true ? sourceName! : context.loc.settings.downloads.hiddenItems,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                if (item.serverId?.isNotEmpty == true)
                  Text(
                    '${context.loc.tagView.id}: ${item.serverId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.loc.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.loc.settings.downloads;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.hiddenRestoreHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  onRestore();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.visibility_outlined),
                label: Text(loc.unhideItem),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => HiddenItemViewer(item: item, booru: booru),
                  ),
                ),
                icon: const Icon(Icons.open_in_full),
                label: Text(loc.openHiddenItemViewer),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stackedContent(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * 0.3).clamp(160.0, 320.0),
          child: _preview(context),
        ),
        const SizedBox(height: 24),
        _details(context),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 920,
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Let the entire dialog scroll when its chrome could crowd out the content.
            if (constraints.maxHeight < 480 ||
                constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 21) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const Divider(height: 1),
                    _stackedContent(context),
                    const Divider(height: 1),
                    _footer(context),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _header(context),
                const Divider(height: 1),
                Expanded(
                  child: constraints.maxWidth >= 680
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _preview(context)),
                              const SizedBox(width: 24),
                              Expanded(child: SingleChildScrollView(child: _details(context))),
                            ],
                          ),
                        )
                      : SingleChildScrollView(child: _stackedContent(context)),
                ),
                const Divider(height: 1),
                _footer(context),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.12) ?? theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color?.withValues(alpha: 0.35) ?? theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: SelectableText(text, style: theme.textTheme.bodySmall),
      ),
    );
  }
}
