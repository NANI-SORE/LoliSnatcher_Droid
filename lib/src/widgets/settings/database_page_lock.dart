import 'package:flutter/foundation.dart';

class DatabasePageLock {
  DatabasePageLock._();

  static final ValueNotifier<bool> isBusy = ValueNotifier(false);

  static Future<void> run(Future<void> Function() action) async {
    if (isBusy.value) return;

    isBusy.value = true;
    try {
      await action();
    } finally {
      isBusy.value = false;
    }
  }
}
