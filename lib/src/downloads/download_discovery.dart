import 'package:lolisnatcher/src/utils/booru_source_resolver.dart';

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/boorus/mergebooru_handler.dart';
import 'package:lolisnatcher/src/boorus/worldxyz_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_network.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';
import 'package:lolisnatcher/src/downloads/transfer_preparation.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/request_scope.dart';

class DiscoveryPage {
  const DiscoveryPage(this.items, this.next, {required this.exhausted});
  final List<({Booru source, BooruItem item})> items;
  final DiscoveryCheckpoint next;
  final bool exhausted;
}

class DownloadDiscovery {
  DownloadDiscovery(this.store, this.configuration, this.settings, this.gate);
  final DownloadStore store;
  final DownloadConfiguration configuration;
  final SettingsHandler settings;
  final DownloadRateGate gate;

  Future<void> advance(Map<String, dynamic> row, CancelToken token) async {
    final spec = DownloadBatchSpec.fromJson(downloadMap(row['spec']));
    final checkpoint = DiscoveryCheckpoint.fromJson(downloadMap(row['checkpoint']));
    final children = downloadMap(checkpoint.extra['children']);
    final sources = spec.sourceNames.map((name) {
      final source = configuration.source(name);
      if (source == null) throw const DownloadBlocked('sourceMissing');
      return source;
    }).toList();
    if (sources.isEmpty) throw const DownloadBlocked('sourceMissing');
    var index = (checkpoint.extra['index'] as num?)?.toInt() ?? 0;
    for (var count = 0; count < sources.length; count++) {
      if (downloadMap(children['$index'])['done'] != true) break;
      index = (index + 1) % sources.length;
    }
    final source = sources[index];
    if (!ContentPolicy.isBooruAllowed(source)) throw const DownloadBlocked('sourceRestricted');
    final child = downloadMap(children['$index']);
    final before = child.isEmpty
        ? DiscoveryCheckpoint(page: spec.startPage)
        : DiscoveryCheckpoint.fromJson(downloadMap(child['checkpoint']));
    final network = DownloadNetwork(
      configuration: configuration,
      gate: gate,
      site: sourceIdentity(source),
      sourceName: source.name ?? '',
      cooldown: (configuration.policy(source.name ?? '')['cooldownMs'] as num?)?.toInt() ?? 1000,
    );
    final scope = RequestScope(
      client: network.client,
      cookies: configuration.cookies,
      saveCookies: configuration.saveCookies,
      settings: settings,
      filters: await configuration.filterEvaluator,
      headless: true,
    );
    await scope.run(
      () => DioNetwork.runWithCancellation(token, () async {
        final query = sources.length == 1
            ? spec.query ?? ''
            : MergebooruHandler(source, 100).cleanBooruIndexesFromTags(spec.query ?? '', index);
        final page = await fetchPage(spec.id, source, ContentPolicy.safeSearchTagsFor(source, query), before);
        final items = page.items.map((e) => e.item).toList();
        if (settings.dbHandler.db != null && items.isNotEmpty) {
          for (var offset = 0; offset < items.length; offset += 100) {
            final window = items.skip(offset).take(100).toList();
            final tracked = await settings.dbHandler.getMultipleTrackedValues(window);
            for (var i = 0; i < window.length; i++) {
              window[i].isSnatched.value = tracked[i][0];
              window[i].isFavourite.value = tracked[i][1];
            }
          }
        }
        final transfers = <PreparedTransfer>[];
        for (final entry in page.items) {
          final entryNetwork = DownloadNetwork(
            configuration: configuration,
            gate: gate,
            site: sourceIdentity(entry.source),
            sourceName: entry.source.name ?? '',
            cooldown: (configuration.policy(entry.source.name ?? '')['cooldownMs'] as num?)?.toInt() ?? 1000,
          );
          await RequestScope(
            client: entryNetwork.client,
            cookies: configuration.cookies,
            saveCookies: configuration.saveCookies,
            settings: settings,
            filters: scope.filters,
            headless: true,
          ).run(() async {
            var item = entry.item;
            final handler = BooruHandlerFactory().getBooruHandler([entry.source], 100).booruHandler;
            if (item.mediaType.value == MediaType.needToLoadItem) {
              if (!handler.hasLoadItemSupport) throw const DownloadBlocked('detailRequired');
              final loaded = await handler.loadItem(item: item, withCapcthaCheck: false);
              if (loaded.failed || loaded.item == null || loaded.item!.mediaType.value == MediaType.needToLoadItem) {
                throw const DownloadBlocked('detailRequired');
              }
              final original = item;
              item = loaded.item!;
              item.isFavourite.value = original.isFavourite.value;
              item.isSnatched.value = original.isSnatched.value;
              item.savedFileName ??= original.savedFileName;
            }
            if (!handler.eligibleForDownload(item, traversal: source)) return;
            final policies = downloadMap(spec.policy['sources']);
            final output = downloadMap(
              policies[source.type?.isFavouritesOrDownloads == true ? source.name : entry.source.name],
            );
            transfers.add(
              await prepareTransfer(
                source: entry.source,
                item: item,
                batchId: spec.id,
                configuration: configuration,
                policy: output.isEmpty ? configuration.policy(entry.source.name ?? '') : output,
                overwrite: spec.policy['overwrite'] == true,
                cooldownMs: (spec.policy['delayMs'] as num?)?.toInt(),
              ),
            );
          });
        }
        DioNetwork.throwIfCancelled();
        children['$index'] = {'checkpoint': page.next.toJson(), 'done': page.exhausted};
        final done = List.generate(sources.length, (i) => downloadMap(children['$i'])['done'] == true).every((e) => e);
        await store.commitPage(
          spec.id,
          transfers,
          DiscoveryCheckpoint(
            page: checkpoint.page + 1,
            extra: {'children': children, 'index': (index + 1) % sources.length},
          ),
          exhausted: done,
          generation: row['generation'] as int?,
        );
      }),
    );
  }

