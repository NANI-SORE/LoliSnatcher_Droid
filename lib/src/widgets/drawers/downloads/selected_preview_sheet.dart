import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/fading_edge_reorderable_listview.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/drawers/downloads/hidden_item_viewer.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

class SelectedPreviewSheet extends StatefulWidget {
  const SelectedPreviewSheet({
    required this.tab,
    required this.itemsMatchingTagQuery,
    required this.selectedPreviewTags,
    required this.searchSuggestions,
    required this.onReorderItem,
    required this.onShowItemInfo,
    required this.onReverseSelected,
    required this.onStartSnatching,
    required this.onShareSelected,
    required this.onShareSelectedLongPress,
    super.key,
  });

  final SearchTab tab;
  final List<BooruItem> Function(Iterable<BooruItem> items, String rawQuery) itemsMatchingTagQuery;
  final List<Tag> Function(BooruItem item) selectedPreviewTags;
  final List<Tag> Function(String token) searchSuggestions;
  final void Function({
    required List<BooruItem> visibleItems,
    required int oldIndex,
    required int newIndex,
  })
  onReorderItem;
  final void Function(BuildContext context, BooruItem item, int selectedIndex) onShowItemInfo;
  final VoidCallback onReverseSelected;
  final Future<void> Function(BuildContext context, bool isLongTap) onStartSnatching;
  final Future<void> Function(BuildContext context) onShareSelected;
  final void Function(BuildContext context) onShareSelectedLongPress;

  @override
  State<SelectedPreviewSheet> createState() => _SelectedPreviewSheetState();
}

class _SelectedPreviewSheetState extends State<SelectedPreviewSheet> {
  SearchTab get tab => widget.tab;

  static const double _minSheetSize = 0.24;

  final TextEditingController _searchController = TextEditingController();
  final _listKey = GlobalKey<_SelectedPreviewListState>();
  bool _hideUnmatched = false;
  bool _isClosing = false;

  @override
  void dispose() {
    _dismissInput();
    _searchController.dispose();
    super.dispose();
  }

