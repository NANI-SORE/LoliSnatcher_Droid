import 'package:flutter/material.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

import 'package:lolisnatcher/src/data/settings/tab_page_restore_mode.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/tabs/tab_row.dart';

class TabRestoreDialogResult {
  const TabRestoreDialogResult({
    required this.selectedMode,
    required this.rememberChoice,
    required this.delay,
  });

  final TabPageRestoreMode selectedMode;
  final bool rememberChoice;
  final int delay;
}

class TabRestoreDialog extends StatefulWidget {
  const TabRestoreDialog({
    required this.pageNum,
    required this.tab,
    super.key,
  });

  final int pageNum;
  final SearchTab tab;

  @override
  State<TabRestoreDialog> createState() => _TabRestoreDialogState();
}

class _TabRestoreDialogState extends State<TabRestoreDialog> {
  TabPageRestoreMode selectedMode = .fetchOnlyPage;
  bool rememberChoice = false;
  final delayController = TextEditingController();

  int get delay => int.tryParse(delayController.text) ?? 200;

  @override
  void initState() {
    super.initState();

    delayController.text = 200.toString();
  }

  @override
  void dispose() {
    delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contentItems = <Widget>[
      Text(
        context.loc.pageChanger.restoreLastViewedPage,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      TabRow(tab: widget.tab),
      const SizedBox(height: 12),
      Text(
        context.loc.pageChanger.browsedToPageLastTime(page: widget.pageNum),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      RadioGroup<TabPageRestoreMode>(
        groupValue: selectedMode,
        onChanged: (value) {
          setState(() {
            selectedMode = value ?? selectedMode;
          });
        },
        child: Column(
          children: TabPageRestoreMode.selectableValues
              .map(
                (mode) => RadioListTile<TabPageRestoreMode>(
                  value: mode,
                  title: Text(mode.locName),
                  subtitle: selectedMode == mode && widget.pageNum > 10
                      ? switch (mode) {
                          .fetchNoScroll || .fetchAndScroll => Text(
                            context.loc.pageChanger.tooManyPagesToRestoreWarning,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          _ => null,
                        }
                      : null,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Theme.of(context).colorScheme.secondary,
                  dense: true,
                ),
              )
              .toList(),
        ),
      ),
      if (selectedMode.isFetchMultiplePages)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SettingsTextInput(
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
        ),
      const SizedBox(height: 8),
      CheckboxListTile(
        value: rememberChoice,
        onChanged: (value) {
          setState(() {
            rememberChoice = value ?? false;
          });
        },
        title: Text(context.loc.pageChanger.rememberMyChoice),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: .end,
        spacing: 8,
        children: [
          CancelButton(
            withIcon: true,
            returnData: TabRestoreDialogResult(
              selectedMode: .ignore,
              rememberChoice: false,
              delay: delay,
            ),
          ),
          ConfirmButton(
            label: context.loc.tabs.filters.apply,
            returnData: TabRestoreDialogResult(
              selectedMode: selectedMode,
              rememberChoice: rememberChoice,
              delay: delay,
            ),
          ),
        ],
      ),
    ];

    return PopScope(
      canPop: false,
      child: SettingsDialog(
        scrollable: false,
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width,
          child: SingleChildScrollView(
            child: ListBody(children: contentItems),
          ),
        ),
      ),
    );
  }
}
