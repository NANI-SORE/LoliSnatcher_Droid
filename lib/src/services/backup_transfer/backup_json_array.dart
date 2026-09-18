import 'dart:convert';

/// Reads one JSON object at a time without retaining the whole exported library.
/// Syntax and UTF-8 errors propagate; callers preflight before writing any rows.
Stream<Map<String, dynamic>> readBackupJsonArray(Stream<List<int>> bytes) async* {
  var started = false;
  var ended = false;
  var expectingValue = true;
  var allowEnd = true;
  var depth = 0;
  var inString = false;
  var escaped = false;
  var firstCharacter = true;
  var record = StringBuffer();
  var length = 0;
  await for (final chunk in bytes.transform(utf8.decoder)) {
    for (final code in chunk.codeUnits) {
      if (firstCharacter && code == 0xfeff) {
        firstCharacter = false;
        continue;
      }
      firstCharacter = false;
      final whitespace = code == 32 || code == 9 || code == 10 || code == 13;
      if (!started) {
        if (whitespace) continue;
        if (code != 91) throw const FormatException('Expected a JSON array');
        started = true;
        continue;
      }
      if (ended) {
        if (!whitespace) throw const FormatException('Unexpected data after JSON array');
        continue;
      }
      if (depth == 0) {
        if (whitespace) continue;
        if (!expectingValue) {
          if (code == 93) {
            ended = true;
            continue;
          }
          if (code != 44) throw const FormatException('Expected a comma between records');
          expectingValue = true;
          allowEnd = false;
          continue;
        }
        if (code == 93 && allowEnd) {
          ended = true;
          continue;
        }
        if (code != 123) throw const FormatException('Expected a JSON object');
        record = StringBuffer();
        length = 0;
      }
      record.writeCharCode(code);
      // Count UTF-8 bytes, not UTF-16 code units. The strict UTF-8 decoder
      // produces valid surrogate pairs: three bytes for the high half plus
      // one for the low half accounts for a four-byte Unicode scalar.
      length += code <= 0x7f
          ? 1
          : code <= 0x7ff
          ? 2
          : code >= 0xdc00 && code <= 0xdfff
          ? 1
          : 3;
      if (length > 8 * 1024 * 1024) throw const FormatException('Backup record exceeds 8 MiB');
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 92) {
          escaped = true;
        } else if (code == 34) {
          inString = false;
        }
      } else if (code == 34) {
        inString = true;
      } else if (code == 123 || code == 91) {
        depth++;
        if (depth > 100) throw const FormatException('Backup record is too deeply nested');
      } else if (code == 125 || code == 93) {
        depth--;
        if (depth == 0) {
          final decoded = jsonDecode(record.toString());
          if (decoded is! Map<String, dynamic>) throw const FormatException('Expected a JSON object');
          yield decoded;
          record = StringBuffer();
          expectingValue = false;
        }
      }
    }
  }
  if (!started || !ended || depth != 0 || inString) throw const FormatException('Incomplete JSON array');
}
