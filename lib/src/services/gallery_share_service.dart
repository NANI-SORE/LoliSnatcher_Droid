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

typedef GalleryShareProgressCallback =
    void Function({
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

  void cancel() {
    snatchHandler.onShareCancel();
  }

  Future<void> cancelAndDeleteCurrentCacheFile() async {
    cancel();
    final item = snatchHandler.shareActiveItem.value;
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
  }) async {
    if (PlatformExt.isDesktop) {
      await ClipboardUtils.copyTextToClipboard(
        text,
        subtitle: subtitle,
      );
    } else if (Platform.isAndroid) {
      await ServiceHandler.loadShareTextIntent(text);
    }
  }

  Future<bool> shareFiles({
    required List<BooruItem> items,
    required Booru booru,
    BuildContext? context,
    String? text,
    GalleryShareProgressCallback? onProgress,
  }) async {
    if (items.isEmpty) return false;

    final operationId = snatchHandler.onShareStart(items, booru);

    if (PlatformExt.isDesktop) {
      if (items.length != 1 || !items.single.mediaType.value.isImageOrAnimation) {
        snatchHandler.onShareDone(operationId);
        return false;
      }

      return _copySingleImageToClipboard(
        operationId: operationId,
        item: items.single,
        booru: booru,
        onProgress: onProgress,
      );
    }

    try {
      final paths = <String>[];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final result = await _getOrDownloadCachePath(
          item: item,
          booru: booru,
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

      if (paths.isEmpty) return false;

      final box = context?.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            for (int i = 0; i < paths.length; i++)
              XFile(
                paths[i],
                mimeType: _mimeType(items[i]),
              ),
          ],
          text: text,
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return true;
    } finally {
      snatchHandler.onShareDone(operationId);
    }
  }

  Future<bool> _copySingleImageToClipboard({
    required int operationId,
    required BooruItem item,
    required Booru booru,
    GalleryShareProgressCallback? onProgress,
  }) async {
    try {
      if (Platform.isWindows) {
        while (true) {
          final result = await _getOrDownloadCachePath(
            item: item,
            booru: booru,
            operationId: operationId,
            itemIndex: 0,
            itemCount: 1,
            onProgress: onProgress,
          );
          if (result.retryCurrent) {
            continue;
          }

          final path = result.path;
          if (path == null) {
            return false;
          }

          try {
            await ClipboardUtils.copyImageFileToClipboard(
              path,
              item,
              rethrowErrors: true,
            );
            return true;
          } catch (_) {
            snatchHandler.onAddRetryableItems(booru: booru, failed: [item]);
            return false;
          }
        }
      }

      while (true) {
        final cancelToken = CancelToken();
        snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);

        try {
          await ClipboardUtils.copyImageToClipboard(
            item,
            booru: booru,
            cancelToken: cancelToken,
            rethrowErrors: true,
            onReceiveProgress: (received, total) {
              if (total != null && total > 0) {
                snatchHandler.onShareProgress(
                  operationId: operationId,
                  item: item,
                  itemIndex: 0,
                  received: received,
                  total: total,
                );
                onProgress?.call(
                  item: item,
                  itemIndex: 0,
                  itemCount: 1,
                  progress: received / total,
                );
              }
            },
          );

          return true;
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e) && snatchHandler.consumeShareRetryCurrent()) {
            continue;
          }

          snatchHandler.onAddRetryableItems(
            booru: booru,
            failed: e is DioException && CancelToken.isCancel(e) ? const [] : [item],
            cancelled: e is DioException && CancelToken.isCancel(e) ? [item] : const [],
          );
          return false;
        }
      }
    } finally {
      snatchHandler.onShareDone(operationId);
    }
  }

  Future<_ShareCachePathResult> _getOrDownloadCachePath({
    required BooruItem item,
    required Booru booru,
    required int operationId,
    required int itemIndex,
    required int itemCount,
    GalleryShareProgressCallback? onProgress,
  }) async {
    final existingPath = await imageWriter.getCachePath(
      item.fileURL,
      'media',
      fileNameExtras: item.fileNameExtras,
    );
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

    try {
      final cacheFilePath = await imageWriter.getCachePathString(
        item.fileURL,
        'media',
        clearName: true,
        fileNameExtras: item.fileNameExtras,
      );
      await DioNetwork.download(
        item.fileURL,
        cacheFilePath,
        cancelToken: cancelToken,
        headers: await Tools.getFileCustomHeaders(
          booru,
          item: item,
          checkForReferer: true,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
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

      final path = await imageWriter.getCachePath(
        item.fileURL,
        'media',
        fileNameExtras: item.fileNameExtras,
      );
      if (path == null) {
        snatchHandler.onAddRetryableItems(booru: booru, failed: [item]);
        return const _ShareCachePathResult();
      }

      final cacheFile = File(path);
      if (!await cacheFile.exists()) {
        snatchHandler.onAddRetryableItems(booru: booru, failed: [item]);
        return const _ShareCachePathResult();
      }

      return _ShareCachePathResult(path: cacheFile.path);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e) && snatchHandler.consumeShareRetryCurrent()) {
        return const _ShareCachePathResult(retryCurrent: true);
      }

      snatchHandler.onAddRetryableItems(
        booru: booru,
        failed: e is DioException && CancelToken.isCancel(e) ? const [] : [item],
        cancelled: e is DioException && CancelToken.isCancel(e) ? [item] : const [],
      );
      return const _ShareCachePathResult();
    }
  }

  String _mimeType(BooruItem item) {
    final type = item.mediaType.value.isVideo ? 'video' : 'image';
    return '$type/${item.fileExt ?? '*'}';
  }
}
