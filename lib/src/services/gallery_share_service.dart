import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

typedef GalleryShareProgressCallback = void Function({
  required BooruItem item,
  required int itemIndex,
  required int itemCount,
  required double progress,
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
        ShareParams(text: text, sharePositionOrigin: _sharePositionOrigin(context)),
      );
    }
  }

  Future<bool> shareFiles({
    required List<BooruItem> items,
    required Booru booru,
    Booru Function(BooruItem item)? sourceBooruFor,
    BuildContext? context,
    String? text,
    GalleryShareProgressCallback? onProgress,
    VoidCallback? onCancelled,
  }) async {
    if (items.isEmpty) return false;
    items = List.of(items);

    final operationId = snatchHandler.onShareStart(items, booru);
    if (operationId == null) return false;
    _operationId = operationId;
    bool dismissed = false;

    try {
      final sources = [for (final item in items) sourceBooruFor?.call(item) ?? booru];
      if (PlatformExt.isDesktop && (items.length != 1 || !items.single.mediaType.value.isImageOrAnimation)) {
        return false;
      }
      if (PlatformExt.isDesktop && !Platform.isWindows) {
        return await _copySingleImageToClipboard(
          operationId: operationId,
          item: items.single,
          booru: sources.single,
          onProgress: onProgress,
        );
      }
      final paths = <String>[];
      for (int i = 0; i < items.length; i++) {
        if (!snatchHandler.isShareActive(operationId)) return false;
        final item = items[i];
        final result = await _getOrDownloadCachePath(
          item: item,
          booru: sources[i],
          operationId: operationId,
          itemIndex: i,
          itemCount: items.length,
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
          return snatchHandler.isShareActive(operationId);
        } catch (_) {
          snatchHandler.onAddRetryableItems(booru: sources.single, failed: [items.single]);
          return false;
        }
      }

      if (context != null && !context.mounted) return false;
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
          sharePositionOrigin: _sharePositionOrigin(context),
        ),
      );
      dismissed = result.status == ShareResultStatus.dismissed;
      return !dismissed && snatchHandler.isShareActive(operationId);
    } catch (_) {
      return false;
    } finally {
      final cancelled = dismissed || !snatchHandler.isShareActive(operationId);
      snatchHandler.onShareDone(operationId);
      if (_operationId == operationId) _operationId = null;
      if (cancelled) onCancelled?.call();
    }
  }

  Future<bool> _copySingleImageToClipboard({
    required int operationId,
    required BooruItem item,
    required Booru booru,
    GalleryShareProgressCallback? onProgress,
  }) async {
    while (snatchHandler.isShareActive(operationId)) {
      final cancelToken = CancelToken();
      snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);
      try {
        await ClipboardUtils.copyImageToClipboard(
          item,
          booru: booru,
          cancelToken: cancelToken,
          rethrowErrors: true,
          onReceiveProgress: (received, total) {
            if (total != null && total > 0 && snatchHandler.isShareActive(operationId)) {
              snatchHandler.onShareProgress(
                operationId: operationId,
                item: item,
                itemIndex: 0,
                received: received,
                total: total,
              );
              onProgress?.call(item: item, itemIndex: 0, itemCount: 1, progress: received / total);
            }
          },
        );
        return snatchHandler.isShareActive(operationId);
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e) && snatchHandler.consumeShareRetryCurrent(operationId)) {
          continue;
        }
        snatchHandler.onAddRetryableItems(
          booru: booru,
          failed: e is DioException && CancelToken.isCancel(e) ? const [] : [item],
          cancelled: e is DioException && CancelToken.isCancel(e) ? [item] : const [],
        );
        return false;
      } finally {
        snatchHandler.onShareFileDone(operationId);
      }
    }
    return false;
  }

  Future<_ShareCachePathResult> _getOrDownloadCachePath({
    required BooruItem item,
    required Booru booru,
    required int operationId,
    required int itemIndex,
    required int itemCount,
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
    final existingPath = await imageWriter.getCachePath(
      item.fileURL,
      'media',
      fileNameExtras: item.fileNameExtras,
    );
    if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
    if (existingPath != null) {
      snatchHandler.onShareProgress(
        operationId: operationId,
        item: item,
        itemIndex: itemIndex,
        received: 1,
        total: 1,
      );
      onProgress?.call(
        item: item,
        itemIndex: itemIndex,
        itemCount: itemCount,
        progress: 1,
      );
      return _ShareCachePathResult(path: existingPath);
    }

    final cancelToken = CancelToken();
    snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);

    File? temporaryFile;
    try {
      final cacheFilePath = await imageWriter.getCachePathString(
        item.fileURL,
        'media',
        clearName: true,
        fileNameExtras: item.fileNameExtras,
      );
      temporaryFile = File('$cacheFilePath.temp_share_${operationId}_${DateTime.now().microsecondsSinceEpoch}');
      final response = await DioNetwork.download(
        item.fileURL,
        temporaryFile.path,
        cancelToken: cancelToken,
        headers: await Tools.getFileCustomHeaders(
          booru,
          item: item,
          checkForReferer: true,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0 && snatchHandler.isShareActive(operationId)) {
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
              progress: received / total,
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

      final existingCompletedPath = await imageWriter.getCachePath(
        item.fileURL,
        'media',
        fileNameExtras: item.fileNameExtras,
      );
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();
      if (existingCompletedPath == null) await temporaryFile.rename(cacheFilePath);
      if (!snatchHandler.isShareActive(operationId)) return const _ShareCachePathResult();

      return _ShareCachePathResult(path: existingCompletedPath ?? cacheFilePath);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e) && snatchHandler.consumeShareRetryCurrent(operationId)) {
        return const _ShareCachePathResult(retryCurrent: true);
      }

      snatchHandler.onAddRetryableItems(
        booru: booru,
        failed: e is DioException && CancelToken.isCancel(e) ? const [] : [item],
        cancelled: e is DioException && CancelToken.isCancel(e) ? [item] : const [],
      );
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

  Rect _sharePositionOrigin(BuildContext? context) {
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
    return '$type/${item.fileExt ?? '*'}';
  }
}
