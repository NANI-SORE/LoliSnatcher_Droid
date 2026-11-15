import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_proxy/http_proxy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_enum.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/download_policy.dart';
import 'package:lolisnatcher/src/utils/http_overrides.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';

const downloadPlatform = MethodChannel('lolisnatcher/downloads');
const downloadWorkerPlatform = MethodChannel('lolisnatcher/downloads/worker');

class DownloadPaths {
  const DownloadPaths(this.root);
  final String root;
  String get database => p.join(root, 'downloads.db');
  String partial(String id) => p.join(root, 'staging', '$id.part');
  String journal(String id) => p.join(root, 'publication', '$id.json');
  static Future<DownloadPaths> open() async {
    final root = Platform.isAndroid || Platform.isIOS
        ? (await downloadPlatform.invokeMethod<String>('runtimeDirectory'))!
        : p.join((await getApplicationSupportDirectory()).path, 'download_runtime');
    for (final dir in [root, p.join(root, 'staging'), p.join(root, 'publication')]) {
      await Directory(dir).create(recursive: true);
    }
    return DownloadPaths(root);
  }
}

class DownloadConfiguration {
  DownloadConfiguration(this.data);
  final Map<String, dynamic> data;
  static const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const storageKey = 'downloadConfigurationV1';
  Future<void> _writes = Future<void>.value();
  Database? cookieDatabase;
  List<Booru> get sources => (data['sources'] as List? ?? const []).map((e) => Booru.fromMap(downloadMap(e))).toList();
  Booru? source(String name) => sources.where((s) => s.name == name).firstOrNull;
  Map<String, dynamic> policy(String name) => downloadMap(downloadMap(data['policies'])[name]);
  Map<String, dynamic> get transport => downloadMap(data['transport']);
  Map<String, dynamic> transportFor(String name) => downloadMap(downloadMap(data['transports'])[name]);
  String profile(String name) {
    final booru = source(name);
    return downloadIdentity([
      booru?.baseURL,
      booru?.type?.name,
      booru?.userID,
      booru?.apiKey,
      transportFor(name),
      policy(name)['cooldownMs'],
      downloadMap(data['settings'])['expandedSourceCompatibilityEnabled'],
    ]);
  }

  static Future<DownloadConfiguration> capture({Iterable<String> mediaUrls = const []}) async {
    final settings = SettingsHandler.instance;
    final registry = SettingsRegistry.instance;
    final sources = settings.booruList;
    if ((Platform.isAndroid || Platform.isIOS) &&
        sources.any((source) => SX.proxyType.valueForBooru(source.name).isSystem)) {
      final proxy = await HttpProxy.createHttpProxy();
      systemProxyAddress = proxy.host?.isNotEmpty == true && proxy.port?.isNotEmpty == true
          ? '${proxy.host}:${proxy.port}'
          : '';
    }
    final policies = <String, dynamic>{};
    final transports = <String, dynamic>{};
    final sourceJson = <Map<String, dynamic>>[];
    final cookieOrigins = <String>{};
    for (final source in sources) {
      final name = source.name ?? '';
      final output = DownloadPolicy.forBooru(source);
      sourceJson.add({...source.toJson(), 'settingOverrides': registry.saveOverridesToMap(name)});
      final path = Platform.isIOS || SX.extPathOverride.value.isEmpty
          ? await ServiceHandler.getPicturesDir()
          : SX.extPathOverride.value;
      policies[name] = {
        'quality': output.quality.toJson(),
        'writeJson': output.writeJson,
        'cooldownMs': SX.snatchCooldown.valueForBooru(name),
        'notifications': SX.downloadNotifications.valueForBooru(name),
        'destination': DestinationRef(
          path: path,
          photos: Platform.isIOS,
          photosReceipts: Platform.isIOS ? p.join(await ServiceHandler.getConfigDir(), 'photos_exports') : null,
        ).toJson(),
      };
      final uri = Uri.tryParse(source.baseURL ?? '');
      transports[name] = {
        'proxyType': SX.proxyType.valueForBooru(name).name,
        'proxyAddress': SX.proxyAddress.valueForBooru(name),
        'proxyUsername': SX.proxyUsername.valueForBooru(name),
        'proxyPassword': SX.proxyPassword.valueForBooru(name),
        'systemProxy': systemProxyAddress,
        'allowSelfSigned': SX.allowSelfSignedCerts.valueForBooru(name),
      };
      if (uri?.hasAuthority == true) cookieOrigins.add(uri!.toString());
    }
    for (final value in mediaUrls) {
      final uri = Uri.tryParse(value);
      if (uri?.hasAuthority == true) cookieOrigins.add(uri!.toString());
    }
    final cookies = <Map<String, dynamic>>[];
    for (final origin in cookieOrigins) {
      cookies.addAll(await Tools.downloadCookies(origin));
    }
    return DownloadConfiguration({
      'version': const Uuid().v4(),
      'settings': registry.toJson(),
      'sources': sourceJson,
      'policies': policies,
      'cookies': cookies,
      'transports': transports,
      'cookieHosts': cookieOrigins.map((u) => Uri.parse(u).host).toSet().toList(),
      'dbPath': settings.dbHandler.db?.path,
      'transport': {
        'proxyType': SX.proxyType.value.name,
        'proxyAddress': SX.proxyAddress.value,
        'proxyUsername': SX.proxyUsername.value,
        'proxyPassword': SX.proxyPassword.value,
        'systemProxy': systemProxyAddress,
        'allowSelfSigned': SX.allowSelfSignedCerts.value,
      },
    });
  }

