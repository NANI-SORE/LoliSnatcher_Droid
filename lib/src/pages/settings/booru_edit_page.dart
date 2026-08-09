import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/handlers/booru_connection_tester.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_form.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_form_controller.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_utils.dart';
import 'package:lolisnatcher/src/pages/settings/booru_overrides_page.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum BooruEditSection { details, overrides }

class BooruEdit extends StatefulWidget {
  const BooruEdit(
    this.booru, {
    this.initialSection = BooruEditSection.details,
    this.initialOverrideCategory,
    this.initialOverrideSettingKey,
    super.key,
  });

  final Booru booru;
  final BooruEditSection initialSection;
  final SettingCategory? initialOverrideCategory;
  final SettingKey? initialOverrideSettingKey;

  @override
  State<BooruEdit> createState() => _BooruEditState();
}

class _BooruEditState extends State<BooruEdit> with SingleTickerProviderStateMixin {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  late final BooruEditFormController formController;
  final connectionTester = const BooruConnectionTester();
  late final TabController sectionController;
  late final String overrideScopeName;
  late int activeSectionIndex;
  bool isTesting = false;

  bool get isAdding => widget.booru.name == 'New';

  void showSourceUnavailableMessage() {
    FlashElements.showSnackbar(
      context: context,
      key: 'sourceUnavailableCurrentSettings',
      isKeyUnique: true,
      title: Text(
        context.loc.settings.booru.sourceUnavailableCurrentSettings,
        style: const TextStyle(fontSize: 20),
      ),
      duration: null,
      tapToClose: false,
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
      actionsBuilder: (context, controller) {
        final colorScheme = Theme.of(context).colorScheme;

        return [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onPrimaryContainer,
              backgroundColor: colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              await launchUrlString(
                Constants.booruSourcesWikiURL,
                mode: LaunchMode.externalApplication,
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(context.loc.mediaPreviews.booruSourcesArticle),
          ),
        ];
      },
    );
  }

  @override
  void initState() {
    super.initState();
    formController = BooruEditFormController(widget.booru);
    overrideScopeName = isAdding ? '__new_booru_draft_${identityHashCode(this)}' : widget.booru.name ?? '';
    activeSectionIndex = widget.initialSection == BooruEditSection.overrides ? 1 : 0;
    sectionController = TabController(
      length: 2,
      initialIndex: activeSectionIndex,
      vsync: this,
    )..addListener(_onSectionChanged);
  }

  void _onSectionChanged() {
    if (activeSectionIndex == sectionController.index) return;
    setState(() => activeSectionIndex = sectionController.index);
  }

