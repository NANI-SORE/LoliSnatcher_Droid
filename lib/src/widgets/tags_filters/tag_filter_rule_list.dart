import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_filter.dart';

enum TagFilterSort { alphabetical, reverseAlphabetical, effect, reverseEffect, suspensionTime }

/// Derived list data for the filter settings screen. Rebuild this only when
/// rules or the booru catalog change; selection and search use [select].
class TagFilterRuleList {
  TagFilterRuleList({required List<TagFilterRule> rules, required List<Booru> boorus, required DateTime now})
    : rules = List.unmodifiable(rules),
      regularBoorus = List.unmodifiable(
        boorus.where((booru) => booru.type?.isFavouritesOrDownloads != true && booru.type?.isMerge != true),
      ),
      _boorus = List.unmodifiable(boorus) {
    for (final booru in regularBoorus) {
      _boorusByScopeKey[sourceScopeKey(booru)] = booru;
    }
    for (final rule in rules) {
      if (_hasMissingSource(rule)) _missingRuleIds.add(rule.id);
      _searchableText[rule.id] =
          '${rule.name} ${rule.query} ${rule.effect.name} ${rule.scope.kind.name} '
                  '${rule.scope.targets.map((target) => '${target.name ?? ''} ${target.baseUrl ?? ''}').join(' ')} '
                  '${rule.scope.excludedSources.map((source) => '${source.name ?? ''} ${source.baseUrl ?? ''}').join(' ')} '
                  '${TagFilterMarker.stableKeyFor(rule.marker)}'
              .toLowerCase();
      effectCounts[rule.effect] = (effectCounts[rule.effect] ?? 0) + 1;
      if (rule.effect == TagFilterEffect.mark) {
        final key = TagFilterMarker.stableKeyFor(rule.marker);
        _markersByKey.putIfAbsent(key, () => rule.marker);
      }
    }
    markerKeys = _markersByKey.keys.toList()
      ..sort((left, right) => _markerSortName(left).compareTo(_markerSortName(right)));

    final alphabetical = [...rules]..sort(_compareAlphabetically);
    _sortedRules[TagFilterSort.alphabetical] = alphabetical;
    _sortedRules[TagFilterSort.reverseAlphabetical] = alphabetical.reversed.toList();
    _sortedRules[TagFilterSort.effect] = [...rules]..sort(_compareByEffect);
    _sortedRules[TagFilterSort.reverseEffect] = [...rules]
      ..sort((left, right) => _compareByEffect(left, right, reverseAlphabetic: true));
    _sortedRules[TagFilterSort.suspensionTime] = [...rules]
      ..sort((left, right) => _compareBySuspensionTime(left, right, now));
  }

  static const globalScopeKey = 'global';
  static const favouritesScopeKey = 'view:favourites';
  static const downloadsScopeKey = 'view:downloads';

  final List<TagFilterRule> rules;
  final List<Booru> regularBoorus;
  final List<Booru> _boorus;
  final Map<String, Booru> _boorusByScopeKey = {};
  final Map<String, String> _searchableText = {};
  final Set<String> _missingRuleIds = {};
  final Map<String, TagFilterMarker?> _markersByKey = {};
  final Map<TagFilterSort, List<TagFilterRule>> _sortedRules = {};
  final Map<TagFilterEffect, int> effectCounts = {for (final effect in TagFilterEffect.values) effect: 0};
  late final List<String> markerKeys;

  static String sourceScopeKey(Booru booru) => 'source:${BooruIdentity.fromBooru(booru).stableKey}';

  List<String> get scopeKeys => [
    globalScopeKey,
    ...regularBoorus.map(sourceScopeKey),
    favouritesScopeKey,
    downloadsScopeKey,
  ];

  Booru? booruForScopeKey(String key) => _boorusByScopeKey[key];
  TagFilterMarker? markerForKey(String key) => _markersByKey[key];

  bool hasMissingSource(TagFilterRule rule) => _missingRuleIds.contains(rule.id);

  bool _hasMissingSource(TagFilterRule rule) => [...rule.scope.targets, ...rule.scope.excludedSources].any(
    (identity) => identity.type?.isFavouritesOrDownloads == true
        ? !_boorus.any((booru) => booru.type == identity.type)
        : !regularBoorus.any(identity.matches),
  );

  List<TagFilterRule> select({
    required String search,
    required Set<TagFilterEffect> effects,
    required Set<String> markers,
    required Set<String> scopes,
    required Set<String> statuses,
    required TagFilterSort sort,
    required bool Function(String ruleId) isInvalid,
    required DateTime now,
  }) {
    final query = search.toLowerCase();
    return _sortedRules[sort]!.where((rule) {
      if (effects.isNotEmpty && !effects.contains(rule.effect)) return false;
      if (markers.isNotEmpty &&
          (rule.effect != TagFilterEffect.mark || !markers.contains(TagFilterMarker.stableKeyFor(rule.marker)))) {
        return false;
      }
      if (scopes.isNotEmpty && !scopes.any((scope) => _matchesScopeKey(rule, scope))) return false;
      final suspended = rule.enabled && rule.disabledUntil?.isAfter(now) == true;
      if (statuses.isNotEmpty &&
          !statuses.any(
            (status) => switch (status) {
              'enabled' => rule.enabled && !suspended,
              'disabled' => !rule.enabled,
              'suspended' => suspended,
              'missing' => hasMissingSource(rule),
              'invalid' => isInvalid(rule.id),
              _ => false,
            },
          )) {
        return false;
      }
      return query.isEmpty || (_searchableText[rule.id]?.contains(query) ?? false);
    }).toList();
  }

  bool _matchesScopeKey(TagFilterRule rule, String scopeKey) {
    if (scopeKey == globalScopeKey) return rule.scope.kind == TagFilterScopeKind.global;
    if (scopeKey == favouritesScopeKey || scopeKey == downloadsScopeKey) {
      final type = scopeKey == favouritesScopeKey ? BooruType.Favourites : BooruType.Downloads;
      return (rule.scope.kind == TagFilterScopeKind.view && rule.scope.viewType == type) ||
          (rule.scope.kind == TagFilterScopeKind.source && rule.scope.targets.any((target) => target.type == type));
    }
    final booru = booruForScopeKey(scopeKey);
    return booru != null &&
        rule.scope.kind == TagFilterScopeKind.source &&
        rule.scope.targets.any((target) => target.matches(booru));
  }

  String _markerSortName(String key) {
    if (key == TagFilterMarker.defaultStableKey) return '';
    final marker = markerForKey(key);
    return (marker?.icon?.name ?? marker?.text ?? key).toLowerCase();
  }

  static String _ruleSortName(TagFilterRule rule) =>
      (rule.name.trim().isEmpty ? rule.query : rule.name).trim().toLowerCase();

  static int _compareAlphabetically(TagFilterRule left, TagFilterRule right) {
    final nameResult = _ruleSortName(left).compareTo(_ruleSortName(right));
    if (nameResult != 0) return nameResult;
    final queryResult = left.query.toLowerCase().compareTo(right.query.toLowerCase());
    if (queryResult != 0) return queryResult;
    return left.id.compareTo(right.id);
  }

  static int _compareByEffect(TagFilterRule left, TagFilterRule right, {bool reverseAlphabetic = false}) {
    final effectResult = left.effect.index.compareTo(right.effect.index);
    if (effectResult != 0) return effectResult;
    final alphabeticResult = _compareAlphabetically(left, right);
    return reverseAlphabetic ? -alphabeticResult : alphabeticResult;
  }

  static int _compareBySuspensionTime(TagFilterRule left, TagFilterRule right, DateTime now) {
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
}
