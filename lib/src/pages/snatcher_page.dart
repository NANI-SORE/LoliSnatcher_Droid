import 'package:lolisnatcher/src/downloads/download_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
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

class _SnatcherPageState extends State<SnatcherPage> {
  final handler = SnatchHandler.instance;
  final query = TextEditingController();
  final amount = TextEditingController();
  final delay = TextEditingController();
  final start = TextEditingController(text: '1');
  final presetName = TextEditingController();
  late Booru source;
  final Set<String> additional = {};
  List<Map<String, dynamic>> presets = [];
  String quality = 'Original', destination = '', error = '';
  bool overwrite = false, busy = false;
  String? presetId;
  bool get supportsStart =>
      ![source, ..._additionalSources].any((s) => s.type?.isWorld == true || s.type?.isHydrus == true);
  List<Booru> get _additionalSources =>
      SettingsHandler.instance.booruList.where((s) => additional.contains(s.name) && s.name != source.name).toList();
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
    amount.text = SX.limit.valueForBooru(source.name).toString();
    delay.text = SX.snatchCooldown.valueForBooru(source.name).clamp(1000, 3600000).toString();
    quality = SX.snatchMode.valueForBooru(source.name).isSample ? 'Sample' : 'Original';
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in [query, amount, delay, start, presetName]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final saved = await (await handler.store).presets();
      final configuration = await DownloadConfiguration.capture();
      final target = downloadMap(configuration.policy(source.name ?? '')['destination'])['path'] as String? ?? '';
      if (mounted) {
        setState(() {
          presets = saved;
          destination = target;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = downloadText('settingsError'));
    }
  }

  Map<String, dynamic> _preset() => {
    'query': query.text,
    'amount': amount.text,
    'delay': delay.text,
    'startPage': supportsStart ? start.text : '1',
    'sourceNames': [source.name, ...additional],
    'quality': quality,
    'overwrite': overwrite,
  };
  void _selectPreset(String? id) {
    final row = presets.where((e) => e['id'] == id).firstOrNull;
    if (row == null) return;
    final data = downloadMap(row['payload']);
    final names = List<String>.from(data['sourceNames'] as List? ?? []);
    final match = SettingsHandler.instance.booruList.where((s) => s.name == names.firstOrNull).firstOrNull;
    setState(() {
      presetId = id;
      presetName.text = row['name'] as String;
      query.text = data['query'] as String? ?? '';
      amount.text = data['amount'] as String? ?? '100';
      delay.text = data['delay'] as String? ?? '1000';
      start.text = data['startPage'] as String? ?? '1';
      quality = data['quality'] as String? ?? 'Original';
      overwrite = data['overwrite'] == true;
      additional
        ..clear()
        ..addAll(names.skip(1));
      if (match != null) {
        source = match;
        error = '';
      } else {
        error = downloadText('missingPresetSource');
      }
    });
    unawaited(_load());
  }

  Future<void> _savePreset() async {
    final name = presetName.text.trim();
    if (name.isEmpty) {
      setState(() => error = downloadText('presetNameRequired'));
      return;
    }
    try {
      final id = presetId ?? const Uuid().v4();
      await handler.savePreset(id, name, _preset());
      if (mounted) {
        setState(() {
          presetId = id;
          error = '';
        });
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => error = downloadText('presetError'));
    }
  }

  Future<void> _enqueue() async {
    final count = int.tryParse(amount.text), first = int.tryParse(start.text), milliseconds = int.tryParse(delay.text);
    if (count == null ||
        count < 1 ||
        supportsStart && (first == null || first < 1) ||
        milliseconds == null ||
        milliseconds < 0) {
      setState(() => error = downloadText('invalidForm'));
      return;
    }
    if (source.name?.isNotEmpty != true ||
        additional.any((name) => !SettingsHandler.instance.booruList.any((s) => s.name == name))) {
      setState(() => error = downloadText('sourceRequired'));
      return;
    }
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
        query.text,
        amount.text,
        milliseconds,
        source,
        sources: [source, ..._additionalSources],
        startPage: supportsStart ? first! : 1,
        quality: quality,
        overwrite: overwrite,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => error = downloadText('batchError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _number(TextEditingController controller, String label, String hint) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SettingsAppBar(title: context.loc.snatcher.title),
    body: AbsorbPointer(
      absorbing: busy,
      child: ListView(
        children: [
          if (busy) const LinearProgressIndicator(),
          SettingsBooruDropdown(
            value: source,
            title: context.loc.booru,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                source = value;
                start.text = '1';
                error = '';
              });
              unawaited(_load());
            },
          ),
          ExpansionTile(
            title: Text(downloadText('additionalSources')),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final candidate in SettingsHandler.instance.booruList.where((s) => s.name != source.name))
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
              ),
            ],
          ),
          TagSearchBox(
            controller: query,
            title: context.loc.tags,
            hintText: context.loc.snatcher.enterTags,
            booru: source,
            allowMultipleTags: true,
            clearable: true,
          ),
          _number(amount, context.loc.snatcher.amount, downloadText('amountHint')),
          if (supportsStart) _number(start, downloadText('startingPage'), downloadText('pageHint')),
          ListTile(
            title: Text(downloadText('destination')),
            subtitle: Text(destination.isEmpty ? downloadText('loading') : destination),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey(quality),
              initialValue: quality,
              decoration: InputDecoration(labelText: downloadText('quality')),
              items: [
                DropdownMenuItem(value: 'Original', child: Text(downloadText('original'))),
                DropdownMenuItem(value: 'Sample', child: Text(downloadText('sample'))),
              ],
              onChanged: (value) => setState(() => quality = value ?? 'Original'),
            ),
          ),
          SwitchListTile(
            title: Text(downloadText('replace')),
            subtitle: Text(downloadText('skipHint')),
            value: overwrite,
            onChanged: (value) => setState(() => overwrite = value),
          ),
          ExpansionTile(
            title: Text(downloadText('advanced')),
            children: [
              _number(delay, context.loc.snatcher.delayInMs, downloadText('delayHint')),
            ],
          ),
          ExpansionTile(
            title: Text(downloadText('presets')),
            initiallyExpanded: presets.isNotEmpty,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: presets.any((e) => e['id'] == presetId) ? presetId : null,
                  hint: Text(downloadText('choosePreset')),
                  onChanged: _selectPreset,
                  items: presets
                      .map((e) => DropdownMenuItem(value: e['id'] as String, child: Text(e['name'] as String)))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: presetName,
                  decoration: InputDecoration(
                    labelText: downloadText('presetName'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _savePreset,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(downloadText('savePreset')),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      presetId = null;
                      presetName.clear();
                    }),
                    child: Text(downloadText('newPreset')),
                  ),
                  if (presetId != null)
                    TextButton(
                      onPressed: () async {
                        await handler.deletePreset(presetId!);
                        if (mounted) {
                          setState(() {
                            presetId = null;
                            presetName.clear();
                          });
                        }
                        await _load();
                      },
                      child: Text(downloadText('deletePreset')),
                    ),
                ],
              ),
            ],
          ),
          Padding(padding: const EdgeInsets.all(16), child: Text(downloadText('durabilityHint'))),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _enqueue,
              icon: const Icon(Icons.download),
              label: Text(context.loc.snatcher.snatchFiles),
            ),
          ),
        ],
      ),
    ),
  );
}
