import 'package:lolisnatcher/src/widgets/drawers/downloads/hidden_items_page.dart';
import 'package:lolisnatcher/src/widgets/preview/waterfall_bottom_bar.dart';
import 'package:lolisnatcher/src/widgets/common/fading_edge_reorderable_listview.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;

import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fpdart/fpdart.dart' show FpdartOnIterable;
import 'package:get/get.dart' hide ContextExt, FirstWhereOrNullExt;
import 'package:intl/intl.dart';
import 'package:lolisnatcher/src/widgets/preview/page_indicator.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/boorus/danbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/downloads_handler.dart';
import 'package:lolisnatcher/src/boorus/favourites_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/meta_tag.dart';
import 'package:lolisnatcher/src/data/pinned_tag.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/data/tag_filter_query.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/pages/gallery_view_page.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/booru_rating.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/text_parser/rules/url_rule.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/utils/booru_source_resolver.dart';
import 'package:lolisnatcher/src/widgets/common/close_dialog_button.dart';
import 'package:lolisnatcher/src/widgets/common/draggable_overflow_text.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/kaomoji.dart';
import 'package:lolisnatcher/src/widgets/common/loli_dropdown.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/common/parsed_text.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/desktop/desktop_scroll.dart';
import 'package:lolisnatcher/src/widgets/dialogs/comments_dialog.dart';
import 'package:lolisnatcher/src/widgets/gallery/notes_renderer.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/preview/main_search_tag_chip.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_selector.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_details_sheet.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_editor.dart';
import 'package:lolisnatcher/src/widgets/tags_manager/tm_list_item_dialog.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_card_build.dart';

class _TagInfoIcon {
  _TagInfoIcon(this.icon, this.color, {this.onTap});

  final dynamic icon;
  final Color color;
  final VoidCallback? onTap;
}

class _MetadataTag {
  const _MetadataTag(this.query, {this.filterQuery, this.canSearch = true});

  final String query;
  final String? filterQuery;
  final bool canSearch;
}

Widget _buildTagInfoIcon(BuildContext context, _TagInfoIcon info) {
  final visual = switch (info.icon) {
    FaIconData _ => FaIcon(info.icon, color: info.color, size: 18),
    IconData _ => Icon(info.icon, color: info.color, size: 20),
    String _ => Text(
      info.icon,
      style: TextStyle(color: info.color, fontSize: 16, fontWeight: FontWeight.w600),
    ),
    _ => const SizedBox.shrink(),
  };
  final child = SizedBox(
    width: 28,
    height: 32,
    child: Center(child: visual),
  );
  if (info.onTap == null) return child;
  return Material(
    color: Colors.transparent,
    child: InkResponse(
      radius: 18,
      onTap: info.onTap,
      child: child,
    ),
  );
}

class TagView extends StatefulWidget {
  const TagView({
    required this.item,
    required this.handler,
    super.key,
  });

  final BooruItem item;
  final BooruHandler handler;

  @override
  State<TagView> createState() => _TagViewState();
}

