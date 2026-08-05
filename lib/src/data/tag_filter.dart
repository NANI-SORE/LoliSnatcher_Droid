import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag_filter_query.dart';

enum TagFilterEffect { hide, blur, mark }

enum TagFilterScopeKind { global, source, view }

@immutable
class BooruIdentity {
  const BooruIdentity({this.name, this.type, this.baseUrl});

  factory BooruIdentity.fromBooru(Booru booru) => BooruIdentity(
    name: booru.name?.trim(),
    type: booru.type,
    baseUrl: normalizeBaseUrl(booru.baseURL),
  );

  factory BooruIdentity.fromJson(Map<String, dynamic> json) => BooruIdentity(
    name: json['name']?.toString(),
    type: BooruType.values.where((value) => value.name == json['type']).firstOrNull,
    baseUrl: normalizeBaseUrl(json['baseUrl']?.toString()),
  );

  final String? name;
  final BooruType? type;
  final String? baseUrl;

  static String? normalizeBaseUrl(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  bool matches(Booru? booru) {
    if (booru == null) return false;
    final candidateUrl = normalizeBaseUrl(booru.baseURL);
    if (type != null && type == booru.type && baseUrl != null && baseUrl == candidateUrl) return true;
    return name?.isNotEmpty == true && name!.toLowerCase() == booru.name?.trim().toLowerCase();
  }

  String get stableKey => '${type?.name ?? ''}|${baseUrl ?? ''}|${name?.toLowerCase() ?? ''}';

  Map<String, dynamic> toJson() => {'name': name, 'type': type?.name, 'baseUrl': baseUrl};

  @override
  bool operator ==(Object other) => other is BooruIdentity && stableKey == other.stableKey;

  @override
  int get hashCode => stableKey.hashCode;
}

class TagFilterScope {
  const TagFilterScope._({required this.kind, this.targets = const [], this.viewType, this.excludedSources = const []});

  const TagFilterScope.global({List<BooruIdentity> excludedSources = const []})
    : this._(kind: TagFilterScopeKind.global, excludedSources: excludedSources);

  factory TagFilterScope.source(BooruIdentity target) => TagFilterScope.sources([target]);

  factory TagFilterScope.sources(List<BooruIdentity> targets) {
    if (targets.isEmpty) throw ArgumentError.value(targets, 'targets', 'A source scope requires at least one booru');
    return TagFilterScope._(kind: TagFilterScopeKind.source, targets: List.unmodifiable(targets));
  }

  const TagFilterScope.view(BooruType viewType) : this._(kind: TagFilterScopeKind.view, viewType: viewType);

  factory TagFilterScope.fromJson(Map<String, dynamic> json) {
    final kind = TagFilterScopeKind.values.byName(json['kind']?.toString() ?? 'global');
    return switch (kind) {
      TagFilterScopeKind.global => TagFilterScope.global(
        excludedSources: (json['excludedSources'] as List? ?? const []).map((entry) {
          if (entry is! Map) throw const FormatException('A source exclusion must be an object');
          return BooruIdentity.fromJson(Map<String, dynamic>.from(entry));
        }).toList(),
      ),
      TagFilterScopeKind.source => () {
        final rawTargets = json['targets'];
        final targets = rawTargets is List
            ? rawTargets.map((entry) {
                if (entry is! Map) throw const FormatException('A source target must be an object');
                return BooruIdentity.fromJson(Map<String, dynamic>.from(entry));
              }).toList()
            : [BooruIdentity.fromJson(Map<String, dynamic>.from(json['target'] as Map))];
        if (targets.isEmpty) throw const FormatException('A source scope must contain at least one booru');
        return TagFilterScope.sources(targets);
      }(),
      TagFilterScopeKind.view => () {
        final type = BooruType.values.byName(json['viewType'].toString());
        if (!type.isFavouritesOrDownloads) {
          throw const FormatException('A view scope must target Favourites or Downloads');
        }
        return TagFilterScope.view(type);
      }(),
    };
  }

