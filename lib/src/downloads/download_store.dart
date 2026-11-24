import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/downloads/contracts.dart';

class DownloadStore {
  DownloadStore._(this.db);
  final Database db;

  static Future<DownloadStore> open(String path, {DatabaseFactory? factory}) async {
    final executor =
        factory ?? (Platform.isAndroid || Platform.isIOS ? sqflite.databaseFactorySqflitePlugin : databaseFactory);
    final db = await executor.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE batches (
          id TEXT PRIMARY KEY, spec TEXT NOT NULL, title TEXT NOT NULL,
          requestedCount INTEGER NOT NULL, selectedCount INTEGER NOT NULL DEFAULT 0,
          discoveryDone INTEGER NOT NULL, checkpoint TEXT NOT NULL,
          state TEXT NOT NULL DEFAULT 'active', discoveryState TEXT NOT NULL DEFAULT 'active',
          generation INTEGER NOT NULL DEFAULT 0, error TEXT, nextEligible INTEGER NOT NULL DEFAULT 0,
          created INTEGER NOT NULL, notice TEXT)''');
          await db.execute('''
CREATE TABLE tasks (
          id TEXT PRIMARY KEY, batchId TEXT NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
          identity TEXT NOT NULL, sourceKey TEXT NOT NULL, host TEXT NOT NULL, payload TEXT NOT NULL,
          state TEXT NOT NULL DEFAULT 'queued', generation INTEGER NOT NULL DEFAULT 0, batchGeneration INTEGER NOT NULL DEFAULT 0,
          attempts INTEGER NOT NULL DEFAULT 0, attemptId TEXT,
          received INTEGER NOT NULL DEFAULT 0, total INTEGER NOT NULL DEFAULT 0,
          nextEligible INTEGER NOT NULL DEFAULT 0, error TEXT, warning TEXT, result TEXT,
          stage TEXT NOT NULL DEFAULT '', validator TEXT, updated INTEGER NOT NULL,
          UNIQUE(batchId, identity))''');
          await db.execute('CREATE INDEX tasks_ready ON tasks(state, nextEligible, updated)');
          await db.execute('CREATE INDEX tasks_batch ON tasks(batchId, state)');
          await db.execute('CREATE INDEX tasks_identity ON tasks(identity)');
          await db.execute('CREATE TABLE rates (scope TEXT PRIMARY KEY, deadline INTEGER NOT NULL)');
          await db.execute('CREATE TABLE receipts (id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
          await db.execute('''
CREATE TABLE completion_events (
          id TEXT PRIMARY KEY, taskId TEXT NOT NULL, payload TEXT NOT NULL)''');
          await db.execute('CREATE TABLE presets (id TEXT PRIMARY KEY, name TEXT NOT NULL, payload TEXT NOT NULL)');
          await db.execute(
            'CREATE TABLE discovery_ids (batchId TEXT NOT NULL, sourceKey TEXT NOT NULL, position INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY(batchId, sourceKey, position))',
          );
          await db.execute('CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await db.execute(
            'CREATE TABLE download_cookies (id TEXT PRIMARY KEY, domain TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE selected_posts (batchId TEXT NOT NULL REFERENCES batches(id) ON DELETE CASCADE, identity TEXT NOT NULL, PRIMARY KEY(batchId, identity))',
          );
        },
      ),
    );
    return DownloadStore._(db);
  }

  Future<void> close() => db.close();

  Future<void> createBatch(DownloadBatchSpec spec) async {
    await _createBatch(db, spec);
  }

  Future<void> _createBatch(DatabaseExecutor executor, DownloadBatchSpec spec) async {
    if (spec.requestedCount < 1 || spec.startPage < 1) throw ArgumentError('Invalid download batch');
    await executor.insert('batches', {
      'id': spec.id,
      'spec': jsonEncode(spec.toJson()),
      'title': spec.title,
      'requestedCount': spec.requestedCount,
      'discoveryDone': spec.query == null ? 1 : 0,
      'checkpoint': jsonEncode(DiscoveryCheckpoint(page: spec.startPage).toJson()),
      'created': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> enqueueAtomic(
    DownloadBatchSpec spec,
    Future<List<PreparedTransfer>> Function(int offset, DatabaseExecutor executor) page,
  ) => db.transaction((txn) async {
    await _createBatch(txn, spec);
    for (var offset = 0; offset < spec.requestedCount; offset += 100) {
      final batch = txn.batch();
      for (final transfer in await page(offset, txn)) {
        batch.insert('tasks', {
          'id': transfer.id,
          'batchId': transfer.batchId,
          'identity': transfer.identity,
          'sourceKey': transfer.sourceKey,
          'host': transfer.host,
          'payload': jsonEncode(transfer.toJson()),
          'updated': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    }
    final selected =
        (await txn.rawQuery('SELECT COUNT(*) AS count FROM tasks WHERE batchId = ?', [spec.id])).single['count']!
            as int;
    await txn.update('batches', {'selectedCount': selected}, where: 'id = ?', whereArgs: [spec.id]);
  });

  Future<Map<String, dynamic>?> batch(String id) async =>
      (await db.query('batches', where: 'id = ?', whereArgs: [id], limit: 1)).firstOrNull;

  Future<List<Map<String, dynamic>>> batches({String? batchId, int offset = 0, int limit = 100}) => db.rawQuery(
    '''
    SELECT b.*, COUNT(t.id) AS total,
      SUM(CASE WHEN t.state = 'completed' THEN 1 ELSE 0 END) AS saved,
      SUM(CASE WHEN t.state = 'skipped' THEN 1 ELSE 0 END) AS skipped,
      SUM(CASE WHEN t.state IN ('failed','needsAction') THEN 1 ELSE 0 END) AS failed,
      SUM(CASE WHEN t.state = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
      SUM(CASE WHEN t.state = 'paused' THEN 1 ELSE 0 END) AS paused,
      SUM(CASE WHEN t.state = 'waitingNetwork' THEN 1 ELSE 0 END) AS waitingNetwork,
      SUM(CASE WHEN t.state = 'waitingRate' THEN 1 ELSE 0 END) AS waitingRate,
      SUM(CASE WHEN t.state IN ('transferring','finalizing') THEN 1 ELSE 0 END) AS running,
      SUM(CASE WHEN t.state IN ('queued','prepared','waitingNetwork','waitingRate') THEN 1 ELSE 0 END) AS waiting
    FROM batches b LEFT JOIN tasks t ON t.batchId = b.id
    ${batchId == null ? '' : 'WHERE b.id = ?'}
    GROUP BY b.id ORDER BY b.created DESC, b.id LIMIT ? OFFSET ?''',
    [?batchId, limit.clamp(1, 100), offset],
  );

  Future<List<Map<String, dynamic>>> discoveries() => db.query(
    'batches',
    where: "discoveryDone = 0 AND state = 'active' AND discoveryState = 'active' AND nextEligible <= ?",
    whereArgs: [DateTime.now().millisecondsSinceEpoch],
    orderBy: 'created',
    limit: 3,
  );

  Future<void> enqueue(List<PreparedTransfer> transfers) => db.transaction((txn) async {
    for (final transfer in transfers) {
      await _insert(txn, transfer);
    }
  });

  Future<bool> _insert(DatabaseExecutor txn, PreparedTransfer transfer) async {
    final existing = await txn.query(
      'tasks',
      columns: ['id'],
      where: 'batchId = ? AND identity = ?',
      whereArgs: [transfer.batchId, transfer.identity],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await txn.insert('tasks', {
      'id': transfer.id,
      'batchId': transfer.batchId,
      'identity': transfer.identity,
      'sourceKey': transfer.sourceKey,
      'host': transfer.host,
      'payload': jsonEncode(transfer.toJson()),
      'updated': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  }

  Future<void> commitPage(
    String batchId,
    List<PreparedTransfer> page,
    DiscoveryCheckpoint next, {
    required bool exhausted,
    int? generation,
  }) => db.transaction((txn) async {
    final rows = await txn.query('batches', where: 'id = ?', whereArgs: [batchId], limit: 1);
    if (rows.isEmpty || rows.first['state'] != 'active' || rows.first['discoveryDone'] == 1) return;
    final row = rows.first;
    if (generation != null && row['generation'] != generation) return;
    var selected = (row['selectedCount']! as num).toInt();
    final maximum = (row['requestedCount']! as num).toInt();
    for (final transfer in page) {
      final post = downloadIdentity([transfer.sourceKey, transfer.item['downloadPostId'] ?? transfer.item['postURL']]);
      final known = await txn.query(
        'selected_posts',
        where: 'batchId = ? AND identity = ?',
        whereArgs: [batchId, post],
        limit: 1,
      );
      if (known.isEmpty) {
        if (selected >= maximum) continue;
        await txn.insert('selected_posts', {'batchId': batchId, 'identity': post});
        selected++;
      }
      await _insert(txn, transfer);
    }
    await txn.update(
      'batches',
      {
        'selectedCount': selected,
        'checkpoint': jsonEncode(next.toJson()),
        'discoveryDone': exhausted || selected >= maximum ? 1 : 0,
        'error': null,
        'nextEligible': 0,
      },
      where: 'id = ?',
      whereArgs: [batchId],
    );
  });

  Future<DownloadTask?> task(String id) async {
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : DownloadTask.fromRow(rows.first);
  }

  Future<List<DownloadTask>> tasks({String? batchId, String? filter, int offset = 0, int limit = 100}) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (batchId != null) {
      clauses.add('batchId = ?');
      args.add(batchId);
    }
    switch (filter) {
      case 'attention':
        clauses.add("state IN ('failed','needsAction')");
      case 'complete':
        clauses.add("state IN ('completed','skipped','cancelled')");
      case 'active':
        clauses.add(
          "state IN ('queued','prepared','transferring','finalizing','paused','waitingNetwork','waitingRate')",
        );
    }
    final rows = await db.query(
      'tasks',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'rowid',
      limit: limit.clamp(1, 100),
      offset: offset,
    );
    return rows.map(DownloadTask.fromRow).toList();
  }

  Future<List<DownloadTask>> ready({bool preparationOnly = false}) async {
    if (preparationOnly) {
      return (await db.rawQuery(
        '''
        SELECT t.* FROM tasks t JOIN batches b ON b.id = t.batchId
        WHERE t.state IN ('queued','waitingRate','waitingNetwork') AND t.nextEligible <= ?
          AND (b.state = 'active' OR t.stage = 'publishing')
        ORDER BY t.updated, t.id LIMIT 100''',
        [DateTime.now().millisecondsSinceEpoch],
      )).map(DownloadTask.fromRow).toList();
    }
    return (await db.rawQuery(
      '''
    SELECT t.* FROM tasks t JOIN batches b ON b.id = t.batchId
    WHERE t.state IN ('queued','waitingRate','waitingNetwork') AND t.nextEligible <= ?
      AND (b.state = 'active' OR t.stage = 'publishing')
      AND NOT EXISTS (SELECT 1 FROM rates r WHERE r.scope IN ('site:' || t.sourceKey, 'host:' || t.host) AND r.deadline > ?)
      AND NOT EXISTS (SELECT 1 FROM tasks a WHERE a.sourceKey = t.sourceKey AND a.state IN ('transferring','finalizing'))
    GROUP BY t.sourceKey
    ORDER BY MIN(t.updated), t.id LIMIT 100''',
      [DateTime.now().millisecondsSinceEpoch, DateTime.now().millisecondsSinceEpoch],
    )).map(DownloadTask.fromRow).toList();
  }

  Future<DownloadTask?> claim(String id, {bool native = false}) => db.transaction((txn) async {
    final rows = await txn.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final before = DownloadTask.fromRow(rows.first);
    if (!before.state.runnable || before.nextEligible > DateTime.now().millisecondsSinceEpoch) return null;
    final parent = await txn.query(
      'batches',
      columns: ['state', 'generation'],
      where: 'id = ?',
      whereArgs: [before.transfer.batchId],
      limit: 1,
    );
    if (parent.firstOrNull?['state'] != 'active' && before.stage != 'publishing') return null;
    final attemptId = const Uuid().v4();
    await txn.update(
      'tasks',
      {
        'state': native ? 'prepared' : 'transferring',
        'attemptId': attemptId,
        'attempts': before.attempts + 1,
        'batchGeneration': parent.first['generation'],
        'error': null,
        'updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return DownloadTask.fromRow((await txn.query('tasks', where: 'id = ?', whereArgs: [id])).single);
  });

  Future<bool> authorizePublication(DownloadTask task) async =>
      await db.update(
        'tasks',
        {'state': 'finalizing', 'stage': 'publishing'},
        where: "id = ? AND attemptId = ? AND generation = ? AND state = 'transferring'",
        whereArgs: [task.id, task.attemptId, task.generation],
      ) ==
      1;

  Future<void> updateAttempt(DownloadTask task, Map<String, Object?> values) async {
    await db.update('tasks', values, where: 'id = ? AND attemptId = ?', whereArgs: [task.id, task.attemptId]);
  }

  Future<void> setState(String id, DownloadState state, {String? error, int retryAt = 0}) async {
    await db.update(
      'tasks',
      {'state': state.name, 'error': error, 'nextEligible': retryAt, 'updated': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> applyReceipt(TransferReceipt receipt) => db.transaction((txn) async {
    if ((await txn.query('receipts', columns: ['id'], where: 'id = ?', whereArgs: [receipt.id])).isNotEmpty) return;
    await txn.insert('receipts', {'id': receipt.id, 'payload': jsonEncode(receipt.toJson())});
    final rows = await txn.query('tasks', where: 'id = ?', whereArgs: [receipt.taskId], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.single;
    final physicalOutcome = receipt.state == DownloadState.completed || receipt.state == DownloadState.skipped;
    if (physicalOutcome) {
      await txn.insert('completion_events', {
        'id': receipt.id,
        'taskId': receipt.taskId,
        'payload': jsonEncode({'transfer': jsonDecode(row['payload']! as String), 'receipt': receipt.toJson()}),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (row['attemptId'] != receipt.attemptId) return;
    if (!physicalOutcome && const ['cancelled', 'paused'].contains(row['state'])) return;
    await txn.update(
      'tasks',
      {
        'state': receipt.state.name,
        'result': receipt.destination,
        'error': receipt.error,
        'warning': receipt.warning,
        'nextEligible': receipt.retryAt,
        if (receipt.attempts != null) 'attempts': receipt.attempts,
        'stage': physicalOutcome ? 'published' : receipt.stage ?? row['stage'],
        'updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [receipt.taskId],
    );
  });

  Future<List<Map<String, dynamic>>> completionEvents() => db.query('completion_events', limit: 100);
  Future<void> acknowledgeEvents(List<String> ids) => db.transaction((txn) async {
    for (final id in ids) {
      await txn.delete('completion_events', where: 'id = ?', whereArgs: [id]);
    }
  });

  Future<void> command(String command, {String? taskId, String? batchId}) => db.transaction((txn) async {
    final where = taskId != null
        ? 'id = ?'
        : batchId != null
        ? 'batchId = ?'
        : '1 = 1';
    final args = <Object?>[if (taskId != null) taskId else ?batchId];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (command == 'pause' || command == 'cancel') {
      final state = command == 'pause' ? 'paused' : 'cancelled';
      await txn.rawUpdate(
        '''
            UPDATE tasks SET state = ?, generation = generation + 1, updated = ?
            WHERE $where AND state NOT IN ('completed','skipped','cancelled','finalizing')''',
        [state, now, ...args],
      );
      if (taskId == null) {
        await txn.rawUpdate(
          "UPDATE batches SET state = ?, generation = generation + 1 ${batchId == null ? '' : 'WHERE id = ?'}",
          [state, ?batchId],
        );
      }
    } else if (const ['resume', 'retry', 'redownload'].contains(command)) {
      final states = command == 'resume'
          ? "('paused','waitingNetwork','waitingRate')"
          : command == 'retry'
          ? "('failed','needsAction')"
          : "('skipped','completed','cancelled','failed','needsAction')";
      if (command == 'redownload') {
        // Change only the selected terminal records, in bounded pages.
        while (true) {
          final rows = await txn.query('tasks', where: '$where AND state IN $states', whereArgs: args, limit: 100);
          if (rows.isEmpty) break;
          for (final row in rows) {
            final payload = downloadMap(row['payload'])..['overwrite'] = true;
            await txn.update(
              'tasks',
              {
                'payload': jsonEncode(payload),
                'state': 'queued',
                'generation': (row['generation']! as int) + 1,
                'attempts': 0,
                'attemptId': null,
                'error': null,
                'nextEligible': 0,
                'updated': now,
                'stage': '',
                'validator': null,
                'received': 0,
                'result': null,
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      }
      await txn.rawUpdate(
        '''
            UPDATE tasks SET state = 'queued', generation = generation + 1,
            attempts = 0, attemptId = NULL, error = NULL, nextEligible = 0, updated = ?
            WHERE $where AND state IN $states''',
        [now, ...args],
      );
      if (taskId == null) {
        await txn.rawDelete(
          "DELETE FROM metadata WHERE key IN (SELECT 'discoveryAttempts:' || id FROM batches ${batchId == null ? '' : 'WHERE id = ?'})",
          [?batchId],
        );
        await txn.rawUpdate("UPDATE batches SET generation = generation + 1 ${batchId == null ? '' : 'WHERE id = ?'}", [
          ?batchId,
        ]);
        await txn.update(
          'batches',
          {'state': 'active', 'discoveryState': 'active', 'error': null, 'nextEligible': 0, 'notice': null},
          where: batchId == null ? null : 'id = ?',
          whereArgs: batchId == null ? null : [batchId],
        );
      } else {
        await txn.rawUpdate(
          "UPDATE batches SET state = 'active', notice = NULL WHERE id IN (SELECT batchId FROM tasks WHERE id = ?)",
          [taskId],
        );
      }
    } else if (command == 'clear') {
      await txn.rawDelete(
        '''
            DELETE FROM batches WHERE (discoveryDone = 1 OR state = 'cancelled')
            AND NOT EXISTS (SELECT 1 FROM tasks WHERE batchId = batches.id
              AND state NOT IN ('completed','skipped','cancelled'))
            AND NOT EXISTS (SELECT 1 FROM completion_events e JOIN tasks t ON t.id = e.taskId WHERE t.batchId = batches.id)
            ${batchId == null ? '' : 'AND id = ?'}''',
        [?batchId],
      );
    }
  });

  Future<List<Map<String, dynamic>>> clearableBatches({String? batchId}) => db.rawQuery(
    '''
    SELECT id FROM batches WHERE (discoveryDone = 1 OR state = 'cancelled')
      AND NOT EXISTS (SELECT 1 FROM tasks WHERE batchId = batches.id AND state NOT IN ('completed','skipped','cancelled'))
      AND NOT EXISTS (SELECT 1 FROM completion_events e JOIN tasks t ON t.id = e.taskId WHERE t.batchId = batches.id)
      ${batchId == null ? '' : 'AND id = ?'} LIMIT 100''',
    [?batchId],
  );

  Future<void> recover({required bool nativeTransfers}) async {
    if (nativeTransfers) return; // URLSession owns these until task/receipt reconciliation.
    await db.rawUpdate("UPDATE tasks SET state = 'queued' WHERE state = 'transferring'");
    // Publication intents are inspected against durable native/filesystem journals.
    await db.rawUpdate("UPDATE tasks SET state = 'queued' WHERE state = 'finalizing'");
  }

  Future<void> discoveryError(String id, String error, {int retryAt = 0, bool actionable = true}) async {
    await db.update(
      'batches',
      {'error': error, 'nextEligible': retryAt, 'discoveryState': actionable ? 'needsAction' : 'active'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deadline(Iterable<String> scopes) async {
    var result = 0;
    for (final scope in scopes) {
      final rows = await db.query('rates', where: 'scope = ?', whereArgs: [scope], limit: 1);
      final value = (rows.firstOrNull?['deadline'] as num?)?.toInt() ?? 0;
      if (value > result) result = value;
    }
    return result;
  }

  Future<void> defer(Iterable<String> scopes, int until) => db.transaction((txn) async {
    for (final scope in scopes) {
      await txn.insert('rates', {'scope': scope, 'deadline': until}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.rawUpdate('UPDATE rates SET deadline = MAX(deadline, ?) WHERE scope = ?', [until, scope]);
    }
  });

  Future<Map<String, dynamic>> summary({bool notificationProgress = false}) async {
    final runtimeError = await db.query('metadata', columns: ['value'], where: 'key = ?', whereArgs: ['runtimeError']);
    final counts = await db.rawQuery('SELECT state, COUNT(*) AS count FROM tasks GROUP BY state');
    final discovery = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM batches WHERE discoveryDone = 0 AND state = 'active' AND discoveryState = 'active'",
    );
    final discoveryAttention = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM batches WHERE discoveryDone = 0 AND state = 'active' AND discoveryState = 'needsAction'",
    );
    final discoveryPaused = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM batches WHERE discoveryDone = 0 AND state = 'paused'",
    );
    final countsSelected = (await db.rawQuery(
      "SELECT COALESCE(SUM(selectedCount),0) AS selected, COALESCE(SUM(requestedCount),0) AS requested FROM batches WHERE discoveryDone = 0 AND state = 'active' AND discoveryState = 'active'",
    )).single;
    return {
      if (notificationProgress) 'notificationProgress': await _notificationProgress(),
      'unfinishedBatches': (await db.rawQuery('''
        SELECT COUNT(*) AS count FROM batches b WHERE b.state != 'cancelled' AND
          (b.discoveryDone = 0 OR EXISTS (SELECT 1 FROM tasks t WHERE t.batchId = b.id
            AND t.state NOT IN ('completed','skipped','cancelled')))
      ''')).single['count'],
      'runtimeError': runtimeError.firstOrNull?['value'],
      for (final row in counts) row['state']! as String: row['count'],
      'discovery': discovery.single['count'],
      'discoveryAttention': discoveryAttention.single['count'],
      'discoveryPaused': discoveryPaused.single['count'],
      'discoverySelected': countsSelected['selected'],
      'discoveryRequested': countsSelected['requested'],
      'activeTasks': (await db.query(
        'tasks',
        where: "state IN ('transferring','finalizing') OR (state = 'prepared' AND received > 0)",
        limit: 3,
      )).map((r) => DownloadTask.fromRow(r).toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> _notificationProgress() async => (await db.rawQuery('''
    WITH current_batches AS (
      SELECT b.id FROM batches b
      WHERE (b.state = 'active' AND b.discoveryDone = 0 AND b.discoveryState = 'active')
        OR EXISTS (SELECT 1 FROM tasks t WHERE t.batchId = b.id
          AND t.state IN ('queued','prepared','transferring','finalizing','waitingNetwork','waitingRate'))
    )
    SELECT COUNT(DISTINCT b.id) AS batches, MIN(b.id) AS batchId, COUNT(t.id) AS total,
      COALESCE(SUM(t.state IN ('completed','skipped')),0) AS done,
      COALESCE(SUM(t.state = 'transferring'),0) AS active,
      COALESCE(SUM(t.state = 'finalizing'),0) AS saving,
      COALESCE(SUM(CASE WHEN t.state = 'transferring' THEN MAX(t.received,0) ELSE 0 END),0) AS received,
      COALESCE(SUM(CASE WHEN t.state = 'transferring' THEN MAX(t.total,0) ELSE 0 END),0) AS bytesTotal,
      COALESCE(SUM(t.state = 'transferring' AND t.total <= 0),0) AS unknownSize
    FROM current_batches b LEFT JOIN tasks t ON t.batchId = b.id
  ''')).single;

  Future<void> putPreset(String id, String name, Map<String, dynamic> payload) async {
    await db.insert('presets', {
      'id': id,
      'name': name,
      'payload': jsonEncode(payload),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> presets() => db.query('presets', orderBy: 'name');
  Future<void> deletePreset(String id) async {
    await db.delete('presets', where: 'id = ?', whereArgs: [id]);
  }
}
