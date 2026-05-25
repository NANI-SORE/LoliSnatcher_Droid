import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

Future<void> main() async {
  group('Tools.urlJoin', () {
    test('joins relative path correctly', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/file.html', 'next.html'),
        'http://example.com/folder/next.html',
      );
    });

    test('replaces path if segment starts with /', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/file.html', '/new/path.html'),
        'http://example.com/new/path.html',
      );
    });

    test('returns segment if base is null', () async {
      expect(
        Tools.urlJoin(null, '/path'),
        '/path',
      );
    });

    test('returns base if segment is null', () async {
      expect(
        Tools.urlJoin('https://example.com', null),
        'https://example.com',
      );
    });

    test('keeps port numbers', () async {
      expect(
        Tools.urlJoin('http://example.com:8080/folder/', 'next.html'),
        'http://example.com:8080/folder/next.html',
      );
    });

    test('handles double slashes segment like Python urljoin', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/file.html', '//other.com/path'),
        'http://other.com/path',
      );
    });

    test('keeps query and fragment from base when joining relative', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/?q=1#frag', 'next.html'),
        'http://example.com/folder/next.html',
      );
    });

    test('joins relative path with query and fragment', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/next.html', 'page.html?q=1#frag'),
        'http://example.com/folder/page.html?q=1#frag',
      );
    });

    test('replaces only query and fragment on same path', () async {
      expect(
        Tools.urlJoin('http://example.com/folder/next.html', '?q=1#frag'),
        'http://example.com/folder/next.html?q=1#frag',
      );
    });
  });
}