  static Future<DownloadConfiguration?> load() async {
    final json = await storage.read(key: storageKey);
    return json == null ? null : DownloadConfiguration(downloadMap(json));
  }

  Future<void> save() {
    final encoded = jsonEncode(data);
    final next = _writes.then((_) => storage.write(key: storageKey, value: encoded));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> attachCookies(Database database, {bool seed = false}) async {
    cookieDatabase = database;
    if (!seed) return;
    if (Platform.isAndroid) await downloadPlatform.invokeMethod<void>('cookieGeneration', data['version']);
    await database.transaction((txn) async {
      await txn.insert('metadata', {
        'key': 'cookieGeneration',
        'value': data['version'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final host in data['cookieHosts'] as List? ?? []) {
        final captured = (data['cookies'] as List? ?? [])
            .map(downloadMap)
            .where((cookie) => host == cookie['domain'] || (host as String).endsWith('.${cookie['domain']}'))
            .toList();
        final seedKey = 'cookieSeed:$host';
        final fingerprint = downloadIdentity(captured);
        final previous = await txn.query('metadata', where: 'key = ?', whereArgs: [seedKey]);
        if (previous.firstOrNull?['value'] == fingerprint) continue;
        await txn.delete('download_cookies', where: "? = domain OR ? LIKE '%.' || domain", whereArgs: [host, host]);
        for (final cookie in captured) {
          await txn.insert('download_cookies', {
            'id': downloadIdentity([cookie['domain'], cookie['path'], cookie['name']]),
            'domain': cookie['domain'],
            'payload': jsonEncode(cookie),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.insert('metadata', {
          'key': seedKey,
          'value': fingerprint,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String> cookies(String url, {DatabaseExecutor? executor}) async {
    if (Platform.isAndroid || Platform.isIOS) return await downloadPlatform.invokeMethod<String>('cookies', url) ?? '';
    final uri = Uri.parse(url);
    final rows = cookieDatabase == null
        ? <Map<String, dynamic>>[]
        : await (executor ?? cookieDatabase!).query(
            'download_cookies',
            where: "? = domain OR ? LIKE '%.' || domain",
            whereArgs: [uri.host, uri.host],
          );
    final Iterable<dynamic> entries = cookieDatabase == null
        ? (data['cookies'] as List? ?? [])
        : rows.map((r) => downloadMap(r['payload']));
    final cookies = entries.map(downloadMap).where((cookie) {
      final domain = cookie['domain'] as String? ?? '';
      final path = cookie['path'] as String? ?? '/';
      final requestPath = uri.path.isEmpty ? '/' : uri.path;
      final expires = (cookie['expires'] as num?)?.toInt() ?? 0;
      return (uri.host == domain || cookie['hostOnly'] != true && uri.host.endsWith('.$domain')) &&
          (cookie['secure'] != true || uri.scheme == 'https') &&
          (expires == 0 || expires > DateTime.now().millisecondsSinceEpoch) &&
          (requestPath == path ||
              requestPath.startsWith(path) &&
                  (path.endsWith('/') || requestPath.substring(path.length).startsWith('/')));
    }).toList()..sort((a, b) => (b['path'] as String).length.compareTo((a['path'] as String).length));
    return cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
  }

  Future<bool> saveCookies(String url, List<String> values) async {
    if (values.isEmpty) return true;
    final database = cookieDatabase;
    if (database == null) return false;
    final uri = Uri.parse(url);
    await database.transaction((txn) async {
      final generation = await txn.query('metadata', where: 'key = ?', whereArgs: ['cookieGeneration']);
      if (generation.firstOrNull?['value'] != data['version']) return;
      if (Platform.isAndroid || Platform.isIOS) {
        await downloadPlatform.invokeMethod<bool>('setCookies', {
          'url': url,
          'cookies': values,
          'generation': data['version'],
        });
        return;
      }
      for (final value in values) {
        Cookie cookie;
        try {
          cookie = Cookie.fromSetCookieValue(value);
        } on FormatException {
          continue;
        }
        final domain = (cookie.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (domain != uri.host &&
            (!uri.host.endsWith('.$domain') ||
                !sources.any((source) => Uri.tryParse(source.baseURL ?? '')?.host == domain))) {
          continue;
        }
        final path = cookie.path?.startsWith('/') == true
            ? cookie.path!
            : uri.path.lastIndexOf('/') > 0
            ? uri.path.substring(0, uri.path.lastIndexOf('/'))
            : '/';
        final expires = cookie.maxAge != null
            ? DateTime.now().add(Duration(seconds: cookie.maxAge!)).millisecondsSinceEpoch
            : cookie.expires?.millisecondsSinceEpoch ?? 0;
        final id = downloadIdentity([domain, path, cookie.name]);
        if (expires > 0 && expires <= DateTime.now().millisecondsSinceEpoch) {
          await txn.delete('download_cookies', where: 'id = ?', whereArgs: [id]);
        } else {
          final entry = {
            'name': cookie.name,
            'value': cookie.value,
            'domain': domain,
            'path': path,
            'hostOnly': cookie.domain == null,
            'secure': cookie.secure,
            'expires': expires,
          };
          await txn.insert('download_cookies', {
            'id': id,
            'domain': domain,
            'payload': jsonEncode(entry),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    return true;
  }

  Future<SettingsHandler> backgroundSettings() async {
    final settings = SettingsHandler(background: true);
    return RequestScope(
      client: () => throw StateError('Network is unavailable during worker initialization'),
      cookies: cookies,
      saveCookies: saveCookies,
      settings: settings,
      headless: true,
    ).run(() async {
      initSettingsEnumRegistry();
      if (SettingsRegistry.instance.isEmpty) registerAllSettings();
      final registry = SettingsRegistry.instance;
      registry.loadFromJson(downloadMap(data['settings']), resetMissing: true);
      settings.booruList.value = sources;
      for (final source in sources) {
        registry.loadOverridesFromMap(source.name ?? '', source.settingOverrides, replace: true);
      }
      final dbPath = data['dbPath'] as String?;
      if (dbPath != null && await File(dbPath).exists()) {
        // Read tracked flags without startup migrations, pruning or backup hooks.
        final factory = Platform.isAndroid || Platform.isIOS ? sqflite.databaseFactorySqflitePlugin : databaseFactory;
        settings.dbHandler.db = await factory.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
      }
      return settings;
    });
  }
}
