import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/preview/page_loading_status.dart';

class PageNumberDialog extends StatefulWidget {
  const PageNumberDialog({super.key});

  @override
  State<PageNumberDialog> createState() => _PageNumberDialogState();
}

class _PageNumberDialogState extends State<PageNumberDialog> {
  final searchHandler = SearchHandler.instance;
  final pageNumberController = TextEditingController();
  final delayController = TextEditingController(text: '200');
  final scrollController = ScrollController();
  late final SearchTab tab;
  bool loadSequentially = true;
  bool showTarget = false;

  bool get isCurrentTab => identical(searchHandler.currentTabOrNull, tab);
  int get currentDisplayPage => max(
    1,
    tab.displayPage(isCurrentTab ? searchHandler.currentScrollPage.value : (tab.scrollPage ?? tab.firstPage)),
  );

  int? get targetPage {
    final number = int.tryParse(pageNumberController.text);
    return number != null && number >= 1 ? tab.apiPage(number) : null;
  }

  int? get delay {
    final value = int.tryParse(delayController.text);
    return value != null && value >= 100 && value <= 10000 ? value : null;
  }

  bool hasVisiblePage(int? page) =>
      page != null && tab.booruHandler.filteredFetched.any((item) => item.fetchedPage == page);

  bool canLoadThrough(int? page) => page != null && page > tab.booruHandler.pageNum && !tab.booruHandler.locked;

  @override
  void initState() {
    super.initState();
    tab = searchHandler.currentTab;
    setPageInput(currentDisplayPage);
    pageNumberController.addListener(onInputChanged);
    delayController.addListener(onInputChanged);
  }

  void setPageInput(int page) {
    final text = page.toString();
    pageNumberController.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
  }

  void onInputChanged() {
    if (mounted) setState(() {});
  }

  void submit({bool reload = false}) {
    final page = targetPage;
    if (!isCurrentTab || page == null || searchHandler.isRunningAutoSearch.value) return;
    final loaded = hasVisiblePage(page);
    final sequential = !reload && !loaded && loadSequentially && canLoadThrough(page);
    if (sequential && (delay == null || tab.booruHandler.errorString.isNotEmpty)) return;

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
    if (!reload && (loaded || sequential)) {
      unawaited(
        searchHandler.executePageRestore(
          tab,
          page,
          loaded || showTarget ? .fetchAndScroll : .fetchNoScroll,
          customDelay: sequential ? delay : 200,
        ),
      );
    } else {
      unawaited(searchHandler.changeCurrentTabPageNumber(page));
    }
  }

