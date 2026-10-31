import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/data/tag_filter_query.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_filter_repository.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/utils/booru_rating.dart';

class CompiledTagFilterRule {
  const CompiledTagFilterRule({required this.rule, required this.index, this.query, this.error});
  final TagFilterRule rule;
  final int index;
  final TagFilterQuery? query;
  final TagFilterQueryError? error;
}

class _PrefixIndexNode {
  final Map<int, _PrefixIndexNode> children = {};
  final List<int> ruleIndexes = [];
}

class _TagPrefixIndex {
  _PrefixIndexNode root = _PrefixIndexNode();
  int ruleCount = 0;

  void clear() {
    root = _PrefixIndexNode();
    ruleCount = 0;
  }

  void add(String prefix, int ruleIndex) {
    var node = root;
    for (final rune in prefix.runes) {
      node = node.children.putIfAbsent(rune, _PrefixIndexNode.new);
    }
    node.ruleIndexes.add(ruleIndex);
    ruleCount++;
  }

  Iterable<List<int>> matchingLists(String tag) sync* {
    var node = root;
    for (final rune in tag.runes) {
      final next = node.children[rune];
      if (next == null) return;
      node = next;
      if (node.ruleIndexes.isNotEmpty) yield node.ruleIndexes;
    }
  }
}

class _PostingCursor {
  _PostingCursor(this.indexes);

  final List<int> indexes;
  int offset = 0;
  int get current => indexes[offset];
  bool get moveNext => ++offset < indexes.length;
}

String _reversedRunes(String value) => String.fromCharCodes(value.runes.toList(growable: false).reversed);

String? _longestString(Iterable<String> values) => values.fold<String?>(
  null,
  (longest, value) => longest == null || value.length > longest.length ? value : longest,
);

class TagFilterHandler {
  TagFilterHandler(this._repository, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static TagFilterHandler get instance => GetIt.instance<TagFilterHandler>();

  static TagFilterHandler register({FilterRepository? repository, DateTime Function()? clock}) {
    if (!GetIt.instance.isRegistered<TagFilterHandler>()) {
      GetIt.instance.registerSingleton(TagFilterHandler(repository, clock: clock));
    }
    return instance;
  }

  static Future<void> unregister() async {
    if (GetIt.instance.isRegistered<TagFilterHandler>()) {
      instance.dispose();
      await GetIt.instance.unregister<TagFilterHandler>();
    }
  }

  FilterRepository? _repository;
  final DateTime Function() _clock;
  TagFilterConfiguration _configuration = const TagFilterConfiguration();
  final ValueNotifier<int> revision = ValueNotifier(0);
  Future<void> _pendingOperations = Future.value();
  Timer? _expiryTimer;
  Timer? _refilterTimer;
  int _refilterGeneration = 0;
  bool _refilterForceRefresh = false;
  DateTime? _nextExpiry;
  bool _disposed = false;
  int _evaluationRevision = 0;
  final List<SettingState<bool>> _activeFilterSettings = [];
  final List<VoidCallback> _optionListenerDisposers = [];
  final Map<TimedFilterOption, int> _manualOptionVersions = {};
  final Map<BooruHandler, int> _activeHandlers = Map.identity();
  bool _applyingOptionTimers = false;
  StreamSubscription<List<Booru>>? _booruCatalogSubscription;

  final List<CompiledTagFilterRule> _compiled = [];
  final Map<String, TagFilterQueryError> _errorsByRuleId = {};
  final Map<String, List<int>> _exactIndex = {};
  final _TagPrefixIndex _prefixIndex = _TagPrefixIndex();
  final _TagPrefixIndex _suffixIndex = _TagPrefixIndex();
  final Map<String, List<int>> _ratingIndex = {};
  final List<int> _fallback = [];

  int get evaluationRevision => _evaluationRevision;

  TagFilterConfiguration get configuration => _configuration;
  List<TagFilterRule> get rules => _configuration.rules;
  FilterRepository get repository => _repository!;
  FilterRecovery? get recovery =>
      _repository is JsonFilterRepository ? (_repository! as JsonFilterRepository).recovery : null;

  Future<void> initialize() async {
    _repository ??= JsonFilterRepository(SettingsHandler.instance.path);
    _configuration = await repository.load();
    _applyOptionTimers();
    _compile();
    _scheduleExpiry();
    _listenForActiveFilterSettingChanges();
    _listenForBooruCatalogChanges();
  }

  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _refilterTimer?.cancel();
    for (final setting in _activeFilterSettings) {
      setting.globalNotifier.removeListener(_activeFilterSettingChanged);
      setting.overridesNotifier.removeListener(_activeFilterSettingChanged);
    }
    _activeFilterSettings.clear();
    for (final dispose in _optionListenerDisposers) {
      dispose();
    }
    _optionListenerDisposers.clear();
    _activeHandlers.clear();
    unawaited(_booruCatalogSubscription?.cancel());
    _booruCatalogSubscription = null;
    revision.dispose();
  }