class _TagViewState extends State<TagView> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;
  final TagHandler tagHandler = TagHandler.instance;

  ScrollController scrollController = ScrollController();

  late BooruItem item;
  late BooruHandler handler;
  BooruHandler? possibleBooruHandler;
  bool hasLoadItemSupport = false;
  bool canLoadItemOnStart = false;
  List<Tag> tags = [];
  List<Tag> filteredTags = [];
  final Map<String, HasTabWithTagResult> tabMatchesMap = {};
  bool? sortTags;
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final GlobalKey searchKey = GlobalKey(debugLabel: 'tagsSearchKey');

  CancelToken? cancelToken;
  bool loadingUpdate = false, failedUpdate = false;

  bool? detailsExpanded;

  Timer? sortTimer;

  @override
  void initState() {
    super.initState();

    item = widget.item;
    handler = widget.handler;
    hasLoadItemSupport = handler.hasLoadItemSupport;
    canLoadItemOnStart = handler.shouldUpdateIteminTagView;
    checkForPossibleBooruHandler();
    tags = [...Set.from(item.tagsList)];
    filteredTags = [...tags];
    WidgetsBinding.instance.addPostFrameCallback((_) => parseSortGroupTags());
    searchHandler.searchTextController.addListener(parseSortGroupTagsWithoutCache);
    searchFocusNode.addListener(searchFocusListener);
    TagFilterHandler.instance.revision.addListener(parseSortGroupTagsWithoutCache);

    reloadItemData(initial: true).then((_) async {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        parseSortGroupTagsWithoutCache();
        sortTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => parseSortGroupTagsWithoutCache(),
        );
      }
    });
  }

  void checkForPossibleBooruHandler() {
    possibleBooruHandler = null;

    Booru? getMergeBooruEntry() {
      if (handler is! MergebooruHandler) return null;

      final fetchedMap = (handler as MergebooruHandler).fetchedMap;
      for (int i = 0; i < fetchedMap.entries.length; i++) {
        final entry = fetchedMap.entries.elementAt(i);
        if (entry.value.items.contains(item)) {
          return entry.value.booru;
        }
      }
      return null;
    }

    final bool isMergeHandler = handler is MergebooruHandler;

    final bool isFavsOrDlsOrMerge = handler is FavouritesHandler || handler is DownloadsHandler || isMergeHandler;
    if (!isFavsOrDlsOrMerge) {
      return;
    }

    final Booru? possibleBooru = isMergeHandler ? getMergeBooruEntry() : BooruSourceResolver.resolve(item);

    if (possibleBooru != null && (isMergeHandler || possibleBooru.type?.isFavouritesOrDownloads != true)) {
      possibleBooruHandler = BooruHandlerFactory().getBooruHandler([possibleBooru], null).booruHandler;
      hasLoadItemSupport = possibleBooruHandler!.hasLoadItemSupport;
      canLoadItemOnStart = possibleBooruHandler!.shouldUpdateIteminTagView;
    }
  }

  @override
  void didUpdateWidget(covariant TagView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != item) {
      item = widget.item;
      checkForPossibleBooruHandler();
      tags = [...Set.from(item.tagsList)];
      filteredTags = [...tags];

      // debounce to avoid getting rate limited due to going too fast by using buttons on left side of tag view
      Debounce.debounce(
        tag: 'tag_view_reload_item',
        callback: () {
          WidgetsBinding.instance.addPostFrameCallback((_) => parseSortGroupTags());
          cancelToken?.cancel();
          reloadItemData(initial: true).then((_) async {
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
              parseSortGroupTagsWithoutCache();
              sortTimer?.cancel();
              sortTimer = Timer.periodic(
                const Duration(seconds: 5),
                (_) => parseSortGroupTagsWithoutCache(),
              );
            }
          });
        },
      );
    }

    if (widget.handler != handler) {
      handler = widget.handler;
      hasLoadItemSupport = handler.hasLoadItemSupport;
      canLoadItemOnStart = handler.shouldUpdateIteminTagView;
      checkForPossibleBooruHandler();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    cancelToken?.cancel();
    sortTimer?.cancel();
    searchHandler.searchTextController.removeListener(parseSortGroupTagsWithoutCache);
    searchController.dispose();
    searchFocusNode.removeListener(searchFocusListener);
    TagFilterHandler.instance.revision.removeListener(parseSortGroupTagsWithoutCache);
    searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> reloadItemData({
    bool initial = false,
    bool force = false,
  }) async {
    if (loadingUpdate) return;

    if (hasLoadItemSupport && (!initial || canLoadItemOnStart) && (!item.isUpdated || force)) {
      loadingUpdate = true;
      failedUpdate = false;
      if (mounted) setState(() {});
      cancelToken = CancelToken();
      final owningHandler = handler;
      final loadingItem = item;
      try {
        final refreshHandler = possibleBooruHandler ?? handler;
        final res = await refreshHandler.loadItem(
          item: item,
          cancelToken: cancelToken,
          withCapcthaCheck: !initial,
        );
        if (!res.failed &&
            res.item != null &&
            refreshHandler.booru.type?.isFavouritesOrDownloads != true &&
            refreshHandler.booru.type?.isMerge != true) {
          res.item!.sourceIdentity = BooruIdentity.fromBooru(refreshHandler.booru);
        }
        if (res.failed) {
          failedUpdate = true;
        } else if (res.item != null && (res.item?.isSnatched.value == true || res.item?.isFavourite.value == true)) {
          unawaited(
            SettingsHandler.instance.dbHandler.updateBooruItem(
              res.item!,
              BooruUpdateMode.urlUpdate,
            ),
          );
        }

        if (!res.failed) {
          owningHandler.filterFetched(forceRefresh: true);
          if (mounted && identical(item, loadingItem)) await getUploaderName();
        }
      } catch (e) {
        failedUpdate = true;
      }
      loadingUpdate = false;
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          if (mounted) parseSortGroupTags();
        },
      );
    }
  }

  Future<void> getUploaderName() async {
    final loadingItem = item;
    final owningHandler = handler;
    final usedHandler = possibleBooruHandler ?? handler;
    if (usedHandler is DanbooruHandler && loadingItem.uploaderId?.isNotEmpty == true) {
      loadingItem.uploaderName = await usedHandler.getUploaderName(loadingItem);
      owningHandler.filterFetched(forceRefresh: true);
    }
  }

  List<Tag> filterTags(List<Tag> tagsToFilter) {
    final List<Tag> tags = [];
    if (searchController.text.isEmpty) {
      return tagsToFilter;
    }

    for (int i = 0; i < tagsToFilter.length; i++) {
      if (tagsToFilter[i].fullString.toLowerCase().contains(searchController.text.toLowerCase())) {
        tags.add(tagsToFilter[i]);
      }
    }
    return tags;
  }

  void sortAndGroupTagsList() {
    if (sortTags == null) {
      tags = [...Set.from(item.tagsList)];
      groupTagsList();
    } else {
      tags.sort(
        (a, b) => sortTags == true ? a.fullString.compareTo(b.fullString) : b.fullString.compareTo(a.fullString),
      );
      filteredTags = [
        ...filterTags([...tags]),
      ];
    }
  }

  void groupTagsList() {
    final Map<TagType, List<Tag>> tagMap = {};
    final List<Tag> groupedTags = [];
    for (int i = 0; i < TagType.values.length; i++) {
      tagMap[TagType.values[i]] = [];
    }

    for (int i = 0; i < tags.length; i++) {
      if (tagHandler.hasTag(tags[i].fullString)) {
        tagMap[tagHandler.getTag(tags[i].fullString).tagType]?.add(tags[i]);
      } else {
        tagMap[TagType.none]?.add(tags[i]);
      }
    }
    // tagMap.forEach((key, value) => {
    //   print("Type: $key Tags: $value")
    // });
    for (final value in tagMap.values) {
      groupedTags.addAll(value);
    }
    tags = groupedTags;
    filteredTags = [
      ...filterTags([...tags]),
    ];
  }

  Future<void> cacheTabMatchData() async {
    final currentBooru = searchHandler.currentBooruOrNull;
    final Set<String> onlyTagCurrentBooru = {};
    final Set<String> onlyTagOtherBooru = {};
    final Set<String> containsTag = {};

    for (final tab in searchHandler.tabs) {
      final parts = tab.tags.toLowerCase().trim().split(' ');
      final isCurrentBooru = tab.selectedBooru.value.matchesIdentity(currentBooru);

      if (parts.length == 1 && parts[0].isNotEmpty) {
        if (isCurrentBooru) {
          onlyTagCurrentBooru.add(parts[0]);
        } else {
          onlyTagOtherBooru.add(parts[0]);
        }
      }
      for (final part in parts) {
        if (part.isNotEmpty) containsTag.add(part);
      }
    }

    for (final tag in filteredTags) {
      final normalized = tag.fullString.toLowerCase().trim();
      if (onlyTagCurrentBooru.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.onlyTag;
      } else if (onlyTagOtherBooru.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.onlyTagDifferentBooru;
      } else if (containsTag.contains(normalized)) {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.containsTag;
      } else {
        tabMatchesMap[tag.fullString] = HasTabWithTagResult.noTag;
      }
    }
  }

  void parseSortGroupTagsWithoutCache() {
    parseSortGroupTags(updateCache: false);
  }

  Future<void> parseSortGroupTags({
    bool updateCache = true,
  }) async {
    sortAndGroupTagsList();
    if (updateCache) {
      await cacheTabMatchData();
    }
    if (mounted) setState(() {});
  }

  void searchFocusListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (searchFocusNode.hasFocus) {
        // doesn't scroll to a proper position in some cases
        // probably because scroll extent changes due to elements being lazily rendered
        await Scrollable.ensureVisible(
          searchKey.currentContext!,
          alignment: (72 + context.viewInsets.top) / context.height,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  Widget tagsButton() {
    final filterEvaluation = handler.filterEvaluationFor(item);
    return SettingsButton(
      name: context.loc.tagView.tags,
      subtitle: Text(searchController.text.isEmpty ? '${tags.length}' : '${filteredTags.length} / ${tags.length}'),
      trailingIcon: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth - 72),
            margin: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLoadItemSupport) ...[
                  if (possibleBooruHandler != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BooruFavicon(
                              possibleBooruHandler?.booru,
                              size: 20,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              possibleBooruHandler?.booru.name ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  //
                  if (loadingUpdate)
                    IconButton(
                      onPressed: () {
                        cancelToken?.cancel();
                      },
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                            ),
                          ),
                          Icon(
                            Icons.close,
                            color: Theme.of(context).iconTheme.color,
                            size: 24,
                          ),
                        ],
                      ),
                    )
                  else
                    IconButton(
                      onPressed: () => reloadItemData(force: true),
                      icon: Icon(
                        failedUpdate ? Icons.error_outline : Icons.refresh,
                        color: failedUpdate ? Colors.red : Theme.of(context).iconTheme.color,
                        size: 28,
                      ),
                    ),
                ],
                if (filterEvaluation.matches.isNotEmpty)
                  IconButton(
                    tooltip: context.loc.settings.itemFilters.tapForDetails,
                    onPressed: () => showTagFilterDetailsSheet(context, filterEvaluation),
                    icon: Badge(
                      label: Text('${filterEvaluation.matches.length}'),
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                  ),
                //
                Transform(
                  alignment: Alignment.center,
                  transform: sortTags == true ? Matrix4.rotationX(pi) : Matrix4.rotationX(0),
                  child: IconButton(
                    icon: Icon(
                      (sortTags == true || sortTags == false) ? Icons.sort : Icons.sort_by_alpha,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onPressed: () {
                      if (sortTags == true) {
                        sortTags = false;
                      } else if (sortTags == false) {
                        sortTags = null;
                      } else {
                        sortTags = true;
                      }
                      sortAndGroupTagsList();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      drawBottomBorder: false,
    );
  }

  Widget commentsButton() {
    final bool hasSupport = (possibleBooruHandler ?? handler).hasCommentsSupport;
    final bool hasComments = item.hasComments == true;
    final IconData icon = hasComments ? CupertinoIcons.text_bubble_fill : CupertinoIcons.text_bubble;

    if (!hasSupport || item.fileURL.isEmpty) {
      return const SizedBox.shrink();
    }

    return SettingsButton(
      name: context.loc.tagView.comments,
      icon: Icon(
        icon,
        color: Theme.of(context).iconTheme.color,
      ),
      action: () {
        SettingsPageOpen(
          context: context,
          page: (_) => CommentsDialog(
            item: item,
            handler: possibleBooruHandler ?? handler,
          ),
        ).open();
      },
      drawBottomBorder: false,
    );
  }

  Widget notesButton() {
    final bool hasSupport = (possibleBooruHandler ?? handler).hasNotesSupport;
    final bool hasNotes = item.hasNotes == true;

    if (!hasSupport || !hasNotes) {
      return const SizedBox.shrink();
    }

    return Obx(() {
      if (item.notes.isNotEmpty) {
        return SettingsButton(
          name: viewerHandler.showNotes.value
              ? context.loc.tagView.hideNotes(count: item.notes.length)
              : context.loc.tagView.showNotes(count: item.notes.length),
          icon: Icon(
            Icons.note_add,
            color: Theme.of(context).iconTheme.color,
          ),
          action: viewerHandler.showNotes.toggle,
          onLongPress: () {
            showDialog(
              context: context,
              builder: (_) => NotesDialog(item),
            );
          },
          drawBottomBorder: false,
        );
      } else {
        return SettingsButton(
          name: context.loc.tagView.loadNotes,
          icon: Icon(
            Icons.note_add,
            color: Theme.of(context).iconTheme.color,
          ),
          action: () async {
            if (item.serverId == null) return;
            item.notes.value = await (possibleBooruHandler ?? handler).getNotes(item.serverId!);
          },
          drawBottomBorder: false,
        );
      }
    });
  }

  Widget sourcesList(List<String> sources) {
    sources = sources.where((l) => l.trim().isNotEmpty).toList();

    if (sources.isNotEmpty) {
      return Column(
        children: [
          Divider(
            color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
          ),
          infoText(context.loc.gallery.sources(count: sources.length), ' ', canCopy: false),
          Column(
            children: sources
                .map(
                  (link) => ListTile(
                    onLongPress: () async {
                      await ServiceHandler.vibrate();
                      await showDialog(
                        context: context,
                        builder: (_) => SourceLinkErrorDialog(link: link),
                      );
                    },
                    onTap: () async {
                      final detectedUrl = UrlParseRule.detectPureUrl(link);
                      if (detectedUrl != null) {
                        if (await canLaunchUrlString(detectedUrl)) {
                          await launchUrlString(
                            detectedUrl,
                            mode: LaunchMode.externalApplication,
                          );
                          return;
                        }
                        // Pure URL but failed to launch — show dialog with error context
                        if (mounted) {
                          await showDialog(
                            context: context,
                            builder: (_) => SourceLinkErrorDialog(link: link),
                          );
                        }
                        return;
                      }

                      // Mixed content or no URL — show dialog without error header
                      if (mounted) {
                        await showDialog(
                          context: context,
                          builder: (_) => SourceLinkErrorDialog(link: link),
                        );
                      }
                    },
                    title: DraggableOverflowText(link),
                  ),
                )
                .toList(),
          ),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  _MetadataTag? metadataTag(List<String> keys, String? value, {String? filterQuery}) {
    if (value == null || value.isEmpty) return null;
    final sourceHandler = possibleBooruHandler ?? handler;
    final metaTag = sourceHandler.availableMetaTags().firstWhereOrNull((meta) => keys.contains(meta.keyName));
    if (metaTag == null) {
      return filterQuery == null ? null : _MetadataTag(filterQuery, filterQuery: filterQuery, canSearch: false);
    }
    if (metaTag is MetaTagWithValues) {
      final matchingValue = metaTag.values.firstWhereOrNull(
        (candidate) => candidate.value.toLowerCase() == value!.toLowerCase(),
      );
      // Older three-rating sources call general content "safe".
      final safeValue = value == 'general'
          ? metaTag.values.firstWhereOrNull((candidate) => candidate.value == 'safe')
          : null;
      if (matchingValue == null && safeValue == null) {
        return filterQuery == null ? null : _MetadataTag(filterQuery, filterQuery: filterQuery, canSearch: false);
      }
      value = (matchingValue ?? safeValue)!.value;
    }
    return _MetadataTag(metaTag.tagBuilder(null, null, value), filterQuery: filterQuery);
  }

  Widget infoText(
    String title,
    String data, {
    bool canCopy = true,
    bool isLink = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
    _MetadataTag? metadata,
  }) {
    if (data.isNotEmpty) {
      void openMetadataDialog() {
        if (metadata == null) return;
        final sourceHandler = possibleBooruHandler ?? handler;
        final query = metadata.query;
        showTagDialog(
          context: context,
          tag: query,
          handler: sourceHandler,
          isInSearch: query
              .split(' ')
              .every(
                (part) => searchHandler.searchTextControllerTags.any(
                  (tag) => tag == part || tag == '-$part' || tag == '~$part',
                ),
              ),
          hasTabWithTag: searchHandler.hasTabWithTag(query, customBooru: sourceHandler.booru),
          evaluation: handler.filterEvaluationFor(item),
          onUpdate: parseSortGroupTagsWithoutCache,
          isMetaTag: true,
          filterQuery: metadata.filterQuery,
          canSearch: metadata.canSearch,
        );
      }

      return GestureDetector(
        onSecondaryTap: metadata == null ? null : openMetadataDialog,
        child: ListTile(
          onTap:
              (metadata == null ? null : openMetadataDialog) ??
              onTap ??
              (canCopy
                  ? () => ClipboardUtils.copyTextToClipboard(
                      data,
                      subtitle: '$title: $data',
                    )
                  : null),
          onLongPress: metadata == null ? onLongPress : openMetadataDialog,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$title: ',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!isLink)
                Expanded(
                  child: AutoSizeText(
                    data,
                    maxLines: 1,
                    minFontSize: 13,
                    maxFontSize: 14,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1,
                    ),
                    overflowReplacement: DraggableOverflowText(
                      data,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          subtitle: isLink
              ? DraggableOverflowText(
                  data,
                  style: const TextStyle(fontSize: 14),
                )
              : null,
          trailing:
              trailing ??
              (isLink
                  ? IconButton(
                      icon: const Icon(Icons.exit_to_app),
                      onPressed: () => launchUrlString(
                        data,
                        mode: LaunchMode.externalApplication,
                      ),
                    )
                  : null),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget tagsItemBuilder(BuildContext context, Tag tag) {
    final String currentTag = tag.fullString;
    final int tagCount = tag.count;

    final evaluation = handler.filterEvaluationFor(item);
    final currentTagLower = currentTag.toLowerCase();
    final filterMatches = evaluation.matches.where((match) => match.matchedTags.contains(currentTagLower)).toList();
    final bool isSound = SettingsHandler.soundTags.contains(currentTag);
    final bool isAi = SettingsHandler.aiTags.contains(currentTag);
    final bool isInSearch =
        searchHandler.searchTextController.text
            .toLowerCase()
            .split(' ')
            .indexWhere(
              (t) =>
                  t == currentTag.toLowerCase() ||
                  t == '-${currentTag.toLowerCase()}' ||
                  t == '~${currentTag.toLowerCase()}' ||
                  RegExp(r'^(?:-|~)?\d+#(?:-|~)?' + currentTag.regexpEscape() + r'$').hasMatch(t),
            ) !=
        -1;
    final HasTabWithTagResult hasTabWithTag = tabMatchesMap.containsKey(currentTag)
        ? tabMatchesMap[currentTag]!
        : HasTabWithTagResult.noTag;

    final List<_TagInfoIcon> tagIconAndColor = [];
    if (isAi) {
      tagIconAndColor.add(_TagInfoIcon(FontAwesomeIcons.robot, Theme.of(context).colorScheme.onSurface));
    }
    if (isSound) {
      tagIconAndColor.add(_TagInfoIcon(Icons.volume_up_rounded, Theme.of(context).colorScheme.onSurface));
    }
    final displayedEffects = <TagFilterEffect>{};
    final displayedMarkers = <String>{};
    for (final match in filterMatches) {
      switch (match.rule.effect) {
        case TagFilterEffect.hide:
          if (!displayedEffects.add(TagFilterEffect.hide)) continue;
          tagIconAndColor.add(_TagInfoIcon(CupertinoIcons.eye_slash, Colors.red));
        case TagFilterEffect.blur:
          if (!displayedEffects.add(TagFilterEffect.blur)) continue;
          tagIconAndColor.add(_TagInfoIcon(Icons.blur_on, Colors.orange));
        case TagFilterEffect.mark:
          final marker = match.rule.marker;
          final markerKey = TagFilterMarker.stableKeyFor(marker);
          if (!displayedMarkers.add(markerKey)) continue;
          final markerMatches = filterMatches
              .where(
                (candidate) =>
                    candidate.rule.effect == TagFilterEffect.mark &&
                    TagFilterMarker.stableKeyFor(candidate.rule.marker) == markerKey,
              )
              .toList(growable: false);
          tagIconAndColor.add(
            _TagInfoIcon(
              marker == null
                  ? Icons.star
                  : marker.kind == TagFilterMarkerKind.icon
                  ? marker.icon!.glyph
                  : marker.text!,
              marker == null ? TagFilterMarkerColor.grey.color : marker.effectiveColor,
              onTap: () => showTagFilterMatchesSheet(
                context,
                markerMatches,
                title: context.loc.settings.itemFilters.relatedFilters,
              ),
            ),
          );
      }
    }

    if (currentTag != '') {
      final tag = tagHandler.getTag(currentTag);

      return ColoredBox(
        key: ValueKey('tag-$currentTag'),
        color: tag.getColour() == null
            ? Colors.transparent
            : Color.lerp(
                context.isLight ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                tag.getColour()?.withValues(alpha: 0.1),
                0.4,
              )!,
        child: Column(
          children: [
            InkWell(
              onTap: () {
                showTagDialog(
                  context: context,
                  tag: currentTag,
                  handler: handler,
                  isInSearch: isInSearch,
                  hasTabWithTag: hasTabWithTag,
                  evaluation: evaluation,
                  onUpdate: parseSortGroupTagsWithoutCache,
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TagText(
                            key: ValueKey(currentTag),
                            tag: tag,
                            filterText: searchController.text,
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.centerLeft,
                            child: tagCount <= 0
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      tagCount.toFormattedString(),
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (tagIconAndColor.isNotEmpty) ...[
                    ...tagIconAndColor.map((info) => _buildTagInfoIcon(context, info)),
                    const SizedBox(width: 5),
                  ],
                  IconButton(
                    icon: Stack(
                      children: [
                        Icon(Icons.add, color: Theme.of(context).colorScheme.secondary),
                        if (isInSearch)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.search,
                              size: 10,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      if (isInSearch) {
                        FlashElements.showSnackbar(
                          context: context,
                          duration: const Duration(seconds: 2),
                          title: Text(
                            context.loc.tagView.thisTagAlreadyInSearch,
                            style: const TextStyle(fontSize: 18),
                          ),
                          content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                          leadingIcon: Icons.warning_amber,
                          leadingIconColor: Colors.yellow,
                          sideColor: Colors.yellow,
                        );
                        return;
                      }

                      searchHandler.addTagToSearch(currentTag);
                      FlashElements.showSnackbar(
                        context: context,
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tagView.addedToCurrentSearch, style: const TextStyle(fontSize: 20)),
                        content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                        leadingIcon: Icons.add,
                        sideColor: Colors.green,
                      );
                    },
                  ),
                  IconButton(
                    icon: Stack(
                      children: [
                        Icon(Icons.fiber_new, color: Theme.of(context).colorScheme.secondary),
                        if (hasTabWithTag.hasTagInAnyForm)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: hasTabWithTag.color(context),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      searchHandler.addTabByString(currentTag);

                      parseSortGroupTags();

                      FlashElements.showSnackbar(
                        context: context,
                        isKeyUnique: true,
                        key: 'added_new_tab',
                        duration: const Duration(seconds: 2),
                        title: Text(context.loc.tagView.addedNewTab, style: const TextStyle(fontSize: 20)),
                        content: Text(currentTag, style: const TextStyle(fontSize: 16)),
                        leadingIcon: Icons.fiber_new,
                        sideColor: Colors.green,
                        primaryActionBuilder: (context, controller) {
                          return Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  ServiceHandler.vibrate();
                                  if (SX.appMode.value.isMobile) {
                                    Navigator.of(context).popUntil((route) => route.isFirst); // exit viewer
                                  }
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    searchHandler.changeTabIndex(searchHandler.tabs.length - 1);
                                  });
                                  controller.dismiss();
                                },
                                icon: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => controller.dismiss(),
                                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    onLongPress: () async {
                      await ServiceHandler.vibrate();
                      if (SX.appMode.value.isMobile) {
                        Navigator.of(context).popUntil((route) => route.isFirst); // exit viewer
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        searchHandler.addTabByString(currentTag, switchToNew: true);
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            Divider(
              color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
            ),
          ],
        ),
      );
    } else {
      // Render nothing if currentTag is an empty string
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = Tools.getFileName(item.fileURL);
    final String fileExt = Tools.getFileExt(item.fileURL);
    final String fileUrl = item.fileURL;
    final String fileRes = (item.fileWidth != null && item.fileHeight != null)
        ? '${item.fileWidth?.toInt() ?? ''}x${item.fileHeight?.toInt() ?? ''}'
        : '';
    final String fileSize = item.fileSize != null ? Tools.formatBytes(item.fileSize!, 2) : '';
    final String itemId = item.serverId ?? '';
    final String rating = item.rating ?? '';
    final String score = item.score ?? '';
    final String md5 = item.md5String ?? '';
    final sourceHandler = possibleBooruHandler ?? handler;
    final normalizedRating = normalizeBooruRating(item.rating, booru: sourceHandler.booru);
    final ratingQuery = const {'safe', 'general', 'sensitive', 'questionable', 'explicit'}.contains(normalizedRating)
        ? 'rating:$normalizedRating'
        : null;
    final List<String> sources = item.sources ?? [];
    final bool tagsAvailable = tags.isNotEmpty || hasLoadItemSupport;
    String postDate = item.postDate ?? '';
    final String postDateFormat = item.postDateFormat ?? '';
    String formattedDate = '';
    if (postDate.isNotEmpty && postDateFormat.isNotEmpty) {
      try {
        // no timezone support in DateFormat? see: https://stackoverflow.com/questions/56189407/dart-parse-date-timezone-gives-unimplementederror/56190055
        // remove timezones from strings until they fix it
        DateTime parsedDate;
        if (postDateFormat == 'unix') {
          parsedDate = DateTime.fromMillisecondsSinceEpoch(int.parse(postDate) * 1000);
        } else if (postDateFormat == 'iso') {
          postDate = postDate.replaceAll(RegExp(r'(?:\+|\-)\d{4}'), '');
          parsedDate = DateTime.parse(postDate).toLocal();
        } else {
          postDate = postDate.replaceAll(RegExp(r'(?:\+|\-)\d{4}'), '');
          parsedDate = DateFormat(postDateFormat).parseLoose(postDate).toLocal();
        }
        // print(postDate);
        formattedDate = DateFormat('dd.MM.yyyy HH:mm').format(parsedDate);
      } catch (e) {
        print('Date Parse Error :: $postDate $postDateFormat :: $e');
      }
    }

    return Scrollbar(
      interactive: true,
      controller: scrollController,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              [
                const SizedBox(height: kMinInteractiveDimension),
                infoText(context.loc.tagView.id, itemId),
                infoText(context.loc.tagView.postURL, item.postURL, isLink: true),
                //
                if (item.uploaderId?.isNotEmpty == true || item.uploaderName?.isNotEmpty == true)
                  Builder(
                    builder: (context) {
                      final bool hasUploaderName = item.uploaderName?.trim().isNotEmpty == true;
                      final String text = hasUploaderName ? item.uploaderName! : item.uploaderId ?? '';
                      final userMetaTag = sourceHandler.availableMetaTags().firstWhereOrNull(
                        (meta) => meta is UserMetaTag,
                      );
                      final userQuery = 'user:${TagFilterQuery.escapeExactTag(item.uploaderName?.trim() ?? '')}';

                      return infoText(
                        context.loc.tagView.uploader,
                        text,
                        metadata: hasUploaderName
                            ? _MetadataTag(
                                userMetaTag?.tagBuilder(null, null, item.uploaderName) ?? userQuery,
                                filterQuery: userQuery,
                                canSearch: userMetaTag != null,
                              )
                            : null,
                      );
                    },
                  ),
                //
                infoText(context.loc.tagView.posted, formattedDate, canCopy: false),
                //
                ExpansionTile(
                  title: Text(
                    context.loc.tagView.details,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  initiallyExpanded: detailsExpanded ?? SX.expandDetails.value,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      detailsExpanded = expanded;
                    });
                  },
                  iconColor: Colors.white.withValues(alpha: 0.66),
                  collapsedIconColor: Colors.white.withValues(alpha: 0.66),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [
                    if (SX.isDebug.value) infoText(context.loc.tagView.filename, fileName),
                    infoText(context.loc.tagView.url, fileUrl, isLink: true),
                    infoText(context.loc.tagView.extension, fileExt),
                    infoText(context.loc.tagView.resolution, fileRes),
                    infoText(context.loc.tagView.size, fileSize),
                    infoText(context.loc.tagView.md5, md5),
                    infoText(
                      context.loc.tagView.rating,
                      rating,
                      metadata: metadataTag(['rating'], normalizedRating, filterQuery: ratingQuery),
                    ),
                    infoText(context.loc.tagView.score, score),
                  ],
                ),
                commentsButton(),
                notesButton(),
                sourcesList(sources),
                if (tagsAvailable) ...[
                  Divider(
                    color: context.theme.dividerTheme.color?.withValues(alpha: 0.66),
                  ),
                  tagsButton(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                          filled: false,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: context.theme.dividerTheme.color!.withValues(alpha: 0.66),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: context.theme.dividerTheme.color!.withValues(alpha: 0.66),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      child: SettingsTextInput(
                        key: searchKey,
                        controller: searchController,
                        focusNode: searchFocusNode,
                        title: context.loc.search,
                        titleAsLabel: true,
                        onlyInput: true,
                        clearable: true,
                        pasteable: true,
                        onChanged: (_) {
                          parseSortGroupTagsWithoutCache();
                        },
                        enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: (filteredTags.isEmpty && tags.isNotEmpty)
                ? Column(
                    children: [
                      const Kaomoji(
                        category: KaomojiCategory.indifference,
                        style: TextStyle(fontSize: 36),
                      ),
                      Text(
                        context.loc.tagView.noTagsFound,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 60),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (c, i) => tagsItemBuilder(c, filteredTags[i]),
              childCount: filteredTags.length,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom + kMinInteractiveDimension,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagText extends StatelessWidget {
  const _TagText({
    required this.tag,
    this.filterText,
    super.key,
  });

  final Tag tag;
  final String? filterText;

  @override
  Widget build(BuildContext context) {
    final Color color = tag.getColour() ?? Theme.of(context).colorScheme.onSurface;
    final basicStyle = TextStyle(
      color: color,
      fontSize: 14,
      fontWeight: filterText?.isNotEmpty == true ? FontWeight.w400 : FontWeight.w600,
    );
    final fullStyle = basicStyle.copyWith(
      color: color,
    );

    if (filterText?.isNotEmpty == true) {
      final List<TextSpan> spans = [];
      final List<String> split = tag.fullString.split(filterText!);

      for (int i = 0; i < split.length; i++) {
        spans.add(
          TextSpan(
            text: split[i],
            style: basicStyle,
          ),
        );
        if (i < split.length - 1) {
          spans.add(
            TextSpan(
              text: filterText,
              style: fullStyle.copyWith(
                backgroundColor: color.withValues(alpha: 0.1),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
      }

      return MarqueeText.rich(
        textSpan: TextSpan(
          children: spans,
          style: basicStyle,
        ),
        isExpanded: false,
        style: basicStyle,
      );
    } else {
      return MarqueeText(
        text: tag.fullString,
        isExpanded: false,
        style: fullStyle,
      );
    }
  }
}

Future<void> showTagDialog({
  required BuildContext context,
  required String tag,
  required BooruHandler handler,
  required bool isInSearch,
  required HasTabWithTagResult hasTabWithTag,
  required VoidCallback onUpdate,
  TagFilterEvaluation evaluation = const TagFilterEvaluation.empty(),
  bool isMetaTag = false,
  String? filterQuery,
  bool canSearch = true,
}) async {
  final parentContext = context;
  final settingsHandler = SettingsHandler.instance;
  final searchHandler = SearchHandler.instance;
  final tagHandler = TagHandler.instance;
  final metadataConditions = filterQuery == null
      ? const <TagFilterCondition>[]
      : TagFilterQuery.parse(filterQuery).query?.conditions ?? const <TagFilterCondition>[];
  final relatedFilterMatches = evaluation.matches
      .where((match) {
        if (!isMetaTag) return match.matchedTags.contains(tag.toLowerCase());
        final conditions = TagFilterQuery.parse(match.rule.query).query?.conditions ?? const [];
        return conditions.any(
          (condition) =>
              (filterQuery?.startsWith('rating:') == true && condition is RatingCondition) ||
              (filterQuery?.startsWith('score:') == true && condition is ScoreCondition) ||
              (metadataConditions.any((candidate) => candidate is UserCondition) && condition is UserCondition),
        );
      })
      .toList(growable: false);

  Future<void> openRuleEditor(BuildContext dialogContext, TagFilterEffect effect) async {
    Navigator.of(dialogContext).pop();
    await Future<void>.delayed(Duration.zero);
    if (!parentContext.mounted) return;
    await showTagFilterEditorSheet(
      parentContext,
      draft: isMetaTag
          ? TagFilterDraft(name: '', query: filterQuery!, effect: effect)
          : TagFilterDraft.exactTag(tag, effect),
    );
  }

  final controller = ScrollController();

  await showDialog(
    context: context,
    routeSettings: RouteSettings(name: 'tagDialog/$tag'),
    builder: (BuildContext context) {
      return SettingsDialog(
        contentPadding: EdgeInsets.zero,
        scrollable: false,
        content: Column(
          mainAxisSize: .min,
          children: [
            Container(
              height: 50,
              width: MediaQuery.sizeOf(context).width,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                title: MarqueeText(
                  key: ValueKey(tag),
                  text: tag,
                  style: TextStyle(
                    color:
                        (isMetaTag ? null : tagHandler.getTag(tag).getColour()) ??
                        Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  isExpanded: false,
                ),
              ),
            ),
            if (!isMetaTag)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Builder(
                  builder: (_) {
                    final t = tagHandler.getTag(tag);

                    return Row(
                      children: [
                        if (!t.tagType.isNone)
                          Container(
                            width: 6,
                            height: 24,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: t.getColour(),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        Text(
                          t.tagType.locName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            //
            Flexible(
              child: Scrollbar(
                controller: controller,
                thumbVisibility: false,
                interactive: true,
                child: FadingEdgeScrollView.from(
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ListBody(
                      children: [
                        if (canSearch)
                          TagContentPreview(
                            tag: tag,
                            boorus: handler.booru.type?.isMerge == true
                                ? [
                                    ...(handler as MergebooruHandler).booruHandlers.map((e) => e.booru),
                                  ]
                                : [handler.booru],
                            parentTab: searchHandler.currentTabOrNull,
                          ),
                        //
                        ListTile(
                          leading: Icon(
                            Icons.copy,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(context.loc.tagView.copy),
                          onTap: () {
                            ClipboardUtils.copyTextToClipboard(tag);

                            Navigator.of(context).pop();
                          },
                        ),
                        //
                        if (canSearch && isInSearch)
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            title: Text(context.loc.tagView.removeFromSearch),
                            onTap: () {
                              for (final part in isMetaTag ? tag.split(' ') : [tag]) {
                                searchHandler.removeTagFromSearch(part);
                              }
                              Navigator.of(context).pop();
                            },
                          )
                        else if (canSearch) ...[
                          ListTile(
                            leading: const Icon(Icons.add, color: Colors.green),
                            title: Text(context.loc.tagView.addToSearch),
                            onTap: () {
                              searchHandler.addTagToSearch(tag);

                              FlashElements.showSnackbar(
                                context: context,
                                duration: const Duration(seconds: 2),
                                title: Text(
                                  context.loc.tagView.addedToSearchBar,
                                  style: const TextStyle(fontSize: 20),
                                ),
                                content: Text(
                                  tag,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                leadingIcon: Icons.add,
                                sideColor: Colors.green,
                              );

                              Navigator.of(context).pop();
                            },
                          ),
                          if (!isMetaTag || !tag.contains(' '))
                            ListTile(
                              leading: const Icon(Icons.remove_rounded, color: Colors.red),
                              title: Text(context.loc.tagView.excludeFromSearch),
                              onTap: () {
                                searchHandler.addTagToSearch('-$tag');

                                FlashElements.showSnackbar(
                                  context: context,
                                  duration: const Duration(seconds: 2),
                                  title: Text(
                                    context.loc.tagView.exclusionAddedToSearchBar,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  content: Text(
                                    tag,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  leadingIcon: Icons.add,
                                  sideColor: Colors.green,
                                );

                                Navigator.of(context).pop();
                              },
                            ),
                        ],
                        //
                        if (relatedFilterMatches.isNotEmpty)
                          ListTile(
                            leading: Badge(
                              label: Text('${relatedFilterMatches.length}'),
                              child: const Icon(Icons.filter_alt_outlined),
                            ),
                            title: Text(context.loc.settings.itemFilters.relatedFilters),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showTagFilterMatchesSheet(
                              context,
                              relatedFilterMatches,
                              title: context.loc.settings.itemFilters.relatedFilters,
                            ),
                          ),
                        if (!isMetaTag || filterQuery != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(child: Icon(Icons.filter_alt_outlined)),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          context.loc.settings.itemFilters.addRule,
                                          style: Theme.of(context).textTheme.bodyLarge,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          ActionChip(
                                            onPressed: () => openRuleEditor(context, TagFilterEffect.mark),
                                            avatar: Icon(
                                              Icons.star_outline,
                                              size: 18,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            label: Text(context.loc.settings.itemFilters.mark),
                                          ),
                                          ActionChip(
                                            onPressed: () => openRuleEditor(context, TagFilterEffect.blur),
                                            avatar: Icon(
                                              Icons.blur_on,
                                              size: 18,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            label: Text(context.loc.settings.itemFilters.blur),
                                          ),
                                          ActionChip(
                                            onPressed: () => openRuleEditor(context, TagFilterEffect.hide),
                                            avatar: Icon(
                                              Icons.visibility_off_outlined,
                                              size: 18,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            label: Text(context.loc.settings.itemFilters.hide),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        //
                        FutureBuilder<PinnedTag?>(
                          future: settingsHandler.dbHandler.getPinnedTag(
                            tag,
                            booruType: (isMetaTag ? handler.booru : searchHandler.currentBooruOrNull)?.type?.name,
                            booruName: (isMetaTag ? handler.booru : searchHandler.currentBooruOrNull)?.name,
                          ),
                          builder: (_, snapshot) {
                            final isPinned = snapshot.data != null;
                            final pinnedTag = snapshot.data;

                            void reopenDialog() {
                              Navigator.of(context).pop();
                              showTagDialog(
                                context: parentContext,
                                tag: tag,
                                handler: handler,
                                isInSearch: isInSearch,
                                hasTabWithTag: hasTabWithTag,
                                evaluation: evaluation,
                                isMetaTag: isMetaTag,
                                filterQuery: filterQuery,
                                canSearch: canSearch,
                                onUpdate: onUpdate,
                              );
                            }

                            return ListTile(
                              title: Text(isPinned ? context.loc.pinnedTags.unpinTag : context.loc.pinnedTags.pinTag),
                              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                              onTap: () async {
                                if (isPinned && pinnedTag != null) {
                                  await showUnpinTagDialog(
                                    context,
                                    tag,
                                    pinnedTag,
                                    () {},
                                  );
                                } else {
                                  await showPinTagDialog(
                                    context,
                                    tag,
                                    isMetaTag ? handler.booru : searchHandler.currentBooruOrNull ?? handler.booru,
                                    () {},
                                  );
                                }
                                reopenDialog();
                              },
                            );
                          },
                        ),
                        //
                        if (hasTabWithTag.hasTagInAnyForm)
                          ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  CupertinoIcons.doc_on_doc,
                                  color: Theme.of(context).iconTheme.color,
                                ),

                                Positioned(
                                  right: -5,
                                  top: -5,
                                  child: Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: hasTabWithTag.color(context),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(context.loc.tagView.relatedTabs),
                            onTap: () => showRelatedTabsDialog(context, tag),
                          ),
                        if (!isMetaTag)
                          ListTile(
                            leading: Icon(
                              Icons.edit,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            title: Text(context.loc.tagView.editTag),
                            onTap: () async {
                              Navigator.of(context).pop();
                              final item = tagHandler.getTag(tag);
                              await showDialog(
                                context: context,
                                builder: (context) => TagsManagerListItemDialog(
                                  tag: item,
                                  onChangedType: (TagType? newValue) {
                                    if (newValue != null && item.tagType != newValue) {
                                      item.tagType = newValue;
                                      tagHandler.putTag(
                                        item,
                                        dbEnabled: SX.dbEnabled.value,
                                        preferTypeIfNone: false,
                                      );
                                      onUpdate();
                                    }
                                  },
                                ),
                              );
                              onUpdate();
                            },
                          ),
                        //
                        ListTile(
                          leading: Icon(
                            Icons.cancel_outlined,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(context.loc.close),
                          onTap: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showRelatedTabsDialog(
  BuildContext context,
  String tag,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _RelatedTabsDialog(tag),
  );
}

class _RelatedTabsDialog extends StatefulWidget {
  const _RelatedTabsDialog(
    this.tag,
  );

  final String tag;

  @override
  State<_RelatedTabsDialog> createState() => _RelatedTabsDialogState();
}

class _RelatedTabsDialogState extends State<_RelatedTabsDialog> {
  final searchHandler = SearchHandler.instance;

  List<(int, SearchTab)> tabsWithOnlyTag = [], tabsWithOnlyTagDifferentBooru = [], tabsContainingTag = [];

  HasTabWithTagResult selectedType = HasTabWithTagResult.noTag;

  @override
  void initState() {
    super.initState();

    tabsWithOnlyTag = searchHandler.getTabsWithOnlyTag(widget.tag);
    tabsWithOnlyTagDifferentBooru = searchHandler.getTabsWithOnlyTagDifferentBooru(widget.tag);
    tabsContainingTag = searchHandler.getTabsContainingTag(widget.tag);

    selectedType = HasTabWithTagResult.noTag;
    if (tabsWithOnlyTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTag;
    } else if (tabsWithOnlyTagDifferentBooru.isNotEmpty) {
      selectedType = HasTabWithTagResult.onlyTagDifferentBooru;
    } else if (tabsContainingTag.isNotEmpty) {
      selectedType = HasTabWithTagResult.containsTag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final listItems = switch (selectedType) {
      .onlyTag => tabsWithOnlyTag,
      .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru,
      .containsTag => tabsContainingTag,
      _ => <(int, SearchTab)>[],
    };

    return SettingsDialog(
      scrollable: false,
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          LoliDropdown(
            value: selectedType,
            onChanged: (newType) {
              setState(() => selectedType = newType ?? HasTabWithTagResult.noTag);
            },
            items: [
              if (tabsWithOnlyTag.isNotEmpty) HasTabWithTagResult.onlyTag,
              if (tabsWithOnlyTagDifferentBooru.isNotEmpty) HasTabWithTagResult.onlyTagDifferentBooru,
              if (tabsContainingTag.isNotEmpty) HasTabWithTagResult.containsTag,
            ],
            itemBuilder: (v) => ListTile(
              leading: Icon(
                Icons.circle,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(
                '${v?.locName(context) ?? ''} (${switch (v) {
                  .onlyTag => tabsWithOnlyTag.length,
                  .onlyTagDifferentBooru => tabsWithOnlyTagDifferentBooru.length,
                  .containsTag => tabsContainingTag.length,
                  _ => 0,
                }})',
              ),
            ),
            selectedItemBuilder: (v) => ListTile(
              leading: Icon(
                Icons.circle,
                size: 12,
                color: v?.color(context),
              ),
              title: Text(v?.locName(context) ?? ''),
            ),
            labelText: context.loc.tagView.relatedTabs,
          ),
          Container(
            width: double.maxFinite,
            height: (listItems.length * 80.0).clamp(0, MediaQuery.sizeOf(context).height * 0.66) + 32,
            decoration: const BoxDecoration(),
            child: ListView.builder(
              itemCount: listItems.length,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemBuilder: (context, index) {
                final (tabIndex, tab) = listItems[index];
                return TabManagerItem(
                  tab: tab,
                  index: index,
                  isFiltered: true,
                  originalIndex: tabIndex,
                  onTap: () async {
                    await ServiceHandler.vibrate();
                    if (SX.appMode.value.isMobile) {
                      Navigator.of(context).popUntil((r) => r.isFirst); // exit viewer
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      searchHandler.changeTabIndex(tabIndex);
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
      actionButtons: const [CloseDialogButton(withIcon: true)],
    );
  }
}

//

class SourceLinkErrorDialog extends StatelessWidget {
  const SourceLinkErrorDialog({
    required this.link,
    super.key,
  });

  final String link;
  List<String> get detectedUrls => const UrlParseRule()
      .findMatches(link)
      .map((m) => m.segment.metadata['url'] as String? ?? m.segment.text)
      .toList();

  Future<void> copy(BuildContext context) async {
    await ClipboardUtils.copyTextToClipboard(link);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.tagView.sourceDialogTitle),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            const SizedBox(height: 16),
            if (detectedUrls.isNotEmpty) ...[
              Text(
                context.loc.tagView.detectedLinks,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              ...detectedUrls.map(
                (url) => InkWell(
                  onTap: () async {
                    final ok = await launchUrlString(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok) {
                      FlashElements.showSnackbar(
                        title: Text(context.loc.failedToOpenLink),
                        content: Text(url),
                      );
                    }
                  },
                  child: SizedBox(
                    height: 50,
                    child: Row(
                      spacing: 12,
                      children: [
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.link,
                          size: 20,
                        ),
                        Expanded(
                          child: DraggableOverflowText(url),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            ParsedText(
              text: link,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        ElevatedButton.icon(
          onPressed: () => copy(context),
          label: Text(context.loc.copy),
          icon: const Icon(Icons.copy),
        ),
        const CloseDialogButton(withIcon: true),
      ],
    );
  }
}

class TagContentPreview extends StatefulWidget {
  TagContentPreview({
    required this.tag,
    required this.boorus,
    required this.parentTab,
    this.readOnly = false,
    super.key,
  }) : assert(
         boorus.isNotEmpty,
         'boorus must not be empty',
       );

  final String tag;
  final List<Booru> boorus;
  final SearchTab? parentTab;
  final bool readOnly;

  @override
  State<TagContentPreview> createState() => _TagContentPreviewState();
}

class _TagContentPreviewState extends State<TagContentPreview> {
  final settingsHandler = SettingsHandler.instance;
  final viewerHandler = ViewerHandler.instance;

  final AutoScrollController scrollController = AutoScrollController(axis: Axis.horizontal);
  final GlobalKey _viewportKey = GlobalKey();
  final ValueNotifier<bool> _dragSelecting = ValueNotifier(false);
  Timer? _dragTimer;
  Offset? _dragStart, _dragPosition;
  int? _dragAnchor, _dragLastIndex;
  bool _dragAdds = true;
  bool _dragArmed = false;
  List<BooruItem> _selectionBeforeDrag = [];
  SearchTab? _dragTab;

  Booru? selectedBooru;

  SearchTab? tab;
  bool loading = false;
  bool isLastPage = false;
  String errorString = '';

  final ValueNotifier<int> viewedIndex = ValueNotifier(-1);

  bool get isSingleBooru => widget.boorus.length == 1;

  final String previewId = const Uuid().v4();

  @override
  void initState() {
    super.initState();

    viewerHandler.addTagPreview(
      widget.parentTab?.id,
      previewId,
      widget.tag,
    );

    if (isSingleBooru) {
      selectedBooru = widget.boorus.first;
    }
  }

  Future<void> loadPreview({bool refresh = false, bool retry = false}) async {
    if (!mounted || selectedBooru == null) return;
    if (refresh || tab == null) {
      _endDragSelection();
      tab = SearchTab(selectedBooru!, null, widget.tag);
      viewedIndex.value = -1;
      loading = false;
      isLastPage = false;
      errorString = '';
      if (scrollController.hasClients) scrollController.jumpTo(0);
    }
    if (loading) return;
    final requestTab = tab!;
    final handler = requestTab.booruHandler;
    if (retry) {
      errorString = '';
      handler.errorString = '';
      isLastPage = false;
      handler.locked = false;
      handler.pageNum--;
    }
    if (isLastPage || errorString.isNotEmpty || handler.locked) return;
    setState(() => loading = true);
    handler.pageNum++;
    try {
      await handler.search(widget.tag, null);
      if (!mounted || !identical(tab, requestTab)) return;
      isLastPage = handler.locked;
      errorString = handler.errorString;
      if (handler.totalCount.value == 0 && errorString.isEmpty) {
        unawaited(handler.searchCount(widget.tag));
      }
    } catch (error) {
      if (!mounted || !identical(tab, requestTab)) return;
      errorString = handler.errorString = error.toString();
    } finally {
      if (mounted && identical(tab, requestTab)) setState(() => loading = false);
    }
  }

  void _toggleSelected(int index) {
    final previewTab = tab;
    if (widget.readOnly || previewTab == null) return;
    final items = previewTab.booruHandler.filteredFetched.toList(growable: false);
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (previewTab.selected.contains(item)) {
      previewTab.selected.remove(item);
    } else {
      previewTab.selected.add(item);
    }
  }

  int? _itemAt(Offset globalPosition) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize || !scrollController.hasClients) return null;
    final local = viewport.globalToLocal(globalPosition);
    if (local.dy < 0 || local.dy > viewport.size.height) return null;
    final x = local.dx.clamp(0.0, viewport.size.width);
    final index = ((x + scrollController.offset - 16) / 120).floor();
    final count = tab?.booruHandler.filteredFetched.length ?? 0;
    return index >= 0 && index < count ? index : null;
  }

  void _startDragSelection(LongPressStartDetails details) {
    final index = _itemAt(details.globalPosition);
    if (index == null || widget.readOnly || tab == null) return;
    _dragTab = tab;
    _dragAnchor = index;
    _dragStart = _dragPosition = details.globalPosition;
    _dragArmed = false;
    _selectionBeforeDrag = [...tab!.selected];
    _dragAdds = !_selectionBeforeDrag.contains(tab!.booruHandler.filteredFetched[index]);
    _applyDragSelection(index);
    _dragSelecting.value = true;
  }

  void _moveDragSelection(LongPressMoveUpdateDetails details) {
    if (_dragAnchor == null) return;
    _dragPosition = details.globalPosition;
    _dragArmed = _dragArmed || (details.globalPosition - _dragStart!).distance >= kTouchSlop;
    final index = _itemAt(details.globalPosition);
    if (index != null) _applyDragSelection(index);
    if (_dragArmed) _dragTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _dragScrollTick());
  }

  void _applyDragSelection(int index) {
    if (_dragAnchor == null || _dragLastIndex == index || !identical(_dragTab, tab)) return;
    final items = tab!.booruHandler.filteredFetched;
    if (_dragAnchor! >= items.length || index >= items.length) return;
    final range = <BooruItem>[];
    final direction = index >= _dragAnchor! ? 1 : -1;
    for (var i = _dragAnchor!; i != index + direction; i += direction) {
      range.add(items[i]);
    }
    final rangeSet = Set<BooruItem>.identity()..addAll(range);
    final initialSet = Set<BooruItem>.identity()..addAll(_selectionBeforeDrag);
    tab!.selected.assignAll(
      _dragAdds
          ? [..._selectionBeforeDrag, ...range.where((item) => !initialSet.contains(item))]
          : _selectionBeforeDrag.where((item) => !rangeSet.contains(item)),
    );
    _dragLastIndex = index;
  }

  void _dragScrollTick() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (!_dragArmed || _dragPosition == null || viewport is! RenderBox || !scrollController.hasClients) return;
    final local = viewport.globalToLocal(_dragPosition!);
    if (local.dy < 0 || local.dy > viewport.size.height) return;
    const edge = 56.0;
    final delta = local.dx < edge
        ? -12 * ((edge - local.dx) / edge).clamp(0.0, 1.0)
        : local.dx > viewport.size.width - edge
        ? 12 * ((local.dx - viewport.size.width + edge) / edge).clamp(0.0, 1.0)
        : 0.0;
    if (delta == 0) return;
    final position = scrollController.position;
    scrollController.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
    final index = _itemAt(_dragPosition!);
    if (index != null) _applyDragSelection(index);
  }

  void _endDragSelection() {
    _dragSelecting.value = false;
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragAnchor = _dragLastIndex = null;
    _dragStart = _dragPosition = null;
    _dragTab = null;
    _dragArmed = false;
    _selectionBeforeDrag = [];
  }

  BooruItem? _leftmostVisibleItem() {
    final previewTab = tab;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (previewTab == null || viewport is! RenderBox || !viewport.hasSize) return null;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    int? bestIndex;
    var bestDistance = double.infinity;
    for (final entry in scrollController.tagMap.entries) {
      final box = entry.value.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.overlaps(bounds)) continue;
      final distance = (rect.left - bounds.left).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = entry.key;
      }
    }
    final items = previewTab.booruHandler.filteredFetched.toList(growable: false);
    return bestIndex != null && bestIndex < items.length ? items[bestIndex] : null;
  }

  SearchTab _createTab({bool restorePosition = false}) {
    final canReuse = !loading && errorString.isEmpty && tab?.booruHandler.filteredFetched.isNotEmpty == true;
    return SearchHandler.instance.addTabByString(
      widget.tag,
      customBooru: selectedBooru,
      previewTab: canReuse ? tab : null,
      scrollToItem: canReuse && restorePosition ? _leftmostVisibleItem() : null,
    );
  }

  Future<void> onPreviewTap(int index) async {
    final previewTab = tab;
    if (previewTab == null || index >= previewTab.booruHandler.filteredFetched.length) return;
    viewedIndex.value = index;
    final viewerKey = GlobalKey(debugLabel: 'viewer-${tab!.tags.replaceAll(' ', '_')}');
    ViewerHandler.instance.addViewer(viewerKey);
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => GalleryViewPage(
          key: viewerKey,
          tab: previewTab,
          initialIndex: index,
          canSelect: !widget.readOnly,
          readOnly: widget.readOnly,
          onPageChanged: (page) async {
            if (!mounted || !identical(tab, previewTab)) return;
            viewedIndex.value = page;
            await scrollController.scrollToIndex(
              page,
              duration: const Duration(milliseconds: 10),
              preferPosition: AutoScrollPosition.begin,
            );
          },
        ),
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        barrierColor: Colors.black26,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return const ZoomPageTransitionsBuilder().buildTransitions(
            MaterialPageRoute(
              builder: (_) => const SizedBox.shrink(),
            ),
            context,
            animation,
            secondaryAnimation,
            child,
          );
        },
      ),
    );
    if (mounted) viewedIndex.value = -1;
  }

  Future<void> onPreviewDoubleTap(int index) async {
    if (widget.readOnly) return;

    await tab?.toggleItemFavourite(index);
  }

  Future<void> onPreviewSecondaryTap(int index) async {
    if (tab == null) {
      return;
    }

    final BooruItem item = tab!.booruHandler.filteredFetched[index];
    await ClipboardUtils.copyTextToClipboard(Uri.encodeFull(item.fileURL));
  }

  Future<void> showTagPreviewsListDialog() async {
    if (widget.parentTab == null) return;

    await showDialog(
      context: context,
      builder: (_) => _TagPreviewsListDialog(widget.parentTab!.id),
    );
  }

  void closePreview() {
    _endDragSelection();
    setState(() {
      tab = null;
      selectedBooru = isSingleBooru ? widget.boorus.first : null;
      loading = false;
      isLastPage = false;
      errorString = '';
    });
  }

  void addPreviewTab() {
    final booru = selectedBooru;
    if (booru == null) return;

    final newTab = _createTab();
    FlashElements.showSnackbar(
      context: context,
      isKeyUnique: true,
      key: 'added_new_tab',
      duration: const Duration(seconds: 2),
      title: Text(context.loc.tagView.addedNewTab, style: const TextStyle(fontSize: 20)),
      content: Text(widget.tag, style: const TextStyle(fontSize: 16)),
      leadingIcon: Icons.fiber_new,
      sideColor: Colors.green,
      primaryActionBuilder: (context, controller) {
        return Row(
          children: [
            IconButton(
              tooltip: context.loc.open,
              onPressed: () {
                ServiceHandler.vibrate();
                if (SX.appMode.value.isMobile) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final search = SearchHandler.instance;
                  final index = search.tabs.indexOf(newTab);
                  if (index >= 0) search.changeTabIndex(index);
                });
                controller.dismiss();
              },
              icon: Icon(Icons.arrow_forward_rounded, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: context.loc.close,
              onPressed: () => controller.dismiss(),
              icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        );
      },
    );
  }

  Future<void> addPreviewTabAndSwitch() async {
    final booru = selectedBooru;

    if (booru == null) return;

    final newTab = _createTab(restorePosition: true);
    await ServiceHandler.vibrate();
    if (!mounted) return;

    if (SX.appMode.value.isMobile) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final search = SearchHandler.instance;
      final index = search.tabs.indexOf(newTab);
      if (index >= 0) search.changeTabIndex(index);
    });
  }

  @override
  void dispose() {
    _endDragSelection();
    _dragSelecting.dispose();
    scrollController.dispose();
    viewedIndex.dispose();
    viewerHandler.removeTagPreview(
      widget.parentTab?.id,
      previewId,
    );
    super.dispose();
  }

  Widget buildPreviewHeader(SearchTab? previewTab) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(Icons.image_search_rounded, color: theme.colorScheme.onSurfaceVariant, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Text(context.loc.tagView.preview, style: theme.textTheme.titleMedium),
                if (previewTab != null)
                  Obx(() {
                    final count = previewTab.booruHandler.totalCount.value;
                    if (count <= 0) return const SizedBox.shrink();

                    return Text(
                      context.loc.imageStats.total(count: count),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    );
                  }),
              ],
            ),
          ),
          if (previewTab != null && !widget.readOnly)
            Obx(
              () => previewTab.allHiddenItems.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: '${context.loc.settings.downloads.hiddenItems} (${previewTab.allHiddenItems.length})',
                      icon: const Icon(Icons.visibility_off_outlined),
                      onPressed: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => HiddenItemsPage(tab: previewTab))),
                    ),
            ),
          if (widget.parentTab != null)
            IconButton(
              tooltip: context.loc.tagView.tagPreviews,
              color: theme.colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.history_rounded),
              onPressed: showTagPreviewsListDialog,
            ),
          if (previewTab != null)
            IconButton(
              tooltip: context.loc.close,
              color: theme.colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.close_rounded),
              onPressed: closePreview,
            ),
        ],
      ),
    );
  }

  Widget buildPreviewControls(SearchTab? previewTab) {
    final hasTabWithTag = SearchHandler.instance.hasTabWithTag(widget.tag, customBooru: selectedBooru);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SettingsBooruDropdown(
              title: context.loc.booru,
              placeholder: context.loc.tagView.selectBooruToLoad,
              value: selectedBooru,
              items: settingsHandler.booruList,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                selectedBooru = value;
                loadPreview(refresh: true);
              },
              titleAsLabel: true,
              drawBottomBorder: false,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: previewTab == null
                ? context.loc.tagView.preview
                : MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSecondaryContainer,
              backgroundColor: colorScheme.secondaryContainer,
              disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
              disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            iconSize: 20,
            onPressed: selectedBooru == null || loading ? null : () => loadPreview(refresh: previewTab != null),
            icon: Icon(previewTab == null ? Icons.search_rounded : Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: context.loc.openInNewTab,
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
            ),
            iconSize: 20,
            onPressed: selectedBooru == null ? null : addPreviewTab,
            onLongPress: selectedBooru == null ? null : addPreviewTabAndSwitch,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.fiber_new),
                if (selectedBooru != null && hasTabWithTag.hasTagInAnyForm)
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    top: -2,
                    end: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasTabWithTag.color(context),
                        border: Border.all(color: colorScheme.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPreviewMessage({
    required IconData icon,
    required String message,
    bool isLoading = false,
    bool isError = false,
    VoidCallback? onAction,
    String? actionLabel,
    IconData actionIcon = Icons.refresh_rounded,
  }) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isError ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: .min,
          children: [
            if (isLoading)
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: color, semanticsLabel: message),
              )
            else
              Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 4),
              IconButton(
                tooltip: actionLabel ?? context.loc.tagView.tryAgain,
                color: color,
                iconSize: 20,
                onPressed: onAction,
                icon: Icon(actionIcon),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildPreviewContent(SearchTab previewTab) {
    final items = previewTab.booruHandler.filteredFetched.toList(growable: false);
    if (items.isEmpty) {
      if (loading) {
        return buildPreviewMessage(
          icon: Icons.search_rounded,
          message: context.loc.tagView.previewIsLoading,
          isLoading: true,
        );
      }
      if (errorString.isNotEmpty) {
        return buildPreviewMessage(
          icon: Icons.error_outline_rounded,
          message: context.loc.tagView.failedToLoadPreview,
          isError: true,
          onAction: () => loadPreview(refresh: true),
        );
      }
      return buildPreviewMessage(
        icon: Icons.search_off_rounded,
        message: context.loc.nothingFound,
        onAction: isLastPage ? null : loadPreview,
        actionLabel: MaterialLocalizations.of(context).nextPageTooltip,
        actionIcon: Icons.navigate_next_rounded,
      );
    }

    return Column(
      mainAxisSize: .min,
      children: [
        SizedBox(
          height: 206,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notif) {
              final isNotAtStart = notif.metrics.pixels > 0;
              final isAtOrNearEdge =
                  notif.metrics.atEdge ||
                  notif.metrics.pixels > (notif.metrics.maxScrollExtent - (notif.metrics.extentInside * 2));
              final isScreenFilled = notif.metrics.extentBefore != 0 || notif.metrics.extentAfter != 0;

              if (!loading && (!isScreenFilled || (isNotAtStart && isAtOrNearEdge))) {
                loadPreview();
              }
              return true;
            },
            child: Scrollbar(
              controller: scrollController,
              interactive: true,
              thickness: 6,
              thumbVisibility: true,
              child: Listener(
                onPointerSignal: (event) => desktopPointerScroll(scrollController, event),
                child: GestureDetector(
                  key: _viewportKey,
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: widget.readOnly ? null : _startDragSelection,
                  onLongPressMoveUpdate: widget.readOnly ? null : _moveDragSelection,
                  onLongPressEnd: (_) => _endDragSelection(),
                  onLongPressCancel: _endDragSelection,
                  child: FadingEdgeScrollView.from(
                    child: ListView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length + (loading ? 1 : 0),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          return SizedBox(
                            width: 64,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: SizedBox(
                            width: 112,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ValueListenableBuilder(
                                valueListenable: viewedIndex,
                                builder: (context, viewedIndex, _) {
                                  final item = items[index];
                                  final isFirstOfPage = index == 0 || item.fetchedPage != items[index - 1].fetchedPage;
                                  return Stack(
                                    children: [
                                      ThumbnailCardBuild(
                                        index: index,
                                        item: item,
                                        handler: previewTab.booruHandler,
                                        scrollController: scrollController,
                                        isHighlighted: viewedIndex == index,
                                        selectable: !widget.readOnly && previewTab.selected.isNotEmpty,
                                        useHero: false,
                                        selectedIndex: previewTab.selectedIndexOf(item),
                                        onSelected: _toggleSelected,
                                        onTap: onPreviewTap,
                                        onDoubleTap: onPreviewDoubleTap,
                                        onSecondaryTap: onPreviewSecondaryTap,
                                      ),
                                      if (isFirstOfPage && item.fetchedPage > -1)
                                        Positioned(
                                          top: 2,
                                          left: 2,
                                          child: IgnorePointer(
                                            child: GridPageIndicator(item.fetchedPage, tab: previewTab),
                                          ),
                                        ),
                                    ],
                                  );
                                },
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
          ),
        ),
        if (errorString.isNotEmpty && !loading)
          buildPreviewMessage(
            icon: Icons.error_outline_rounded,
            message: context.loc.tagView.failedToLoadPreviewPage,
            isError: true,
            onAction: () => loadPreview(retry: true),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewTab = tab;
    final colorScheme = Theme.of(context).colorScheme;

    // Give dialogs an intrinsic width without measuring the lazy thumbnail list.
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Material(
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: [
                buildPreviewHeader(previewTab),
                buildPreviewControls(previewTab),
                if (previewTab != null)
                  Obx(() {
                    previewTab.selected.length;
                    return buildPreviewContent(previewTab);
                  }),
                if (previewTab != null && !widget.readOnly)
                  ValueListenableBuilder(
                    valueListenable: _dragSelecting,
                    builder: (_, selecting, _) => IgnorePointer(
                      ignoring: selecting,
                      child: SelectionButtons(key: ValueKey(previewTab.id), tab: previewTab),
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

class _TagPreviewsListDialog extends StatelessWidget {
  const _TagPreviewsListDialog(
    this.tabId,
  );

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final viewerHandler = ViewerHandler.instance;
    final searchHandler = SearchHandler.instance;

    final list = viewerHandler.tagPreviewsHistory[tabId] ?? [];
    final controllers = List.generate(list.length, (_) => ScrollController());
    // scroll to end of each stack history item
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   for (final c in controllers) {
    //     c.jumpTo(c.position.maxScrollExtent);
    //   }
    // });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Material(
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              //
              Text(
                context.loc.tagView.tagPreviews,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              //
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, entryIndex) {
                    final entry = list[list.length - entryIndex - 1];
                    final bool isActive = entry == list.last;
                    final bool isSecondsToLast = list.length > 1 && entry == list[list.length - 2];

                    if (entry.isEmpty) return const SizedBox.shrink();

                    bool matchesCurrentState = true;
                    final currentState = viewerHandler.currentTagPreviewState(tabId).map((e) => e.value).toList();
                    entry.forEachIndexed((i, e) {
                      if (i >= currentState.length || currentState[i] != e.value) {
                        matchesCurrentState = false;
                        return;
                      }
                    });

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isActive || isSecondsToLast)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              isActive ? context.loc.tagView.currentState : context.loc.tagView.history,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        //
                        Material(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            shape: Border(
                              top: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: context.theme.dividerColor,
                                width: 0.5,
                              ),
                            ),
                            trailing: (isActive || matchesCurrentState)
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.history),
                                    onPressed: () async {
                                      Navigator.of(context).pop();

                                      final state = viewerHandler.currentTagPreviewState(tabId);

                                      entry.forEachIndexed((index, e) async {
                                        final tag = e.value;
                                        final currentHandler = searchHandler.currentBooruHandlerOrNull;

                                        // skip if tag already in stack
                                        if (currentHandler != null && state.all((e) => e.value != tag)) {
                                          unawaited(
                                            showTagDialog(
                                              context: context,
                                              tag: tag,
                                              handler: currentHandler,
                                              isInSearch:
                                                  searchHandler.searchTextController.text
                                                      .toLowerCase()
                                                      .split(' ')
                                                      .indexWhere(
                                                        (t) =>
                                                            t == tag.toLowerCase() ||
                                                            t == '-${tag.toLowerCase()}' ||
                                                            t == '~${tag.toLowerCase()}' ||
                                                            RegExp(
                                                              r'^(?:-|~)?\d+#(?:-|~)?' + tag.regexpEscape() + r'$',
                                                            ).hasMatch(t),
                                                      ) !=
                                                  -1,
                                              hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                              onUpdate: () {},
                                            ),
                                          );
                                          await Future.delayed(const Duration(milliseconds: 50));
                                        }
                                      });
                                    },
                                  ),
                            title: SizedBox(
                              height: 40,
                              width: double.maxFinite,
                              child: FadingEdgeScrollView.from(
                                child: ListView(
                                  controller: controllers[entryIndex],
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  children: [
                                    ...entry.mapWithIndex(
                                      (e, i) {
                                        final tag = e.value;
                                        final bool isLast = i == entry.length - 1;

                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            MainSearchTagChip(
                                              tag: tag,
                                              booru: searchHandler.currentBooruOrNull,
                                              isSelected: isActive && isLast,
                                              onTap: () {
                                                if (isActive) {
                                                  // close everything up to this tag
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    Navigator.of(context).popUntil(
                                                      (route) =>
                                                          route.settings.name == 'tagDialog/$tag' || route.isFirst,
                                                    );
                                                  });
                                                } else {
                                                  // open dialog for this tag
                                                  final currentHandler = searchHandler.currentBooruHandlerOrNull;
                                                  if (currentHandler == null) {
                                                    return;
                                                  }

                                                  Navigator.of(context).pop();
                                                  unawaited(
                                                    showTagDialog(
                                                      context: context,
                                                      tag: tag,
                                                      handler: currentHandler,
                                                      isInSearch:
                                                          searchHandler.searchTextController.text
                                                              .toLowerCase()
                                                              .split(' ')
                                                              .indexWhere(
                                                                (t) =>
                                                                    t == tag.toLowerCase() ||
                                                                    t == '-${tag.toLowerCase()}' ||
                                                                    t == '~${tag.toLowerCase()}' ||
                                                                    RegExp(
                                                                      r'^(?:-|~)?\d+#(?:-|~)?' +
                                                                          tag.regexpEscape() +
                                                                          r'$',
                                                                    ).hasMatch(t),
                                                              ) !=
                                                          -1,
                                                      hasTabWithTag: searchHandler.hasTabWithTag(tag),
                                                      onUpdate: () {},
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                            if (!isLast)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 4),
                                                child: Icon(
                                                  Icons.arrow_forward,
                                                  size: 14,
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              //
              ListTile(
                leading: Icon(
                  Icons.cancel_outlined,
                  color: Theme.of(context).iconTheme.color,
                ),
                title: Text(context.loc.close),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              //
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
