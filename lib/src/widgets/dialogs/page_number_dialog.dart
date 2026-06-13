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

  int get pageNumber {
    final int? parsedNumber = int.tryParse(pageNumberController.text);

    return parsedNumber != null ? parsedNumber - 1 : 0;
  }

  int get delay => int.tryParse(delayController.text) ?? 200;

  @override
  void initState() {
    super.initState();

    pageNumberController.text = searchHandler.currentScrollPage.value.toString();
    delayController.text = 200.toString();
  }

  @override
  void dispose() {
    pageNumberController.dispose();
    delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int total = searchHandler.currentBooruHandler.totalCount.value;
    final int possibleMaxPageNum = total != 0 ? (total / SX.limit.value).round() : 0;
    final bool isPageBelowCurrentLoaded = pageNumber <= searchHandler.currentBooruHandler.pageNum;

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
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.loc.validationErrors.invalidNumber;
            } else if (int.tryParse(value) == null) {
              return context.loc.validationErrors.invalidNumericValue;
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
          ignoring: isPageBelowCurrentLoaded,
          child: Opacity(
            opacity: isPageBelowCurrentLoaded ? 0.66 : 1,
            child: SettingsToggle(
              value: isPageBelowCurrentLoaded || scrollToFetchedPage,
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
          value: searchHandler.currentTab.savePageEnabled.value,
          onChanged: (newValue) {
            setState(() {
              searchHandler.currentTab.savePageEnabled.value = newValue;
            });
          },
          title: context.loc.pageChanger.saveViewedPage,
          leadingIcon: Icon(
            searchHandler.currentTab.savePageEnabled.value ? Icons.bookmark : Icons.bookmark_border,
            color: Theme.of(context).iconTheme.color,
          ),
        ),
        SettingsButton(
          name: context.loc.pageChanger.currentPage(number: searchHandler.currentBooruHandler.pageNum),
          action: () {
            pageNumberController.text = searchHandler.currentScrollPage.value.toString();
          },
        ),
        if (possibleMaxPageNum != 0)
          SettingsButton(
            name: context.loc.pageChanger.possibleMaxPage(number: possibleMaxPageNum),
            action: () {
              pageNumberController.text = possibleMaxPageNum.toString();
            },
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
                  onPressed: searchHandler.isRunningAutoSearch.value
                      ? null
                      : () {
                          if (pageNumberController.text.isNotEmpty) {
                            searchHandler.changeCurrentTabPageNumber(pageNumber);
                            Navigator.of(context).pop();
                          }
                        },
                ),
              ),
            ),
            Obx(() {
              return ElevatedButton.icon(
                icon: Icon(
                  isPageBelowCurrentLoaded ? Icons.swipe_up : Icons.search_rounded,
                ),
                label: Text(
                  isPageBelowCurrentLoaded
                      ? context.loc.pageChanger.scrollToPage
                      : context.loc.pageChanger.searchUntilPage,
                ),
                onPressed: searchHandler.isRunningAutoSearch.value
                    ? null
                    : () {
                        if (pageNumberController.text.isNotEmpty) {
                          searchHandler.executePageRestore(
                            searchHandler.currentTab,
                            pageNumber,
                            (isPageBelowCurrentLoaded || scrollToFetchedPage) ? .fetchAndScroll : .fetchNoScroll,
                            customDelay: delay,
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