  void _listenForActiveFilterSettingChanges() {
    if (_activeFilterSettings.isNotEmpty) return;
    const keys = [
      SettingKey.filterMarked,
      SettingKey.filterFavourites,
      SettingKey.filterSnatched,
      SettingKey.filterAi,
    ];
    for (final key in keys) {
      final setting = SettingsRegistry.instance.get<bool>(key);
      if (setting == null) continue;
      _activeFilterSettings.add(setting);
      setting.globalNotifier.addListener(_activeFilterSettingChanged);
      setting.overridesNotifier.addListener(_activeFilterSettingChanged);
    }
    for (final option in TimedFilterOption.values) {
      final setting = _optionSetting(option);
      void changed() {
        if (_disposed || _applyingOptionTimers) return;
        final expected = configuration.enabledUntil[option];
        if (expected == null) return;
        final manualValue = setting.globalValue;
        final version = (_manualOptionVersions[option] ?? 0) + 1;
        _manualOptionVersions[option] = version;
        unawaited(
          _enqueueOperation(() async {
            if (configuration.enabledUntil[option] != expected || _manualOptionVersions[option] != version) return;
            final deadlines = {...configuration.enabledUntil}..remove(option);
            await _commitNow(_copyConfiguration(enabledUntil: deadlines));
            if (_manualOptionVersions[option] != version) return;
            _applyingOptionTimers = true;
            try {
              setting.setValue(manualValue);
            } finally {
              _applyingOptionTimers = false;
            }
          }).catchError((Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stackTrace, library: 'filter timers'),
            );
          }),
        );
      }

