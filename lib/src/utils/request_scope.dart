import 'dart:async';

import 'package:dio/dio.dart';

// Explicit dependencies for non-interactive site requests. Zones also isolate
// simultaneous UI requests from download-only pacing and authentication rules.
class RequestScope {
  const RequestScope({
    required this.client,
    required this.cookies,
    required this.saveCookies,
    this.settings,
    this.headless = false,
  });
  final Dio Function() client;
  final Future<String> Function(String) cookies;
  final Future<bool> Function(String, List<String>) saveCookies;
  final Object? settings;
  final bool headless;
  static final Object _key = Object();
  static RequestScope? get current => Zone.current[_key] as RequestScope?;
  Future<T> run<T>(Future<T> Function() action) => runZoned(action, zoneValues: {_key: this});
}
