import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Retry-After dates and seconds never shorten the server deadline', () {
    final now = DateTime.utc(2026, 11, 12);
    expect(RateLimitPolicy.retryAfter('120', now), now.add(const Duration(seconds: 120)));
    expect(
      RateLimitPolicy.retryAfter(HttpDate.format(now.add(const Duration(hours: 1))), now),
      now.add(const Duration(hours: 1)),
    );
    expect(RateLimitPolicy.retryAfter('invalid', now), isNull);
    expect(const RateLimitPolicy(cooldownMs: 0).delayMs, 1000);
    expect(const RateLimitPolicy(cooldownMs: 3500).delayMs, 3500);
  });

  group('durable attempt ownership', () {
    late DownloadStore store;
    setUp(() async {
      sqfliteFfiInit();
      store = await DownloadStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      await store.createBatch(const DownloadBatchSpec(id: 'batch', title: 'Batch', requestedCount: 2, query: 'test'));
    });
    tearDown(() => store.close());

    PreparedTransfer transfer(String id) => PreparedTransfer(
      id: id,
      batchId: 'batch',
      sourceKey: 'example.test',
      sourceName: 'Example',
      url: 'https://example.test/$id.jpg',
      filename: '$id.jpg',
      destination: const DestinationRef(path: '/downloads'),
      item: {'postURL': 'https://example.test/posts/$id'},
    );

    test('replayed discovery page does not duplicate tasks or exceed its cap', () async {
      final page = [transfer('a'), transfer('b'), transfer('c')];
      await store.commitPage('batch', page, const DiscoveryCheckpoint(page: 2), exhausted: false);
      await store.commitPage('batch', page, const DiscoveryCheckpoint(page: 2), exhausted: false);
      expect((await store.tasks(batchId: 'batch')).length, 2);
      expect((await store.batch('batch'))!['discoveryDone'], 1);
    });

    test('only one claimant can own an attempt', () async {
      await store.enqueue([transfer('a')]);
      final claims = await Future.wait([store.claim('a'), store.claim('a')]);
      expect(claims.whereType<DownloadTask>().length, 1);
    });

    test('duplicate receipts create only one completion event', () async {
      await store.enqueue([transfer('a')]);
      final task = (await store.claim('a'))!;
      final receipt = TransferReceipt(
        id: 'receipt',
        taskId: 'a',
        attemptId: task.attemptId!,
        state: DownloadState.completed,
        destination: '/downloads/a.jpg',
      );
      await store.applyReceipt(receipt);
      await store.applyReceipt(receipt);
      expect((await store.completionEvents()).length, 1);
      expect((await store.task('a'))!.state, DownloadState.completed);
    });

    test('cancelled transfer cannot authorize publication', () async {
      await store.enqueue([transfer('a')]);
      final task = (await store.claim('a'))!;
      await store.command('cancel', taskId: 'a');
      expect(await store.authorizePublication(task), isFalse);
    });

    test('cancel during authorized publication preserves the saved outcome', () async {
      await store.enqueue([transfer('a')]);
      final task = (await store.claim('a'))!;
      expect(await store.authorizePublication(task), isTrue);
      await store.command('cancel', taskId: 'a');
      await store.applyReceipt(
        TransferReceipt(
          id: 'saved',
          taskId: 'a',
          attemptId: task.attemptId!,
          state: DownloadState.completed,
          destination: '/downloads/a.jpg',
        ),
      );
      expect((await store.task('a'))!.state, DownloadState.completed);
      expect((await store.completionEvents()).length, 1);
    });

    test('retry failed does not requeue skipped files', () async {
      await store.enqueue([transfer('a'), transfer('b')]);
      await store.setState('a', DownloadState.failed, error: 'http404');
      await store.setState('b', DownloadState.skipped);
      await store.command('retry', batchId: 'batch');
      expect((await store.task('a'))!.state, DownloadState.queued);
      expect((await store.task('b'))!.state, DownloadState.skipped);
    });

    test('publication recovery survives cancellation of its parent batch', () async {
      await store.enqueue([transfer('a')]);
      final task = (await store.claim('a'))!;
      expect(await store.authorizePublication(task), isTrue);
      await store.command('cancel', batchId: 'batch');
      await store.recover(nativeTransfers: false);
      expect((await store.ready()).map((e) => e.id), contains('a'));
      expect(await store.claim('a'), isNotNull);
    });

    test('a blocked search does not block files already discovered', () async {
      await store.enqueue([transfer('a')]);
      await store.discoveryError('batch', 'authentication');
      expect(await store.discoveries(), isEmpty);
      expect(await store.claim('a'), isNotNull);
    });

    test('a page from before pause and resume cannot advance the checkpoint', () async {
      await store.command('pause', batchId: 'batch');
      await store.command('resume', batchId: 'batch');
      await store.commitPage(
        'batch',
        [transfer('a')],
        const DiscoveryCheckpoint(page: 2),
        exhausted: false,
        generation: 0,
      );
      expect(await store.tasks(batchId: 'batch'), isEmpty);
      expect((await store.batch('batch'))!['selectedCount'], 0);
    });

    test('multiple files from one post count once and remain selected together', () async {
      final first = transfer('a').withValues({
        'item': {'postURL': 'post/1', 'serverId': '1_a', 'downloadPostId': '1'},
      });
      final second = transfer('b').withValues({
        'item': {'postURL': 'post/1', 'serverId': '1_b', 'downloadPostId': '1'},
      });
      await store.commitPage(
        'batch',
        [first, second, transfer('c'), transfer('d')],
        const DiscoveryCheckpoint(page: 2),
        exhausted: false,
      );
      expect((await store.tasks(batchId: 'batch')).length, 3);
      expect((await store.batch('batch'))!['selectedCount'], 2);
    });

    test('one site cooldown does not hide eligible work from another site', () async {
      await store.enqueue([
        for (var i = 0; i < 150; i++) transfer('a$i'),
        transfer('other').withValues({'sourceKey': 'other.test', 'url': 'https://other.test/image.jpg'}),
      ]);
      await store.defer(['site:example.test'], DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      expect((await store.ready()).map((e) => e.id), ['other']);
    });

    test('download again does not change replacement policy of queued files', () async {
      await store.enqueue([transfer('a'), transfer('b')]);
      await store.setState('a', DownloadState.skipped);
      await store.command('redownload', batchId: 'batch');
      expect((await store.task('a'))!.transfer.overwrite, isTrue);
      expect((await store.task('b'))!.transfer.overwrite, isFalse);
    });

    test('publication receipt retains staged bytes for a retry', () async {
      await store.enqueue([transfer('a')]);
      final task = (await store.claim('a', native: true))!;
      await store.applyReceipt(
        TransferReceipt(
          id: 'publication',
          taskId: 'a',
          attemptId: task.attemptId!,
          state: DownloadState.needsAction,
          error: 'photosPermission',
          stage: 'publishing',
        ),
      );
      await store.command('retry', taskId: 'a');
      expect((await store.task('a'))!.stage, 'publishing');
    });

    test('enqueue rolls back both batch and pages if preparation fails', () async {
      const spec = DownloadBatchSpec(id: 'atomic', title: 'Atomic', requestedCount: 200);
      await expectLater(
        store.enqueueAtomic(spec, (offset, executor) async {
          if (offset == 100) throw StateError('interrupted preparation');
          // Reads inside preparation use the supplied transaction, avoiding a
          // second connection waiting for its own open write transaction.
          await executor.query('download_cookies');
          return [
            for (var i = 0; i < 100; i++) transfer('atomic$i').withValues({'batchId': 'atomic'}),
          ];
        }),
        throwsStateError,
      );
      expect(await store.batch('atomic'), isNull);
      expect(await store.tasks(batchId: 'atomic'), isEmpty);
    });

    test('ten thousand persisted files keep UI and native preparation pages bounded', () async {
      const spec = DownloadBatchSpec(id: 'large', title: 'Large queue', requestedCount: 10000);
      await store.enqueueAtomic(
        spec,
        (offset, executor) async => [
          for (var i = offset; i < offset + 100; i++) transfer('large$i').withValues({'batchId': 'large'}),
        ],
      );
      expect((await store.batch('large'))!['selectedCount'], 10000);
      expect((await store.tasks(batchId: 'large', limit: 10000)).length, 100);
      expect((await store.ready(preparationOnly: true)).length, 100);
      expect((await store.tasks(batchId: 'large', offset: 9900)).length, 100);
    });
  });
}