  void _dismissInput() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _close() {
    if (_isClosing) {
      return;
    }

    _isClosing = true;
    _dismissInput();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  String get _searchQuery => _searchController.value.text.trim();

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _onSearchChanged(String _) {
    setState(() {
      if (_searchQuery.isEmpty) _hideUnmatched = false;
    });
  }

  List<BooruItem> _filteredSelectedItems() {
    if (_searchQuery.isEmpty) {
      return [...tab.selected];
    }

    return widget.itemsMatchingTagQuery(tab.selected, _searchQuery);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) => _dismissInput(),
      child: _PreviewConstrainedBottomSheet(
        onDismiss: _close,
        child: NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            if (notification.extent <= _minSheetSize + 0.005) {
              _close();
            }
            return false;
          },
          child: DraggableScrollableSheet(
            expand: false,
            // The notification listener owns dismissal at the minimum size.
            shouldCloseOnMinExtent: false,
            initialChildSize: MediaQuery.viewInsetsOf(context).bottom > 0 ? 0.92 : 0.66,
            minChildSize: _minSheetSize,
            maxChildSize: 0.92,
            builder: (context, scrollController) => SettingsBottomSheet(
              onClosePressed: _close,
              pinActionButtonsToBottom: true,
              title: Obx(() {
                final total = tab.selected.length;
                final countText = _searchQuery.isEmpty
                    ? total.toFormattedString()
                    : '${_filteredSelectedItems().length.toFormattedString()}/${total.toFormattedString()}';

                return _SelectionSheetTitle('${context.loc.tagView.preview} ($countText)');
              }),
              content: Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _SelectedPreviewSearchInput(
                          controller: _searchController,
                          maxSuggestionsHeight: (constraints.maxHeight - 160).clamp(0.0, 168.0),
                          title: context.loc.search,
                          hintText: context.loc.searchBar.searchForTags,
                          suggestionsForToken: widget.searchSuggestions,
                          onChanged: _onSearchChanged,
                          actions: _searchQuery.isEmpty
                              ? null
                              : Obx(() {
                                  final hasMatches = _filteredSelectedItems().isNotEmpty;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                                        onPressed: hasMatches ? () => _listKey.currentState?.scrollToMatch(-1) : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                        onPressed: hasMatches ? () => _listKey.currentState?.scrollToMatch(1) : null,
                                      ),
                                      IconButton(
                                        isSelected: _hideUnmatched,
                                        icon: const Icon(Icons.filter_list),
                                        selectedIcon: const Icon(Icons.filter_list_off),
                                        onPressed: () => setState(() => _hideUnmatched = !_hideUnmatched),
                                      ),
                                    ],
                                  );
                                }),
                        ),
                      ),
                      Expanded(
                        child: _SelectedPreviewList(
                          key: _listKey,
                          tab: tab,
                          scrollController: scrollController,
                          query: _searchQuery,
                          hideUnmatched: _hideUnmatched,
                          itemsMatchingTagQuery: widget.itemsMatchingTagQuery,
                          selectedPreviewTags: widget.selectedPreviewTags,
                          onReorderItem: widget.onReorderItem,
                          onShowItemInfo: widget.onShowItemInfo,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionSpacing: 4,
              actionButtons: [
                Tooltip(
                  message: context.loc.settings.downloads.reverseSelectedOrder,
                  child: IconButton(
                    icon: const Icon(Icons.swap_vert_rounded),
                    onPressed: () {
                      widget.onReverseSelected();
                      setState(() {});
                    },
                  ),
                ),
                Obx(() {
                  final allSelected = [...tab.selected];
                  final filtered = _searchQuery.isEmpty ? const <BooruItem>[] : _filteredSelectedItems();
                  final canKeepFiltered = filtered.isNotEmpty && filtered.length < allSelected.length;

                  if (!canKeepFiltered) {
                    return const SizedBox.shrink();
                  }

                  return IconButton(
                    icon: const Icon(Icons.filter_alt_outlined),
                    onPressed: () {
                      tab.selected.assignAll(filtered);
                      _clearSearch();
                    },
                  );
                }),
                Obx(() {
                  final allSelected = [...tab.selected];
                  final filtered = _searchQuery.isEmpty ? const <BooruItem>[] : _filteredSelectedItems();
                  final canKeepUnmatched = filtered.isNotEmpty;

                  if (!canKeepUnmatched) {
                    return const SizedBox.shrink();
                  }

                  return IconButton(
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    onPressed: () {
                      final filteredSet = Set<BooruItem>.identity()..addAll(filtered);
                      tab.selected.assignAll(
                        allSelected.where((item) => !filteredSet.contains(item)),
                      );
                      _clearSearch();
                    },
                  );
                }),
                Tooltip(
                  message: context.loc.settings.downloads.snatchSelected,
                  child: GestureDetector(
                    onLongPress: () => widget.onStartSnatching(context, true),
                    child: IconButton(
                      icon: const Icon(Icons.download_sharp),
                      onPressed: () => widget.onStartSnatching(context, false),
                    ),
                  ),
                ),
                Tooltip(
                  message: context.loc.galleryButtons.share,
                  child: GestureDetector(
                    onLongPress: () => widget.onShareSelectedLongPress(context),
                    child: IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () => widget.onShareSelected(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedPreviewList extends StatefulWidget {
  const _SelectedPreviewList({
    required this.tab,
    required this.scrollController,
    required this.query,
    required this.hideUnmatched,
    required this.itemsMatchingTagQuery,
    required this.selectedPreviewTags,
    required this.onReorderItem,
    required this.onShowItemInfo,
    super.key,
  });

  final SearchTab tab;
  final ScrollController scrollController;
  final String query;
  final bool hideUnmatched;
  final List<BooruItem> Function(Iterable<BooruItem> items, String rawQuery) itemsMatchingTagQuery;
  final List<Tag> Function(BooruItem item) selectedPreviewTags;
  final void Function({
    required List<BooruItem> visibleItems,
    required int oldIndex,
    required int newIndex,
  })
  onReorderItem;
  final void Function(BuildContext context, BooruItem item, int selectedIndex) onShowItemInfo;

  @override
  State<_SelectedPreviewList> createState() => _SelectedPreviewListState();
}

class _SelectedPreviewListState extends State<_SelectedPreviewList> {
  String? _scrolledQuery;
  bool _scrolledHideUnmatched = false;
  BooruItem? _focusedMatch;
  int _scrollRequest = 0;

  void _scrollToItem(int index) {
    final request = ++_scrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _scrollRequest || !widget.scrollController.hasClients) return;
      final rowExtent = _selectedPreviewRowHeight(context) + 8;
      final target = (index * rowExtent).clamp(0.0, widget.scrollController.position.maxScrollExtent);
      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void scrollToMatch(int direction) {
    if (widget.query.isEmpty) return;
    final selected = [...widget.tab.selected];
    final matches = widget.itemsMatchingTagQuery(selected, widget.query);
    if (matches.isEmpty) return;
    final current = _focusedMatch == null ? -1 : matches.indexOf(_focusedMatch!);
    final next = current < 0 ? (direction > 0 ? 0 : matches.length - 1) : (current + direction) % matches.length;
    final item = matches[next];
    setState(() => _focusedMatch = item);
    _scrollToItem(widget.hideUnmatched ? next : selected.indexOf(item));
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => _buildList(context));
  }

  Widget _buildList(BuildContext context) {
    final allSelected = [...widget.tab.selected];
    final matchingItems = widget.query.isEmpty
        ? null
        : (Set<BooruItem>.identity()..addAll(widget.itemsMatchingTagQuery(allSelected, widget.query)));
    final visibleItems = widget.hideUnmatched && matchingItems != null
        ? allSelected.where(matchingItems.contains).toList()
        : allSelected;
    final rowExtent = _selectedPreviewRowHeight(context) + 8;
    if (_scrolledQuery != widget.query || _scrolledHideUnmatched != widget.hideUnmatched) {
      if (_scrolledQuery != widget.query) _focusedMatch = null;
      _scrolledQuery = widget.query;
      _scrolledHideUnmatched = widget.hideUnmatched;
      ++_scrollRequest;
      final matches = matchingItems == null ? const <BooruItem>[] : visibleItems.where(matchingItems.contains).toList();
      if (!matches.contains(_focusedMatch)) _focusedMatch = matches.firstOrNull;
      if (_focusedMatch != null) _scrollToItem(visibleItems.indexOf(_focusedMatch!));
    }
    if (allSelected.isEmpty) {
      return Center(
        child: Text(context.loc.settings.downloads.noItemsSelected),
      );
    }
    if (visibleItems.isEmpty) {
      return Center(child: Text(context.loc.preview.error.noResults));
    }

    return FadingEdgeScrollView.from(
      child: ReorderableListView.builder(
        scrollController: widget.scrollController,
        padding: const EdgeInsets.all(12),
        itemExtent: rowExtent,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) => child,
        itemCount: visibleItems.length,
        onReorderItem: (oldIndex, newIndex) => widget.onReorderItem(
          visibleItems: visibleItems,
          oldIndex: oldIndex,
          newIndex: newIndex,
        ),
        itemBuilder: (context, index) {
          final item = visibleItems[index];
          final isDimmed = matchingItems != null && !matchingItems.contains(item);
          final selectedIndex = widget.tab.selectedIndexOf(item) ?? index;
          final previewTags = widget.selectedPreviewTags(item);

          return ReorderableDelayedDragStartListener(
            key: ValueKey(item.key),
            index: index,
            child: _SelectedPreviewCard(
              item: item,
              selectedIndex: selectedIndex,
              previewTags: previewTags,
              isDimmed: isDimmed,
              isSearchTarget: matchingItems != null && identical(item, _focusedMatch),
              tab: widget.tab,
              onTap: () => widget.onShowItemInfo(context, item, selectedIndex),
            ),
          );
        },
      ),
    );
  }
}

class _SelectedPreviewCard extends StatelessWidget {
  const _SelectedPreviewCard({
    required this.item,
    required this.selectedIndex,
    required this.previewTags,
    required this.isDimmed,
    required this.isSearchTarget,
    required this.tab,
    required this.onTap,
  });

  final BooruItem item;
  final int selectedIndex;
  final List<Tag> previewTags;
  final bool isDimmed;
  final bool isSearchTarget;
  final SearchTab tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = tab.booruHandler.sourceBooruFor(item);
    final rowHeight = _selectedPreviewRowHeight(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSearchTarget ? BorderSide(color: colorScheme.primary, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: rowHeight,
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 76,
                      height: rowHeight,
                      child: ThumbnailBuild(
                        item: item,
                        handler: tab.booruHandler,
                        selectedIndex: selectedIndex,
                        onSelected: () => tab.selected.remove(item),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '#${selectedIndex + 1} · ${source.name ?? ''} ${item.serverId ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            Text(
                              _previewMetadata(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final style = Theme.of(context).textTheme.bodySmall;
                                  final fontSize = style?.fontSize ?? 12;
                                  final lineHeight =
                                      MediaQuery.textScalerOf(context).scale(fontSize) * (style?.height ?? 1.25);
                                  final linesThatFit = (constraints.maxHeight / lineHeight).floor();
                                  final maxLines = linesThatFit < 1 ? 1 : linesThatFit;

                                  return Text.rich(
                                    TextSpan(
                                      style: style,
                                      children: [
                                        for (final tag in previewTags)
                                          TextSpan(
                                            text: '${tag.fullString} ',
                                            style: TextStyle(
                                              color: tag.tagType.getColour(),
                                            ),
                                          ),
                                      ],
                                    ),
                                    maxLines: maxLines,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: context.loc.settings.downloads.clearSelected,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => tab.selected.remove(item),
                        ),
                        ReorderableDragStartListener(
                          index: selectedIndex,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (isDimmed) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: colorScheme.surface.withValues(alpha: 0.46),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: colorScheme.outline.withValues(alpha: 0.44),
                      child: const SizedBox(width: 3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SelectedItemPreviewSheet extends StatefulWidget {
  const SelectedItemPreviewSheet({
    required this.tab,
    required this.initialItem,
    required this.initialIndex,
    required this.selectedPreviewTags,
    required this.onMoveItem,
    super.key,
  });

  final SearchTab tab;
  final BooruItem initialItem;
  final int initialIndex;
  final List<Tag> Function(BooruItem item) selectedPreviewTags;
  final void Function(BooruItem item, int targetIndex) onMoveItem;

  @override
  State<SelectedItemPreviewSheet> createState() => _SelectedItemPreviewSheetState();
}

class _SelectedItemPreviewSheetState extends State<SelectedItemPreviewSheet> {
  SearchTab get tab => widget.tab;

  late final RxInt _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final selected = [...tab.selected];
    var initialIndex = selected.indexOf(widget.initialItem);
    if (initialIndex == -1) {
      initialIndex = widget.initialIndex;
    }
    if (initialIndex < 0) {
      initialIndex = 0;
    }
    if (selected.isNotEmpty && initialIndex >= selected.length) {
      initialIndex = selected.length - 1;
    }

    _currentIndex = initialIndex.obs;
    _pageController = PageController(initialPage: initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int targetIndex) {
    final count = tab.selected.length;
    if (count == 0) {
      return;
    }

    final page = targetIndex.clamp(0, count - 1);
    _currentIndex.value = page;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PreviewConstrainedBottomSheet(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.66,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scrollController) => SettingsBottomSheet(
          pinActionButtonsToBottom: true,
          actionSpacing: 0,
          title: Obx(() {
            final count = tab.selected.length;
            final safeIndex = count == 0 ? 0 : _currentIndex.value.clamp(0, count - 1);
            return _SelectionSheetTitle('${context.loc.item} #${safeIndex + 1}/$count');
          }),
          content: Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    SizedBox(
                      height: (constraints.maxHeight * 0.45).clamp(0.0, 220.0),
                      child: Obx(() {
                        final selected = [...tab.selected];
                        if (selected.isEmpty) {
                          return Center(
                            child: Text(context.loc.settings.downloads.noItemsSelected),
                          );
                        }

                        final canGoPrevious = _currentIndex.value > 0;
                        final canGoNext = _currentIndex.value < selected.length - 1;

                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            PageView.builder(
                              controller: _pageController,
                              itemCount: selected.length,
                              onPageChanged: (value) => _currentIndex.value = value,
                              itemBuilder: (context, pageIndex) {
                                final pageItem = selected[pageIndex];

                                return Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 220,
                                      maxHeight: 260,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio:
                                          pageItem.previewAspectRatio ??
                                          pageItem.sampleAspectRatio ??
                                          pageItem.fileAspectRatio ??
                                          0.75,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: ThumbnailBuild(
                                          item: pageItem,
                                          handler: tab.booruHandler,
                                          selectable: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              left: 8,
                              child: _PreviewPageArrowButton(
                                icon: Icons.chevron_left_rounded,
                                tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                                onPressed: canGoPrevious ? () => _goToPage(_currentIndex.value - 1) : null,
                              ),
                            ),
                            Positioned(
                              right: 8,
                              child: _PreviewPageArrowButton(
                                icon: Icons.chevron_right_rounded,
                                tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                                onPressed: canGoNext ? () => _goToPage(_currentIndex.value + 1) : null,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    if (constraints.maxHeight >= 180)
                      Obx(() {
                        final selected = [...tab.selected];
                        if (selected.isEmpty) return const SizedBox.shrink();
                        final item = selected[_currentIndex.value.clamp(0, selected.length - 1)];
                        final source = tab.booruHandler.sourceBooruFor(item);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${source.name ?? ''} · ${item.serverId ?? ''}\n${_previewMetadata(item)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Obx(() {
                          final selected = [...tab.selected];
                          if (selected.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final safeIndex = _currentIndex.value.clamp(0, selected.length - 1);
                          final tags = widget
                              .selectedPreviewTags(selected[safeIndex])
                              .where((t) => t.fullString.trim().isNotEmpty);

                          return Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in tags)
                                Chip(
                                  label: Text(tag.fullString),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: tag.tagType.getColour()?.withValues(alpha: 0.18),
                                  side: BorderSide(
                                    color: tag.tagType.getColour() ?? Theme.of(context).dividerColor,
                                  ),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actionButtons: [
            Obx(() {
              final selected = [...tab.selected];
              if (selected.isEmpty) return const SizedBox.shrink();
              final index = _currentIndex.value.clamp(0, selected.length - 1);
              final item = selected[index];
              return IconButton(
                tooltip: context.loc.settings.downloads.openHiddenItemViewer,
                icon: const Icon(Icons.open_in_full),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => HiddenItemViewer(item: item, booru: tab.booruHandler.sourceBooruFor(item)),
                  ),
                ),
              );
            }),
            Obx(() {
              final selected = [...tab.selected];
              if (selected.isEmpty) return const SizedBox.shrink();
              final index = _currentIndex.value.clamp(0, selected.length - 1);
              return IconButton(
                tooltip: context.loc.settings.downloads.clearSelected,
                icon: const Icon(Icons.deselect),
                onPressed: () {
                  tab.selected.remove(selected[index]);
                  if (tab.selected.isEmpty) {
                    Navigator.of(context).pop();
                  } else {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _goToPage(index);
                    });
                  }
                },
              );
            }),
            _MoveItemButton(
              tab: tab,
              currentIndex: _currentIndex,
              icon: Icons.vertical_align_top,
              targetIndexFor: (_, _) => 0,
              enabledFor: (index, _) => index > 0,
              onMoveItem: widget.onMoveItem,
              goToPage: _goToPage,
            ),
            _MoveItemButton(
              tab: tab,
              currentIndex: _currentIndex,
              icon: Icons.keyboard_arrow_up_rounded,
              targetIndexFor: (index, _) => index - 1,
              enabledFor: (index, _) => index > 0,
              onMoveItem: widget.onMoveItem,
              goToPage: _goToPage,
            ),
            _MoveItemButton(
              tab: tab,
              currentIndex: _currentIndex,
              icon: Icons.keyboard_arrow_down_rounded,
              targetIndexFor: (index, count) => index + 1,
              enabledFor: (index, count) => index < count - 1,
              onMoveItem: widget.onMoveItem,
              goToPage: _goToPage,
            ),
            _MoveItemButton(
              tab: tab,
              currentIndex: _currentIndex,
              icon: Icons.vertical_align_bottom,
              targetIndexFor: (_, count) => count - 1,
              enabledFor: (index, count) => index < count - 1,
              onMoveItem: widget.onMoveItem,
              goToPage: _goToPage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveItemButton extends StatelessWidget {
  const _MoveItemButton({
    required this.tab,
    required this.currentIndex,
    required this.icon,
    required this.targetIndexFor,
    required this.enabledFor,
    required this.onMoveItem,
    required this.goToPage,
  });

  final SearchTab tab;
  final RxInt currentIndex;
  final IconData icon;
  final int Function(int index, int count) targetIndexFor;
  final bool Function(int index, int count) enabledFor;
  final void Function(BooruItem item, int targetIndex) onMoveItem;
  final void Function(int targetIndex) goToPage;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final selected = [...tab.selected];
      if (selected.isEmpty) {
        return const SizedBox.shrink();
      }
      final safeIndex = currentIndex.value.clamp(0, selected.length - 1);
      final currentItem = selected[safeIndex];
      final targetIndex = targetIndexFor(safeIndex, selected.length);

      return IconButton(
        tooltip: context.loc.move,
        onPressed: enabledFor(safeIndex, selected.length)
            ? () {
                onMoveItem(currentItem, targetIndex);
                goToPage(targetIndex);
              }
            : null,
        icon: Icon(icon),
      );
    });
  }
}

class _PreviewPageArrowButton extends StatelessWidget {
  const _PreviewPageArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
      shape: const CircleBorder(),
      elevation: onPressed == null ? 0 : 2,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _SelectedPreviewSearchInput extends StatefulWidget {
  const _SelectedPreviewSearchInput({
    required this.controller,
    required this.title,
    required this.hintText,
    required this.suggestionsForToken,
    required this.onChanged,
    required this.maxSuggestionsHeight,
    this.actions,
  });

  final TextEditingController controller;
  final String title;
  final String hintText;
  final List<Tag> Function(String token) suggestionsForToken;
  final ValueChanged<String> onChanged;
  final double maxSuggestionsHeight;
  final Widget? actions;

  @override
  State<_SelectedPreviewSearchInput> createState() => _SelectedPreviewSearchInputState();
}

class _SelectedPreviewSearchInputState extends State<_SelectedPreviewSearchInput> {
  static const double _suggestionItemExtent = 48;

  late final FocusNode _focusNode;
  late final ScrollController _suggestionsScrollController;
  late TextEditingValue _latestInputValue;
  int _highlightedSuggestionIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _suggestionsScrollController = ScrollController();
    _focusNode.addListener(_onInputChanged);
    _latestInputValue = widget.controller.value;
    widget.controller.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _focusNode.unfocus();
    widget.controller.removeListener(_onInputChanged);
    _focusNode.removeListener(_onInputChanged);
    _focusNode.dispose();
    _suggestionsScrollController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    _latestInputValue = widget.controller.value;
    _highlightedSuggestionIndex = 0;
    if (_suggestionsScrollController.hasClients) {
      _suggestionsScrollController.jumpTo(0);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _setText(String text) {
    final nextValue = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _latestInputValue = nextValue;
    widget.controller.value = nextValue;
    widget.onChanged(text);
    setState(() {});
  }

  void _selectSuggestion(Tag tag) {
    final nextValue = _replaceCurrentSearchToken(widget.controller.value, tag.fullString);
    _latestInputValue = nextValue;
    widget.controller.value = nextValue;
    widget.onChanged(nextValue.text);
    _focusNode.requestFocus();
    setState(() {});
  }

  void _moveHighlightedSuggestion(int delta, List<Tag> suggestions) {
    if (suggestions.isEmpty) {
      return;
    }

    final nextIndex = (_highlightedSuggestionIndex + delta) % suggestions.length;
    if (nextIndex == _highlightedSuggestionIndex) {
      return;
    }

    setState(() {
      _highlightedSuggestionIndex = nextIndex;
    });
    _scrollToHighlightedSuggestion();
  }

  void _highlightSuggestion(int index) {
    if (index == _highlightedSuggestionIndex) {
      return;
    }

    setState(() {
      _highlightedSuggestionIndex = index;
    });
  }

  void _scrollToHighlightedSuggestion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_suggestionsScrollController.hasClients) {
        return;
      }

      final position = _suggestionsScrollController.position;
      final itemTop = _highlightedSuggestionIndex * _suggestionItemExtent;
      final itemBottom = itemTop + _suggestionItemExtent;
      double? targetOffset;

      if (itemTop < position.pixels) {
        targetOffset = itemTop;
      } else if (itemBottom > position.pixels + position.viewportDimension) {
        targetOffset = itemBottom - position.viewportDimension;
      }

      if (targetOffset == null) {
        return;
      }

      _suggestionsScrollController.animateTo(
        targetOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, List<Tag> suggestions) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlightedSuggestion(1, suggestions);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlightedSuggestion(-1, suggestions);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.tab) {
      if (suggestions.isEmpty) {
        return KeyEventResult.ignored;
      }

      _selectSuggestion(suggestions[_highlightedSuggestionIndex.clamp(0, suggestions.length - 1)]);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final List<Tag> suggestions = _focusNode.hasFocus && widget.maxSuggestionsHeight >= _suggestionItemExtent
        ? widget.suggestionsForToken(_currentSearchToken(_latestInputValue))
        : const <Tag>[];
    if (_highlightedSuggestionIndex >= suggestions.length) {
      _highlightedSuggestionIndex = suggestions.isEmpty ? 0 : suggestions.length - 1;
    }
    _focusNode.onKeyEvent = (node, event) => _handleKeyEvent(node, event, suggestions);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            labelText: widget.title,
            hintText: widget.hintText,
            prefixIcon: widget.actions == null ? const Icon(Icons.search) : null,
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?widget.actions,
                      IconButton(
                        key: const Key('selected-preview-search-clear'),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onPressed: () => _setText(''),
                      ),
                    ],
                  ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: suggestions.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: widget.maxSuggestionsHeight),
                      child: ListView.builder(
                        controller: _suggestionsScrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemExtent: _suggestionItemExtent,
                        itemCount: suggestions.length,
                        itemBuilder: (context, index) {
                          final option = suggestions[index];
                          final color = option.tagType.getColour();
                          final isHighlighted = index == _highlightedSuggestionIndex;

                          return MouseRegion(
                            onEnter: (_) => _highlightSuggestion(index),
                            child: TextFieldTapRegion(
                              child: ListTile(
                                onTap: () => _selectSuggestion(option),
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                selected: isHighlighted,
                                selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                                leading: Icon(
                                  Icons.sell_outlined,
                                  color:
                                      color ??
                                      (isHighlighted
                                          ? Theme.of(context).colorScheme.onPrimaryContainer
                                          : Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                title: Text(
                                  option.fullString,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        color ??
                                        (isHighlighted ? Theme.of(context).colorScheme.onPrimaryContainer : null),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

String _currentSearchToken(TextEditingValue value) {
  final text = value.text;
  if (text.isEmpty) {
    return '';
  }

  final cursor = value.selection.baseOffset < 0 ? text.length : value.selection.baseOffset.clamp(0, text.length);
  var start = cursor;
  while (start > 0 && !_isSelectedPreviewSearchSeparator(text.codeUnitAt(start - 1))) {
    start--;
  }

  var end = cursor;
  while (end < text.length && !_isSelectedPreviewSearchSeparator(text.codeUnitAt(end))) {
    end++;
  }

  return text.substring(start, end);
}

TextEditingValue _replaceCurrentSearchToken(TextEditingValue value, String replacement) {
  final text = value.text;
  final cursor = value.selection.baseOffset < 0 ? text.length : value.selection.baseOffset.clamp(0, text.length);
  var start = cursor;
  while (start > 0 && !_isSelectedPreviewSearchSeparator(text.codeUnitAt(start - 1))) {
    start--;
  }

  var end = cursor;
  while (end < text.length && !_isSelectedPreviewSearchSeparator(text.codeUnitAt(end))) {
    end++;
  }

  final currentToken = text.substring(start, end);
  final prefix = currentToken.startsWith('-') ? '-' : '';
  final replacementText = '$prefix$replacement';
  final nextText = text.replaceRange(start, end, replacementText);
  final nextOffset = start + replacementText.length;

  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
  );
}

bool _isSelectedPreviewSearchSeparator(int codeUnit) {
  return codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13 || codeUnit == 126;
}

class _PreviewConstrainedBottomSheet extends StatelessWidget {
  const _PreviewConstrainedBottomSheet({
    required this.child,
    this.onDismiss,
  });

  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxSheetWidth = width < 720 ? width : (width * 0.62).clamp(480.0, 680.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss ?? () => Navigator.of(context).pop(),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxSheetWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

double _selectedPreviewRowHeight(BuildContext context) =>
    96.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);

String _previewMetadata(BooruItem item) => [
  item.fileExt?.toUpperCase() ?? '',
  if (item.fileWidth != null && item.fileHeight != null) '${item.fileWidth!.round()} × ${item.fileHeight!.round()}',
  if (item.fileSize != null) Tools.formatBytes(item.fileSize!, 1),
].where((part) => part.isNotEmpty).join(' · ');

class _SelectionSheetTitle extends StatelessWidget {
  const _SelectionSheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}
