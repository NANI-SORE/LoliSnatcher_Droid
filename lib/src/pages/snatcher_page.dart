import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_localizations.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';

class SnatcherPage extends StatefulWidget {
  const SnatcherPage({super.key});
  @override
  State<SnatcherPage> createState() => _SnatcherPageState();
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.initialName});
  final String initialName;
  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final name = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(downloadText('savePreset')),
    content: TextField(
      controller: name,
      autofocus: true,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(labelText: downloadText('presetName')),
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
      },
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(downloadText('cancel'))),
      ValueListenableBuilder(
        valueListenable: name,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : () => Navigator.pop(context, value.text.trim()),
          child: Text(downloadText('save')),
        ),
      ),
    ],
  );
}

class _SnatcherPageState extends State<SnatcherPage> {
  final handler = SnatchHandler.instance;
  final _form = GlobalKey<FormState>();
  final _options = ExpansibleController();
  final query = TextEditingController(), amount = TextEditingController(), delay = TextEditingController();
  final start = TextEditingController(text: '1');
  late Booru source;
  final Set<String> additional = {};
  List<Map<String, dynamic>> presets = [];
  String quality = 'Original', destination = '', error = '', presetName = '';
  bool overwrite = false, busy = false, _missingSource = false;
  bool _qualityEdited = false, _delayEdited = false, _amountEdited = false;
  String? presetId;
  int _loadGeneration = 0;

  List<Booru> get _additionalSources =>
      SettingsHandler.instance.booruList.where((s) => additional.contains(s.name) && s.name != source.name).toList();
  Iterable<String> get _missingAdditional =>
      additional.where((name) => !SettingsHandler.instance.booruList.any((s) => s.name == name));
  bool get supportsStart =>
      ![source, ..._additionalSources].any((s) => s.type?.isWorld == true || s.type?.isHydrus == true);
  void _sourceDefaults() {
    if (!_amountEdited) amount.text = SX.limit.valueForBooru(source.name).toString();
    if (!_delayEdited) {
      delay.text = (SX.snatchCooldown.valueForBooru(source.name).clamp(1000, 3600000) / 1000).toString();
    }
    if (!_qualityEdited) quality = SX.snatchMode.valueForBooru(source.name).isSample ? 'Sample' : 'Original';
  }

  @override
  void initState() {
    super.initState();
    final search = SearchHandler.instance;
    final available = SettingsHandler.instance.booruList;
    source =
        available.where((s) => s.name == search.currentBooruOrNull?.name).firstOrNull ??
        available.firstOrNull ??
        Booru.unknown();
    query.text = search.currentTabOrNull?.tags ?? '';
    _sourceDefaults();
    unawaited(_load());
  }