  final TagFilterScopeKind kind;
  final List<BooruIdentity> targets;
  BooruIdentity? get target => targets.firstOrNull;
  final BooruType? viewType;
  final List<BooruIdentity> excludedSources;

  bool appliesTo(FilterContext context) => switch (kind) {
    TagFilterScopeKind.global => !excludedSources.any(context.matchesSource),
    TagFilterScopeKind.source => targets.any(context.matchesSource),
    TagFilterScopeKind.view => context.viewBooru.type == viewType,
  };

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (targets.isNotEmpty) 'targets': targets.map((target) => target.toJson()).toList(),
    if (viewType != null) 'viewType': viewType!.name,
    if (excludedSources.isNotEmpty) 'excludedSources': excludedSources.map((item) => item.toJson()).toList(),
  };

  String get stableKey =>
      '${kind.name}|${(targets.map((item) => item.stableKey).toList()..sort()).join(',')}|${viewType?.name ?? ''}|'
      '${(excludedSources.map((item) => item.stableKey).toList()..sort()).join(',')}';
}

enum TagFilterMarkerIcon {
  star(Icons.star),
  bookmark(Icons.bookmark),
  flag(Icons.flag),
  warning(Icons.warning_amber),
  ban(FontAwesomeIcons.ban),
  check(Icons.check_circle),
  close(Icons.cancel),
  bolt(Icons.bolt),
  diamond(Icons.diamond),
  pushPin(Icons.push_pin),
  label(Icons.label),
  shield(Icons.shield),
  lock(Icons.lock),
  info(Icons.info),
  help(Icons.help),
  clock(Icons.schedule),
  calendar(Icons.calendar_month),
  link(Icons.link),
  award(FontAwesomeIcons.award),
  person(Icons.person),
  group(Icons.groups),
  idBadge(FontAwesomeIcons.idBadge),
  male(Icons.male),
  female(Icons.female),
  pets(Icons.pets),
  palette(Icons.palette),
  paintbrush(FontAwesomeIcons.paintbrush),
  penNib(FontAwesomeIcons.penNib),
  music(Icons.music_note),
  video(Icons.videocam),
  animation(Icons.animation),
  gif(Icons.gif_box),
  retroCamera(FontAwesomeIcons.cameraRetro),
  headphones(FontAwesomeIcons.headphones),
  microphone(FontAwesomeIcons.microphone),
  openBook(FontAwesomeIcons.bookOpen),
  masksTheater(FontAwesomeIcons.masksTheater),
  game(Icons.sports_esports),
  language(FontAwesomeIcons.language),
  layerGroup(FontAwesomeIcons.layerGroup),
  clone(FontAwesomeIcons.clone),
  copyright(Icons.copyright),
  home(Icons.home),
  work(Icons.work),
  school(Icons.school),
  cake(Icons.cake),
  rocket(Icons.rocket_launch),
  ghost(FontAwesomeIcons.ghost),
  robot(FontAwesomeIcons.robot),
  crown(FontAwesomeIcons.crown),
  skull(FontAwesomeIcons.skull),
  dragon(FontAwesomeIcons.dragon),
  magicWand(FontAwesomeIcons.wandMagicSparkles),
  cat(FontAwesomeIcons.cat),
  dog(FontAwesomeIcons.dog),
  fish(FontAwesomeIcons.fish),
  spider(FontAwesomeIcons.spider),
  frog(FontAwesomeIcons.frog),
  feather(FontAwesomeIcons.feather),
  leaf(FontAwesomeIcons.leaf),
  snowflake(FontAwesomeIcons.snowflake),
  moon(FontAwesomeIcons.moon),
  sun(FontAwesomeIcons.sun),
  flask(FontAwesomeIcons.flask),
  atom(FontAwesomeIcons.atom),
  code(FontAwesomeIcons.code),
  mask(FontAwesomeIcons.mask),
  secretUser(FontAwesomeIcons.userSecret),
  shirt(FontAwesomeIcons.shirt),
  droplet(FontAwesomeIcons.droplet);

