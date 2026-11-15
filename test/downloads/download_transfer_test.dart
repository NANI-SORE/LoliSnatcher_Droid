import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_network.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';
import 'package:lolisnatcher/src/downloads/download_transfer.dart';

void main() {
  late Directory root;
  late DownloadPaths paths;
  late DownloadStore store;
  late HttpServer server;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('download-invariant-');
    paths = DownloadPaths(root.path);
    await Directory(p.join(root.path, 'staging')).create();
    await Directory(p.join(root.path, 'publication')).create();
    store = await DownloadStore.open(paths.database, factory: databaseFactoryFfi);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    await store.createBatch(const DownloadBatchSpec(id: 'batch', title: 'Controlled server', requestedCount: 1));
  });
  tearDown(() async {
    await server.close(force: true);
    await store.close();
    await root.delete(recursive: true);
  });

  Future<DownloadTask> task() async {
    await store.enqueue([
      PreparedTransfer(
        id: 'file',
        batchId: 'batch',
        sourceKey: 'controlled',
        sourceName: 'Controlled',
        url: 'http://127.0.0.1:${server.port}/file',
        filename: 'file.bin',
        destination: DestinationRef(path: p.join(root.path, 'published')),
        item: const {'postURL': 'controlled/1'},
        expectedSize: 6,
        checksum: md5.convert('abcdef'.codeUnits).toString(),
      ),
    ]);
    return (await store.claim('file'))!;
  }

  DownloadTransfer executor() => DownloadTransfer(
    store,
    paths,
    DownloadNetwork(configuration: DownloadConfiguration({}), gate: DownloadRateGate(store), site: 'controlled'),
  );

  test('a partial 206 response is continued before publication', () async {
    final ranges = <String?>[];
    server.listen((request) async {
      final range = request.headers.value('range');
      ranges.add(range);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set('etag', '"v1"');
      request.response.headers.set('content-type', 'application/octet-stream');
      request.response.headers.set('content-range', range == null ? 'bytes 0-2/6' : 'bytes 3-5/6');
      request.response.contentLength = 3;
      request.response.add((range == null ? 'abc' : 'def').codeUnits);
      await request.response.close();
    });
    await executor().run(await task(), CancelToken());
    expect(ranges, [null, 'bytes=3-']);
    expect((await store.task('file'))!.state, DownloadState.completed);
    expect(await File(p.join(root.path, 'published', 'file.bin')).readAsString(), 'abcdef');
  });

  test('416 with matching validator reconciles an already complete partial', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set('content-range', 'bytes */6');
      request.response.headers.set('etag', '"v1"');
      await request.response.close();
    });
    final claimed = await task();
    await File(paths.partial('file')).writeAsString('abcdef', flush: true);
    await store.updateAttempt(claimed, {'validator': '"v1"'});
    await executor().run((await store.task('file'))!, CancelToken());
    expect((await store.task('file'))!.state, DownloadState.completed);
    expect(await File(p.join(root.path, 'published', 'file.bin')).readAsString(), 'abcdef');
  });

  test('mismatching content never reaches the destination', () async {
    server.listen((request) async {
      request.response.headers.set('content-type', 'application/octet-stream');
      request.response.contentLength = 6;
      request.response.add('broken'.codeUnits);
      await request.response.close();
    });
    await executor().run(await task(), CancelToken());
    expect(await File(p.join(root.path, 'published', 'file.bin')).exists(), isFalse);
    expect((await store.task('file'))!.error, 'checksum');
    expect(await store.completionEvents(), isEmpty);
  });
}
