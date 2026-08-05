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
  DateTime? _nextExpiry;
  bool _disposed = false;
  int _evaluationRevision = 0;
  final List<SettingState<bool>> _activeFilterSettings = [];
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

  Future<void> initialize() async {
    _repository ??= JsonFilterRepository(SettingsHandler.instance.path);
    _configuration = await repository.load();
    _compile();
    _scheduleExpiry();
    _listenForActiveFilterSettingChanges();
    _listenForBooruCatalogChanges();
  }

  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    for (final setting in _activeFilterSettings) {
      setting.globalNotifier.removeListener(_activeFilterSettingChanged);
      setting.overridesNotifier.removeListener(_activeFilterSettingChanged);
    }
    _activeFilterSettings.clear();
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
  }

  void _activeFilterSettingChanged() {
    if (_disposed) return;
    _refilterLoadedTabs(forceRefresh: false);
  }

  void _listenForBooruCatalogChanges() {
    if (_booruCatalogSubscription != null || !GetIt.instance.isRegistered<SettingsHandler>()) return;
    _booruCatalogSubscription = SettingsHandler.instance.booruList.listen((_) {
      if (_disposed) return;
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

  Future<void> updateRule(TagFilterRule rule) => _enqueueOperation(() async {
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    final updated = [...rules]..[index] = rule;
    await _commitNow(_copyConfiguration(rules: updated));
  });

  Future<void> updateRules(Iterable<TagFilterRule> replacements) => _enqueueOperation(() async {
    final byId = {for (final rule in replacements) rule.id: rule};
    if (byId.isEmpty) return;
    var changed = false;
    final updated = rules
        .map((rule) {
          final replacement = byId[rule.id];
          if (replacement == null) return rule;
          changed = true;
          return replacement;
        })
        .toList(growable: false);
    if (changed) await _commitNow(_copyConfiguration(rules: updated));
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
      ..[index] = rule.copyWith(disabledUntil: until?.toUtc(), clearDisabledUntil: until == null);
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
      ),
    );
    return additions.length;
  }

  Set<String> normalizeTags(BooruItem item) =>
      item.tagsList.map((tag) => tag.fullString.trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet();

  TagFilterEvaluation evaluate(BooruItem item, FilterContext context, {Set<String>? normalizedTags}) {
    final now = _clock().toUtc();
    final usedTags = normalizedTags ?? normalizeTags(item);
    final matches = <TagFilterRuleMatch>[];

    for (final index in _orderedCandidateIndexes(item, usedTags)) {
      final compiled = _compiled[index];
      if (compiled.query == null || !compiled.rule.isActiveAt(now) || !compiled.rule.scope.appliesTo(context)) continue;
      final queryMatch = compiled.query!.match(item, normalizedTags: usedTags);
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

  Iterable<int> _orderedCandidateIndexes(BooruItem item, Set<String> normalizedTags) {
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
    add(_ratingIndex[_normalizedRating(item.rating)]);

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

  String? _normalizedRating(String? rating) => switch (rating?.trim().toLowerCase()) {
    's' => 'safe',
    'q' => 'questionable',
    'e' => 'explicit',
    final rating => rating,
  };

  TagFilterConfiguration _copyConfiguration({List<TagFilterRule>? rules, HideAsBlurState? hideAsBlur}) {
    return TagFilterConfiguration(
      schemaVersion: _configuration.schemaVersion,
      legacyImportVersion: _configuration.legacyImportVersion,
      rules: rules ?? _configuration.rules,
      hideAsBlur: hideAsBlur ?? _configuration.hideAsBlur,
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
      _scheduleExpiry();
      return;
    }
    _evaluationRevision++;
    _scheduleExpiry();
    _refilterLoadedTabs();
    if (!_disposed) revision.value = _evaluationRevision;
  }

  void _refilterLoadedTabs({bool forceRefresh = true}) {
    if (!GetIt.instance.isRegistered<SearchHandler>()) return;
    for (final tab in SearchHandler.instance.tabs) {
      tab.booruHandler.filterFetched(forceRefresh: forceRefresh);
    }
  }
}
