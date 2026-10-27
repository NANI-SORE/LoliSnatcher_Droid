import 'package:flutter/foundation.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';

/// A source's type and base URL survive display-name changes and local storage.
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
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return trimmed;
    // Paths can be case-sensitive. URI normalization handles scheme, host and
    // default ports; credentials, query and fragment do not identify a source.
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
    ).toString();
  }

  bool matches(Booru? booru) => booru != null && matchesIdentity(BooruIdentity.fromBooru(booru));

  bool matchesIdentity(BooruIdentity other) {
    if (type != null && baseUrl != null && other.type != null && other.baseUrl != null) {
      return type == other.type && normalizeBaseUrl(baseUrl) == normalizeBaseUrl(other.baseUrl);
    }
    if (type != null && other.type != null && type != other.type) return false;
    final identityName = name?.trim().toLowerCase();
    return identityName?.isNotEmpty == true && identityName == other.name?.trim().toLowerCase();
  }

  String get stableKey => '${type?.name ?? ''}|${normalizeBaseUrl(baseUrl) ?? ''}|${name?.toLowerCase() ?? ''}';

  Map<String, dynamic> toJson() => {'name': name, 'type': type?.name, 'baseUrl': normalizeBaseUrl(baseUrl)};

  @override
  bool operator ==(Object other) => other is BooruIdentity && stableKey == other.stableKey;

  @override
  int get hashCode => stableKey.hashCode;
}
