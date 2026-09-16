import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/pulse_widget.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class PageNumberDialog extends StatefulWidget {
  const PageNumberDialog({super.key});

  @override
  State<PageNumberDialog> createState() => _PageNumberDialogState();
}

class _PageNumberDialogState extends State<PageNumberDialog> {
  final SearchHandler searchHandler = SearchHandler.instance;

  final pageNumberController = TextEditingController(), delayController = TextEditingController();

  bool scrollToFetchedPage = false;
  late final SearchTab tab;

  bool get isCurrentTab => identical(searchHandler.currentTabOrNull, tab);

  int get currentDisplayPage => max(
    1,
    tab.displayPage(isCurrentTab ? searchHandler.currentScrollPage.value : (tab.scrollPage ?? tab.firstPage)),
  );

  int? get pageNumber {
    final parsedNumber = int.tryParse(pageNumberController.text);
    return parsedNumber != null && parsedNumber >= 1 ? tab.apiPage(parsedNumber) : null;
  }

  int? get delay {
    final parsedDelay = int.tryParse(delayController.text);
    return parsedDelay != null && parsedDelay >= 100 && parsedDelay <= 10000 ? parsedDelay : null;
  }

  void onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();

    tab = searchHandler.currentTab;
    pageNumberController.text = currentDisplayPage.toString();
    delayController.text = 200.toString();
    pageNumberController.addListener(onInputChanged);
    delayController.addListener(onInputChanged);
  }

  @override
  void dispose() {
    pageNumberController.dispose();
    delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int total = tab.booruHandler.totalCount.value;
    final int possibleMaxPageNum = total > 0 && SX.limit.value > 0 ? (total / SX.limit.value).ceil() : 0;
    final targetPage = pageNumber;
    final bool isPageLoaded =
        targetPage != null && tab.booruHandler.filteredFetched.any((item) => item.fetchedPage == targetPage);

    return SettingsBottomSheet(
      title: Text(
        context.loc.pageChanger.title,
        style: const TextStyle(fontSize: 20),
      ),
      contentItems: [
        SettingsTextInput(
          title: context.loc.pageChanger.pageLabel,
          titleAsLabel: true,
          hintText: context.loc.pageChanger.pageLabel,
          onlyInput: true,
          controller: pageNumberController,
          autofocus: true,
          inputType: TextInputType.number,
          numberButtons: true,
          numberStep: 1,
          numberMin: 0,
          numberMax: double.infinity,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.loc.validationErrors.invalidNumber;
            } else if (int.tryParse(value) == null) {
              return context.loc.validationErrors.invalidNumericValue;
            } else if (int.parse(value) < 0) {
              return context.loc.validationErrors.invalidNumber;
            }
            return null;
          },
        ),
        Divider(
          color: Theme.of(context).dividerColor,
          thickness: 1,
          height: 1,
        ),
        SettingsTextInput(
          title: context.loc.pageChanger.delayBetweenLoadings,
          titleAsLabel: true,
          hintText: context.loc.pageChanger.delayInMs,
          onlyInput: true,
          controller: delayController,
          autofocus: false,
          inputType: TextInputType.number,
          numberButtons: true,
          numberStep: 100,
          numberMin: 100,
          numberMax: 10000,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.loc.validationErrors.invalidNumber;
            } else if (int.tryParse(value) == null) {
              return context.loc.validationErrors.invalidNumericValue;
            } else if (int.tryParse(value)! < 100 || int.tryParse(value)! > 10000) {
              return context.loc.validationErrors.invalidNumber;
            }
            return null;
          },
        ),
        IgnorePointer(
          ignoring: isPageLoaded,
          child: Opacity(
            opacity: isPageLoaded ? 0.66 : 1,
            child: SettingsToggle(
              value: isPageLoaded || scrollToFetchedPage,
              onChanged: (newValue) {
                setState(() {
                  scrollToFetchedPage = newValue;
                });
              },
              title: context.loc.pageChanger.scrollToFetchedPage,
              drawTopBorder: true,
            ),
          ),
        ),
        SettingsToggle(
          value: tab.savePageEnabled.value,
          onChanged: (newValue) async {
            setState(() {
              tab.savePageEnabled.value = newValue;
            });
            await searchHandler.backupTabs();
          },
          title: context.loc.pageChanger.saveViewedPage,
          leadingIcon: Icon(
            tab.savePageEnabled.value ? Icons.bookmark : Icons.bookmark_border,
            color: Theme.of(context).iconTheme.color,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SettingsButton(
                name: possibleMaxPageNum == 0
                    ? context.loc.pageChanger.currentPage(number: currentDisplayPage)
                    : context.loc.pageChanger.currentPageShort(number: currentDisplayPage),
                action: () {
                  pageNumberController.text = currentDisplayPage.toString();
                },
              ),
            ),
            //
            if (possibleMaxPageNum != 0)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  child: SettingsButton(
                    name: context.loc.pageChanger.possibleMaxPageShort(number: possibleMaxPageNum),
                    action: () {
                      pageNumberController.text = possibleMaxPageNum.toString();
                    },
                  ),
                ),
              ),
          ],
        ),
        Obx(
          () => searchHandler.isRunningAutoSearch.value
              ? SettingsButton(
                  name: context.loc.pageChanger.searchCurrentlyRunning,
                  icon: const PulseWidget(
                    child: Icon(
                      Icons.warning_amber,
                      color: Colors.yellow,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        //
        const SizedBox(height: 12),
        Column(
          mainAxisSize: .min,
          mainAxisAlignment: .spaceEvenly,
          crossAxisAlignment: .stretch,
          children: [
            Obx(
              () => searchHandler.isRunningAutoSearch.value
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text(context.loc.pageChanger.stopSearching),
                        onPressed: () {
                          searchHandler.isRunningAutoSearch.value = false;
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Obx(
              () => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                  label: Text(context.loc.pageChanger.jumpToPage),
                  onPressed: searchHandler.isRunningAutoSearch.value || !isCurrentTab || pageNumber == null
                      ? null
                      : () {
                          final targetPage = pageNumber;
                          if (isCurrentTab && targetPage != null) {
                            searchHandler.changeCurrentTabPageNumber(targetPage);
                            Navigator.of(context).pop();
                          }
                        },
                ),
              ),
            ),
            Obx(() {
              return ElevatedButton.icon(
                icon: Icon(
                  isPageLoaded ? Icons.swipe_up : Icons.search_rounded,
                ),
                label: Text(
                  isPageLoaded ? context.loc.pageChanger.scrollToPage : context.loc.pageChanger.searchUntilPage,
                ),
                onPressed:
                    searchHandler.isRunningAutoSearch.value || !isCurrentTab || pageNumber == null || delay == null
                    ? null
                    : () {
                        final targetPage = pageNumber;
                        final loadingDelay = delay;
                        if (isCurrentTab && targetPage != null && loadingDelay != null) {
                          searchHandler.executePageRestore(
                            tab,
                            targetPage,
                            (isPageLoaded || scrollToFetchedPage) ? .fetchAndScroll : .fetchNoScroll,
                            customDelay: loadingDelay,
                          );
                          Navigator.of(context).pop();
                        }
                      },
              );
            }),
          ],
        ),
      ],
    );
  }
}
