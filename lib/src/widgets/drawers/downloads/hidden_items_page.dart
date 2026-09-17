import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart' show SettingsHandler, TagsListData;
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/hidden_item_details_dialog.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

enum _HiddenItemsScope { all, manual, filters }

/// Retains the originating tab even if the active search changes underneath it.
class HiddenItemsPage extends StatefulWidget {
  const HiddenItemsPage({required this.tab, super.key});

  final SearchTab tab;

  @override
  State<HiddenItemsPage> createState() => _HiddenItemsPageState();
}

class _HiddenItemsPageState extends State<HiddenItemsPage> {
  _HiddenItemsScope scope = .all;
  String query = '';
  bool unblurThumbnails = false;

  String _reasonLabel(BooruItemFilterReason reason) {
    final loc = context.loc.settings.downloads;
    return switch (reason) {
      .hiddenTags => loc.hiddenReasonTags,
      .markedTags => loc.hiddenReasonMarked,
      .ai => loc.hiddenReasonAi,
      .favourite => loc.hiddenReasonFavourite,
      .snatched => loc.hiddenReasonSnatched,
    };
  }

  List<HiddenItemFilterMatch> _reasonDetails(
    BooruItem item,
    List<BooruItemFilterReason> reasons, {
    required bool manuallyHidden,
  }) {
    // Resolve tags only for rendered rows, and retain every match in both views.
    final hasTagFilter = reasons.any((reason) => reason == .hiddenTags || reason == .markedTags || reason == .ai);
    final matches = hasTagFilter
        ? SettingsHandler.instance.parseTagsList(item.tagsList, isCapped: false)
        : const TagsListData();
    return [
      if (manuallyHidden) (label: context.loc.settings.downloads.hiddenManually, tags: const <String>[]),
      ...reasons.map((reason) {
        final tags = switch (reason) {
          .hiddenTags => matches.hiddenTags,
          .markedTags => matches.markedTags,
          .ai => matches.aiTags,
          .favourite || .snatched => const <String>[],
        };
        return (label: _reasonLabel(reason), tags: tags);
      }),
    ];
  }

  void _showDetails(BooruItem item, List<HiddenItemFilterMatch> matches) {
    showDialog<void>(
      context: context,
      builder: (context) => HiddenItemDetailsDialog(
        item: item,
        booru: widget.tab.booruHandler.sourceBooruFor(item),
        matches: matches,
        forceUnblur: unblurThumbnails,
        onRestore: () => widget.tab.unhideItem(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final loc = context.loc.settings.downloads;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.hiddenItems),
        actions: [
          Obx(
            () => IconButton(
              tooltip: loc.unblurThumbnails,
              icon: const Icon(Icons.blur_off),
              onPressed: tab.hasHiddenItems && !unblurThumbnails ? () => setState(() => unblurThumbnails = true) : null,
            ),
          ),
          Obx(
            () => IconButton(
              tooltip: loc.unhideHidden,
              icon: const Icon(Icons.visibility_outlined),
              onPressed: tab.hasHiddenItems ? tab.unhideItems : null,
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: context.loc.search,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => query = value.trim().toLowerCase()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final value in _HiddenItemsScope.values)
                        ChoiceChip(
                          label: Text(switch (value) {
                            .all => loc.hiddenAll,
                            .manual => loc.hiddenManually,
                            .filters => loc.hiddenByFilters,
                          }),
                          selected: scope == value,
                          onSelected: (_) => setState(() => scope = value),
                        ),
                    ],
                  ),
                ),
                Padding(padding: const EdgeInsets.all(16), child: Text(loc.hiddenItemsInfo)),
              ],
            ),
          ),
          Obx(() {
            final manual = tab.hiddenItems.value;
            final filtered = tab.booruHandler.filterHiddenItems.value;
            final items = tab.allHiddenItems.where((item) {
              if (scope == .manual && !manual.contains(item)) return false;
              if (scope == .filters && !filtered.containsKey(item)) return false;
              return query.isEmpty ||
                  (item.serverId ?? '').toLowerCase().contains(query) ||
                  item.postURL.toLowerCase().contains(query) ||
                  item.tagsList.any((tag) => tag.fullString.toLowerCase().contains(query));
            }).toList();
            if (items.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Kaomoji(
                          category: KaomojiCategory.indifference,
                          style: TextStyle(fontSize: 36),
                        ),
                        const SizedBox(height: 10),
                        Text(loc.noHiddenItems, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }
            return SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final reasons = filtered[item] ?? const <BooruItemFilterReason>[];
                final matches = _reasonDetails(item, reasons, manuallyHidden: manual.contains(item));
                final reasonText = matches
                    .map((match) => match.tags.isEmpty ? match.label : '${match.label}: ${match.tags.join(', ')}')
                    .join('\n');
                final source = tab.booruHandler.sourceBooruFor(item);
                return InkWell(
                  key: ObjectKey(item),
                  onTap: () => _showDetails(item, matches),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          height: 144,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Thumbnail(
                              item: item,
                              booru: source,
                              isStandalone: true,
                              useHero: false,
                              forceUnblur: unblurThumbnails,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  source.name ?? '',
                                  item.serverId ?? item.fileURL,
                                ].where((text) => text.isNotEmpty).join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(reasonText, style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: loc.unhideItem,
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () => tab.unhideItem(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}
