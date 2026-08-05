import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/loli_dropdown.dart';
import 'package:lolisnatcher/src/widgets/common/marquee_text.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_editor.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_query_text.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_suspension_sheet.dart';

class TagsFiltersPage extends StatefulWidget {
  const TagsFiltersPage({super.key});

  @override
  State<TagsFiltersPage> createState() => _TagsFiltersPageState();
}

enum _FilterSort { alphabetical, reverseAlphabetical, effect, reverseEffect, suspensionTime }

class _TagsFiltersPageState extends State<TagsFiltersPage> {
  static const String _globalScopeKey = 'global';
  static const String _favouritesScopeKey = 'view:favourites';
  static const String _downloadsScopeKey = 'view:downloads';

  final TextEditingController searchController = TextEditingController();
  final ScrollController filterControlsScrollController = ScrollController();
  final ScrollController rulesScrollController = ScrollController();
  final ValueNotifier<int> countdownRevision = ValueNotifier(0);
  Timer? debounce;
  Timer? countdownRefreshTimer;
  String search = '';
  final Set<TagFilterEffect> selectedEffects = {};
  final Set<String> selectedMarkers = {};
  final Set<String> selectedScopes = {};
  final Set<String> selectedStatuses = {};
  final Set<String> expandedTimerRuleIds = {};
  final Set<String> selectedRuleIds = {};
  bool _selectionMode = false;
  _FilterSort sortMode = _FilterSort.alphabetical;
  final Map<String, String> searchableText = {};
  final Map<String, TagFilterMarker?> markersByKey = {};
  final Map<TagFilterEffect, int> effectCounts = {};
  List<String> markerFilterKeys = [];
  List<TagFilterRule> alphabeticalRules = [];
  final Map<_FilterSort, List<TagFilterRule>> sortedRules = {};
  List<TagFilterRule> filteredRules = [];
  List<Booru> cachedRegularBoorus = [];
  final Map<String, Booru> boorusByScopeKey = {};

  @override
  void initState() {
    super.initState();
    TagFilterHandler.instance.revision.addListener(_refresh);
    _rebuildRuleCache();
    _applyFilters();
    _scheduleCountdownRefresh();
  }

  @override
  void dispose() {
    debounce?.cancel();
    countdownRefreshTimer?.cancel();
    searchController.dispose();
    filterControlsScrollController.dispose();
    rulesScrollController.dispose();
    countdownRevision.dispose();
    TagFilterHandler.instance.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    _rebuildRuleCache();
    selectedMarkers.removeWhere((key) => !markerFilterKeys.contains(key));
    selectedScopes.removeWhere((key) => !_scopeFilterKeys.contains(key));
    expandedTimerRuleIds.retainWhere((id) => TagFilterHandler.instance.rules.any((rule) => rule.id == id));
    selectedRuleIds.retainWhere((id) => TagFilterHandler.instance.rules.any((rule) => rule.id == id));
    _applyFilters();
    _scheduleCountdownRefresh();
    if (mounted) setState(() {});
  }