  Future<DiscoveryPage> fetchPage(String batchId, Booru source, String query, DiscoveryCheckpoint checkpoint) async {
    // Inkbunny expands each submission into multiple files. Bound its search
    // page to one submission so expansion cannot multiply a 100-post window.
    final result = BooruHandlerFactory().getBooruHandler([source], source.type?.isInkBunny == true ? 1 : 100);
    final handler = result.booruHandler;
    final page = result.startingPage + checkpoint.page;
    List<BooruItem> items;
    if (handler is HydrusHandler) {
      items = await _hydrus(batchId, handler, query, checkpoint.page - 1);
    } else if (source.type?.isFavouritesOrDownloads == true) {
      if (settings.dbHandler.db == null) throw const DownloadBlocked('databaseUnavailable');
      // Random ordering cannot form a recoverable offset-based traversal.
      if (query.contains('order:random')) throw const DownloadBlocked('randomDiscovery');
      items = await settings.dbHandler.searchDB(
        query,
        '${(checkpoint.page - 1) * 100}',
        '100',
        isDownloads: source.type?.isDownloads == true,
      );
    } else {
      if (handler is WorldXyzHandler) {
        handler.cursor = checkpoint.cursor;
        handler.isXyz = checkpoint.extra['isXyz'] != false;
      }
      items = await handler.fetchDownloadPage(query, page);
    }
    final fingerprint = downloadIdentity(items.map((e) => e.postURL).toList());
    if (items.isNotEmpty && checkpoint.extra['fingerprint'] == fingerprint) {
      throw const DownloadBlocked('paginationStalled');
    }
    final entries = <({Booru source, BooruItem item})>[];
    for (final item in items) {
      var origin = source;
      if (source.type?.isFavouritesOrDownloads == true) {
        final resolved = BooruSourceResolver.resolve(item, sources: configuration.sources);
        if (resolved == null) throw const DownloadBlocked('sourceAmbiguous');
        origin = resolved;
      }
      entries.add((source: origin, item: item));
    }
    return DiscoveryPage(
      entries,
      DiscoveryCheckpoint(
        page: checkpoint.page + 1,
        cursor: handler is WorldXyzHandler ? handler.cursor : '',
        extra: {'fingerprint': fingerprint, if (handler is WorldXyzHandler) 'isXyz': handler.isXyz},
      ),
      exhausted: items.isEmpty,
    );
  }