  @override
  void dispose() {
    sectionController
      ..removeListener(_onSectionChanged)
      ..dispose();
    if (isAdding) {
      final draftMascotPath = SX.drawerMascotPathOverride.state.getOverrideFor(overrideScopeName);
      if (draftMascotPath?.isNotEmpty == true) {
        final draftMascot = File(draftMascotPath!);
        unawaited(draftMascot.exists().then((exists) => exists ? draftMascot.delete() : null));
      }
      SettingsRegistry.instance.removeAllOverridesForBooru(overrideScopeName, save: false);
    }
    formController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: SettingsAppBar(
        title: context.loc.settings.booruEditor.title,
        bottom: TabBar(
          controller: sectionController,
          tabs: [
            Tab(icon: const Icon(Icons.edit_outlined), text: isAdding ? context.loc.add : context.loc.edit),
            Tab(icon: const Icon(Icons.tune), text: context.loc.settings.perBooruSettings),
          ],
        ),
      ),
      floatingActionButton: activeSectionIndex == 0
          ? GestureDetector(
              onLongPress: SX.isDebug.value ? () => _save(force: true) : null,
              child: FloatingActionButton.extended(
                onPressed: _save,
                icon: isTesting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(context.loc.settings.booruEditor.saveBooru),
              ),
            )
          : null,
      body: TabBarView(
        controller: sectionController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildDetailsTab(context),
          BooruOverridesEditor(
            booruName: overrideScopeName,
            displayName: isAdding && formController.name.text.trim().isNotEmpty
                ? formController.name.text.trim()
                : widget.booru.name,
            initialCategory: widget.initialOverrideCategory,
            initialSettingKey: widget.initialOverrideSettingKey,
            autosave: !isAdding,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(BuildContext context) {
    return BooruEditForm(
      initialBooru: widget.booru,
      controller: formController,
      onChanged: () => setState(() {}),
    );
  }

  Future<bool> _testConnection() async {
    formController.sanitizeName();
    setState(() {});

    if (formController.name.text.trim().isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.booruNameRequired,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }

    if (formController.url.text.trim().isEmpty) {
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          context.loc.settings.booruEditor.booruUrlRequired,
          style: const TextStyle(fontSize: 20),
        ),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }

    formController.url.text = normalizeBooruUrl(formController.url.text);

    if (!ContentPolicy.isBooruTypeAllowed(formController.selectedType)) {
      showSourceUnavailableMessage();
      return false;
    }

    // pre-select booru type for popular sites to avoid false positives for autodetect
    if (formController.selectedType.isAutodetect) {
      final knownType = knownBooruTypeForHost(normalizedBooruHost(formController.url.text));
      if (knownType != null) {
        formController.selectedType = knownType;
      }
      setState(() {});
    }

    formController.url.text = booruApiUrlFor(formController.url.text);
    if (!ContentPolicy.isBooruTypeAllowed(formController.selectedType)) {
      showSourceUnavailableMessage();
      return false;
    }

    formController.favicon.text = formController.favicon.text.trim().isEmpty
        ? booruFaviconUrlFor(formController.url.text)
        : formController.favicon.text;

    //Call the booru test
    final testBooru = formController.toBooru();
    if (!ContentPolicy.isBooruAllowed(testBooru)) {
      showSourceUnavailableMessage();
      return false;
    }

    isTesting = true;
    setState(() {});

    late final BooruConnectionTestResult testResults;
    try {
      testResults = await connectionTester.test(
        testBooru,
        formController.selectedType,
        hydrusFailureMessage: context.loc.settings.booruEditor.failedVerifyApiHydrus,
      );
    } finally {
      isTesting = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return false;
    final testBooruType = testResults.booruType;
    final String errorString = testResults.errorString?.isNotEmpty == true ? testResults.errorString! : '';

    // If a booru type is returned set the widget state
    if (testBooruType != null) {
      formController.markTestSuccessful(testBooruType);
      return true;
    } else {
      FlashElements.showSnackbar(
        context: context,
        duration: const Duration(seconds: 5),
        title: Text(
          context.loc.settings.booruEditor.testBooruFailedTitle,
          style: const TextStyle(fontSize: 20),
        ),
        content: Column(
          spacing: 12,
          children: [
            Text(
              context.loc.settings.booruEditor.testBooruFailedMsg,
              style: const TextStyle(fontSize: 16),
            ),
            if (errorString.trim().isNotEmpty)
              LoliHtml(
                '${context.loc.error}: $errorString',
              ),
          ],
        ),
        actionsBuilder: (context, controller) {
          return [
            if (errorString.trim().isNotEmpty)
              ElevatedButton.icon(
                onPressed: () => ClipboardUtils.copyTextToClipboard(errorString),
                icon: const Icon(Icons.copy),
                label: Text(context.loc.copyErrorText),
              ),
          ];
        },
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.red,
        sideColor: Colors.red,
      );
      return false;
    }
  }

  Future<void> _save({bool force = false}) async {
    formController.sanitizeName();
    setState(() {});

    if (force && !isAdding) {
      formController.testedType = formController.selectedType;
      if (formController.testedType!.isAutodetect) return;
    } else if (formController.testedType != null && !formController.hasCurrentSuccessfulTest) {
      formController.clearTestResult();
    }

    if (formController.testedType == null) {
      _showRunningTestMessage();
      if (!await _testConnection()) return;
      await FlashElements.dismissAll();
      if (!mounted) return;
    }

    final newBooru = _buildSaveCandidate();
    if (!ContentPolicy.isBooruAllowed(newBooru)) {
      showSourceUnavailableMessage();
      return;
    }

    final conflict = findBooruEditConflict(
      existingBoorus: settingsHandler.booruList,
      original: widget.booru,
      candidate: newBooru,
    );
    if (conflict != null) {
      _showConflictMessage(_conflictReason(conflict));
      return;
    }
    if (!await _confirmSave(newBooru) || !mounted) return;
    if (!await getStoragePermission() || !mounted) return;

    if (!await _persistBooru(newBooru) || !mounted) return;

    _showSavedMessage();
    _syncOpenTabs(newBooru);
    SettingsRegistry.instance.setCurrentBooru(searchHandler.currentBooruOrNull?.name);
    Navigator.of(context).pop(true);
  }

  void _showRunningTestMessage() {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        context.loc.settings.booruEditor.runningTest,
        style: const TextStyle(fontSize: 20),
      ),
      leadingIcon: Icons.refresh,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
    );
  }

  Booru _buildSaveCandidate() {
    final testedType = formController.testedType!;
    final policyBooru = formController.toBooru(type: testedType, tags: '');
    final safeTags = ContentPolicy.safeSearchTagsFor(
      policyBooru,
      formController.defaultTags.text,
    );
    return formController.toBooru(type: testedType, tags: safeTags);
  }

  String _conflictReason(BooruEditConflict conflict) {
    return switch (conflict) {
      BooruEditConflict.duplicate => context.loc.settings.booruEditor.booruConfigExistsError,
      BooruEditConflict.name => context.loc.settings.booruEditor.booruSameNameExistsError,
      BooruEditConflict.url => context.loc.settings.booruEditor.booruSameUrlExistsError,
    };
  }

  void _showConflictMessage(String reason) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(reason, style: const TextStyle(fontSize: 20)),
      content: Text(
        context.loc.settings.booruEditor.thisBooruConfigWontBeAdded,
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.red,
      sideColor: Colors.red,
    );
  }

