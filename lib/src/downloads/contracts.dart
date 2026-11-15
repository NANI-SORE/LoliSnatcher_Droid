import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

enum DownloadState {
  queued,
  prepared,
  discovering,
  transferring,
  finalizing,
  completed,
  skipped,
  paused,
  cancelled,
  failed,
  waitingNetwork,
  waitingRate,
  needsAction,
}

extension DownloadStateStatus on DownloadState {
  bool get terminal => const {DownloadState.completed, DownloadState.skipped, DownloadState.cancelled}.contains(this);
  bool get runnable =>
      const {DownloadState.queued, DownloadState.waitingNetwork, DownloadState.waitingRate}.contains(this);
}

Map<String, dynamic> downloadMap(Object? value) => value is String
    ? Map<String, dynamic>.from(jsonDecode(value) as Map)
    : Map<String, dynamic>.from(value as Map? ?? const {});

String downloadIdentity(Iterable<Object?> parts) => sha256.convert(utf8.encode(jsonEncode(parts.toList()))).toString();

class DestinationRef {
  const DestinationRef({required this.path, this.photos = false, this.photosReceipts});
  factory DestinationRef.fromJson(Map<String, dynamic> json) => DestinationRef(
    path: json['path'] as String,
    photos: json['photos'] == true,
    photosReceipts: json['photosReceipts'] as String?,
  );
  final String path;
  final bool photos;
  final String? photosReceipts;
  bool get isSaf => path.startsWith('content://');
  Map<String, dynamic> toJson() => {'path': path, 'photos': photos, 'photosReceipts': photosReceipts};
}

class DiscoveryCheckpoint {
  const DiscoveryCheckpoint({this.page = 1, this.cursor = '', this.extra = const {}});
  factory DiscoveryCheckpoint.fromJson(Map<String, dynamic> json) => DiscoveryCheckpoint(
    page: (json['page'] as num?)?.toInt() ?? 1,
    cursor: json['cursor'] as String? ?? '',
    extra: downloadMap(json['extra']),
  );
  final int page;
  final String cursor;
  final Map<String, dynamic> extra;
  Map<String, dynamic> toJson() => {'page': page, 'cursor': cursor, 'extra': extra};
}

class DownloadBatchSpec {
  const DownloadBatchSpec({
    required this.id,
    required this.title,
    required this.requestedCount,
    this.query,
    this.sourceNames = const [],
    this.startPage = 1,
    this.policy = const {},
    this.contextId = 'current',
  });
  factory DownloadBatchSpec.fromJson(Map<String, dynamic> json) => DownloadBatchSpec(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    requestedCount: (json['requestedCount'] as num).toInt(),
    query: json['query'] as String?,
    sourceNames: List<String>.from(json['sourceNames'] as List? ?? const []),
    startPage: (json['startPage'] as num?)?.toInt() ?? 1,
    policy: downloadMap(json['policy']),
    contextId: json['contextId'] as String? ?? 'current',
  );
  final String id;
  final String title;
  final int requestedCount;
  final String? query;
  final List<String> sourceNames;
  final int startPage;
  final Map<String, dynamic> policy;
  final String contextId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'requestedCount': requestedCount,
    'query': query,
    'sourceNames': sourceNames,
    'startPage': startPage,
    'policy': policy,
    'contextId': contextId,
  };
}

class PreparedTransfer {
  const PreparedTransfer({
    required this.id,
    required this.batchId,
    required this.sourceKey,
    required this.sourceName,
    required this.url,
    required this.filename,
    required this.destination,
    required this.item,
    this.headers = const {},
    this.cooldownMs = 1000,
    this.overwrite = false,
    this.writeJson = false,
    this.quality = 'original',
    this.mediaType = 'image',
    this.checksum,
    this.expectedSize,
    this.foregroundOnly = false,
    this.transport = const {},
  });
  factory PreparedTransfer.fromJson(Map<String, dynamic> json) => PreparedTransfer(
    id: json['id'] as String,
    batchId: json['batchId'] as String,
    sourceKey: json['sourceKey'] as String,
    sourceName: json['sourceName'] as String,
    url: json['url'] as String,
    filename: json['filename'] as String,
    destination: DestinationRef.fromJson(downloadMap(json['destination'])),
    item: downloadMap(json['item']),
    headers: Map<String, String>.from(json['headers'] as Map? ?? const {}),
    cooldownMs: (json['cooldownMs'] as num?)?.toInt() ?? 1000,
    overwrite: json['overwrite'] == true,
    writeJson: json['writeJson'] == true,
    quality: json['quality'] as String? ?? 'original',
    mediaType: json['mediaType'] as String? ?? 'image',
    checksum: json['checksum'] as String?,
    expectedSize: (json['expectedSize'] as num?)?.toInt(),
    foregroundOnly: json['foregroundOnly'] == true,
    transport: downloadMap(json['transport']),
  );
  final String id, batchId, sourceKey, sourceName, url, filename, quality, mediaType;
  final DestinationRef destination;
  final Map<String, dynamic> item, transport;
  final Map<String, String> headers;
  final int cooldownMs;
  final bool overwrite, writeJson, foregroundOnly;
  final String? checksum;
  final int? expectedSize;
  String get host => Uri.parse(url).host.toLowerCase();
  String get identity => downloadIdentity([
    sourceKey,
    item['serverId'] ?? item['postURL'] ?? Uri.parse(url).replace(query: '').toString(),
    quality,
    destination.path,
    destination.photos,
  ]);
  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'sourceKey': sourceKey,
    'sourceName': sourceName,
    'url': url,
    'filename': filename,
    'destination': destination.toJson(),
    'item': item,
    'headers': headers,
    'cooldownMs': cooldownMs,
    'overwrite': overwrite,
    'writeJson': writeJson,
    'quality': quality,
    'mediaType': mediaType,
    'checksum': checksum,
    'expectedSize': expectedSize,
    'foregroundOnly': foregroundOnly,
    'transport': transport,
  };
  PreparedTransfer withValues(Map<String, dynamic> changes) => PreparedTransfer.fromJson({...toJson(), ...changes});
}