  Future<List<BooruItem>> _hydrus(String batchId, HydrusHandler handler, String query, int page) async {
    final source = handler.booru;
    final key = sourceIdentity(source);
    final marker = 'hydrus:$batchId:$key';
    final initialized = await store.db.query('metadata', where: 'key = ?', whereArgs: [marker]);
    if (initialized.isEmpty) {
      await store.db.delete('discovery_ids', where: 'batchId = ? AND sourceKey = ?', whereArgs: [batchId, key]);
      // Hydrus returns every matching ID in one response. Stream the numeric
      // array into SQLite instead of keeping the result set in the Dart heap.
      final response = await DioNetwork.get(
        handler.makeURL(query),
        headers: handler.getHeaders(),
        options: Options(responseType: ResponseType.stream),
      );
      var buffer = '';
      var started = false;
      var finished = false;
      var position = 0;
      try {
        await for (final part in (response.data as ResponseBody).stream.cast<List<int>>().transform(utf8.decoder)) {
          buffer += part;
          if (!started) {
            final match = RegExp(r'"file_ids"\s*:\s*\[').firstMatch(buffer);
            if (match == null) {
              if (buffer.length > 65536) throw const DownloadBlocked('invalidResponse');
              continue;
            }
            buffer = buffer.substring(match.end);
            started = true;
          }
          var batch = store.db.batch();
          var records = 0;
          while (buffer.isNotEmpty) {
            buffer = buffer.trimLeft();
            if (buffer.startsWith(']')) {
              finished = true;
              break;
            }
            final number = RegExp(r'^(\d+)\s*([,\]])').firstMatch(buffer);
            if (number == null) break;
            batch.insert('discovery_ids', {
              'batchId': batchId,
              'sourceKey': key,
              'position': position++,
              'value': number.group(1),
            });
            records++;
            if (records == 100) {
              await batch.commit(noResult: true);
              batch = store.db.batch();
              records = 0;
            }
            buffer = buffer.substring(number.end - (number.group(2) == ']' ? 1 : 0));
          }
          if (records > 0) await batch.commit(noResult: true);
          if (finished) break;
          if (buffer.length > 65536) throw const DownloadBlocked('invalidResponse');
        }
      } finally {
        DownloadNetwork.release(response.requestOptions);
      }
      if (!finished) throw const DownloadBlocked('invalidResponse');
      await store.db.insert('metadata', {
        'key': marker,
        'value': 'ready',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final ids = await store.db.query(
      'discovery_ids',
      columns: ['value'],
      where: 'batchId = ? AND sourceKey = ? AND position >= ?',
      whereArgs: [batchId, key, page * 100],
      orderBy: 'position',
      limit: 100,
    );
    if (ids.isEmpty) return [];
    final response = await DioNetwork.get(
      '${source.baseURL}/get_files/file_metadata',
      queryParameters: {'file_ids': '[${ids.map((e) => e['value']).join(',')}]'},
      headers: handler.getHeaders(),
    );
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! Map || data['metadata'] is! List) throw const DownloadBlocked('invalidResponse');
    return (data['metadata'] as List).map((value) {
      final row = downloadMap(value);
      final id = row['file_id'];
      if (id == null) throw const DownloadBlocked('invalidResponse');
      final tags = <Tag>[];
      for (final service in downloadMap(row['tags']).values) {
        final fields = downloadMap(service);
        if (fields['name'] == 'all known tags') {
          tags.addAll((downloadMap(fields['display_tags'])['0'] as List? ?? []).map((e) => Tag('$e')));
        }
      }
      return BooruItem(
        fileURL: '${source.baseURL}/get_files/file?file_id=$id',
        sampleURL: '${source.baseURL}/get_files/thumbnail?file_id=$id',
        thumbnailURL: '${source.baseURL}/get_files/thumbnail?file_id=$id',
        postURL: '${source.baseURL}/get_files/file_metadata?file_ids=[$id]',
        tagsList: tags,
        serverId: '$id',
        fileExt: (row['ext'] as String? ?? '').replaceFirst('.', ''),
        fileWidth: (row['width'] as num?)?.toDouble(),
        fileHeight: (row['height'] as num?)?.toDouble(),
        fileSize: (row['size'] as num?)?.toInt(),
        md5String: row['hash'] as String?,
        sources: (row['known_urls'] as List? ?? []).map((e) => '$e').toList(),
        fileNameExtras: 'Hydrus',
      );
    }).toList();
  }
}