  const TagFilterMarkerIcon(this.glyph);

  final Object glyph;

  Widget build({required double size, Color? color}) {
    final child = switch (glyph) {
      // Font Awesome's glyphs fill more of their em square than Material
      // icons. Match the 18:20 ratio used by tag-row status icons.
      final FaIconData icon => FaIcon(icon, size: size * 0.9, color: color),
      final IconData icon => Icon(icon, size: size, color: color),
      _ => const SizedBox.shrink(),
    };
    return SizedBox.square(
      dimension: size,
      child: Center(child: child),
    );
  }
}

const List<TagFilterMarkerIcon> tagFilterMarkerIconCatalog = [
  TagFilterMarkerIcon.star,
  TagFilterMarkerIcon.bookmark,
  TagFilterMarkerIcon.flag,
  TagFilterMarkerIcon.warning,
  TagFilterMarkerIcon.ban,
  TagFilterMarkerIcon.check,
  TagFilterMarkerIcon.close,
  TagFilterMarkerIcon.bolt,
  TagFilterMarkerIcon.diamond,
  TagFilterMarkerIcon.pushPin,
  TagFilterMarkerIcon.label,
  TagFilterMarkerIcon.shield,
  TagFilterMarkerIcon.lock,
  TagFilterMarkerIcon.info,
  TagFilterMarkerIcon.help,
  TagFilterMarkerIcon.clock,
  TagFilterMarkerIcon.calendar,
  TagFilterMarkerIcon.link,
  TagFilterMarkerIcon.award,
  TagFilterMarkerIcon.person,
  TagFilterMarkerIcon.group,
  TagFilterMarkerIcon.idBadge,
  TagFilterMarkerIcon.male,
  TagFilterMarkerIcon.female,
  TagFilterMarkerIcon.pets,
  TagFilterMarkerIcon.palette,
  TagFilterMarkerIcon.paintbrush,
  TagFilterMarkerIcon.penNib,
  TagFilterMarkerIcon.music,
  TagFilterMarkerIcon.video,
  TagFilterMarkerIcon.animation,
  TagFilterMarkerIcon.gif,
  TagFilterMarkerIcon.retroCamera,
  TagFilterMarkerIcon.headphones,
  TagFilterMarkerIcon.microphone,
  TagFilterMarkerIcon.openBook,
  TagFilterMarkerIcon.masksTheater,
  TagFilterMarkerIcon.game,
  TagFilterMarkerIcon.language,
  TagFilterMarkerIcon.layerGroup,
  TagFilterMarkerIcon.clone,
  TagFilterMarkerIcon.copyright,
  TagFilterMarkerIcon.home,
  TagFilterMarkerIcon.work,
  TagFilterMarkerIcon.school,
  TagFilterMarkerIcon.cake,
  TagFilterMarkerIcon.rocket,
  TagFilterMarkerIcon.ghost,
  TagFilterMarkerIcon.robot,
  TagFilterMarkerIcon.crown,
  TagFilterMarkerIcon.skull,
  TagFilterMarkerIcon.dragon,
  TagFilterMarkerIcon.magicWand,
  TagFilterMarkerIcon.cat,
  TagFilterMarkerIcon.dog,
  TagFilterMarkerIcon.fish,
  TagFilterMarkerIcon.spider,
  TagFilterMarkerIcon.frog,
  TagFilterMarkerIcon.feather,
  TagFilterMarkerIcon.leaf,
  TagFilterMarkerIcon.snowflake,
  TagFilterMarkerIcon.moon,
  TagFilterMarkerIcon.sun,
  TagFilterMarkerIcon.flask,
  TagFilterMarkerIcon.atom,
  TagFilterMarkerIcon.code,
  TagFilterMarkerIcon.mask,
  TagFilterMarkerIcon.secretUser,
  TagFilterMarkerIcon.shirt,
  TagFilterMarkerIcon.droplet,
];

