import 'package:lolisnatcher/gen/strings.g.dart';

/// Flat-map lookup keeps download state/error codes separate from UI wording.
String downloadText(String key, [Map<String, Object> values = const {}]) {
  var text = loc['downloadQueue.$key'] as String;
  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }
  return text;
}