class DownloadTask {
  DownloadTask.fromRow(Map<String, dynamic> row)
    : transfer = PreparedTransfer.fromJson(downloadMap(row['payload'])),
      state = DownloadState.values.byName(row['state'] as String),
      generation = (row['generation'] as num?)?.toInt() ?? 0,
      batchGeneration = (row['batchGeneration'] as num?)?.toInt() ?? 0,
      attempts = (row['attempts'] as num?)?.toInt() ?? 0,
      received = (row['received'] as num?)?.toInt() ?? 0,
      total = (row['total'] as num?)?.toInt() ?? 0,
      nextEligible = (row['nextEligible'] as num?)?.toInt() ?? 0,
      attemptId = row['attemptId'] as String?,
      error = row['error'] as String?,
      stage = row['stage'] as String? ?? '',
      validator = row['validator'] as String?,
      result = row['result'] as String?,
      warning = row['warning'] as String?;
  final PreparedTransfer transfer;
  final DownloadState state;
  final int generation, batchGeneration, attempts, received, total, nextEligible;
  final String? attemptId, error, validator, result, warning;
  final String stage;
  String get id => transfer.id;
  Map<String, dynamic> toJson() => {
    'payload': transfer.toJson(),
    'state': state.name,
    'generation': generation,
    'batchGeneration': batchGeneration,
    'attempts': attempts,
    'received': received,
    'total': total,
    'nextEligible': nextEligible,
    'attemptId': attemptId,
    'error': error,
    'stage': stage,
    'validator': validator,
    'result': result,
    'warning': warning,
  };
}

class TransferReceipt {
  const TransferReceipt({
    required this.id,
    required this.taskId,
    required this.attemptId,
    required this.state,
    this.destination,
    this.error,
    this.warning,
    this.filename,
    this.stage,
    this.attempts,
    this.retryAt = 0,
  });
  factory TransferReceipt.fromJson(Map<String, dynamic> json) => TransferReceipt(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    attemptId: json['attemptId'] as String,
    state: DownloadState.values.byName(json['state'] as String),
    destination: json['destination'] as String?,
    error: json['error'] as String?,
    warning: json['warning'] as String?,
    filename: json['filename'] as String?,
    stage: json['stage'] as String?,
    attempts: (json['attempts'] as num?)?.toInt(),
    retryAt: (json['retryAt'] as num?)?.toInt() ?? 0,
  );
  final String id, taskId, attemptId;
  final DownloadState state;
  final String? destination, error, warning, filename, stage;
  final int? attempts;
  final int retryAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'attemptId': attemptId,
    'state': state.name,
    'destination': destination,
    'error': error,
    'warning': warning,
    'retryAt': retryAt,
    'filename': filename,
    'stage': stage,
    'attempts': attempts,
  };
}

class RateLimitPolicy {
  const RateLimitPolicy({this.cooldownMs = 1000, this.floorMs = 1000});
  final int cooldownMs, floorMs;
  int get delayMs => math.max(1000, math.max(cooldownMs, floorMs));
  static DateTime? retryAfter(String? value, DateTime now) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return now.add(Duration(seconds: math.max(0, seconds)));
    try {
      final date = HttpDate.parse(value);
      return date.isAfter(now) ? date : now;
    } on HttpException {
      return null;
    }
  }

  static Duration backoff(int attempt, {double jitter = 0}) => Duration(
    milliseconds: math.min(300000, 5000 * math.pow(2, math.max(0, attempt - 1)) * (1 + jitter.clamp(0, .2))).round(),
  );
}
