import 'dart:io';

import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';

/// Shared by the UI and the headless Android executor. The database claim keeps
/// concurrent clients from alerting twice for the same actionable cause.
class DownloadNotices {
  DownloadNotices(this.store);
  final DownloadStore store;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  int _offset = 0;

  Future<void> check({bool force = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!force && DateTime.now().difference(_last).inSeconds < 4) return;
    _last = DateTime.now();
    final batches = await store.batches(offset: _offset);
    _offset = batches.length == 100 ? _offset + 100 : 0;
    for (final batch in batches) {
      final spec = DownloadBatchSpec.fromJson(downloadMap(batch['spec']));
      if (spec.policy['notifications'] == false) continue;
      final causes = (await store.db.rawQuery(
        "SELECT DISTINCT error FROM tasks WHERE batchId = ? AND state IN ('failed','needsAction') AND error IS NOT NULL",
        [batch['id']],
      )).map((row) => row['error']! as String).toSet();
      if (batch['discoveryState'] == 'needsAction' && batch['error'] != null) causes.add(batch['error'] as String);
      final complete =
          batch['discoveryDone'] == 1 &&
          batch['running'] == 0 &&
          batch['waiting'] == 0 &&
          batch['paused'] == 0 &&
          batch['failed'] == 0 &&
          (batch['saved'] as int) + (batch['skipped'] as int) > 0;
      if (complete) causes.add('complete');
      for (final cause in causes) {
        final key = 'notice:${batch['id']}:$cause';
        final claimed = await store.db.transaction((txn) async {
          if ((await txn.query('metadata', where: 'key = ?', whereArgs: [key])).isNotEmpty) return false;
          await txn.insert('metadata', {'key': key, 'value': '1'});
          return true;
        });
        if (!claimed) continue;
        try {
          await downloadPlatform.invokeMethod<void>('alert', {
            'id': key,
            'batchId': batch['id'],
            'complete': cause == 'complete',
          });
        } catch (_) {
          await store.db.delete('metadata', where: 'key = ?', whereArgs: [key]);
          rethrow;
        }
      }
    }
  }
}
