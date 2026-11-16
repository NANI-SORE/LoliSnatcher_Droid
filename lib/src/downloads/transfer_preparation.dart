import 'dart:math';

import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

String sourceIdentity(Booru source) => downloadIdentity([
  Uri.parse(source.baseURL ?? '').replace(query: '', fragment: '').toString(), source.type?.name,
  source.userID, // Account partitions remain below the shared host budget.
]);

String downloadFilename(BooruItem item, Booru booru, {String? url}) => ImageWriter.filenameFor(item, booru, url: url);

Future<PreparedTransfer> prepareTransfer({
  required Booru source,
  required BooruItem item,
  required String batchId,
  required DownloadConfiguration configuration,
  Map<String, dynamic>? policy,
  bool overwrite = false,
  int? cooldownMs,
  Future<String> Function(String)? cookiesOverride,
}) async {
  final output = policy ?? configuration.policy(source.name ?? '');
  final sample = output['quality'] == 'Sample' || output['quality'] == 'sample';
  final url = sample && item.sampleURL.isNotEmpty ? item.sampleURL : item.fileURL;
  final headers = await Tools.getFileCustomHeaders(source, item: item, checkForReferer: true);
  final cookies = await (cookiesOverride ?? configuration.cookies)(url);
  headers.remove('Cookie');
  if (cookies.isNotEmpty) headers['Cookie'] = cookies;
  if (source.type?.isHydrus == true && source.apiKey?.isNotEmpty == true) {
    headers['Hydrus-Client-API-Access-Key'] = source.apiKey!;
  }
  final itemJson = Map<String, dynamic>.from(item.toJson())
    ..['fileNameExtras'] = item.fileNameExtras
    ..['serverId'] = item.serverId
    ..['md5String'] = item.md5String
    ..['fileExt'] = item.fileExt
    ..['rating'] = item.rating
    ..['needsDetail'] = item.mediaType.value == MediaType.needToLoadItem
    ..['fileSize'] = item.fileSize;
  itemJson['downloadPostId'] = source.type?.isInkBunny == true ? item.serverId?.split('_').first : item.postURL;
  final transport = configuration.transportFor(source.name ?? '');
  final proxyType = transport['proxyType'] as String? ?? 'direct';
  return PreparedTransfer(
    id: const Uuid().v4(),
    batchId: batchId,
    sourceKey: sourceIdentity(source),
    sourceName: source.name ?? '',
    url: url,
    filename: downloadFilename(item, source, url: url),
    destination: DestinationRef.fromJson(downloadMap(output['destination'])),
    item: itemJson,
    headers: headers,
    cooldownMs: max(
      1000,
      max(
        cooldownMs ?? 0,
        max(
          (output['cooldownMs'] as num?)?.toInt() ?? 0,
          (configuration.policy(source.name ?? '')['cooldownMs'] as num?)?.toInt() ?? 0,
        ),
      ),
    ),
    overwrite: overwrite,
    writeJson: output['writeJson'] == true,
    quality: sample ? 'sample' : 'original',
    mediaType: item.mediaType.value.toJson(),
    expectedSize: sample ? null : item.fileSize,
    checksum: !sample && RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(item.md5String ?? '') ? item.md5String : null,
    foregroundOnly:
        !{'direct', 'system'}.contains(proxyType.toLowerCase()) ||
        transport['allowSelfSigned'] == true ||
        headers.keys.any((key) => key.toLowerCase() == 'hydrus-client-api-access-key') ||
        headers.containsKey('LS-IGNORE-REDIRECT'),
    transport: {...transport, 'profile': configuration.profile(source.name ?? '')},
  );
}
