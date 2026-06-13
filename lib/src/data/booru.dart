import 'dart:convert';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

class Booru {
  Booru(
    this.name,
    this.type,
    this.faviconURL,
    this.baseURL,
    this.defTags,
  );

  Booru.unknown() : this(null, null, null, null, null);

  Booru.withKey(
    this.name,
    this.type,
    this.faviconURL,
    this.baseURL,
    this.defTags,
    this.apiKey,
    this.userID,
  );

  Booru.fromJSON(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    setFromMap(json);
  }

  Booru.fromMap(Map<String, dynamic> json) {
    setFromMap(json);
  }

  Booru.fromLink(String link) {
    final String jsonString = String.fromCharCodes(base64Decode(link.split('?')[1]));
    final Map<String, dynamic> json = jsonDecode(jsonString);
    setFromMap(json);
  }

  String? name = '', faviconURL = '', baseURL = '', apiKey = '', userID = '', defTags = '';
  BooruType? type;

  /// Per-booru setting overrides. Stored in each booru's config file.
  /// Keys are setting JSON keys (matching SettingKey.jsonKey), values are
  /// JSON-serialized setting values.
  /// Null or empty means no overrides — all settings use global defaults.
  Map<String, dynamic>? settingOverrides;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type?.name,
      'faviconURL': faviconURL,
      'baseURL': baseURL,
      'defTags': defTags,
      'apiKey': apiKey,
      'userID': userID,
      if (settingOverrides != null && settingOverrides!.isNotEmpty) 'settingOverrides': settingOverrides,
    };
  }

  String toLink(bool withSensitiveData) {
    final Map json = toJson();
    // Never share per-booru setting overrides — they're personal preferences
    json.remove('settingOverrides');
    if (withSensitiveData == false) {
      json.remove('apiKey');
      json.remove('userID');
    }
    final String jsonString = jsonEncode(json);
    return 'https://www.loli.snatcher?${base64UrlEncode(jsonString.codeUnits)}';
  }

  void setFromMap(Map<String, dynamic> json) {
    name = json['name']?.toString();
    type = BooruType.values.firstWhereOrNull((e) => e.name.toLowerCase() == json['type']?.toString().toLowerCase());
    faviconURL = json['faviconURL']?.toString();
    baseURL = json['baseURL']?.toString();
    defTags = json['defTags']?.toString();
    apiKey = json['apiKey']?.toString();
    userID = json['userID']?.toString();
    settingOverrides = json['settingOverrides'] is Map
        ? Map<String, dynamic>.from(json['settingOverrides'] as Map)
        : null;
  }

  @override
  String toString() {
    return 'Name: $name, Type: $type, BaseURL: $baseURL, FaviconURL: $faviconURL, APIKey: $apiKey, UserID: $userID';
  }

  Booru copyWith({
    String? name,
    BooruType? type,
    String? faviconURL,
    String? baseURL,
    String? defTags,
    String? apiKey,
    String? userID,
    Map<String, dynamic>? settingOverrides,
  }) {
    return Booru.withKey(
      name ?? this.name,
      type ?? this.type,
      faviconURL ?? this.faviconURL,
      baseURL ?? this.baseURL,
      defTags ?? this.defTags,
      apiKey ?? this.apiKey,
      userID ?? this.userID,
    )..settingOverrides = settingOverrides ?? this.settingOverrides;
  }
}