enum TagFilterMarkerKind { icon, text }

enum TagFilterMarkerColor {
  grey(Colors.grey),
  red(Colors.redAccent),
  orange(Colors.deepOrangeAccent),
  yellow(Colors.amber),
  green(Colors.greenAccent),
  teal(Colors.tealAccent),
  cyan(Colors.cyanAccent),
  blue(Colors.blueAccent),
  indigo(Colors.indigoAccent),
  purple(Colors.purpleAccent),
  pink(Colors.pinkAccent);

  const TagFilterMarkerColor(this.color);

  final Color color;
}

const List<String> tagFilterPresetEmojis = [
  '🔥',
  '✨',
  '✅',
  '❌',
  '⚠️',
  '💎',
  '⚡',
  '💯',
  '🚫',
  '❓',
  '❗',
  '🏆',
  '🤩',
  '😂',
  '😭',
  '😡',
  '👍',
  '👎',
  '📌',
  '🔖',
  '🚩',
  '👀',
  '🙈',
  '😎',
  '🤔',
  '😴',
  '🤯',
  '😏',
  '🤢',
  '🥵',
  '🤡',
  '👌',
  '🫣',
  '👑',
  '♂️',
  '♀️',
  '👤',
  '👥',
  '🎨',
  '🖌️',
  '✏️',
  '🎵',
  '🎬',
  '📷',
  '🎮',
  '📖',
  '🎭',
  '🌐',
  '💬',
  '🐾',
  '🐱',
  '🐶',
  '🦊',
  '🐺',
  '🐰',
  '🐉',
  '🦄',
  '🦋',
  '👻',
  '🤖',
  '💀',
  '🌸',
  '🌙',
  '☀️',
  '🌈',
  '🩸',
  '⚔️',
  '🛡️',
  '🔒',
  '🔞',
];

class TagFilterMarker {
  const TagFilterMarker.icon(
    this.icon, {
    this.color = TagFilterMarkerColor.grey,
    this.customColor,
  }) : kind = TagFilterMarkerKind.icon,
       text = null;
  const TagFilterMarker.text(
    this.text, {
    this.color = TagFilterMarkerColor.grey,
    this.customColor,
  }) : kind = TagFilterMarkerKind.text,
       icon = null;

  factory TagFilterMarker.fromJson(Map<String, dynamic> json) {
    final kind = TagFilterMarkerKind.values.byName(json['kind'].toString());
    final rawColor = json['color']?.toString();
    final presetColor = rawColor == null || rawColor == 'custom'
        ? TagFilterMarkerColor.grey
        : TagFilterMarkerColor.values.byName(rawColor);
    final customColor = rawColor == 'custom' ? _parseCustomMarkerColor(json['colorValue']) : null;
    return switch (kind) {
      TagFilterMarkerKind.icon => TagFilterMarker.icon(
        TagFilterMarkerIcon.values.byName(json['value'].toString()),
        color: presetColor,
        customColor: customColor,
      ),
      TagFilterMarkerKind.text => () {
        final text = json['value']?.toString() ?? '';
        if (text.characters.length != 1) {
          throw const FormatException('A custom marker must contain one Unicode grapheme');
        }
        return TagFilterMarker.text(
          text,
          color: presetColor,
          customColor: customColor,
        );
      }(),
    };
  }

  static const String defaultStableKey = 'icon:star:grey';

  final TagFilterMarkerKind kind;
  final TagFilterMarkerIcon? icon;
  final String? text;
  final TagFilterMarkerColor color;
  final Color? customColor;

  Color get effectiveColor => customColor ?? color.color;

