import 'dart:async';

// Session-scoped scheduling. A pending direct write always represents the latest intent.
class ServerFavoriteCoordinator {
  ServerFavoriteCoordinator._();

  static final Set<String> _running = {};
  static final Map<String, _PendingFavoriteWrite> _pending = {};

  static bool tryStart(String key) => _running.add(key);

  static void finish(String key) {
    _running.remove(key);
    final next = _pending.remove(key);
    if (next != null) unawaited(_run(key, next));
  }

  static Future<void> submit(String key, Future<void> Function() action) {
    final pending = _PendingFavoriteWrite(action);
    if (_running.contains(key)) {
      final previous = _pending[key];
      if (previous != null) pending.waiters.addAll(previous.waiters);
      _pending[key] = pending;
    } else {
      unawaited(_run(key, pending));
    }
    return pending.waiters.first.future;
  }

  static Future<void> _run(String key, _PendingFavoriteWrite pending) async {
    _running.add(key);
    try {
      await pending.zone.run(pending.action);
      for (final waiter in pending.waiters) {
        waiter.complete();
      }
    } catch (error, stack) {
      for (final waiter in pending.waiters) {
        waiter.completeError(error, stack);
      }
    } finally {
      finish(key);
    }
  }
}

class _PendingFavoriteWrite {
  _PendingFavoriteWrite(this.action);

  final Future<void> Function() action;
  final Zone zone = Zone.current;
  final List<Completer<void>> waiters = [Completer<void>()];
}