  String loadedRanges(List<int> pages) {
    final ranges = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final start = pages[i];
      var end = start;
      while (i + 1 < pages.length && pages[i + 1] == end + 1) {
        end = pages[++i];
      }
      ranges.add(start == end ? '$start' : '$start–$end');
    }
    return ranges.join(', ');
  }

  @override
  void dispose() {
    pageNumberController.dispose();
    delayController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loc = context.loc.pageNavigation;
      final handler = tab.booruHandler;
      // Empty/filtered responses change the page set too, so observe requests.
      final loading = searchHandler.isLoading.value;
      final fetchingPage = searchHandler.pageNum.value;
      final error = searchHandler.errorString.value;
      final running = searchHandler.isAutoSearchingTab(tab);
      final busy = searchHandler.isRunningAutoSearch.value;
      final current = isCurrentTab;
      final page = targetPage;
      final loaded = hasVisiblePage(page);
      final canLoad = canLoadThrough(page);
      final sequential = loadSequentially && canLoad && !loaded;
      final pages = handler.fetchedPageNumbers.map(tab.displayPage).toList()..sort();
      final ranges = loadedRanges(pages);
      final total = handler.totalCount.value;
      final maxPage = total > 0 && handler.limit > 0 ? (total / handler.limit).ceil() : null;
      final failed = current && error.isNotEmpty;
      final valid = current && !busy && page != null && (!sequential || (delay != null && !failed));
      final smallStyle = Theme.of(context).textTheme.bodySmall;

      final body = <Widget>[
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => setPageInput(currentDisplayPage),
              child: Text(loc.viewing(page: currentDisplayPage)),
            ),
            if (pages.isNotEmpty)
              TextButton(
                onPressed: () => setPageInput(pages.last),
                child: Text(loc.lastLoaded(page: pages.last)),
              ),
          ],
        ),
        if (pages.isNotEmpty || maxPage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              [
                if (pages.isNotEmpty) loc.loadedRange(pages: ranges),
                if (maxPage != null) loc.approximateTotal(pages: maxPage),
              ].join(' · '),
              style: smallStyle,
            ),
          ),
        SettingsTextInput(
          title: context.loc.pageChanger.pageLabel,
          titleAsLabel: true,
          onlyInput: true,
          controller: pageNumberController,
          autofocus: !running,
          inputType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => submit(),
          numberButtons: true,
          numberMin: 1,
          numberMax: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          validator: (_) => targetPage == null ? loc.invalidPage : null,
        ),
        if (current && !running && !loaded)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text(loc.loadThrough),
                  selected: sequential,
                  onSelected: busy || !canLoad ? null : (_) => setState(() => loadSequentially = true),
                ),
                ChoiceChip(
                  label: Text(loc.openPage),
                  selected: !sequential,
                  onSelected: busy ? null : (_) => setState(() => loadSequentially = false),
                ),
              ],
            ),
          ),
        if (!current)
          Text(loc.tabChanged, style: smallStyle)
        else if (loaded)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(loc.alreadyLoaded, style: smallStyle),
              Tooltip(
                message: loc.freshResults,
                child: TextButton(
                  onPressed: busy ? null : () => submit(reload: true),
                  child: Text(loc.startSearchHere),
                ),
              ),
            ],
          )
        else
          Text(
            page != null && handler.fetchedPageNumbers.contains(page)
                ? loc.noVisiblePosts
                : sequential
                ? loc.keepResults
                : loc.freshResults,
            style: smallStyle,
          ),
        if (!running && loading && current)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(loc.loadingPage(page: max(1, tab.displayPage(fetchingPage))), style: smallStyle),
          ),
        if (current && !running && sequential)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failed) Text(loc.retryFirst, style: smallStyle),
              CheckboxListTile(
                value: showTarget,
                onChanged: (value) => setState(() => showTarget = value ?? true),
                title: Text(loc.showWhenReady, style: Theme.of(context).textTheme.bodyMedium),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              SettingsTextInput(
                title: loc.requestDelay,
                titleAsLabel: true,
                onlyInput: true,
                controller: delayController,
                inputType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => submit(),
                numberButtons: true,
                numberStep: 100,
                numberMin: 100,
                numberMax: 10000,
                margin: const EdgeInsets.symmetric(vertical: 4),
                validator: (_) => delay == null ? loc.invalidDelay : null,
              ),
            ],
          ),
        CheckboxListTile(
          value: tab.savePageEnabled.value,
          onChanged: !current
              ? null
              : (value) {
                  tab.savePageEnabled.value = value ?? false;
                  unawaited(searchHandler.backupTabs());
                },
          title: Text(loc.rememberTab, style: Theme.of(context).textTheme.bodyMedium),
          secondary: Icon(
            tab.savePageEnabled.value ? Icons.bookmark : Icons.bookmark_border,
            size: 20,
          ),
          subtitle: Text(
            tab.savePageEnabled.value && (!tab.hasValidPageCoordinates || tab.hasPageSizeChanges())
                ? loc.freshSearchToRemember
                : '',
            style: smallStyle,
          ),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
      ];

      return LayoutBuilder(
        builder: (context, constraints) => SettingsBottomSheet(
          title: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: max(0, constraints.maxWidth - 100)),
            child: Text(loc.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
          ),
          content: Flexible(
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 0, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ),
          ),
          actionPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          actionButtons: [
            SizedBox(
              width: double.infinity,
              child: running
                  ? PageLoadingStatus(tab: tab)
                  : FilledButton.icon(
                      onPressed: valid ? submit : null,
                      icon: Icon(
                        loaded
                            ? Icons.swipe_up
                            : sequential
                            ? Icons.download
                            : Icons.subdirectory_arrow_right,
                      ),
                      label: Text(
                        loaded
                            ? loc.goToLoaded
                            : sequential
                            ? loc.loadThrough
                            : loc.openPage,
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }
}