  String get colorKey =>
      customColor == null ? color.name : 'custom:${customColor!.toARGB32().toRadixString(16).padLeft(8, '0')}';

  String get stableKey => '${kind.name}:${icon?.name ?? text ?? ''}:$colorKey';

  static String stableKeyFor(TagFilterMarker? marker) => marker?.stableKey ?? defaultStableKey;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'value': icon?.name ?? text,
    'color': customColor == null ? color.name : 'custom',
    if (customColor != null)
      'colorValue': '#${customColor!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
  };
}

Color _parseCustomMarkerColor(dynamic value) {
  var encoded = value?.toString().trim() ?? '';
  if (encoded.startsWith('#')) encoded = encoded.substring(1);
  if (encoded.length == 6) encoded = 'FF$encoded';
  if (encoded.length != 8) {
    throw const FormatException('A custom marker color must be a 6- or 8-digit hexadecimal value');
  }
  final parsed = int.tryParse(encoded, radix: 16);
  if (parsed == null) throw const FormatException('A custom marker color must be hexadecimal');
  return Color(parsed);
}

class TagFilterRule {
  const TagFilterRule({
    required this.id,
    required this.name,
    required this.query,
    required this.effect,
    required this.scope,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.disabledUntil,
    this.marker,
    this.showMarkerInGrid = true,
    this.legacySourceKey,
  });

  factory TagFilterRule.fromJson(Map<String, dynamic> json) {
    String requiredString(String key, {bool allowEmpty = false}) {
      final value = json[key];
      if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
        throw FormatException('Rule $key must be a${allowEmpty ? '' : ' non-empty'} string');
      }
      return value;
    }

