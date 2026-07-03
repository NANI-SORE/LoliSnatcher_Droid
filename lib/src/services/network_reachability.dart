import 'dart:async';
import 'dart:io';

class NetworkReachability {
  NetworkReachability._();
  static final NetworkReachability instance = NetworkReachability._();

  static const Duration _cacheDuration = Duration(seconds: 5);
  static const Duration _timeout = Duration(seconds: 2);

  DateTime? _checkedAt;
  bool? _hasConnection;
  Future<bool>? _activeCheck;

  Future<bool> hasConnection() {
    final checkedAt = _checkedAt;
    final cached = _hasConnection;
    if (checkedAt != null && cached != null && DateTime.now().difference(checkedAt) < _cacheDuration) {
      return Future.value(cached);
    }

    final activeCheck = _activeCheck;
    if (activeCheck != null) {
      return activeCheck;
    }

    final check = _checkNow();
    _activeCheck = check;
    return check.whenComplete(() {
      _activeCheck = null;
    });
  }

  Future<bool> _checkNow() async {
    bool result = false;
    try {
      final addresses = await InternetAddress.lookup('example.com').timeout(_timeout);
      result = addresses.any((address) => address.rawAddress.isNotEmpty);
    } catch (_) {
      result = false;
    }

    _checkedAt = DateTime.now();
    _hasConnection = result;
    return result;
  }
}