  @override
  void dispose() {
    _options.dispose();
    for (final controller in [query, amount, delay, start]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final saved = await (await handler.store).presets();
      final target = Platform.isIOS || SX.extPathOverride.value.isEmpty
          ? await ServiceHandler.getPicturesDir()
          : SX.extPathOverride.value;
      if (mounted && generation == _loadGeneration) {
        setState(() {
          presets = saved;
          destination = target;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) setState(() => error = downloadText('settingsError'));
    }
  }

  int get _delayMs => ((double.tryParse(delay.text) ?? 1) * 1000).round().clamp(1000, 3600000);
  Map<String, dynamic> _preset() => {
    'query': query.text,
    'amount': amount.text,
    'delay': _delayMs.toString(),
    'startPage': supportsStart ? start.text : '1',
    'sourceNames': [source.name, ...additional],
    'quality': quality,
    'overwrite': overwrite,
  };
  void _selectPreset(String id) {
    final row = presets.where((e) => e['id'] == id).firstOrNull;
    if (row == null) return;
    final data = downloadMap(row['payload']);
    final names = List<String>.from(data['sourceNames'] as List? ?? []);
    final match = SettingsHandler.instance.booruList.where((s) => s.name == names.firstOrNull).firstOrNull;
    setState(() {
      presetId = id;
      presetName = row['name'] as String;
      query.text = data['query'] as String? ?? '';
      amount.text = data['amount']?.toString() ?? '100';
      delay.text = ((double.tryParse(data['delay']?.toString() ?? '') ?? 1000).clamp(1000, 3600000) / 1000).toString();
      start.text = data['startPage']?.toString() ?? '1';
      quality = data['quality'] == 'Sample' ? 'Sample' : 'Original';
      overwrite = data['overwrite'] == true;
      _qualityEdited = _delayEdited = _amountEdited = true;
      additional
        ..clear()
        ..addAll(names.skip(1));
      _missingSource = match == null;
      if (match != null) source = match;
      error = _missingSource ? downloadText('missingPresetSource') : '';
    });
    unawaited(_load());
  }

  Future<void> _savePreset({bool asNew = false}) async {
    if (!_validate()) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _PresetNameDialog(initialName: asNew ? '' : presetName),
    );
    if (!mounted || chosen == null) return;
    setState(() => busy = true);
    try {
      final id = asNew ? const Uuid().v4() : presetId ?? const Uuid().v4();
      await handler.savePreset(id, chosen, _preset());
      if (mounted) {
        setState(() {
          presetId = id;
          presetName = chosen;
          error = '';
        });
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = downloadText('presetError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _presetAction(String value) async {
    if (value == '_save' || value == '_new') {
      await _savePreset(asNew: value == '_new');
      return;
    }
    if (value != '_delete') {
      _selectPreset(value);
      return;
    }
    if (presetId == null) return;
    setState(() => busy = true);
    try {
      await handler.deletePreset(presetId!);
      if (mounted) {
        setState(() {
          presetId = null;
          presetName = '';
        });
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = downloadText('presetError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _validate() {
    if (_missingSource || !SettingsHandler.instance.booruList.any((s) => s.name == source.name)) {
      setState(() => error = downloadText('sourceRequired'));
      return false;
    }
    if (_missingAdditional.isNotEmpty) {
      _options.expand();
      setState(() => error = downloadText('missingPresetSource'));
      return false;
    }
    final first = int.tryParse(start.text);
    final count = int.tryParse(amount.text);
    final seconds = double.tryParse(delay.text);
    final validOptions =
        (!supportsStart || first != null && first > 0) &&
        seconds != null &&
        seconds.isFinite &&
        seconds >= 1 &&
        seconds <= 3600;
    if (!validOptions) _options.expand();
    return (_form.currentState?.validate() ?? false) && count != null && count > 0 && validOptions;
  }

  Future<void> _enqueue() async {
    if (busy || !_validate()) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (!await setPermissions()) {
        if (mounted) setState(() => error = downloadText('storageRequired'));
        return;
      }
      await handler.searchSnatch(
        query.text.trim(),
        amount.text,
        _delayMs,
        source,
        sources: [source, ..._additionalSources],
        startPage: supportsStart ? int.parse(start.text) : 1,
        quality: quality,
        overwrite: overwrite,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(downloadText('batchAdded'))));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => error = downloadText('batchError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _number(
    TextEditingController controller,
    String label, {
    bool seconds = false,
    String Function()? resetText,
    ValueChanged<String>? onChanged,
  }) => SettingsTextInput(
    controller: controller,
    title: label,
    onlyInput: true,
    titleAsLabel: true,
    margin: EdgeInsets.zero,
    resetText: resetText ?? () => '1',
    numberButtons: true,
    alwaysShowNumberButtons: true,
    numberMin: 1,
    numberMax: seconds ? 3600 : 2147483647,
    onChanged: onChanged,
    inputType: TextInputType.numberWithOptions(decimal: seconds),
    inputFormatters: [
      if (seconds) FilteringTextInputFormatter.allow(RegExp('[0-9.]')) else FilteringTextInputFormatter.digitsOnly,
    ],
    validator: (text) {
      final value = seconds ? double.tryParse(text ?? '') : int.tryParse(text ?? '');
      if (value == null || !value.isFinite || value < 1) return downloadText('positiveNumber');
      if (seconds && value > 3600) return downloadText('delayMaximum');
      return null;
    },
  );
  String get _destinationName {
    if (destination.isEmpty) return downloadText('loading');
    if (Platform.isIOS) return downloadText('filesAndPhotos');
    if (destination.startsWith('content://')) {
      final segment = Uri.tryParse(destination)?.pathSegments.lastOrNull ?? '';
      return segment.contains(':') ? segment.substring(segment.indexOf(':') + 1) : segment;
    }
    return p.basename(p.normalize(destination));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SettingsAppBar(
      title: context.loc.snatcher.title,
      actions: [
        PopupMenuButton<String>(
          enabled: !busy,
          tooltip: downloadText('presets'),
          icon: const Icon(Icons.bookmarks_outlined),
          onSelected: _presetAction,
          itemBuilder: (_) => [
            for (final preset in presets)
              CheckedPopupMenuItem(
                value: preset['id'] as String,
                checked: preset['id'] == presetId,
                child: Text(preset['name'] as String),
              ),
            if (presets.isNotEmpty) const PopupMenuDivider(),
            PopupMenuItem(value: '_save', child: Text(downloadText(presetId == null ? 'savePreset' : 'updatePreset'))),
            if (presetId != null) ...[
              PopupMenuItem(value: '_new', child: Text(downloadText('saveAsPreset'))),
              PopupMenuItem(value: '_delete', child: Text(downloadText('deletePreset'))),
            ],
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: AbsorbPointer(
          absorbing: busy,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (presetId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.bookmark_outline, size: 16),
                      label: Text(presetName),
                      onDeleted: () => setState(() {
                        presetId = null;
                        presetName = '';
                      }),
                    ),
                  ),
                ),
              SettingsBooruDropdown(
                value: _missingSource ? null : source,
                title: context.loc.booru,
                drawBottomBorder: false,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    source = value;
                    additional.remove(value.name);
                    start.text = '1';
                    _missingSource = false;
                    error = '';
                    _sourceDefaults();
                  });
                  unawaited(_load());
                },
              ),
              TagSearchBox(
                controller: query,
                title: context.loc.tags,
                hintText: context.loc.snatcher.enterTags,
                booru: source,
                allowMultipleTags: true,
                clearable: true,
                drawBottomBorder: false,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _number(
                  amount,
                  downloadText('postCount'),
                  resetText: () => SX.limit.valueForBooru(source.name).toString(),
                  onChanged: (_) => _amountEdited = true,
                ),
              ),
              ExpansionTile(
                controller: _options,
                maintainState: true,
                title: Text(downloadText('options')),
                subtitle: Text(
                  '${downloadText(quality.toLowerCase())} · ${downloadText(overwrite ? 'replace' : 'skipExisting')}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(quality),
                      initialValue: quality,
                      decoration: InputDecoration(
                        labelText: downloadText('quality'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(value: 'Original', child: Text(downloadText('original'))),
                        DropdownMenuItem(value: 'Sample', child: Text(downloadText('sample'))),
                      ],
                      onChanged: (value) => setState(() {
                        quality = value ?? 'Original';
                        _qualityEdited = true;
                      }),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(downloadText('replace')),
                    value: overwrite,
                    onChanged: (value) => setState(() => overwrite = value),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      spacing: 12,
                      children: [
                        if (supportsStart) _number(start, downloadText('startingPage')),
                        _number(
                          delay,
                          downloadText('delaySeconds'),
                          seconds: true,
                          resetText: () =>
                              (SX.snatchCooldown.valueForBooru(source.name).clamp(1000, 3600000) / 1000).toString(),
                          onChanged: (_) => _delayEdited = true,
                        ),
                      ],
                    ),
                  ),
                  if (SettingsHandler.instance.booruList.length > 1 || _missingAdditional.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(downloadText('additionalSources'), style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final name in _missingAdditional)
                                InputChip(
                                  avatar: const Icon(Icons.error_outline, size: 18),
                                  label: Text(name),
                                  tooltip: downloadText('missingPresetSource'),
                                  onDeleted: () => setState(() {
                                    additional.remove(name);
                                    error = '';
                                  }),
                                ),
                              for (final candidate in SettingsHandler.instance.booruList.where(
                                (s) => s.name != source.name,
                              ))
                                FilterChip(
                                  label: Text(candidate.name ?? ''),
                                  selected: additional.contains(candidate.name),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      additional.add(candidate.name ?? '');
                                    } else {
                                      additional.remove(candidate.name);
                                    }
                                    start.text = '1';
                                  }),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_destinationName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(downloadText('destination')),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(downloadText('destination')),
                    content: SelectableText(destination),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(downloadText('close')))],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _enqueue,
                icon: busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                label: Text(downloadText(busy ? 'adding' : 'addToQueue')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
