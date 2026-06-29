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

  Future<void> shareText(String text) async {
    if (PlatformExt.isDesktop) {
      await ClipboardUtils.copyTextToClipboard(text);
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

    if (PlatformExt.isDesktop && items.length == 1 && items.single.mediaType.value.isImageOrAnimation) {
      return _copySingleImageToClipboard(
        operationId: operationId,
        item: items.single,
        booru: booru,
        onProgress: onProgress,
      );
    }

    final paths = <String>[];
    try {
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final path = await _getOrDownloadCachePath(
          item: item,
          booru: booru,
          operationId: operationId,
          itemIndex: i,
          itemCount: items.length,
          onProgress: onProgress,
        );
        if (path == null) {
          return false;
        }
        paths.add(path);
      }
    } finally {
      snatchHandler.onShareDone(operationId);
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
  }

  Future<bool> _copySingleImageToClipboard({
    required int operationId,
    required BooruItem item,
    required Booru booru,
    GalleryShareProgressCallback? onProgress,
  }) async {
    final cancelToken = CancelToken();
    snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);

    try {
      await ClipboardUtils.copyImageToClipboard(
        item,
        booru: booru,
        cancelToken: cancelToken,
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
    } finally {
      snatchHandler.onShareDone(operationId);
    }
  }

  Future<String?> _getOrDownloadCachePath({
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
      return existingPath;
    }

    final cancelToken = CancelToken();
    snatchHandler.onShareCancelTokenCreate(cancelToken, operationId);

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
    if (path == null) return null;

    final cacheFile = File(path);
    if (!await cacheFile.exists()) return null;

    return cacheFile.path;
  }

  String _mimeType(BooruItem item) {
    final type = item.mediaType.value.isVideo ? 'video' : 'image';
    return '$type/${item.fileExt ?? '*'}';
  }
}
