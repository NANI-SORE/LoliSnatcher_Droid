import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DBHandler handler;
  setUp(() async {
    sqfliteFfiInit();
    handler = DBHandler()..db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await handler.updateTable();
  });
  tearDown(() => handler.closeDb());

  BooruItem item({String? id, String? filename, bool favourite = false, bool snatched = false}) => BooruItem.fromMap({
    'fileURL': 'https://source.example/media.jpg',
    'sampleURL': '',
    'thumbnailURL': '',
    'postURL': 'https://source.example/posts/42',
    'tagsList': <String>[],
    'serverId': id,
    'savedFileName': filename,
    'isFavourite': favourite,
    'isSnatched': snatched,
  });

  Future<void> expectMerged() async {
    final rows = await handler.db!.query('BooruItem');
    expect(rows, hasLength(1));
    expect(rows.single, containsPair('isFavourite', 1));
    expect(rows.single, containsPair('isSnatched', 1));
    expect(rows.single, containsPair('serverId', '42'));
    expect(rows.single, containsPair('savedFileName', 'actual-provider-name.avif'));
  }

  for (final batch in [false, true]) {
    test('${batch ? 'batch' : 'single'} sync merges flags without replacing local offline metadata', () async {
      await handler.updateBooruItem(
        item(id: '42', filename: 'actual-provider-name.avif', snatched: true),
        BooruUpdateMode.local,
      );
      final incoming = item(id: '', filename: 'other-device.jpg', favourite: true);
      if (batch) {
        await handler.updateMultipleBooruItems([incoming], BooruUpdateMode.sync);
      } else {
        await handler.updateBooruItem(incoming, BooruUpdateMode.sync);
      }
      await expectMerged();
    });
  }

  test('streamed backup import coalesces duplicate rows and fills sparse offline metadata', () async {
    await handler.importBooruItems(
      Stream.fromIterable([
        item(favourite: true),
        item(id: '42', filename: 'actual-provider-name.avif', snatched: true),
        item(id: '', filename: 'other-device.jpg', favourite: true),
      ]),
      keepIndexes: false,
    );
    await expectMerged();
  });

  test('schema upgrades preserve old rows and add both merged metadata columns idempotently', () async {
    await handler.db!.execute('DROP TABLE BooruItem');
    await handler.db!.execute(
      'CREATE TABLE BooruItem(id INTEGER PRIMARY KEY, thumbnailURL TEXT, sampleURL TEXT, fileURL TEXT, postURL TEXT, mediaType TEXT, isSnatched INTEGER, isFavourite INTEGER)',
    );
    await handler.db!.insert('BooruItem', {'postURL': 'legacy', 'isFavourite': 1});
    await handler.updateTable();
    await handler.updateTable();
    final row = (await handler.db!.query('BooruItem')).single;
    expect(row['postURL'], 'legacy');
    expect(row.containsKey('serverId'), true);
    expect(row.containsKey('savedFileName'), true);
  });
}
