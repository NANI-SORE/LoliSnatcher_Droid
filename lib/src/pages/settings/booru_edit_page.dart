import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/handlers/booru_connection_tester.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
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
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum BooruEditSection { details, overrides }

enum BooruEditMode { add, edit }

class BooruEdit extends StatefulWidget {
  BooruEdit.add({
    Booru? initialBooru,
    this.initialSection = BooruEditSection.details,
    this.initialOverrideCategory,
    this.initialOverrideSettingKey,
    super.key,
  }) : booru = initialBooru ?? Booru('', null, '', '', ''),
       mode = BooruEditMode.add;

  const BooruEdit.edit(
    this.booru, {
    this.initialSection = BooruEditSection.details,
    this.initialOverrideCategory,
    this.initialOverrideSettingKey,
    super.key,
  }) : mode = BooruEditMode.edit;

  final Booru booru;
  final BooruEditMode mode;
  final BooruEditSection initialSection;
  final SettingCategory? initialOverrideCategory;
  final SettingKey? initialOverrideSettingKey;

  @override
  State<BooruEdit> createState() => _BooruEditState();
}

class _BooruEditState extends State<BooruEdit> with SingleTickerProviderStateMixin {
  static const _testingSnackbarKey = 'booruConnectionTest';
  static int _nextDraftId = 0;

  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;

  late final BooruEditFormController formController;
  final connectionTester = const BooruConnectionTester();
  late final TabController sectionController;
  late final String overrideScopeName;
  late int activeSectionIndex;
  bool isTesting = false;
  bool isSaving = false;

  bool get isBusy => isTesting || isSaving;

