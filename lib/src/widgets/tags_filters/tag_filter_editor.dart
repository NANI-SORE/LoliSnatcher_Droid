import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/data/tag_filter_query.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_handler.dart';
import 'package:lolisnatcher/src/widgets/common/loli_dropdown.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_suspension_sheet.dart';

enum _MarkerEditorMode { predefined, custom }

bool _isEmojiMarkerText(String? value) =>
    value != null && RegExp(r'[\u{1F000}-\u{1FAFF}\u{FE0F}\u{20E3}]', unicode: true).hasMatch(value);

@immutable
class TagFilterDraft {
  const TagFilterDraft({
    required this.name,
    required this.query,
    required this.effect,
    this.scope = const TagFilterScope.global(),
  });

  factory TagFilterDraft.exactTag(String tag, TagFilterEffect effect) => TagFilterDraft(
    name: '',
    query: TagFilterQuery.escapeExactTag(tag),
    effect: effect,
  );

  final String name;
  final String query;
  final TagFilterEffect effect;
  final TagFilterScope scope;
}

Future<void> showTagFilterEditorSheet(BuildContext context, {TagFilterRule? rule, TagFilterDraft? draft}) {
  assert(rule == null || draft == null, 'An editor cannot open with both a rule and a draft');
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 700),
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: TagFilterEditor(rule: rule, draft: draft),
    ),
  );
}

class TagFilterEditor extends StatefulWidget {
  const TagFilterEditor({this.rule, this.draft, super.key})
    : assert(rule == null || draft == null, 'An editor cannot have both a rule and a draft');
  final TagFilterRule? rule;
  final TagFilterDraft? draft;

  @override
  State<TagFilterEditor> createState() => _TagFilterEditorState();
}

class _TagFilterEditorState extends State<TagFilterEditor> {
  static const String _allBoorusScopeKey = 'scope:all';
  static const String _onlySelectedScopeKey = 'scope:only-selected';
  static const String _allExceptSelectedScopeKey = 'scope:all-except-selected';

  late final TextEditingController nameController;
  late final TextEditingController queryController;
  late final TextEditingController markerController;

  late TagFilterEffect effect;
  late TagFilterScopeKind scopeKind;
  late bool enabled;
  late bool showMarkerInGrid;
  bool showEmptyScopeWarning = false;
  DateTime? disabledUntil;
  final List<Booru> sourceBoorus = [];
  final List<BooruIdentity> missingSources = [];
  BooruType viewType = BooruType.Favourites;
  Booru? suggestionBooru;
  final Set<BooruIdentity> exclusions = {};
  late _MarkerEditorMode markerMode;
  TagFilterMarkerIcon markerIcon = tagFilterMarkerIconCatalog.first;
  TagFilterMarkerColor markerColor = TagFilterMarkerColor.grey;
  Color? customMarkerColor;
  String? presetEmoji;

  List<Booru> get regularBoorus => SettingsHandler.instance.booruList
      .where((booru) => booru.type?.isFavouritesOrDownloads != true && booru.type?.isMerge != true)
      .toList();