  Future<bool> _confirmSave(Booru booru) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.loc.settings.booruEditor.booruConfigShouldSave),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BooruFavicon(
                      null,
                      customFaviconUrl: booru.faviconURL,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${booru.name} (${booru.baseURL})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  context.loc.settings.booruEditor.booruConfigSelectedType(
                    booruType: booru.type!.name,
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            actions: const [
              CancelButton(returnData: false),
              ConfirmButton(returnData: true),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _persistBooru(Booru newBooru) async {
    final registry = SettingsRegistry.instance;
    final oldBooruName = widget.booru.name;
    final newBooruName = newBooru.name;

    if (!isAdding) {
      final oldIndex = settingsHandler.booruList.indexWhere(
        (item) =>
            identical(item, widget.booru) || (item.name == widget.booru.name && item.baseURL == widget.booru.baseURL),
      );
      if (oldIndex >= 0) {
        settingsHandler.booruList.removeAt(oldIndex);
      }
      await settingsHandler.deleteBooru(widget.booru, removeOverrides: false);
    }

    if (oldBooruName != null && newBooruName != null && !isAdding && oldBooruName != newBooruName) {
      registry.copyOverrides(oldBooruName, newBooruName, save: false);
      registry.removeAllOverridesForBooru(oldBooruName, save: false);
    }

    final committingDraftOverrides = isAdding && newBooruName != null;
    if (committingDraftOverrides) {
      registry.copyOverrides(overrideScopeName, newBooruName, save: false);
    }

    // New-booru overrides remain only under [overrideScopeName] until the
    // connection test and confirmation gates above have both succeeded.
    try {
      if (await settingsHandler.saveBooru(newBooru, onlySave: true) != true) {
        if (committingDraftOverrides) {
          registry.removeAllOverridesForBooru(newBooruName, save: false);
        }
        return false;
      }
    } catch (_) {
      if (committingDraftOverrides) {
        registry.removeAllOverridesForBooru(newBooruName, save: false);
      }
      rethrow;
    }
    if (isAdding) {
      registry.removeAllOverridesForBooru(overrideScopeName, save: false);
    }
    await settingsHandler.loadBoorus();
    return true;
  }

  void _showSavedMessage() {
    FlashElements.showSnackbar(
      context: context,
      title: Text(
        context.loc.settings.booruEditor.booruConfigSaved,
        style: const TextStyle(fontSize: 20),
      ),
      content: widget.booru.name == 'New'
          ? const SizedBox(height: 20)
          : Text(
              context.loc.settings.booruEditor.existingTabsNeedReload,
              style: const TextStyle(fontSize: 16),
            ),
      leadingIcon: Icons.done,
      leadingIconColor: Colors.green,
      sideColor: Colors.green,
    );
  }

  void _syncOpenTabs(Booru newBooru) {
    if (searchHandler.tabs.isEmpty) {
      searchHandler.addTabByString(SX.defTags.value, customBooru: newBooru);
      unawaited(searchHandler.runSearch());
    }

    for (final tab in searchHandler.tabs) {
      if (tab.selectedBooru.value.type == newBooru.type && tab.selectedBooru.value.baseURL == newBooru.baseURL) {
        tab.selectedBooru.value = newBooru;
      }
    }

    unawaited(
      Future.delayed(const Duration(seconds: 1)).then((_) {
        searchHandler.rootRestate?.call();
      }),
    );
  }
}