      setting.globalNotifier.addListener(changed);
      _optionListenerDisposers.add(() => setting.globalNotifier.removeListener(changed));
    }
  }

  SettingState<bool> _optionSetting(TimedFilterOption option) => switch (option) {
    TimedFilterOption.favourites => SX.filterFavourites.state,
    TimedFilterOption.snatched => SX.filterSnatched.state,
    TimedFilterOption.marked => SX.filterMarked.state,
    TimedFilterOption.ai => SX.filterAi.state,
  };

  bool optionEnabled(TimedFilterOption option, {String? booruName}) {
    final setting = _optionSetting(option);
    if (booruName != null && setting.hasOverrideFor(booruName)) return setting.valueForBooru(booruName);
    final until = configuration.enabledUntil[option];
    return until == null ? setting.globalValue : _clock().toUtc().isBefore(until);
  }

  Future<void> enableOptionUntil(TimedFilterOption option, DateTime until) => _enqueueOperation(() async {
    final deadline = until.toUtc();
    if (!deadline.isAfter(_clock().toUtc())) {
      throw ArgumentError.value(until, 'until', 'Deadline must be in the future');
    }
    await _commitNow(_copyConfiguration(enabledUntil: {...configuration.enabledUntil, option: deadline}));
  });

  void _applyOptionTimers() {
    _applyingOptionTimers = true;
    try {
      for (final entry in configuration.enabledUntil.entries) {
        final setting = _optionSetting(entry.key);
        final enabled = _clock().toUtc().isBefore(entry.value);
        if (setting.globalValue != enabled) setting.setValue(enabled);
      }
    } finally {
      _applyingOptionTimers = false;
    }
  }

  /// Keeps preview/viewer handlers current even when their tab is not in the catalog.
  VoidCallback watchHandler(BooruHandler handler) {
    final alreadyWatching = _activeHandlers.containsKey(handler);
    _activeHandlers.update(handler, (count) => count + 1, ifAbsent: () => 1);
    if (!alreadyWatching) _refilterLoadedTabs();
    return () {
      final count = _activeHandlers[handler];
      if (count == null) return;
      if (count == 1) {
        _activeHandlers.remove(handler);
      } else {
        _activeHandlers[handler] = count - 1;
      }
    };
  }

  void _activeFilterSettingChanged() {
    if (_disposed) return;
    _refilterLoadedTabs(forceRefresh: false);
  }

  void _listenForBooruCatalogChanges() {
    if (_booruCatalogSubscription != null || !GetIt.instance.isRegistered<SettingsHandler>()) return;
    _booruCatalogSubscription = SettingsHandler.instance.booruList.listen((_) {
      if (_disposed) return;
      // Source-scoped evaluations also change for standalone media.
      _evaluationRevision++;
      revision.value = _evaluationRevision;
      _refilterLoadedTabs(forceRefresh: true);
    });
  }

  TagFilterQueryParseResult validateQuery(String query) => TagFilterQuery.parse(query);

  TagFilterQueryError? errorFor(String ruleId) => _errorsByRuleId[ruleId];

  Future<void> addRule(TagFilterRule rule) => _enqueueOperation(() async {
    if (rules.any((existing) => existing.id == rule.id)) {
      throw ArgumentError.value(rule.id, 'rule.id', 'A filter rule with this id already exists');
    }
    await _commitNow(_copyConfiguration(rules: [...rules, rule]));
  });

  Future<void> updateRule(TagFilterRule rule, {TagFilterRule? original}) => _enqueueOperation(() async {
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    final latest = rules[index];
    // Content snapshots never implicitly change availability. The editor passes
    // its original rule to distinguish explicit availability edits from stale data.
    final enabled = original != null && rule.enabled != original.enabled ? rule.enabled : latest.enabled;
    final until = original != null && rule.disabledUntil != original.disabledUntil
        ? rule.disabledUntil
        : latest.disabledUntil;
    final merged = latest.copyWith(
      name: original == null || rule.name != original.name ? rule.name : latest.name,
      query: original == null || rule.query != original.query ? rule.query : latest.query,
      effect: original == null || rule.effect != original.effect ? rule.effect : latest.effect,
      scope: original == null || rule.scope.stableKey != original.scope.stableKey ? rule.scope : latest.scope,
      marker: original == null || rule.marker?.stableKey != original.marker?.stableKey ? rule.marker : latest.marker,
      clearMarker: rule.marker == null && (original == null || original.marker != null),
      showMarkerInGrid: original == null || rule.showMarkerInGrid != original.showMarkerInGrid
          ? rule.showMarkerInGrid
          : latest.showMarkerInGrid,
      enabled: enabled,
      disabledUntil: until,
      clearDisabledUntil: until == null,
    );
    final updated = [...rules]..[index] = merged;
    await _commitNow(_copyConfiguration(rules: updated));
  });

  Future<void> changeRules(Set<String> ids, TagFilterRule Function(TagFilterRule) change) =>
      _enqueueOperation(() async {
        if (!rules.any((rule) => ids.contains(rule.id))) return;
        await _commitNow(
          _copyConfiguration(
            rules: [
              for (final rule in rules)
                if (ids.contains(rule.id)) change(rule) else rule,
            ],
          ),
        );
      });

  Future<void> deleteRule(String id) => _enqueueOperation(
    () => _commitNow(_copyConfiguration(rules: rules.where((rule) => rule.id != id).toList())),
  );

  Future<void> deleteRules(Set<String> ids) => _enqueueOperation(() async {
    if (ids.isEmpty) return;
    final updated = rules.where((rule) => !ids.contains(rule.id)).toList(growable: false);
    if (updated.length != rules.length) await _commitNow(_copyConfiguration(rules: updated));
  });

  Future<void> suspendRule(String id, DateTime? until) => _enqueueOperation(() async {
    final rule = rules.where((item) => item.id == id).firstOrNull;
    if (rule == null) return;
    final index = rules.indexOf(rule);
    final updated = [...rules]
      ..[index] = rule.copyWith(enabled: true, disabledUntil: until?.toUtc(), clearDisabledUntil: until == null);
    await _commitNow(_copyConfiguration(rules: updated));
  });

  Future<void> setHideAsBlur({required bool enabled, DateTime? until}) => _enqueueOperation(
    () => _commitNow(
      _copyConfiguration(
        hideAsBlur: HideAsBlurState(enabled: enabled, until: until?.toUtc()),
      ),
    ),
  );

  Future<void> replaceFromString(String content) => _enqueueOperation(() async {
    await repository.replaceFromString(content);
    _configuration = await repository.load();
    _configurationChanged();
  });

  Future<String> export() => _enqueueOperation(repository.export);

  Future<int> importLegacy({bool force = false}) => _enqueueOperation(() => _importLegacyNow(force: force));

  Future<int> _importLegacyNow({required bool force}) async {
    const importVersion = 2;
    if (!force && _configuration.legacyImportVersion >= importVersion) return 0;

    final now = _clock().toUtc();
    final additions = <TagFilterRule>[];
    final existingKeys = rules.map((rule) => rule.legacySourceKey).whereType<String>().toSet();
    final filterHatedState = SX.filterHated.state;
    final globalHide = filterHatedState.globalValue;
    final overrides = <Booru, bool>{};
    for (final booru in SettingsHandler.instance.booruList) {
      final name = booru.name;
      if (name == null || booru.type?.isFavouritesOrDownloads == true) continue;
      final override = filterHatedState.getOverrideFor(name);
      if (override != null && override != globalHide) overrides[booru] = override;
    }

    void add({
      required String sourceKey,
      required String tag,
      required TagFilterEffect effect,
      required TagFilterScope scope,
    }) {
      if (!existingKeys.add(sourceKey)) return;
      additions.add(
        TagFilterRule(
          id: const Uuid().v4(),
          name: tag,
          query: TagFilterQuery.escapeExactTag(tag.trim().toLowerCase()),
          effect: effect,
          scope: scope,
          enabled: true,
          legacySourceKey: sourceKey,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (final rawTag in LinkedHashSet<String>.from(SX.hiddenTags.value.map((tag) => tag.trim().toLowerCase()))) {
      if (rawTag.isEmpty) continue;
      final excludedSources = overrides.keys.map(BooruIdentity.fromBooru).toList();
      add(
        sourceKey: 'legacy:hidden:$rawTag:global',
        tag: rawTag,
        effect: globalHide ? TagFilterEffect.hide : TagFilterEffect.blur,
        scope: TagFilterScope.global(excludedSources: excludedSources),
      );
      for (final entry in overrides.entries) {
        add(
          sourceKey: 'legacy:hidden:$rawTag:${BooruIdentity.fromBooru(entry.key).stableKey}',
          tag: rawTag,
          effect: entry.value ? TagFilterEffect.hide : TagFilterEffect.blur,
          scope: TagFilterScope.source(BooruIdentity.fromBooru(entry.key)),
        );
      }
    }

    for (final rawTag in LinkedHashSet<String>.from(SX.markedTags.value.map((tag) => tag.trim().toLowerCase()))) {
      if (rawTag.isEmpty) continue;
      add(
        sourceKey: 'legacy:marked:$rawTag:global',
        tag: rawTag,
        effect: TagFilterEffect.mark,
        scope: const TagFilterScope.global(),
      );
    }

    await _commitNow(
      TagFilterConfiguration(
        schemaVersion: _configuration.schemaVersion,
        legacyImportVersion: importVersion,
        rules: [...rules, ...additions],
        hideAsBlur: _configuration.hideAsBlur,
        enabledUntil: _configuration.enabledUntil,
      ),
    );
    return additions.length;
  }

  Set<String> normalizeTags(BooruItem item) =>
      item.tagsList.map((tag) => tag.fullString.trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet();

  TagFilterEvaluation evaluate(BooruItem item, FilterContext context, {Set<String>? normalizedTags}) {
    final now = _clock().toUtc();
    final usedTags = normalizedTags ?? normalizeTags(item);
    final rating = normalizeBooruRating(item.rating, booru: context.sourceBooru, sourceType: item.sourceIdentity?.type);
    final matches = <TagFilterRuleMatch>[];

    for (final index in _orderedCandidateIndexes(rating, usedTags)) {
      final compiled = _compiled[index];
      if (compiled.query == null || !compiled.rule.isActiveAt(now) || !compiled.rule.scope.appliesTo(context)) continue;
      final queryMatch = compiled.query!.match(item, normalizedTags: usedTags, normalizedRating: rating);
      if (queryMatch.matches) {
        matches.add(TagFilterRuleMatch(rule: compiled.rule, matchedTags: queryMatch.matchedTags));
      }
    }
    if (matches.isEmpty) return const TagFilterEvaluation.empty();

    int priority(TagFilterEffect effect) => switch (effect) {
      TagFilterEffect.hide => 0,
      TagFilterEffect.blur => 1,
      TagFilterEffect.mark => 2,
    };

    var primary = matches.first;
    for (final match in matches.skip(1)) {
      if (priority(match.rule.effect) < priority(primary.rule.effect)) primary = match;
    }
    final hideAsBlur = primary.rule.effect == TagFilterEffect.hide && _configuration.hideAsBlur.isActiveAt(now);
    return TagFilterEvaluation(
      effectiveEffect: hideAsBlur ? TagFilterEffect.blur : primary.rule.effect,
      primaryMatch: primary,
      matches: List.unmodifiable(matches),
      hideAsBlur: hideAsBlur,
    );
  }

  Iterable<int> _orderedCandidateIndexes(String? rating, Set<String> normalizedTags) {
    final postingLists = <List<int>>[];
    final seenLists = HashSet<List<int>>.identity();

    void add(List<int>? indexes) {
      if (indexes != null && indexes.isNotEmpty && seenLists.add(indexes)) postingLists.add(indexes);
    }

    add(_fallback);
    for (final tag in normalizedTags) {
      add(_exactIndex[tag]);
      for (final indexes in _prefixIndex.matchingLists(tag)) {
        add(indexes);
      }
      if (_suffixIndex.ruleCount > 0) {
        for (final indexes in _suffixIndex.matchingLists(_reversedRunes(tag))) {
          add(indexes);
        }
      }
    }
    add(_ratingIndex[rating]);

    if (postingLists.isEmpty) return const [];
    if (postingLists.length == 1) return postingLists.single;
    return _mergePostingLists(postingLists);
  }

  Iterable<int> _mergePostingLists(List<List<int>> postingLists) sync* {
    final queue = HeapPriorityQueue<_PostingCursor>((left, right) => left.current.compareTo(right.current));
    queue.addAll(postingLists.map(_PostingCursor.new));
    while (queue.isNotEmpty) {
      final cursor = queue.removeFirst();
      yield cursor.current;
      if (cursor.moveNext) queue.add(cursor);
    }
  }

  TagFilterConfiguration _copyConfiguration({
    List<TagFilterRule>? rules,
    HideAsBlurState? hideAsBlur,
    Map<TimedFilterOption, DateTime>? enabledUntil,
  }) {
    return TagFilterConfiguration(
      schemaVersion: _configuration.schemaVersion,
      legacyImportVersion: _configuration.legacyImportVersion,
      rules: rules ?? _configuration.rules,
      hideAsBlur: hideAsBlur ?? _configuration.hideAsBlur,
      enabledUntil: Map.unmodifiable(enabledUntil ?? _configuration.enabledUntil),
    );
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    if (_disposed) return Future.error(StateError('TagFilterHandler has been disposed'));
    final completer = Completer<T>();
    _pendingOperations = _pendingOperations.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _commitNow(TagFilterConfiguration configuration) async {
    await repository.save(configuration);
    _configuration = configuration;
    _configurationChanged();
  }

  void _configurationChanged() {
    _applyOptionTimers();
    _compile();
    if (_disposed) return;
    _evaluationRevision++;
    _scheduleExpiry();
    _refilterLoadedTabs();
    if (!_disposed) revision.value = _evaluationRevision;
  }

  void _compile() {
    final previousById = {for (final compiled in _compiled) compiled.rule.id: compiled};
    _compiled.clear();
    _errorsByRuleId.clear();
    _exactIndex.clear();
    _prefixIndex.clear();
    _suffixIndex.clear();
    _ratingIndex.clear();
    _fallback.clear();
    for (var index = 0; index < rules.length; index++) {
      final rule = rules[index];
      final previous = previousById[rule.id];
      TagFilterQuery? query;
      TagFilterQueryError? error;
      if (previous != null && previous.rule.query == rule.query) {
        query = previous.query;
        error = previous.error;
      } else {
        final parsed = TagFilterQuery.parse(rule.query);
        query = parsed.query;
        error = parsed.error;
      }
      final compiled = CompiledTagFilterRule(rule: rule, index: index, query: query, error: error);
      _compiled.add(compiled);
      if (error != null) _errorsByRuleId[rule.id] = error;
      if (query == null || !rule.enabled) continue;
      final anchor = query.positiveExactTags.firstOrNull;
      if (anchor != null) {
        (_exactIndex[anchor] ??= []).add(index);
        continue;
      }
      final wildcardPrefix = _longestString(query.positiveWildcardPrefixes);
      final wildcardSuffix = _longestString(query.positiveWildcardSuffixes);
      if (wildcardPrefix != null && (wildcardSuffix == null || wildcardPrefix.length >= wildcardSuffix.length)) {
        _prefixIndex.add(wildcardPrefix, index);
        continue;
      }
      if (wildcardSuffix != null) {
        _suffixIndex.add(_reversedRunes(wildcardSuffix), index);
        continue;
      }
      final rating = query.positiveRatings.firstOrNull;
      if (rating != null) {
        (_ratingIndex[rating] ??= []).add(index);
        continue;
      }
      _fallback.add(index);
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _nextExpiry = null;
    final now = _clock().toUtc();
    final expiries = <DateTime>[
      ...configuration.enabledUntil.values.where((time) => time.isAfter(now)),
      ...rules
          .where((rule) => rule.enabled)
          .map((rule) => rule.disabledUntil)
          .whereType<DateTime>()
          .where((time) => time.isAfter(now)),
      if (_configuration.hideAsBlur.enabled && _configuration.hideAsBlur.until?.isAfter(now) == true)
        _configuration.hideAsBlur.until!,
    ]..sort();
    if (expiries.isEmpty) return;
    _nextExpiry = expiries.first;
    _expiryTimer = Timer(_nextExpiry!.difference(now), () {
      if (_disposed) return;
      _applyOptionTimers();
      _evaluationRevision++;
      _scheduleExpiry();
      _refilterLoadedTabs();
      if (!_disposed) revision.value = _evaluationRevision;
    });
  }

  void handleAppResumed() {
    if (_disposed) return;
    final now = _clock().toUtc();
    final expiryReached = _nextExpiry != null && !now.isBefore(_nextExpiry!);
    if (!expiryReached) {
      _applyOptionTimers();
      _scheduleExpiry();
      return;
    }
    _evaluationRevision++;
    _applyOptionTimers();
    _scheduleExpiry();
    _refilterLoadedTabs();
    if (!_disposed) revision.value = _evaluationRevision;
  }

  void _refilterLoadedTabs({bool forceRefresh = true}) {
    final generation = ++_refilterGeneration;
    _refilterForceRefresh |= forceRefresh;
    _refilterTimer?.cancel();
    _refilterTimer = Timer(Duration.zero, () {
      final refresh = _refilterForceRefresh;
      _refilterForceRefresh = false;
      unawaited(_runRefilter(generation, forceRefresh: refresh));
    });
  }

  Future<void> _runRefilter(int generation, {required bool forceRefresh}) async {
    if (_disposed) return;
    final search = GetIt.instance.isRegistered<SearchHandler>() ? SearchHandler.instance : null;
    bool shouldCancel() => _disposed || generation != _refilterGeneration;
    try {
      final handlers = <BooruHandler>{..._activeHandlers.keys, ...?search?.tabs.map((tab) => tab.booruHandler)};
      for (final handler in handlers) {
        if (shouldCancel()) return;
        bool isPresent() =>
            _activeHandlers.containsKey(handler) ||
            (search?.tabs.any((tab) => identical(tab.booruHandler, handler)) ?? false);
        if (!isPresent()) continue;
        await handler.refilterFetched(
          forceRefresh: forceRefresh,
          shouldCancel: () => shouldCancel() || !isPresent(),
        );
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'tag filters',
          context: ErrorDescription('while refreshing loaded tabs'),
        ),
      );
    }
  }
}