  List<Booru> get scopeBoorus =>
      SettingsHandler.instance.booruList.where((booru) => booru.type?.isMerge != true).toList();

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final draft = widget.draft;
    nameController = TextEditingController(
      text: rule == null ? draft?.name ?? '' : (rule.hasDistinctName ? rule.name : ''),
    );
    queryController = TextEditingController(text: rule?.query ?? draft?.query ?? '');
    markerController = TextEditingController(text: rule?.marker?.text ?? '');
    effect = rule?.effect ?? draft?.effect ?? TagFilterEffect.hide;
    showMarkerInGrid = rule?.showMarkerInGrid ?? true;
    final initialScope = rule?.scope ?? draft?.scope ?? const TagFilterScope.global();
    scopeKind = initialScope.kind;
    enabled = rule?.enabled ?? true;
    disabledUntil = rule?.disabledUntil;
    for (final target in initialScope.targets) {
      final source = scopeBoorus.where((booru) => _identityMatchesBooru(target, booru)).firstOrNull;
      if (source == null) {
        missingSources.add(target);
      } else if (!sourceBoorus.contains(source)) {
        sourceBoorus.add(source);
      }
    }
    viewType = initialScope.viewType ?? BooruType.Favourites;
    if (initialScope.kind == TagFilterScopeKind.view) {
      scopeKind = TagFilterScopeKind.source;
      final source = scopeBoorus.where((booru) => booru.type == viewType).firstOrNull;
      if (source == null) {
        missingSources.add(BooruIdentity(type: viewType));
      } else if (!sourceBoorus.contains(source)) {
        sourceBoorus.add(source);
      }
    }
    exclusions.addAll(initialScope.excludedSources);
    final initialMarker = rule?.marker;
    markerIcon = initialMarker?.icon ?? tagFilterMarkerIconCatalog.first;
    markerColor = initialMarker?.color ?? TagFilterMarkerColor.grey;
    customMarkerColor = initialMarker?.customColor;
    if (initialMarker == null || initialMarker.kind == TagFilterMarkerKind.icon) {
      markerMode = _MarkerEditorMode.predefined;
    } else if (tagFilterPresetEmojis.contains(initialMarker.text)) {
      markerMode = _MarkerEditorMode.predefined;
      presetEmoji = initialMarker.text;
    } else {
      markerMode = _MarkerEditorMode.custom;
    }
    suggestionBooru =
        sourceBoorus.where((booru) => booru.type?.isFavouritesOrDownloads != true).firstOrNull ??
        SearchHandler.instance.currentBooruOrNull ??
        regularBoorus.firstOrNull;
  }

  @override
  void dispose() {
    nameController.dispose();
    queryController.dispose();
    markerController.dispose();
    super.dispose();
  }

  String _suggestionInput(String input) {
    var escaping = false;
    final result = StringBuffer();
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (escaping) {
        result.write(char);
        escaping = false;
      } else if (char == r'\') {
        escaping = true;
      } else if (char == '*') {
        break;
      } else if (char != '"') {
        result.write(char);
      }
    }
    if (escaping) result.write(r'\');
    return result.toString().trim();
  }

  TagFilterScope? _scope() => switch (scopeKind) {
    TagFilterScopeKind.global => TagFilterScope.global(excludedSources: exclusions.toList()),
    TagFilterScopeKind.source =>
      [...sourceBoorus.map(_identityForBooru), ...missingSources].isEmpty
          ? null
          : TagFilterScope.sources([...sourceBoorus.map(_identityForBooru), ...missingSources]),
    TagFilterScopeKind.view => TagFilterScope.view(viewType),
  };

  TagFilterMarker? _marker() {
    if (effect != TagFilterEffect.mark) return null;
    final usedMarkerColor = _selectedMarkerIsEmoji ? TagFilterMarkerColor.grey : markerColor;
    final usedCustomColor = _selectedMarkerIsEmoji ? null : customMarkerColor;
    if (markerMode == _MarkerEditorMode.predefined) {
      return presetEmoji == null
          ? TagFilterMarker.icon(markerIcon, color: usedMarkerColor, customColor: usedCustomColor)
          : TagFilterMarker.text(presetEmoji, color: usedMarkerColor, customColor: usedCustomColor);
    }
    final characters = markerController.text.trim().characters;
    if (characters.length != 1) return null;
    return TagFilterMarker.text(characters.first, color: usedMarkerColor, customColor: usedCustomColor);
  }

  bool get _selectedMarkerIsEmoji {
    if (presetEmoji != null) return true;
    if (markerMode != _MarkerEditorMode.custom) return false;
    return _isEmojiMarkerText(markerController.text);
  }

  bool get markerValid =>
      effect != TagFilterEffect.mark ||
      markerMode != _MarkerEditorMode.custom ||
      markerController.text.trim().characters.length == 1;

  TagFilterQueryParseResult get queryResult => TagFilterQuery.parse(queryController.text);

  bool get isDuplicate {
    final scope = _scope();
    if (scope == null) return false;
    final normalized = queryController.text.trim().toLowerCase();
    return TagFilterHandler.instance.rules.any(
      (rule) =>
          rule.id != widget.rule?.id &&
          rule.effect == effect &&
          rule.scope.stableKey == scope.stableKey &&
          rule.query.trim().toLowerCase() == normalized,
    );
  }

  Future<void> _save() async {
    final scope = _scope();
    if (scope == null) {
      setState(() => showEmptyScopeWarning = true);
      return;
    }
    if (!queryResult.isValid || !markerValid || isDuplicate) return;
    final now = DateTime.now().toUtc();
    final existing = widget.rule;
    final query = queryController.text.trim();
    final enteredName = nameController.text.trim();
    final rule = TagFilterRule(
      id: existing?.id ?? const Uuid().v4(),
      name: enteredName,
      query: query,
      effect: effect,
      scope: scope,
      enabled: enabled,
      disabledUntil: disabledUntil,
      marker: _marker(),
      showMarkerInGrid: effect == TagFilterEffect.mark ? showMarkerInGrid : true,
      legacySourceKey: existing?.legacySourceKey,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await TagFilterHandler.instance.addRule(rule);
    } else {
      await TagFilterHandler.instance.updateRule(rule);
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _effectName(TagFilterEffect value) => switch (value) {
    TagFilterEffect.hide => context.loc.settings.itemFilters.hide,
    TagFilterEffect.blur => context.loc.settings.itemFilters.blur,
    TagFilterEffect.mark => context.loc.settings.itemFilters.mark,
  };

  Future<void> _showQueryHelp() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (sheetContext) {
      final loc = sheetContext.loc.settings.itemFilters;
      final details = <(IconData, String)>[
        (Icons.join_inner, loc.queryHelpAnd),
        (Icons.remove_circle_outline, loc.queryHelpNegation),
        (Icons.auto_awesome, loc.queryHelpWildcards),
        (Icons.tune, loc.queryHelpMetadata),
        (Icons.format_quote, loc.queryHelpQuotes),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(loc.queryHelpTitle, style: Theme.of(sheetContext).textTheme.titleLarge),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(loc.syntaxHelp),
                ),
                for (final detail in details)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Icon(detail.$1),
                    title: Text(detail.$2),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _changeAvailability() async {
    final activeTimer = enabled && disabledUntil?.isAfter(DateTime.now().toUtc()) == true;
    final change = await showTagFilterSuspensionSheet(
      context,
      showReenable: !enabled || activeTimer,
    );
    if (change == null || !mounted) return;
    setState(() {
      enabled = change.enabled;
      disabledUntil = change.disabledUntil;
    });
  }

  IconData _effectIcon(TagFilterEffect value) => switch (value) {
    TagFilterEffect.hide => Icons.visibility_off,
    TagFilterEffect.blur => Icons.blur_on,
    TagFilterEffect.mark => Icons.star,
  };

  Widget _effectOption(TagFilterEffect? value) {
    final usedValue = value ?? effect;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_effectIcon(usedValue), size: 20),
        const SizedBox(width: 10),
        Text(_effectName(usedValue)),
      ],
    );
  }

  Widget _selectedMarkerPreview({double size = 22}) {
    return _markerPreview(color: _effectiveMarkerColor, size: size);
  }

  Widget _markerPreview({required Color color, required double size}) {
    if (markerMode == _MarkerEditorMode.custom) {
      return _customMarkerPreview(color: color, size: size);
    }
    if (presetEmoji != null) {
      return SizedBox.square(
        dimension: size,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            presetEmoji!,
            style: TextStyle(color: color, fontSize: size),
          ),
        ),
      );
    }
    return markerIcon.build(size: size, color: color);
  }

  Widget _markerEditorRow({required String title, required VoidCallback onTap, Widget? preview}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: preview ?? _selectedMarkerPreview(size: 18)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownSheetItem(Widget child) => Container(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  void _selectMarkerIcon(TagFilterMarkerIcon value) {
    setState(() {
      markerMode = _MarkerEditorMode.predefined;
      markerIcon = value;
      presetEmoji = null;
    });
  }

  void _selectMarkerEmoji(String value) {
    setState(() {
      markerMode = _MarkerEditorMode.predefined;
      presetEmoji = value;
      markerColor = TagFilterMarkerColor.grey;
      customMarkerColor = null;
    });
  }

  void _selectCustomMarker() {
    if (markerController.text.trim().characters.length != 1) return;
    setState(() => markerMode = _MarkerEditorMode.custom);
  }

  Future<void> _showMarkerPicker() async {
    final selection = await showModalBottomSheet<_MarkerPickerSelection>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 620),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MarkerPickerSheet(
        initialTab: markerMode == _MarkerEditorMode.custom
            ? _MarkerPickerTab.symbol
            : presetEmoji != null
            ? _MarkerPickerTab.emojis
            : _MarkerPickerTab.icons,
        selectedIcon: markerMode == _MarkerEditorMode.predefined && presetEmoji == null ? markerIcon : null,
        selectedEmoji: markerMode == _MarkerEditorMode.predefined ? presetEmoji : null,
        initialSymbol: markerController.text,
        markerColor: _effectiveMarkerColor,
      ),
    );
    if (!mounted || selection == null) return;
    switch (selection.tab) {
      case _MarkerPickerTab.icons:
        _selectMarkerIcon(selection.icon!);
      case _MarkerPickerTab.emojis:
        _selectMarkerEmoji(selection.value!);
      case _MarkerPickerTab.symbol:
        markerController.text = selection.value!;
        _selectCustomMarker();
    }
  }

  Future<void> _selectCustomMarkerColor() => _selectMarkerColor((color) => _markerPreview(color: color, size: 20));

  Color get _effectiveMarkerColor =>
      _selectedMarkerIsEmoji ? TagFilterMarkerColor.grey.color : customMarkerColor ?? markerColor.color;

  Future<void> _selectMarkerColor(Widget Function(Color color) previewBuilder) async {
    final selection = await _showMarkerColorSelector(previewBuilder);
    if (!mounted || selection == null) return;
    if (selection.custom) {
      final color = await _showCustomMarkerColorPicker(previewBuilder);
      if (!mounted || color == null) return;
      setState(() => customMarkerColor = color);
      return;
    }
    setState(() {
      markerColor = selection.preset!;
      customMarkerColor = null;
    });
  }

  Widget _customMarkerPreview({required Color color, required double size}) {
    final characters = markerController.text.trim().characters;
    if (characters.length != 1) {
      return Icon(Icons.text_fields, color: color, size: size);
    }
    return Text(
      characters.first,
      style: TextStyle(
        color: color,
        fontSize: size,
        height: 1,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Future<({TagFilterMarkerColor? preset, bool custom})?> _showMarkerColorSelector(
    Widget Function(Color color) previewBuilder,
  ) {
    return showModalBottomSheet<({TagFilterMarkerColor? preset, bool custom})>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 520),
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sheetContext.loc.settings.itemFilters.markerColor,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TagFilterMarkerColor.values
                        .map<Widget>(
                          (color) => SizedBox.square(
                            dimension: 48,
                            child: ChoiceChip(
                              selected: customMarkerColor == null && markerColor == color,
                              showCheckmark: false,
                              side: BorderSide.none,
                              backgroundColor: colors.surfaceContainerHighest,
                              selectedColor: colors.primaryContainer,
                              padding: const EdgeInsets.all(10),
                              labelPadding: EdgeInsets.zero,
                              label: SizedBox.square(
                                dimension: 28,
                                child: Center(
                                  child: previewBuilder(color.color),
                                ),
                              ),
                              onSelected: (_) => Navigator.of(
                                sheetContext,
                              ).pop((preset: color, custom: false)),
                            ),
                          ),
                        )
                        .followedBy([
                          Tooltip(
                            message: sheetContext.loc.settings.theme.custom,
                            child: SizedBox(
                              height: 48,
                              child: ChoiceChip(
                                selected: customMarkerColor != null,
                                showCheckmark: false,
                                side: BorderSide.none,
                                backgroundColor: colors.surfaceContainerHighest,
                                selectedColor: colors.primaryContainer,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                labelPadding: EdgeInsets.zero,
                                label: _AnimatedRainbowColorLabel(
                                  label: sheetContext.loc.settings.theme.custom,
                                ),
                                onSelected: (_) => Navigator.of(
                                  sheetContext,
                                ).pop((preset: null, custom: true)),
                              ),
                            ),
                          ),
                        ])
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Color?> _showCustomMarkerColorPicker(Widget Function(Color color) previewBuilder) {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 520),
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CustomMarkerColorPickerSheet(
        initialColor: _effectiveMarkerColor,
        previewBuilder: previewBuilder,
      ),
    );
  }

  BooruIdentity _identityForBooru(Booru booru) =>
      booru.type?.isFavouritesOrDownloads == true ? BooruIdentity(type: booru.type) : BooruIdentity.fromBooru(booru);

  bool _identityMatchesBooru(BooruIdentity identity, Booru booru) =>
      identity.type?.isFavouritesOrDownloads == true ? identity.type == booru.type : identity.matches(booru);

  String _sourceScopeKey(Booru booru) => 'source:${_identityForBooru(booru).stableKey}';

  String _missingSourceKey(BooruIdentity source) => 'missing:${source.stableKey}';

  BooruIdentity? _missingSourceForKey(String key) =>
      _missingScopeSources.where((source) => _missingSourceKey(source) == key).firstOrNull;

  Booru? _booruForIdentity(BooruIdentity identity) =>
      scopeBoorus.where((booru) => _identityMatchesBooru(identity, booru)).firstOrNull;

  List<BooruIdentity> get _missingScopeSources => {
    ...missingSources,
    ...exclusions.where((source) => _booruForIdentity(source) == null),
  }.toList();

  String _scopeKeyForIdentity(BooruIdentity identity) {
    final booru = _booruForIdentity(identity);
    return booru == null ? _missingSourceKey(identity) : _sourceScopeKey(booru);
  }

  List<String> get _booruScopeKeys => [
    ...scopeBoorus.map(_sourceScopeKey),
    ..._missingScopeSources.map(_missingSourceKey),
  ];

  List<String> get _scopeKeys => [
    _allBoorusScopeKey,
    _onlySelectedScopeKey,
    _allExceptSelectedScopeKey,
    ..._booruScopeKeys,
  ];

  List<String> get _selectedScopeKeys => switch (scopeKind) {
    TagFilterScopeKind.global =>
      exclusions.isEmpty ? [_allBoorusScopeKey] : [_allExceptSelectedScopeKey, ...exclusions.map(_scopeKeyForIdentity)],
    TagFilterScopeKind.source => [
      _onlySelectedScopeKey,
      ...sourceBoorus.map(_sourceScopeKey),
      ...missingSources.map(_missingSourceKey),
    ],
    TagFilterScopeKind.view => [
      _onlySelectedScopeKey,
      _missingSourceKey(BooruIdentity(type: viewType)),
    ],
  };

  Booru? _booruForScopeKey(String key) => scopeBoorus.where((booru) => _sourceScopeKey(booru) == key).firstOrNull;

  BooruIdentity? _identityForScopeKey(String key) {
    final booru = _booruForScopeKey(key);
    return booru == null ? _missingSourceForKey(key) : BooruIdentity.fromBooru(booru);
  }

  void _setScopeKeys(List<String> keys) {
    final previous = _selectedScopeKeys;
    if (keys.length == previous.length && keys.every(previous.contains)) return;
    final selectedSources = keys.map(_identityForScopeKey).nonNulls.toList();
    setState(() {
      showEmptyScopeWarning = false;
      if (keys.contains(_allBoorusScopeKey)) {
        scopeKind = TagFilterScopeKind.global;
        exclusions.clear();
        sourceBoorus.clear();
        missingSources.clear();
      } else if (keys.contains(_allExceptSelectedScopeKey)) {
        scopeKind = TagFilterScopeKind.global;
        exclusions
          ..clear()
          ..addAll(selectedSources);
        sourceBoorus.clear();
        missingSources.clear();
      } else {
        scopeKind = TagFilterScopeKind.source;
        exclusions.clear();
        sourceBoorus
          ..clear()
          ..addAll(selectedSources.map(_booruForIdentity).nonNulls);
        missingSources
          ..clear()
          ..addAll(selectedSources.where((source) => _booruForIdentity(source) == null));
        if (!sourceBoorus.contains(suggestionBooru)) {
          suggestionBooru =
              sourceBoorus.where((booru) => booru.type?.isFavouritesOrDownloads != true).firstOrNull ??
              regularBoorus.firstOrNull;
        }
      }
    });
  }

  String _scopeName(String? key) {
    final loc = context.loc.settings.itemFilters;
    if (key == _allBoorusScopeKey) return loc.allBoorus;
    if (key == _onlySelectedScopeKey) return loc.onlySelectedBoorus;
    if (key == _allExceptSelectedScopeKey) return loc.allExceptSelectedBoorus;
    final missingSource = _missingSourceForKey(key ?? '');
    if (missingSource != null) return missingSource.type?.alias ?? missingSource.name ?? loc.missingSource;
    return _booruForScopeKey(key ?? '')?.name ?? loc.missingSource;
  }

  Widget _scopeOption(String? key) {
    final booru = _booruForScopeKey(key ?? '');
    final sourceType = booru?.type ?? _missingSourceForKey(key ?? '')?.type;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sourceType == BooruType.Favourites)
          const Icon(Icons.favorite, size: 20)
        else if (sourceType == BooruType.Downloads)
          const Icon(Icons.download, size: 20)
        else if (booru != null)
          BooruFavicon(booru, size: 20)
        else
          Icon(
            _missingSourceForKey(key ?? '') != null
                ? Icons.link_off
                : key == _allBoorusScopeKey
                ? Icons.public
                : key == _onlySelectedScopeKey
                ? Icons.playlist_add_check
                : key == _allExceptSelectedScopeKey
                ? Icons.playlist_remove
                : Icons.link_off,
            size: 20,
          ),
        const SizedBox(width: 10),
        Flexible(child: Text(_scopeName(key), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _selectedScopeOptions(List<String> keys) {
    if (keys.isEmpty) return Text(context.loc.select);
    final mode = keys.first;
    if (mode == _allBoorusScopeKey) {
      return _scopeOption(mode);
    }
    final selectedCount = keys.where(_isBooruScopeKey).length;
    return Row(
      children: [
        Icon(mode == _allExceptSelectedScopeKey ? Icons.playlist_remove : Icons.playlist_add_check, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${_scopeName(mode)} ($selectedCount)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  bool _isBooruScopeKey(String key) => key.startsWith('source:') || key.startsWith('missing:');

  bool _isScopeModeKey(String key) => {
    _allBoorusScopeKey,
    _onlySelectedScopeKey,
    _allExceptSelectedScopeKey,
  }.contains(key);

  List<String> _normalizeScopeSelection(List<String> selected, String toggled) {
    final selectedBoorus = selected.where(_isBooruScopeKey).toList();
    if (_isScopeModeKey(toggled)) {
      if (toggled == _allBoorusScopeKey) {
        return [toggled];
      }
      return [toggled, ...selectedBoorus];
    }
    final currentMode = selected.where(_isScopeModeKey).firstOrNull;
    return [
      if (currentMode == _onlySelectedScopeKey || currentMode == _allExceptSelectedScopeKey)
        currentMode!
      else
        _onlySelectedScopeKey,
      ...selectedBoorus,
    ];
  }

  List<String> _clearScopeSelection(List<String> _) => [_onlySelectedScopeKey];

  List<String> _selectAllScopes(List<String> _) => [_allBoorusScopeKey];

  List<String> _invertScopeSelection(List<String> selected) {
    final mode = selected.where(_isScopeModeKey).firstOrNull;
    final selectedBoorus = selected.where(_isBooruScopeKey).toSet();
    if (mode == _allExceptSelectedScopeKey) {
      return [_onlySelectedScopeKey, ...selectedBoorus];
    }
    if (mode == _allBoorusScopeKey) return [_onlySelectedScopeKey];
    return [
      _onlySelectedScopeKey,
      ..._booruScopeKeys.where((key) => !selectedBoorus.contains(key)),
    ];
  }

  String _formatTimerEnd(DateTime until) {
    final localUntil = until.toLocal();
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatFullDate(localUntil)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(localUntil))}';
  }

  String _formatTimeLeft(DateTime until) {
    final loc = context.loc.settings.itemFilters;
    final remaining = until.difference(DateTime.now().toUtc());
    if (remaining.inSeconds < Duration.secondsPerMinute) return loc.timeLeftLessThanMinute;
    final calculatedMinutes = (remaining.inSeconds / Duration.secondsPerMinute).ceil();
    final totalMinutes = calculatedMinutes < 1 ? 1 : calculatedMinutes;
    final days = totalMinutes ~/ Duration.minutesPerDay;
    if (days > 0) {
      final hours = (totalMinutes % Duration.minutesPerDay) ~/ Duration.minutesPerHour;
      return loc.timeLeftDaysHours(days: days, hours: hours);
    }
    final hours = totalMinutes ~/ Duration.minutesPerHour;
    if (hours > 0) {
      final minutes = totalMinutes % Duration.minutesPerHour;
      return loc.timeLeftHoursMinutes(hours: hours, minutes: minutes);
    }
    return loc.timeLeftMinutes(minutes: totalMinutes);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc.settings.itemFilters;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.9,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(
                    widget.rule == null ? loc.addRule : loc.editRule,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: loc.ruleName,
                            hintText: loc.optional,
                            helperText: loc.emptyNameUsesQuery,
                            helperMaxLines: 5,
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 24),
                        TagSearchBox(
                          controller: queryController,
                          title: loc.query,
                          booru: suggestionBooru,
                          allowMultipleTags: true,
                          showBooruSelector: true,
                          titleAsLabel: true,
                          onlyInput: true,
                          drawBottomBorder: false,
                          margin: EdgeInsets.zero,
                          suggestionInputTransform: _suggestionInput,
                          inputTokenizer: TagFilterQuery.splitRawConditions,
                          suffixActions: [
                            IconButton(
                              tooltip: loc.queryHelpTitle,
                              icon: const Icon(Icons.help_outline),
                              onPressed: _showQueryHelp,
                            ),
                          ],
                          onBooruChanged: (value) => setState(() => suggestionBooru = value),
                          onChanged: (_, booru) => setState(() {
                            if (booru != null) suggestionBooru = booru;
                          }),
                        ),
                        if (queryController.text.isNotEmpty && !queryResult.isValid)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              queryResult.error!.message,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        LoliDropdown<TagFilterEffect>(
                          value: effect,
                          labelText: loc.effect,
                          items: TagFilterEffect.values,
                          itemBuilder: (value) => _dropdownSheetItem(_effectOption(value)),
                          selectedItemBuilder: _effectOption,
                          onChanged: (value) => setState(() => effect = value!),
                        ),
                        const SizedBox(height: 12),
                        LoliMultiselectDropdown<String>(
                          value: _selectedScopeKeys,
                          items: _scopeKeys,
                          onChanged: _setScopeKeys,
                          itemBuilder: (key) => _dropdownSheetItem(_scopeOption(key)),
                          selectedItemBuilder: _selectedScopeOptions,
                          labelText: loc.scope,
                          selectionNormalizer: _normalizeScopeSelection,
                          clearSelection: _clearScopeSelection,
                          selectAllSelection: _selectAllScopes,
                          invertSelection: _invertScopeSelection,
                          invertSelectionLabel: loc.invertSelection,
                          selectionCount: (keys) => keys.where(_isBooruScopeKey).length,
                          showSelectionOrder: false,
                        ),
                        if (showEmptyScopeWarning && _scope() == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              loc.selectAtLeastOneBooru,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (effect == TagFilterEffect.mark) ...[
                          const SizedBox(height: 12),
                          _markerEditorRow(
                            title: loc.marker,
                            onTap: _showMarkerPicker,
                          ),
                          if (!_selectedMarkerIsEmoji) ...[
                            const SizedBox(height: 8),
                            _markerEditorRow(
                              title: loc.markerColor,
                              onTap: _selectCustomMarkerColor,
                              preview: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: _effectiveMarkerColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(Icons.grid_view_rounded),
                            value: showMarkerInGrid,
                            title: Text(loc.showMarkerInGrid),
                            subtitle: Text(loc.showMarkerInGridHelp),
                            onChanged: (value) => setState(() => showMarkerInGrid = value),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (enabled && disabledUntil?.isAfter(DateTime.now().toUtc()) == true) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loc.timeLeft(
                                          value: _formatTimeLeft(disabledUntil!),
                                        ),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        loc.endsAt(
                                          value: _formatTimerEnd(disabledUntil!),
                                        ),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.rule != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.timer_off_outlined),
                            title: Text(loc.disableFor),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _changeAvailability,
                          ),
                        if (widget.rule != null)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: enabled,
                            title: Text(loc.enabled),
                            onChanged: (value) => setState(() {
                              enabled = value;
                              if (value) disabledUntil = null;
                            }),
                          ),
                        if (isDuplicate)
                          Text(loc.duplicateFilter, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.loc.cancel)),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: queryResult.isValid && markerValid && !isDuplicate ? _save : null,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(context.loc.save),
                      ),
                    ],
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

enum _MarkerPickerTab { icons, emojis, symbol }

@immutable
class _MarkerPickerSelection {
  const _MarkerPickerSelection.icon(TagFilterMarkerIcon this.icon) : tab = _MarkerPickerTab.icons, value = null;

  const _MarkerPickerSelection.emoji(String this.value) : tab = _MarkerPickerTab.emojis, icon = null;

  const _MarkerPickerSelection.symbol(String this.value) : tab = _MarkerPickerTab.symbol, icon = null;

  final _MarkerPickerTab tab;
  final TagFilterMarkerIcon? icon;
  final String? value;
}

class _MarkerPickerSheet extends StatefulWidget {
  const _MarkerPickerSheet({
    required this.initialTab,
    required this.selectedIcon,
    required this.selectedEmoji,
    required this.initialSymbol,
    required this.markerColor,
  });

  final _MarkerPickerTab initialTab;
  final TagFilterMarkerIcon? selectedIcon;
  final String? selectedEmoji;
  final String initialSymbol;
  final Color markerColor;

  @override
  State<_MarkerPickerSheet> createState() => _MarkerPickerSheetState();
}

class _MarkerPickerSheetState extends State<_MarkerPickerSheet> {
  late final TextEditingController symbolController = TextEditingController(text: widget.initialSymbol);

  bool get symbolValid => symbolController.text.trim().characters.length == 1;

  @override
  void dispose() {
    symbolController.dispose();
    super.dispose();
  }

  void _useSymbol() {
    if (!symbolValid) return;
    Navigator.of(context).pop(_MarkerPickerSelection.symbol(symbolController.text.trim()));
  }

  Widget _iconGrid() {
    final colors = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 58,
        mainAxisExtent: 48,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: tagFilterMarkerIconCatalog.length,
      itemBuilder: (_, index) {
        final icon = tagFilterMarkerIconCatalog[index];
        final selected = widget.initialTab == _MarkerPickerTab.icons && widget.selectedIcon == icon;
        return _MarkerPickerChoice(
          selected: selected,
          label: icon.build(
            size: 20,
            color: selected ? widget.markerColor : colors.onSurfaceVariant,
          ),
          onSelected: () => Navigator.of(context).pop(_MarkerPickerSelection.icon(icon)),
        );
      },
    );
  }

  Widget _emojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 58,
        mainAxisExtent: 48,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: tagFilterPresetEmojis.length,
      itemBuilder: (_, index) {
        final emoji = tagFilterPresetEmojis[index];
        return _MarkerPickerChoice(
          selected: widget.initialTab == _MarkerPickerTab.emojis && widget.selectedEmoji == emoji,
          label: Text(emoji, style: const TextStyle(fontSize: 18)),
          onSelected: () => Navigator.of(context).pop(_MarkerPickerSelection.emoji(emoji)),
        );
      },
    );
  }

  Widget _symbolPage() {
    final colors = Theme.of(context).colorScheme;
    final characters = symbolController.text.trim().characters;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Center(
              child: characters.length == 1
                  ? Text(
                      characters.first,
                      style: TextStyle(
                        color: _isEmojiMarkerText(characters.first) ? Colors.grey : widget.markerColor,
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Icon(Icons.text_fields, color: widget.markerColor, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: symbolController,
          inputFormatters: [LengthLimitingTextInputFormatter(1)],
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.loc.settings.itemFilters.customMarker,
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _useSymbol(),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: symbolValid ? _useSymbol : null,
          icon: const Icon(Icons.check),
          label: Text(context.loc.confirm),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc.settings.itemFilters;
    final theme = Theme.of(context);
    return DefaultTabController(
      length: _MarkerPickerTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(loc.marker, style: theme.textTheme.titleLarge),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                TabBar(
                  tabs: [
                    Tab(icon: const Icon(Icons.apps), text: loc.icons),
                    Tab(icon: const Icon(Icons.emoji_emotions_outlined), text: loc.popularEmojis),
                    Tab(icon: const Icon(Icons.text_fields), text: loc.symbol),
                  ],
                ),
                const Divider(height: 1),
                Flexible(
                  child: TabBarView(
                    children: [_iconGrid(), _emojiGrid(), _symbolPage()],
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

class _MarkerPickerChoice extends StatelessWidget {
  const _MarkerPickerChoice({required this.selected, required this.label, required this.onSelected});

  final bool selected;
  final Widget label;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 48,
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        side: BorderSide.none,
        backgroundColor: colors.surfaceContainerHighest,
        selectedColor: colors.primaryContainer,
        padding: const EdgeInsets.all(10),
        labelPadding: EdgeInsets.zero,
        label: SizedBox.square(dimension: 28, child: Center(child: label)),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _AnimatedRainbowColorLabel extends StatefulWidget {
  const _AnimatedRainbowColorLabel({required this.label});

  final String label;

  @override
  State<_AnimatedRainbowColorLabel> createState() => _AnimatedRainbowColorLabelState();
}

class _AnimatedRainbowColorLabelState extends State<_AnimatedRainbowColorLabel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Colors.red,
              Colors.orange,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
            transform: GradientRotation(_controller.value * math.pi * 2),
          ).createShader(bounds),
          child: child,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.palette_outlined, size: 20, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              widget.label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomMarkerColorPickerSheet extends StatefulWidget {
  const _CustomMarkerColorPickerSheet({
    required this.initialColor,
    required this.previewBuilder,
  });

  final Color initialColor;
  final Widget Function(Color color) previewBuilder;

  @override
  State<_CustomMarkerColorPickerSheet> createState() => _CustomMarkerColorPickerSheetState();
}

class _CustomMarkerColorPickerSheetState extends State<_CustomMarkerColorPickerSheet> {
  late final ValueNotifier<Color> _selectedColor = ValueNotifier(widget.initialColor);

  @override
  void dispose() {
    _selectedColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.loc.settings.theme.selectColor,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    ValueListenableBuilder<Color>(
                      valueListenable: _selectedColor,
                      builder: (_, color, _) => Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(child: widget.previewBuilder(color)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ColorPicker(
                  key: const ValueKey('custom-marker-color-picker'),
                  color: widget.initialColor,
                  onColorChanged: (color) => _selectedColor.value = color,
                  mainAxisSize: MainAxisSize.min,
                  padding: EdgeInsets.zero,
                  wheelDiameter: 280,
                  showColorName: true,
                  showColorCode: true,
                  showEditIconButton: true,
                  colorCodeHasColor: true,
                  hasBorder: true,
                  selectedPickerTypeColor: colors.primary,
                  pickersEnabled: const {
                    ColorPickerType.wheel: true,
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.loc.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).pop(_selectedColor.value),
                      icon: const Icon(Icons.check),
                      label: Text(context.loc.confirm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
