class ServerIdParser {
  const ServerIdParser._();

  static String? fromUrl(String url) {
    final uri = Uri.tryParse(url);
    final queryId = uri?.queryParameters['id'];
    if (_isUsableId(queryId)) return queryId;

    final segments = uri?.pathSegments ?? const [];
    final postsIndex = segments.indexOf('posts');
    if (postsIndex != -1 && segments.length > postsIndex + 1) {
      final id = segments[postsIndex + 1];
      if (_isUsableId(id)) return id;
    }

    final postIndex = segments.indexOf('post');
    if (postIndex != -1 && segments.length > postIndex + 2 && segments[postIndex + 1] == 'show') {
      final id = segments[postIndex + 2];
      if (_isUsableId(id)) return id;
    }

    final showMatch = RegExp('/post/show/([^/?#]+)').firstMatch(url);
    final showId = showMatch?.group(1);
    if (_isUsableId(showId)) return showId;

    final postsMatch = RegExp('/posts/([^/?#]+)').firstMatch(url);
    final postsId = postsMatch?.group(1);
    if (_isUsableId(postsId)) return postsId;

    final idMatch = RegExp('[?&]id=([^&#]+)').firstMatch(url);
    final id = idMatch?.group(1);
    if (_isUsableId(id)) return id;

    return null;
  }

  static String? fromStoredValue(dynamic value, String postUrl) {
    final stored = value?.toString();
    if (_isUsableId(stored)) return stored;
    return fromUrl(postUrl);
  }

  static bool _isUsableId(String? value) {
    return value != null && value.isNotEmpty && value != 'null';
  }
}