  void _scheduleCountdownRefresh() {
    countdownRefreshTimer?.cancel();
    final now = DateTime.now();
    final nowUtc = now.toUtc();
    final handler = TagFilterHandler.instance;
    final hasActiveTimer =
        handler.rules.any((rule) => rule.enabled && rule.disabledUntil?.isAfter(nowUtc) == true) ||
        (handler.configuration.hideAsBlur.enabled && handler.configuration.hideAsBlur.until?.isAfter(nowUtc) == true);
    if (!hasActiveTimer) return;
    final millisecondsIntoMinute = now.second * Duration.millisecondsPerSecond + now.millisecond;
    final delay = Duration(milliseconds: Duration.millisecondsPerMinute - millisecondsIntoMinute);
    countdownRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      countdownRevision.value++;
      setState(() {});
      _scheduleCountdownRefresh();
    });
  }

  void _rebuildRuleCache() {
    final rules = TagFilterHandler.instance.rules;
    final now = DateTime.now().toUtc();
    cachedRegularBoorus = SettingsHandler.instance.booruList
        .where((booru) => booru.type?.isFavouritesOrDownloads != true && booru.type?.isMerge != true)
        .toList();
    boorusByScopeKey
      ..clear()
      ..addEntries(cachedRegularBoorus.map((booru) => MapEntry(_sourceScopeKey(booru), booru)));
    searchableText
      ..clear()
      ..addEntries(
        rules.map(
          (rule) => MapEntry(
            rule.id,
            '${rule.name} ${rule.query} ${rule.effect.name} ${rule.scope.kind.name} '
                    '${rule.scope.targets.map((target) => '${target.name ?? ''} ${target.baseUrl ?? ''}').join(' ')} '
                    '${rule.scope.excludedSources.map((source) => '${source.name ?? ''} ${source.baseUrl ?? ''}').join(' ')} '
                    '${TagFilterMarker.stableKeyFor(rule.marker)}'
                .toLowerCase(),
          ),
        ),
      );
    alphabeticalRules = [...rules]..sort(_compareAlphabetically);
    sortedRules
      ..clear()
      ..[_FilterSort.alphabetical] = alphabeticalRules
      ..[_FilterSort.reverseAlphabetical] = alphabeticalRules.reversed.toList()
      ..[_FilterSort.effect] = ([...rules]..sort(_compareByEffect))
      ..[_FilterSort.reverseEffect] = ([...rules]..sort((left, right) => _compareByEffect(left, right, reverse: true)))
      ..[_FilterSort.suspensionTime] = ([...rules]..sort((left, right) => _compareBySuspensionTime(left, right, now)));
    effectCounts
      ..clear()
      ..addEntries(TagFilterEffect.values.map((effect) => MapEntry(effect, 0)));
    markersByKey.clear();
    for (final rule in rules) {
      effectCounts[rule.effect] = effectCounts[rule.effect]! + 1;
      if (rule.effect == TagFilterEffect.mark) markersByKey.putIfAbsent(_markerKey(rule.marker), () => rule.marker);
    }
    markerFilterKeys = markersByKey.keys.toList()
      ..sort((left, right) => _markerSortName(left).compareTo(_markerSortName(right)));
  }

  void _applyFilters() {
    final query = search.toLowerCase();
    final now = DateTime.now().toUtc();
    final handler = TagFilterHandler.instance;
    filteredRules = (sortedRules[sortMode] ?? alphabeticalRules).where((rule) {
      if (selectedEffects.isNotEmpty && !selectedEffects.contains(rule.effect)) return false;
      if (selectedMarkers.isNotEmpty &&
          rule.effect == TagFilterEffect.mark &&
          !selectedMarkers.contains(_markerKey(rule.marker))) {
        return false;
      }
      if (!_matchesScopeFilter(rule)) return false;
      final suspended = rule.enabled && rule.disabledUntil?.isAfter(now) == true;
      final matchesStatus =
          selectedStatuses.isEmpty ||
          selectedStatuses.any(
            (status) => switch (status) {
              'enabled' => rule.enabled && !suspended,
              'disabled' => !rule.enabled,
              'suspended' => suspended,
              'missing' => _isMissingSource(rule),
              'invalid' => handler.errorFor(rule.id) != null,
              _ => false,
            },
          );
      if (!matchesStatus) return false;
      return query.isEmpty || (searchableText[rule.id]?.contains(query) ?? false);
    }).toList();
  }

  String _ruleSortName(TagFilterRule rule) => (rule.name.trim().isEmpty ? rule.query : rule.name).trim().toLowerCase();

  int _compareAlphabetically(TagFilterRule left, TagFilterRule right) {
    final nameResult = _ruleSortName(left).compareTo(_ruleSortName(right));
    if (nameResult != 0) return nameResult;
    final queryResult = left.query.toLowerCase().compareTo(right.query.toLowerCase());
    if (queryResult != 0) return queryResult;
    return left.id.compareTo(right.id);
  }

  int _compareByEffect(TagFilterRule left, TagFilterRule right, {bool reverse = false}) {
    final effectResult = left.effect.index.compareTo(right.effect.index);
    if (effectResult != 0) return effectResult;
    final alphabeticResult = _compareAlphabetically(left, right);
    return reverse ? -alphabeticResult : alphabeticResult;
  }

  int _compareBySuspensionTime(TagFilterRule left, TagFilterRule right, DateTime now) {
    final leftUntil = left.enabled && left.disabledUntil?.isAfter(now) == true ? left.disabledUntil : null;
    final rightUntil = right.enabled && right.disabledUntil?.isAfter(now) == true ? right.disabledUntil : null;
    if (leftUntil != null && rightUntil != null) {
      final timeResult = leftUntil.compareTo(rightUntil);
      return timeResult != 0 ? timeResult : _compareAlphabetically(left, right);
    }
    if (leftUntil != null) return -1;
    if (rightUntil != null) return 1;
    return _compareAlphabetically(left, right);
  }

  Future<void> _openEditor([TagFilterRule? rule]) => showTagFilterEditorSheet(context, rule: rule);

  String _effectName(TagFilterEffect value) => switch (value) {
    TagFilterEffect.hide => context.loc.settings.itemFilters.hide,
    TagFilterEffect.blur => context.loc.settings.itemFilters.blur,
    TagFilterEffect.mark => context.loc.settings.itemFilters.mark,
  };

  IconData _effectIcon(TagFilterEffect value) => switch (value) {
    TagFilterEffect.hide => Icons.visibility_off,
    TagFilterEffect.blur => Icons.blur_on,
    TagFilterEffect.mark => Icons.star,
  };

  Color _effectContainerColor(TagFilterEffect effect) => switch (effect) {
    TagFilterEffect.hide => Theme.of(context).colorScheme.errorContainer,
    TagFilterEffect.blur => Theme.of(context).colorScheme.tertiaryContainer,
    TagFilterEffect.mark => Theme.of(context).colorScheme.primaryContainer,
  };

  Color _onEffectContainerColor(TagFilterEffect effect) => switch (effect) {
    TagFilterEffect.hide => Theme.of(context).colorScheme.onErrorContainer,
    TagFilterEffect.blur => Theme.of(context).colorScheme.onTertiaryContainer,
    TagFilterEffect.mark => Theme.of(context).colorScheme.onPrimaryContainer,
  };

  String _markerKey(TagFilterMarker? marker) => TagFilterMarker.stableKeyFor(marker);

  String _markerSortName(String key) {
    if (key == TagFilterMarker.defaultStableKey) return '';
    final marker = markersByKey[key];
    return (marker?.icon?.name ?? marker?.text ?? key).toLowerCase();
  }

  TagFilterMarker? _markerForKey(String key) => markersByKey[key];

  Widget _markerVisual(TagFilterMarker? marker, {double size = 20, Color? color}) {
    if (marker == null) return Icon(Icons.star, size: size, color: TagFilterMarkerColor.grey.color);
    if (marker.kind == TagFilterMarkerKind.icon) {
      return marker.icon!.build(size: size, color: marker.effectiveColor);
    }
    return SizedBox.square(
      dimension: size,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          marker.text ?? '',
          style: TextStyle(color: marker.effectiveColor, fontWeight: FontWeight.w700, height: 1),
        ),
      ),
    );
  }

  Widget _markerOption(String? key) {
    if (key != null) {
      return _markerVisual(
        _markerForKey(key),
        size: 22,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.loc.settings.itemFilters.allMarkers,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _ruleEffectVisual(TagFilterRule rule, {double size = 20, Color? color}) {
    if (rule.effect == TagFilterEffect.mark) return _markerVisual(rule.marker, size: size, color: color);
    return Icon(_effectIcon(rule.effect), size: size, color: color);
  }

  Widget _ruleEffectAvatar(TagFilterRule rule) => CircleAvatar(
    backgroundColor: _effectContainerColor(rule.effect),
    foregroundColor: _onEffectContainerColor(rule.effect),
    child: _ruleEffectVisual(rule, color: _onEffectContainerColor(rule.effect)),
  );

  List<Booru> get regularBoorus => cachedRegularBoorus;

  String _sourceScopeKey(Booru booru) => 'source:${BooruIdentity.fromBooru(booru).stableKey}';

  List<String> get _scopeFilterKeys => [
    _globalScopeKey,
    ...regularBoorus.map(_sourceScopeKey),
    _favouritesScopeKey,
    _downloadsScopeKey,
  ];

  Booru? _booruForScopeKey(String key) => boorusByScopeKey[key];

  bool _matchesScopeFilter(TagFilterRule rule) {
    if (selectedScopes.isEmpty) return true;
    return selectedScopes.any((scopeKey) => _matchesScopeKey(rule, scopeKey));
  }

  bool _matchesScopeKey(TagFilterRule rule, String scopeKey) {
    if (scopeKey == _globalScopeKey) return rule.scope.kind == TagFilterScopeKind.global;
    if (scopeKey == _favouritesScopeKey) {
      return (rule.scope.kind == TagFilterScopeKind.view && rule.scope.viewType == BooruType.Favourites) ||
          (rule.scope.kind == TagFilterScopeKind.source &&
              rule.scope.targets.any((target) => target.type == BooruType.Favourites));
    }
    if (scopeKey == _downloadsScopeKey) {
      return (rule.scope.kind == TagFilterScopeKind.view && rule.scope.viewType == BooruType.Downloads) ||
          (rule.scope.kind == TagFilterScopeKind.source &&
              rule.scope.targets.any((target) => target.type == BooruType.Downloads));
    }
    final booru = _booruForScopeKey(scopeKey);
    return booru != null &&
        rule.scope.kind == TagFilterScopeKind.source &&
        rule.scope.targets.any((target) => target.matches(booru));
  }

  String _scopeName(String key) {
    final loc = context.loc.settings.itemFilters;
    if (key == _globalScopeKey) return loc.allBoorus;
    if (key == _favouritesScopeKey) return BooruType.Favourites.alias;
    if (key == _downloadsScopeKey) return BooruType.Downloads.alias;
    return _booruForScopeKey(key)?.name ?? loc.missingSource;
  }

  Widget _scopeOption(String? key) {
    if (key == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.loc.settings.itemFilters.allScopes,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final value = key;
    final booru = _booruForScopeKey(value);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (booru != null)
          BooruFavicon(booru, size: 20)
        else
          Icon(
            value == _globalScopeKey
                ? Icons.public
                : value == _favouritesScopeKey
                ? Icons.favorite
                : Icons.download,
            size: 20,
          ),
        const SizedBox(width: 8),
        Flexible(child: Text(_scopeName(value), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  List<({BooruIdentity target, Booru? booru})> _resolvedSources(TagFilterRule rule) => rule.scope.targets.map((target) {
    final booru = target.type?.isFavouritesOrDownloads == true
        ? SettingsHandler.instance.booruList.where((booru) => booru.type == target.type).firstOrNull
        : regularBoorus.where(target.matches).firstOrNull;
    return (target: target, booru: booru);
  }).toList();

  Widget _ruleScopeLabel(TagFilterRule rule) {
    final loc = context.loc.settings.itemFilters;
    if (rule.scope.kind == TagFilterScopeKind.global) {
      final excludedCount = rule.scope.excludedSources.length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.public, size: 16),
          const SizedBox(width: 5),
          Text(loc.allBoorus),
          if (excludedCount > 0) ...[
            const SizedBox(width: 6),
            const Icon(Icons.block, size: 14),
            const SizedBox(width: 4),
            Text(loc.excludedBoorusCount(count: excludedCount)),
          ],
        ],
      );
    }
    if (rule.scope.kind == TagFilterScopeKind.view) {
      final isFavourites = rule.scope.viewType == BooruType.Favourites;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isFavourites ? Icons.favorite : Icons.download, size: 16),
          const SizedBox(width: 5),
          Text(isFavourites ? BooruType.Favourites.alias : BooruType.Downloads.alias),
        ],
      );
    }
    final sources = _resolvedSources(rule);
    final displayed = sources.take(2).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < displayed.length; index++) ...[
          if (displayed[index].target.type == BooruType.Favourites)
            const Icon(Icons.favorite, size: 16)
          else if (displayed[index].target.type == BooruType.Downloads)
            const Icon(Icons.download, size: 16)
          else if (displayed[index].booru != null)
            BooruFavicon(displayed[index].booru, size: 16)
          else
            const Icon(Icons.link_off, size: 16),
          const SizedBox(width: 5),
          Text(
            displayed[index].booru?.name ??
                displayed[index].target.type?.alias ??
                displayed[index].target.name ??
                loc.missingSource,
          ),
          if (index < displayed.length - 1) const Text(',  '),
        ],
        if (sources.length > displayed.length) Text(' +${sources.length - displayed.length}'),
      ],
    );
  }

  Widget _scopeChip(TagFilterRule rule) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSurfaceVariant;
    return Chip(
      backgroundColor: colors.surfaceContainerHighest,
      side: BorderSide.none,
      labelStyle: TextStyle(color: foreground),
      label: IconTheme(
        data: IconThemeData(color: foreground),
        child: _ruleScopeLabel(rule),
      ),
    );
  }

  Widget _effectOption(TagFilterEffect? value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        value == null ? Icons.auto_awesome_motion_outlined : _effectIcon(value),
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value == null ? context.loc.settings.itemFilters.allEffects : _effectName(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _selectionSummary({required IconData icon, required int count}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.loc.settings.itemFilters.selectedCount(count: count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _selectedEffectOptions(List<TagFilterEffect> values) {
    if (values.isEmpty) return _effectOption(null);
    if (values.length == 1) return _effectOption(values.single);
    return _selectionSummary(icon: Icons.auto_awesome_motion_outlined, count: values.length);
  }

  Widget _selectedMarkerOptions(List<String> values) {
    if (values.isEmpty) return _markerOption(null);
    if (values.length == 1) return _markerOption(values.single);
    return _selectionSummary(icon: Icons.auto_awesome_outlined, count: values.length);
  }

  Widget _selectedScopeOptions(List<String> values) {
    if (values.isEmpty) return _scopeOption(null);
    if (values.length == 1) return _scopeOption(values.single);
    return _selectionSummary(icon: Icons.filter_alt_outlined, count: values.length);
  }

  Widget _selectedStatusOptions(List<String> values) {
    if (values.isEmpty) return _statusOption(null);
    if (values.length == 1) return _statusOption(values.single);
    return _selectionSummary(icon: Icons.tune, count: values.length);
  }

  String _sortName(_FilterSort value) {
    final loc = context.loc.settings.itemFilters;
    return switch (value) {
      _FilterSort.alphabetical => loc.sortAlphabetical,
      _FilterSort.reverseAlphabetical => loc.sortReverseAlphabetical,
      _FilterSort.effect => loc.sortEffect,
      _FilterSort.reverseEffect => loc.sortReverseEffect,
      _FilterSort.suspensionTime => loc.sortSuspensionTime,
    };
  }

  IconData _sortIcon(_FilterSort value) => switch (value) {
    _FilterSort.alphabetical || _FilterSort.reverseAlphabetical => Icons.sort_by_alpha,
    _FilterSort.effect || _FilterSort.reverseEffect => Icons.category_outlined,
    _FilterSort.suspensionTime => Icons.timer_outlined,
  };

  Widget _sortOption(_FilterSort? value) {
    final usedValue = value ?? sortMode;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_sortIcon(usedValue), size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(child: Text(_sortName(usedValue), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  bool get hasActiveListFilter =>
      search.trim().isNotEmpty ||
      selectedEffects.isNotEmpty ||
      selectedMarkers.isNotEmpty ||
      selectedScopes.isNotEmpty ||
      selectedStatuses.isNotEmpty;

  bool get hasModifiedListControls => hasActiveListFilter || sortMode != _FilterSort.alphabetical;

  void _resetListFilters() {
    debounce?.cancel();
    searchController.clear();
    setState(() {
      search = '';
      selectedEffects.clear();
      selectedMarkers.clear();
      selectedScopes.clear();
      selectedStatuses.clear();
      sortMode = _FilterSort.alphabetical;
      _applyFilters();
    });
  }

  String _statusName(String value) {
    final loc = context.loc.settings.itemFilters;
    return switch (value) {
      'enabled' => loc.enabled,
      'disabled' => loc.disabled,
      'suspended' => loc.suspended,
      'missing' => loc.missingSource,
      'invalid' => loc.invalidQuery,
      _ => loc.allStates,
    };
  }

  IconData _statusIcon(String value) => switch (value) {
    'enabled' => Icons.check_circle_outline,
    'disabled' => Icons.pause_circle_outline,
    'suspended' => Icons.timer_outlined,
    'missing' => Icons.link_off,
    'invalid' => Icons.error_outline,
    _ => Icons.tune,
  };

  Color _statusContainerColor(String value) => switch (value) {
    'enabled' => Theme.of(context).colorScheme.primaryContainer,
    'suspended' => Theme.of(context).colorScheme.tertiaryContainer,
    'missing' || 'invalid' => Theme.of(context).colorScheme.errorContainer,
    _ => Theme.of(context).colorScheme.surfaceContainerHighest,
  };

  Color _onStatusContainerColor(String value) => switch (value) {
    'enabled' => Theme.of(context).colorScheme.onPrimaryContainer,
    'suspended' => Theme.of(context).colorScheme.onTertiaryContainer,
    'missing' || 'invalid' => Theme.of(context).colorScheme.onErrorContainer,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  Widget _effectChip(TagFilterRule rule) {
    final foreground = _onEffectContainerColor(rule.effect);
    return Chip(
      backgroundColor: _effectContainerColor(rule.effect),
      side: BorderSide.none,
      avatar: _ruleEffectVisual(rule, size: 16, color: foreground),
      label: Text(_effectName(rule.effect)),
      labelStyle: TextStyle(color: foreground),
    );
  }

  Widget _timerBadge(String ruleId, DateTime until) {
    const state = 'suspended';
    final foreground = _onStatusContainerColor(state);
    final endDate = _formatTimerEnd(context, until);
    final timeLeft = _formatTimeLeft(context, until);
    final expanded = expandedTimerRuleIds.contains(ruleId);
    return Tooltip(
      message: expanded ? timeLeft : endDate,
      child: Material(
        color: _statusContainerColor(state),
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          borderRadius: BorderRadius.circular(100),
          onTap: () => setState(() {
            if (expanded) {
              expandedTimerRuleIds.remove(ruleId);
            } else {
              expandedTimerRuleIds.add(ruleId);
            }
          }),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: foreground),
                  const SizedBox(width: 6),
                  Text(expanded ? endDate : timeLeft, style: TextStyle(color: foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _issueChip(String state) {
    final foreground = _onStatusContainerColor(state);
    return Chip(
      backgroundColor: _statusContainerColor(state),
      side: BorderSide.none,
      avatar: Icon(_statusIcon(state), size: 16, color: foreground),
      label: Text(_statusName(state)),
      labelStyle: TextStyle(color: foreground),
    );
  }

  Widget _statusOption(String? value) {
    final usedValue = value ?? 'all';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_statusIcon(usedValue), size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(child: Text(_statusName(usedValue), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _dropdownSheetItem(Widget child) => Container(
    constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );

  String _formatTimerEnd(BuildContext context, DateTime until) {
    final localUntil = until.toLocal();
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatFullDate(localUntil)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(localUntil))}';
  }

  String _formatTimeLeft(BuildContext context, DateTime until) {
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

  Widget _hideAsBlurTimerBadge(BuildContext context, DateTime until) {
    final colors = Theme.of(context).colorScheme;
    final loc = context.loc.settings.itemFilters;
    return Tooltip(
      message: loc.endsAt(value: _formatTimerEnd(context, until)),
      child: Chip(
        backgroundColor: colors.tertiaryContainer,
        side: BorderSide.none,
        avatar: Icon(Icons.timer_outlined, size: 16, color: colors.onTertiaryContainer),
        label: Text(_formatTimeLeft(context, until)),
        labelStyle: TextStyle(color: colors.onTertiaryContainer),
      ),
    );
  }

  Future<void> _setHideAsBlurDuration(String value) async {
    final now = DateTime.now().toUtc();
    final until = switch (value) {
      '15m' => now.add(const Duration(minutes: 15)),
      '30m' => now.add(const Duration(minutes: 30)),
      '1h' => now.add(const Duration(hours: 1)),
      '6h' => now.add(const Duration(hours: 6)),
      '12h' => now.add(const Duration(hours: 12)),
      '1d' => now.add(const Duration(days: 1)),
      '1w' => now.add(const Duration(days: 7)),
      'custom' => await showTagFilterCustomUntilSheet(context),
      _ => null,
    };
    if (value == 'off') {
      await TagFilterHandler.instance.setHideAsBlur(enabled: false);
    } else if (value == 'forever') {
      await TagFilterHandler.instance.setHideAsBlur(enabled: true);
    } else if (until != null) {
      await TagFilterHandler.instance.setHideAsBlur(enabled: true, until: until);
    }
  }

  Future<void> _showHideAsBlurOptions() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final loc = sheetContext.loc.settings.itemFilters;
      final options = <(String, String, IconData)>[
        ('15m', loc.minutesPlural(count: 15), Icons.timer_outlined),
        ('30m', loc.minutesPlural(count: 30), Icons.timer_outlined),
        ('1h', loc.hoursPlural(count: 1), Icons.schedule),
        ('6h', loc.hoursPlural(count: 6), Icons.schedule),
        ('12h', loc.hoursPlural(count: 12), Icons.schedule),
        ('1d', loc.daysPlural(count: 1), Icons.today_outlined),
        ('1w', loc.weeksPlural(count: 1), Icons.date_range_outlined),
        ('custom', loc.customDuration, Icons.edit_calendar_outlined),
        ('forever', loc.indefinitely, Icons.all_inclusive),
        ('off', loc.disabled, Icons.visibility_off_outlined),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(loc.hideAsBlur, style: Theme.of(sheetContext).textTheme.titleLarge)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    leading: Icon(option.$3),
                    title: Text(option.$2),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _setHideAsBlurDuration(option.$1);
                    },
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _runRuleAction(TagFilterRule rule, String value) async {
    final handler = TagFilterHandler.instance;
    switch (value) {
      case 'edit':
        await _openEditor(rule);
      case 'delete':
        await handler.deleteRule(rule.id);
    }
  }

  Future<void> _changeRuleAvailability(TagFilterRule rule) async {
    final activeTimer = rule.enabled && rule.disabledUntil?.isAfter(DateTime.now().toUtc()) == true;
    final change = await showTagFilterSuspensionSheet(
      context,
      showReenable: !rule.enabled || activeTimer,
    );
    if (change == null) return;
    await TagFilterHandler.instance.updateRule(
      rule.copyWith(
        enabled: change.enabled,
        disabledUntil: change.disabledUntil,
        clearDisabledUntil: change.disabledUntil == null,
      ),
    );
  }

  Future<void> _showRuleActions(TagFilterRule rule) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final loc = sheetContext.loc.settings.itemFilters;
      final activeTimer = rule.enabled && rule.disabledUntil?.isAfter(DateTime.now().toUtc()) == true;
      final showQuery = rule.hasDistinctName;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: _ruleEffectAvatar(rule),
                title: showQuery
                    ? MarqueeText(
                        text: rule.displayName,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                        isExpanded: false,
                      )
                    : TagFilterQueryText(
                        query: rule.query,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showQuery) TagFilterQueryText(query: rule.query),
                    Text(_effectName(rule.effect)),
                    if (activeTimer)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.timeLeft(
                                      value: _formatTimeLeft(sheetContext, rule.disabledUntil!),
                                    ),
                                  ),
                                  Text(
                                    loc.endsAt(
                                      value: _formatTimerEnd(sheetContext, rule.disabledUntil!),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(loc.editRule),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _runRuleAction(rule, 'edit');
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: Text(loc.disableFor),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _changeRuleAvailability(rule);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(sheetContext).colorScheme.error),
                title: Text(context.loc.delete, style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _runRuleAction(rule, 'delete');
                },
              ),
            ],
          ),
        ),
      );
    },
  );

  bool _isMissingSource(TagFilterRule rule) {
    return [...rule.scope.targets, ...rule.scope.excludedSources].any(
      (source) => !cachedRegularBoorus.any(source.matches),
    );
  }

  bool get _isSelecting => selectedRuleIds.isNotEmpty || _selectionMode;

  void _toggleSelection(String id) {
    setState(() {
      _selectionMode = true;
      if (!selectedRuleIds.add(id)) selectedRuleIds.remove(id);
    });
  }

  void _closeSelection() {
    setState(() {
      selectedRuleIds.clear();
      _selectionMode = false;
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectionMode = true;
      final visibleIds = filteredRules.map((rule) => rule.id).toSet();
      if (visibleIds.isNotEmpty && selectedRuleIds.containsAll(visibleIds)) {
        selectedRuleIds.removeAll(visibleIds);
      } else {
        selectedRuleIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _applyAvailabilityToRules(TagFilterAvailabilityChange change, Set<String> ids) async {
    if (ids.isEmpty) return;
    final disabledUntil = change.disabledUntil?.toUtc();
    final replacements = TagFilterHandler.instance.rules
        .where((rule) => ids.contains(rule.id))
        .where((rule) => rule.enabled != change.enabled || rule.disabledUntil != disabledUntil)
        .map(
          (rule) => rule.copyWith(
            enabled: change.enabled,
            disabledUntil: disabledUntil,
            clearDisabledUntil: disabledUntil == null,
          ),
        );
    await TagFilterHandler.instance.updateRules(replacements);
  }

  Future<void> _applyEffectToRules(TagFilterEffect effect, Set<String> ids) async {
    if (ids.isEmpty) return;
    final replacements = TagFilterHandler.instance.rules
        .where((rule) => ids.contains(rule.id) && rule.effect != effect)
        .map((rule) => rule.copyWith(effect: effect));
    await TagFilterHandler.instance.updateRules(replacements);
  }

  Future<void> _suspendSelected(Set<String> ids) async {
    final change = await showTagFilterSuspensionSheet(context, showReenable: false);
    if (change != null) await _applyAvailabilityToRules(change, ids);
  }

  Future<void> _confirmDeleteSelected(Set<String> ids) async {
    final count = ids.length;
    if (count == 0) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetContext.loc.settings.itemFilters.deleteSelected(count: count),
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(sheetContext.loc.settings.itemFilters.deleteSelectedConfirm(count: count)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(sheetContext.loc.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(sheetContext).colorScheme.error,
                    foregroundColor: Theme.of(sheetContext).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(sheetContext.loc.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    _closeSelection();
    await TagFilterHandler.instance.deleteRules(ids);
  }

  Future<void> _showBatchActions() {
    final selectedIds = Set<String>.of(selectedRuleIds);
    final now = DateTime.now().toUtc();
    final selectedRules = TagFilterHandler.instance.rules.where((rule) => selectedIds.contains(rule.id)).toList();
    final enableIds = selectedRules
        .where((rule) => !rule.enabled || rule.disabledUntil?.isAfter(now) == true)
        .map((rule) => rule.id)
        .toSet();
    final suspendIds = selectedRules.map((rule) => rule.id).toSet();
    final disableIds = selectedRules.where((rule) => rule.enabled).map((rule) => rule.id).toSet();
    final changeToHideIds = selectedRules
        .where((rule) => rule.effect == TagFilterEffect.blur)
        .map((rule) => rule.id)
        .toSet();
    final changeToBlurIds = selectedRules
        .where((rule) => rule.effect == TagFilterEffect.hide)
        .map((rule) => rule.id)
        .toSet();
    final deleteIds = Set<String>.of(suspendIds);

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) {
        final loc = sheetContext.loc.settings.itemFilters;
        Future<void> run(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await action();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(loc.batchActions, style: Theme.of(sheetContext).textTheme.titleLarge),
              subtitle: Text(loc.selectedCount(count: selectedRules.length)),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            const Divider(height: 1),
            if (enableIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(loc.enableSelected(count: enableIds.length)),
                onTap: () => run(
                  () => _applyAvailabilityToRules(
                    const TagFilterAvailabilityChange(enabled: true),
                    enableIds,
                  ),
                ),
              ),
            if (suspendIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: Text(loc.suspendSelected(count: suspendIds.length)),
                onTap: () => run(() => _suspendSelected(suspendIds)),
              ),
            if (disableIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(loc.disableSelected(count: disableIds.length)),
                onTap: () => run(
                  () => _applyAvailabilityToRules(
                    const TagFilterAvailabilityChange(enabled: false),
                    disableIds,
                  ),
                ),
              ),
            if (changeToHideIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.visibility_off),
                title: Text(loc.changeSelectedToHide(count: changeToHideIds.length)),
                onTap: () => run(() => _applyEffectToRules(TagFilterEffect.hide, changeToHideIds)),
              ),
            if (changeToBlurIds.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.blur_on),
                title: Text(loc.changeSelectedToBlur(count: changeToBlurIds.length)),
                onTap: () => run(() => _applyEffectToRules(TagFilterEffect.blur, changeToBlurIds)),
              ),
            if (deleteIds.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(sheetContext).colorScheme.error),
                title: Text(
                  loc.deleteSelected(count: deleteIds.length),
                  style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                ),
                onTap: () => run(() => _confirmDeleteSelected(deleteIds)),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showFilterSettings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (sheetContext) => ValueListenableBuilder<int>(
      valueListenable: TagFilterHandler.instance.revision,
      builder: (sheetContext, _, _) => ValueListenableBuilder<int>(
        valueListenable: countdownRevision,
        builder: (sheetContext, _, _) {
          final handler = TagFilterHandler.instance;
          final loc = sheetContext.loc.settings.itemFilters;
          final now = DateTime.now().toUtc();
          final hideAsBlur = handler.configuration.hideAsBlur;
          final temporaryUntil = hideAsBlur.enabled && hideAsBlur.until?.isAfter(now) == true ? hideAsBlur.until : null;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(loc.filteringSettings, style: Theme.of(sheetContext).textTheme.titleLarge),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(loc.hideAsBlur),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(loc.hideAsBlurHelp),
                            if (temporaryUntil != null) ...[
                              const SizedBox(height: 6),
                              _hideAsBlurTimerBadge(sheetContext, temporaryUntil),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: handler.configuration.hideAsBlur.isActiveAt(now),
                              onChanged: (value) => handler.setHideAsBlur(enabled: value),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              tooltip: loc.customDuration,
                              onPressed: _showHideAsBlurOptions,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      for (final state in SettingsRegistry.instance.byCategory(SettingCategory.tagsFilters))
                        if (SettingsRegistry.instance.isSettingVisible(state) &&
                            state.def.widgetBuilder != null &&
                            !{
                              SettingKey.hiddenTags,
                              SettingKey.markedTags,
                              SettingKey.filterHated,
                            }.contains(state.def.key))
                          state.buildWidget(sheetContext),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = context.loc.settings.itemFilters;
    final handler = TagFilterHandler.instance;
    final now = DateTime.now().toUtc();
    final rules = filteredRules;
    return Scaffold(
      appBar: AppBar(
        leading: _isSelecting
            ? IconButton(
                tooltip: context.loc.close,
                onPressed: _closeSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(_isSelecting ? loc.selectedCount(count: selectedRuleIds.length) : loc.rules),
        actions: _isSelecting
            ? [
                IconButton(
                  tooltip: context.loc.selectAll,
                  onPressed: _selectAllVisible,
                  icon: const Icon(Icons.select_all),
                ),
              ]
            : [
                IconButton(
                  tooltip: loc.selectFilters,
                  onPressed: () => setState(() => _selectionMode = true),
                  icon: const Icon(Icons.checklist_rtl),
                ),
                IconButton(
                  tooltip: loc.filteringSettings,
                  onPressed: _showFilterSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  tooltip: loc.importLegacy,
                  onPressed: () async {
                    final count = await handler.importLegacy(force: true);
                    if (context.mounted) {
                      FlashElements.showSnackbar(
                        context: context,
                        title: Text(loc.legacyImported(count: count)),
                        sideColor: Colors.green,
                        leadingIcon: Icons.check,
                      );
                    }
                  },
                  icon: const Icon(Icons.file_download_outlined),
                ),
              ],
      ),
      floatingActionButton: _isSelecting
          ? FloatingActionButton.extended(
              onPressed: selectedRuleIds.isEmpty ? null : _showBatchActions,
              icon: const Icon(Icons.playlist_add_check),
              label: Text(loc.batchActions),
            )
          : FloatingActionButton(onPressed: _openEditor, child: const Icon(Icons.add)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: context.loc.search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() {
                          searchController.clear();
                          search = '';
                          _applyFilters();
                        }),
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) {
                debounce?.cancel();
                debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) {
                    setState(() {
                      search = value;
                      _applyFilters();
                    });
                  }
                });
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FadingEdgeScrollView.fromSingleChildScrollView(
                  child: SingleChildScrollView(
                    controller: filterControlsScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 180,
                          child: LoliMultiselectDropdown<TagFilterEffect>(
                            value: selectedEffects.toList(),
                            labelText: loc.effect,
                            items: TagFilterEffect.values,
                            itemBuilder: (value) => _dropdownSheetItem(_effectOption(value)),
                            selectedItemBuilder: _selectedEffectOptions,
                            onChanged: (values) => setState(() {
                              selectedEffects
                                ..clear()
                                ..addAll(values);
                              if (selectedEffects.isNotEmpty && !selectedEffects.contains(TagFilterEffect.mark)) {
                                selectedMarkers.clear();
                              }
                              _applyFilters();
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 190,
                          child: LoliMultiselectDropdown<String>(
                            value: selectedMarkers.toList(),
                            labelText: loc.marker,
                            items: markerFilterKeys,
                            itemBuilder: (value) => _dropdownSheetItem(_markerOption(value)),
                            selectedItemBuilder: _selectedMarkerOptions,
                            onChanged: (values) => setState(() {
                              selectedMarkers
                                ..clear()
                                ..addAll(values);
                              if (selectedMarkers.isNotEmpty) {
                                selectedEffects
                                  ..clear()
                                  ..add(TagFilterEffect.mark);
                              }
                              _applyFilters();
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 220,
                          child: LoliMultiselectDropdown<String>(
                            value: selectedScopes.toList(),
                            labelText: loc.scope,
                            items: _scopeFilterKeys,
                            itemBuilder: (value) => _dropdownSheetItem(_scopeOption(value)),
                            selectedItemBuilder: _selectedScopeOptions,
                            onChanged: (values) => setState(() {
                              selectedScopes
                                ..clear()
                                ..addAll(values);
                              _applyFilters();
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 190,
                          child: LoliMultiselectDropdown<String>(
                            value: selectedStatuses.toList(),
                            labelText: loc.allStates,
                            items: const ['enabled', 'disabled', 'suspended', 'missing', 'invalid'],
                            itemBuilder: (value) => _dropdownSheetItem(_statusOption(value)),
                            selectedItemBuilder: _selectedStatusOptions,
                            onChanged: (values) => setState(() {
                              selectedStatuses
                                ..clear()
                                ..addAll(values);
                              _applyFilters();
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 250,
                          child: LoliDropdown<_FilterSort>(
                            value: sortMode,
                            labelText: context.loc.sort,
                            items: _FilterSort.values,
                            itemBuilder: (value) => _dropdownSheetItem(_sortOption(value)),
                            selectedItemBuilder: _sortOption,
                            onChanged: (value) => setState(() {
                              sortMode = value!;
                              _applyFilters();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
                child: IconButton.outlined(
                  onPressed: hasModifiedListControls ? _resetListFilters : null,
                  tooltip: context.loc.reset,
                  icon: const Icon(Icons.restart_alt),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(label: Text(loc.counterTotal(count: handler.rules.length))),
                  if (hasActiveListFilter) Chip(label: Text(loc.counterShown(count: rules.length))),
                  Chip(
                    backgroundColor: _effectContainerColor(TagFilterEffect.hide),
                    side: BorderSide.none,
                    avatar: Icon(
                      Icons.visibility_off,
                      size: 16,
                      color: _onEffectContainerColor(TagFilterEffect.hide),
                    ),
                    label: Text(
                      loc.counterHide(count: effectCounts[TagFilterEffect.hide] ?? 0),
                    ),
                    labelStyle: TextStyle(color: _onEffectContainerColor(TagFilterEffect.hide)),
                  ),
                  Chip(
                    backgroundColor: _effectContainerColor(TagFilterEffect.blur),
                    side: BorderSide.none,
                    avatar: Icon(
                      Icons.blur_on,
                      size: 16,
                      color: _onEffectContainerColor(TagFilterEffect.blur),
                    ),
                    label: Text(
                      loc.counterBlur(count: effectCounts[TagFilterEffect.blur] ?? 0),
                    ),
                    labelStyle: TextStyle(color: _onEffectContainerColor(TagFilterEffect.blur)),
                  ),
                  Chip(
                    backgroundColor: _effectContainerColor(TagFilterEffect.mark),
                    side: BorderSide.none,
                    avatar: Icon(
                      Icons.star,
                      size: 16,
                      color: _onEffectContainerColor(TagFilterEffect.mark),
                    ),
                    label: Text(
                      loc.counterMark(count: effectCounts[TagFilterEffect.mark] ?? 0),
                    ),
                    labelStyle: TextStyle(color: _onEffectContainerColor(TagFilterEffect.mark)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showFilterSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(loc.filteringSettings),
              ),
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? Center(child: Text(loc.noFiltersFound))
                : FadingEdgeScrollView.fromScrollView(
                    child: ListView.builder(
                      controller: rulesScrollController,
                      itemCount: rules.length,
                      itemBuilder: (context, index) {
                        final rule = rules[index];
                        final error = handler.errorFor(rule.id);
                        final activeTimer = rule.enabled && rule.disabledUntil?.isAfter(now) == true;
                        final missing = _isMissingSource(rule);
                        final showQuery = rule.hasDistinctName;
                        final selected = selectedRuleIds.contains(rule.id);
                        return ListTile(
                          selected: selected,
                          tileColor: activeTimer
                              ? Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.24)
                              : null,
                          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45),
                          leading: _isSelecting
                              ? Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggleSelection(rule.id),
                                )
                              : _ruleEffectAvatar(rule),
                          title: showQuery
                              ? MarqueeText(
                                  text: rule.displayName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  isExpanded: false,
                                )
                              : TagFilterQueryText(
                                  query: rule.query,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showQuery) TagFilterQueryText(query: rule.query),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _effectChip(rule),
                                  if (activeTimer) _timerBadge(rule.id, rule.disabledUntil!),
                                  _scopeChip(rule),
                                  if (error != null) _issueChip('invalid'),
                                  if (missing) _issueChip('missing'),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () => _isSelecting ? _toggleSelection(rule.id) : _openEditor(rule),
                          onLongPress: () => _toggleSelection(rule.id),
                          trailing: _isSelecting
                              ? null
                              : SizedBox(
                                  width: 108,
                                  height: kMinInteractiveDimension,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Switch(
                                        value: rule.enabled,
                                        onChanged: (value) => handler.updateRule(
                                          rule.copyWith(enabled: value, clearDisabledUntil: true),
                                        ),
                                      ),
                                      SizedBox.square(
                                        dimension: kMinInteractiveDimension,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.more_vert),
                                          tooltip: context.loc.searchBar.more,
                                          onPressed: () => _showRuleActions(rule),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