  bool get isAdding => widget.mode == BooruEditMode.add;

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
    formController = BooruEditFormController(widget.booru, trustInitialConnection: !isAdding);
    overrideScopeName = isAdding ? '__new_booru_draft_${_nextDraftId++}' : widget.booru.name ?? '';
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
      floatingActionButton: (activeSectionIndex == 0 || isAdding)
          ? GestureDetector(
              onLongPress: SX.isDebug.value && !isBusy ? () => _save(force: true) : null,
              child: FloatingActionButton.extended(
                onPressed: isBusy ? null : _save,
                icon: isBusy
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
      body: IgnorePointer(
        ignoring: isBusy,
        child: TabBarView(
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

  void _showDetailsForError() {
    if (sectionController.index != 0) {
      sectionController.animateTo(0);
    }
  }

  Future<bool> _testConnection({bool skipNetwork = false}) async {
    formController.sanitizeName();
    setState(() {});

    if (formController.name.text.trim().isEmpty) {
      _showDetailsForError();
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
      _showDetailsForError();
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
      _showDetailsForError();
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
      _showDetailsForError();
      showSourceUnavailableMessage();
      return false;
    }

    formController.favicon.text = formController.favicon.text.trim().isEmpty
        ? booruFaviconUrlFor(formController.url.text)
        : formController.favicon.text;

    //Call the booru test
    final testBooru = formController.toBooru();
    if (!ContentPolicy.isBooruAllowed(testBooru)) {
      _showDetailsForError();
      showSourceUnavailableMessage();
      return false;
    }

    if (skipNetwork) {
      if (formController.selectedType.isAutodetect) {
        _showDetailsForError();
        return false;
      }
      formController.markTestSuccessful(formController.selectedType);
      return true;
    }

    final testedSignature = formController.testSignature();

    isTesting = true;
    setState(() {});
    _showRunningTestMessage();

    BooruConnectionTestResult? testResults;
    try {
      testResults = await connectionTester.test(
        testBooru,
        formController.selectedType,
        hydrusFailureMessage: context.loc.settings.booruEditor.failedVerifyApiHydrus,
      );
    } catch (e, s) {
      Logger.Inst().log(
        'Booru connection test failed: $e',
        'BooruEdit',
        '_testConnection',
        LogTypes.exception,
        s: s,
      );
      if (mounted) {
        _showDetailsForError();
        _showTestFailure(e.toString());
      }
      return false;
    } finally {
      isTesting = false;
      await FlashElements.dismissKey(_testingSnackbarKey);
      if (mounted) setState(() {});
    }
    if (!mounted) return false;
    final testBooruType = testResults.booruType;
    if (testBooruType != null && !formController.markTestSuccessfulIfCurrent(testBooruType, testedSignature)) {
      _showDetailsForError();
      FlashElements.showSnackbar(
        context: context,
        title: Text(context.loc.settings.booruEditor.connectionSettingsChanged),
        leadingIcon: Icons.warning_amber,
        leadingIconColor: Colors.orange,
        sideColor: Colors.orange,
      );
      return false;
    }

    final errorString = testResults.errorString?.isNotEmpty == true ? testResults.errorString! : '';

    // If a booru type is returned set the widget state
    if (testBooruType != null) {
      return true;
    }

    _showDetailsForError();
    _showTestFailure(errorString);
    return false;
  }

  void _showTestFailure(String errorString) {
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
          if (errorString.trim().isNotEmpty) LoliHtml('${context.loc.error}: $errorString'),
        ],
      ),
      actionsBuilder: (context, controller) => [
        if (errorString.trim().isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => ClipboardUtils.copyTextToClipboard(errorString),
            icon: const Icon(Icons.copy),
            label: Text(context.loc.copyErrorText),
          ),
      ],
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.red,
      sideColor: Colors.red,
    );
  }

  Future<void> _save({bool force = false}) async {
    if (isBusy) return;
    isSaving = true;
    setState(() {});

    try {
      await _performSave(force: force);
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to save booru: $e',
        'BooruEdit',
        '_save',
        LogTypes.exception,
        s: s,
      );
      if (mounted) {
        _showDetailsForError();
        FlashElements.showSnackbar(
          context: context,
          title: Text(context.loc.settings.booruEditor.saveFailed),
          content: Text(e.toString()),
          leadingIcon: Icons.error_outline,
          leadingIconColor: Colors.red,
          sideColor: Colors.red,
        );
      }
    } finally {
      isSaving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _performSave({required bool force}) async {
    formController.sanitizeName();
    setState(() {});

    if (formController.testedType != null && !formController.hasCurrentSuccessfulTest) {
      formController.clearTestResult();
    }

    if (formController.testedType == null) {
      if (!await _testConnection(skipNetwork: force && !isAdding)) return;
      if (!mounted) return;
    }

    final newBooru = _buildSaveCandidate();
    if (!ContentPolicy.isBooruAllowed(newBooru)) {
      _showDetailsForError();
      showSourceUnavailableMessage();
      return;
    }

    final conflict = findBooruEditConflict(
      existingBoorus: settingsHandler.booruList,
      original: isAdding ? null : widget.booru,
      candidate: newBooru,
    );
    if (conflict != null) {
      _showDetailsForError();
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
      key: _testingSnackbarKey,
      isKeyUnique: true,
      duration: null,
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
          builder: (context) => SettingsDialog(
            title: Row(
              children: [
                Icon(
                  Icons.save_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(context.loc.settings.booruEditor.booruConfigShouldSave),
                ),
              ],
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            borderRadius: BorderRadius.circular(20),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _BooruSaveSummary(
                name: booru.name ?? '',
                url: booru.baseURL ?? '',
                type: booru.type?.alias ?? '',
                faviconUrl: booru.faviconURL,
                urlLabel: context.loc.settings.booruEditor.booruUrl,
                typeLabel: context.loc.type,
              ),
            ),
            actionButtons: [
              const CancelButton(
                withIcon: true,
                returnData: false,
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.save_outlined),
                label: Text(context.loc.settings.booruEditor.saveBooru),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _persistBooru(Booru newBooru) async {
    final registry = SettingsRegistry.instance;
    final newBooruName = newBooru.name;

    if (!isAdding) {
      return settingsHandler.replaceBooru(widget.booru, newBooru);
    }

    final committingDraftOverrides = newBooruName != null;
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
    registry.removeAllOverridesForBooru(overrideScopeName, save: false);
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
      content: isAdding
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
      final selected = tab.selectedBooru.value;
      final matchesEditedBooru =
          !isAdding &&
          (identical(selected, widget.booru) ||
              (selected.name == widget.booru.name && selected.baseURL == widget.booru.baseURL));
      final matchesAddedBooru = isAdding && selected.type == newBooru.type && selected.baseURL == newBooru.baseURL;
      if (matchesEditedBooru || matchesAddedBooru) {
        tab.selectedBooru.value = newBooru;
      }
      unawaited(searchHandler.backupTabs());
    }

    unawaited(
      Future.delayed(const Duration(seconds: 1)).then((_) {
        searchHandler.rootRestate?.call();
      }),
    );
  }
}

class _BooruSaveSummary extends StatelessWidget {
  const _BooruSaveSummary({
    required this.name,
    required this.url,
    required this.type,
    required this.urlLabel,
    required this.typeLabel,
    this.faviconUrl,
  });

  final String name;
  final String url;
  final String type;
  final String urlLabel;
  final String typeLabel;
  final String? faviconUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: BooruFavicon(
                    null,
                    customFaviconUrl: faviconUrl,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BooruSaveDetail(
                  icon: Icons.link_rounded,
                  label: urlLabel,
                  value: url,
                ),
                const SizedBox(height: 14),
                _BooruSaveDetail(
                  icon: Icons.category_outlined,
                  label: typeLabel,
                  value: type,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BooruSaveDetail extends StatelessWidget {
  const _BooruSaveDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: colors.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                softWrap: true,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
