import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/share_staging.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

typedef GalleryShareProgressCallback = void Function({
  required BooruItem item,
  required int itemIndex,
  required int itemCount,
  required double? progress,
});

class _ShareCachePathResult {
  const _ShareCachePathResult({
    this.path,
    this.retryCurrent = false,
  });

  final String? path;
  final bool retryCurrent;
}

class GalleryShareService {
  GalleryShareService({
    ImageWriter? imageWriter,
  }) : imageWriter = imageWriter ?? ImageWriter();

  final ImageWriter imageWriter;
  final SnatchHandler snatchHandler = SnatchHandler.instance;
  int? _operationId;

  void cancel({int? operationId}) {
    final id = operationId ?? _operationId;
    if (id != null) snatchHandler.onShareCancel(id);
  }

  Future<void> cancelAndDeleteCurrentCacheFile() async {
    final id = _operationId;
    if (id == null || !snatchHandler.isShareActive(id)) return;
    final item = snatchHandler.shareActiveItem.value;
    cancel(operationId: id);
    if (item == null) return;

    await imageWriter.deleteFileFromCache(
      item.fileURL,
      'media',
      fileNameExtras: item.fileNameExtras,
    );
  }

  Future<void> shareText(
    String text, {
    String? subtitle,
    BuildContext? context,
  }) async {
    if (context != null && !context.mounted) return;
    if (PlatformExt.isDesktop) {
      await ClipboardUtils.copyTextToClipboard(
        text,
        subtitle: subtitle,
      );
    } else if (Platform.isAndroid) {
      await ServiceHandler.loadShareTextIntent(text);
    } else if (Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(text: text, sharePositionOrigin: _sharePositionOrigin()),
      );
    }
  }

  Future<bool> shareFiles({
    required List<BooruItem> items,
    required Booru booru,
    Booru Function(BooruItem item)? sourceBooruFor,
    String? text,
    GalleryShareProgressCallback? onProgress,
    VoidCallback? onCancelled,
    VoidCallback? onCompleted,
  }) async {
    if (items.isEmpty) return false;
    items = List.of(items);

    final operationId = snatchHandler.onShareStart(items, booru);
    if (operationId == null) return false;
    _operationId = operationId;
    bool dismissed = false;
    ShareStaging? staging;
    bool handedOff = false;
    bool completed = false;
    bool canRetry = false;
    final sources = Map<BooruItem, Booru>.identity();

    try {
      for (final item in items) {
        sources[item] = sourceBooruFor?.call(item) ?? booru;
      }
      if (PlatformExt.isDesktop && (items.length != 1 || !items.single.mediaType.value.isImageOrAnimation)) {
        return false;
      }
      canRetry = true;
      staging = await ShareStaging.create();
      final paths = <String>[];
      for (int i = 0; i < items.length; i++) {
        if (!snatchHandler.isShareActive(operationId)) return false;
        final item = items[i];
        final result = await _getOrDownloadCachePath(
          item: item,
          booru: sources[item]!,
          operationId: operationId,
          itemIndex: i,
          itemCount: items.length,
          staging: staging,
          onProgress: onProgress,
        );
        if (result.retryCurrent) {
          i--;
          continue;
        }

        final path = result.path;
        if (path == null) {
          return false;
        }
        paths.add(path);
      }

      if (paths.isEmpty || !snatchHandler.isShareActive(operationId)) return false;

      if (PlatformExt.isDesktop) {
        try {
          await ClipboardUtils.copyImageFileToClipboard(paths.single, items.single, rethrowErrors: true);
          return completed = snatchHandler.isShareActive(operationId);
        } catch (_) {
          return false;
        }
      }

      // Native consumers may continue reading after the share result arrives.
      handedOff = true;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            for (int i = 0; i < paths.length; i++)
              XFile(
                paths[i],
                mimeType: _mimeType(items[i]),
              ),
          ],
          text: text,
          sharePositionOrigin: _sharePositionOrigin(),
        ),
      );
      dismissed = result.status == ShareResultStatus.dismissed;
      return completed = !dismissed && snatchHandler.isShareActive(operationId);
    } catch (_) {
      return false;
    } finally {
      await staging?.release(handedOff: handedOff);
      final cancelled = dismissed || !snatchHandler.isShareActive(operationId);
      if (canRetry && !completed && !handedOff) {
        final item = snatchHandler.shareActiveItem.value ?? items.first;
        snatchHandler.onAddRetryableItems(
          booru: sources[item] ?? booru,
          failed: cancelled ? const [] : [item],
          cancelled: cancelled ? [item] : const [],
          shareItemCount: items.length,
          retryShare: () => shareFiles(
            items: items,
            booru: booru,
            sourceBooruFor: (item) => sources[item]!,
            text: text,
            onCompleted: onCompleted,
          ),
        );
      }
      snatchHandler.onShareDone(operationId);
      if (_operationId == operationId) _operationId = null;
      if (completed) onCompleted?.call();
      if (cancelled) onCancelled?.call();
    }
  }

  Future<_ShareCachePathResult> _getOrDownloadCachePath({
    required BooruItem item,
    required Booru booru,
    required int operationId,
    required int itemIndex,
    required int itemCount,
    required ShareStaging staging,
    GalleryShareProgressCallback? onProgress,
  }) async {
    if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
    snatchHandler.onShareProgress(
      operationId: operationId,
      item: item,
      itemIndex: itemIndex,
      received: 0,
      total: 0,
    );
    final cancelToken = CancelToken();

    File? temporaryFile;
    try {
      final cacheFilePath = await imageWriter.getCachePathString(
        item.fileURL,
        'media',
        clearName: true,
        fileNameExtras: item.fileNameExtras,
      );
      final sharePath = staging.pathFor(itemIndex, cacheFilePath);
      final existingPath = await imageWriter.getCachePath(
        item.fileURL,
        'media',
        fileNameExtras: item.fileNameExtras,
      );
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
      if (existingPath != null) {
        try {
          // Copy before collecting another item: the media cache has no lease.
          final copy = await File(existingPath).copy(sharePath);
          final length = await copy.length();
          if (length > 0 && snatchHandler.isShareActive(operationId)) {
            snatchHandler.onShareProgress(
              operationId: operationId,
              item: item,
              itemIndex: itemIndex,
              received: length,
              total: length,
            );
            onProgress?.call(item: item, itemIndex: itemIndex, itemCount: itemCount, progress: 1);
            return _ShareCachePathResult(path: sharePath);
          }
        } on FileSystemException {
          // Cache eviction raced the copy; download directly into staging.
        }
      }
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
      temporaryFile = File('$sharePath.temp_share');
      snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);
      final response = await DioNetwork.download(
        item.fileURL,
        temporaryFile.path,
        cancelToken: cancelToken,
        customInterceptor: PlatformExt.isDesktop && !Platform.isWindows
            ? (client) => DioNetwork.captchaInterceptor(client, customUserAgent: Tools.appUserAgent)
            : null,
        headers: await Tools.getFileCustomHeaders(
          booru,
          item: item,
          checkForReferer: true,
        ),
        onReceiveProgress: (received, total) {
          if (snatchHandler.isShareActive(operationId) && !cancelToken.isCancelled) {
            snatchHandler.onShareProgress(
              operationId: operationId,
              item: item,
              itemIndex: itemIndex,
              received: received,
              total: total,
            );
            onProgress?.call(
              item: item,
              itemIndex: itemIndex,
              itemCount: itemCount,
              progress: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
            );
          }
        },
      );
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      snatchHandler.onShareFileDone(operationId);
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();

      final length = await temporaryFile.length();
      final expectedLength = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
      final contentEncoding = response.headers.value(HttpHeaders.contentEncodingHeader)?.trim().toLowerCase();
      final unencoded = contentEncoding == null || contentEncoding.isEmpty || contentEncoding == 'identity';
      if (!Tools.isGoodResponse(response) ||
          length == 0 ||
          (unencoded && expectedLength != null && expectedLength != length)) {
        throw const FileSystemException('Share download is incomplete');
      }

      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
      await temporaryFile.rename(sharePath);
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
      snatchHandler.onShareProgress(
        operationId: operationId,
        item: item,
        itemIndex: itemIndex,
        received: length,
        total: length,
      );
      onProgress?.call(item: item, itemIndex: itemIndex, itemCount: itemCount, progress: 1);
      return _ShareCachePathResult(path: sharePath);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e) && snatchHandler.consumeShareRetryCurrent(operationId)) {
        return const _ShareCachePathResult(retryCurrent: true);
      }

      return const _ShareCachePathResult();
    } finally {
      snatchHandler.onShareFileDone(operationId);
      if (temporaryFile != null) {
        try {
          if (await temporaryFile.exists()) await temporaryFile.delete();
        } catch (_) {}
      }
    }
  }

  Rect _sharePositionOrigin() {
    final context = NavigationHandler.instance.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      final renderObject = context.findRenderObject();
      if (renderObject is RenderBox && renderObject.attached && renderObject.hasSize) {
        final bounds = renderObject.localToGlobal(Offset.zero) & renderObject.size;
        final screenSize = MediaQuery.maybeSizeOf(context);
        final visibleBounds = screenSize == null ? bounds : bounds.intersect(Offset.zero & screenSize);
        if (visibleBounds.isFinite && !visibleBounds.isEmpty) return visibleBounds;
      }
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  String _mimeType(BooruItem item) {
    final type = item.mediaType.value.isVideo ? 'video' : 'image';
    final subtype = switch (item.fileExt?.toLowerCase()) {
      'jpg' || 'jpeg' => 'jpeg',
      'svg' => 'svg+xml',
      'tif' || 'tiff' => 'tiff',
      'mov' => 'quicktime',
      'mkv' => 'x-matroska',
      null || '' => '*',
      final extension => extension,
    };
    return '$type/$subtype';
  }
}