    DateTime? optionalUtcDate(String key) {
      final value = json[key];
      if (value == null) return null;
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null) throw FormatException('Rule $key must be a valid ISO-8601 date or null');
      return parsed.toUtc();
    }

    final effect = TagFilterEffect.values.byName(json['effect'].toString());
    return TagFilterRule(
      id: requiredString('id'),
      name: requiredString('name', allowEmpty: true),
      query: requiredString('query', allowEmpty: true),
      effect: effect,
      scope: TagFilterScope.fromJson(Map<String, dynamic>.from(json['scope'] as Map)),
      enabled: json['enabled'] as bool? ?? true,
      disabledUntil: optionalUtcDate('disabledUntil'),
      marker: effect == TagFilterEffect.mark && json['marker'] is Map
          ? TagFilterMarker.fromJson(Map<String, dynamic>.from(json['marker'] as Map))
          : null,
      showMarkerInGrid: effect == TagFilterEffect.mark ? json['showMarkerInGrid'] as bool? ?? true : true,
      legacySourceKey: json['legacySourceKey']?.toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'].toString()).toUtc(),
    );
  }

  final String id;
  final String name;
  final String query;
  final TagFilterEffect effect;
  final TagFilterScope scope;
  final bool enabled;
  final DateTime? disabledUntil;
  final TagFilterMarker? marker;
  final bool showMarkerInGrid;
  final String? legacySourceKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasDistinctName {
    final normalizedName = name.trim().toLowerCase();
    if (normalizedName.isEmpty || normalizedName == query.trim().toLowerCase()) return false;
    final parsed = TagFilterQuery.parse(query).query;
    if (parsed?.conditions case [final TagCondition condition]) {
      if (!condition.negated && !condition.hasWildcard && condition.pattern == normalizedName) return false;
    }
    return true;
  }

  String get displayName => hasDistinctName ? name.trim() : query.trim();

  bool isActiveAt(DateTime now) => enabled && (disabledUntil == null || !now.isBefore(disabledUntil!));

  TagFilterRule copyWith({
    String? name,
    String? query,
    TagFilterEffect? effect,
    TagFilterScope? scope,
    bool? enabled,
    DateTime? disabledUntil,
    bool clearDisabledUntil = false,
    TagFilterMarker? marker,
    bool clearMarker = false,
    bool? showMarkerInGrid,
  }) {
    final nextEffect = effect ?? this.effect;
    return TagFilterRule(
      id: id,
      name: name ?? this.name,
      query: query ?? this.query,
      effect: nextEffect,
      scope: scope ?? this.scope,
      enabled: enabled ?? this.enabled,
      disabledUntil: clearDisabledUntil ? null : (disabledUntil ?? this.disabledUntil),
      marker: nextEffect == TagFilterEffect.mark ? (clearMarker ? null : marker ?? this.marker) : null,
      showMarkerInGrid: nextEffect == TagFilterEffect.mark ? showMarkerInGrid ?? this.showMarkerInGrid : true,
      legacySourceKey: legacySourceKey,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'effect': effect.name,
    'scope': scope.toJson(),
    'enabled': enabled,
    'disabledUntil': disabledUntil?.toIso8601String(),
    if (effect == TagFilterEffect.mark && marker != null) 'marker': marker!.toJson(),
    if (effect == TagFilterEffect.mark) 'showMarkerInGrid': showMarkerInGrid,
    if (legacySourceKey != null) 'legacySourceKey': legacySourceKey,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class FilterContext {
  FilterContext({required this.viewBooru, this.sourceBooru})
    : _sourceName = sourceBooru?.name?.trim().toLowerCase(),
      _sourceType = sourceBooru?.type,
      _sourceBaseUrl = BooruIdentity.normalizeBaseUrl(sourceBooru?.baseURL),
      cacheKey =
          '${viewBooru.type?.name ?? ''}|${sourceBooru?.type?.name ?? ''}|'
          '${BooruIdentity.normalizeBaseUrl(sourceBooru?.baseURL) ?? ''}|'
          '${sourceBooru?.name?.trim().toLowerCase() ?? ''}';

  final Booru viewBooru;
  final Booru? sourceBooru;
  final String cacheKey;
  final String? _sourceName;
  final BooruType? _sourceType;
  final String? _sourceBaseUrl;

  bool matchesSource(BooruIdentity identity) {
    if (identity.type?.isFavouritesOrDownloads == true) {
      return identity.type == viewBooru.type;
    }
    if (sourceBooru == null) return false;
    if (identity.type != null && identity.type == _sourceType && identity.baseUrl != null) {
      if (identity.baseUrl == _sourceBaseUrl) return true;
    }
    return identity.name?.isNotEmpty == true && identity.name!.toLowerCase() == _sourceName;
  }
}

class HideAsBlurState {
  const HideAsBlurState({this.enabled = false, this.until});

  factory HideAsBlurState.fromJson(Map<String, dynamic>? json) {
    final rawUntil = json?['until'];
    final parsedUntil = rawUntil is String ? DateTime.tryParse(rawUntil) : null;
    if (rawUntil != null && parsedUntil == null) {
      throw const FormatException('Hide-as-blur until must be a valid ISO-8601 date or null');
    }
    return HideAsBlurState(
      enabled: json?['enabled'] as bool? ?? false,
      until: parsedUntil?.toUtc(),
    );
  }

  final bool enabled;
  final DateTime? until;
  bool isActiveAt(DateTime now) => enabled && (until == null || now.isBefore(until!));
  Map<String, dynamic> toJson() => {'enabled': enabled, 'until': until?.toIso8601String()};
}

class TagFilterConfiguration {
  const TagFilterConfiguration({
    this.schemaVersion = 1,
    this.legacyImportVersion = 0,
    this.rules = const [],
    this.hideAsBlur = const HideAsBlurState(),
  });

  final int schemaVersion;
  final int legacyImportVersion;
  final List<TagFilterRule> rules;
  final HideAsBlurState hideAsBlur;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'legacyImportVersion': legacyImportVersion,
    'rules': rules.map((rule) => rule.toJson()).toList(),
    'hideAsBlur': hideAsBlur.toJson(),
  };
}
