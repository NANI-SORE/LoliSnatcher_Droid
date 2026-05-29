import 'package:clipboard/clipboard.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

class ClipboardUtils {
  static Future<void> copyTextToClipboard(
    String text, {
    bool notify = true,
    String? subtitle,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));

    final ctx = NavigationHandler.instance.navContext;

    FlashElements.showSnackbar(
      context: ctx,
      title: Text(
        ctx.loc.copiedToClipboard,
        style: const TextStyle(fontSize: 20),
      ),
      content: subtitle?.isEmpty == true
          ? const SizedBox.shrink()
          : Text(
              subtitle ?? text,
              style: const TextStyle(fontSize: 16),
            ),
      sideColor: Colors.green,
      leadingIcon: Icons.copy,
      leadingIconColor: Colors.green,
      duration: const Duration(seconds: 2),
    );
  }

  static Future<void> copyImageToClipboard(
    BooruItem item, {
    Booru? booru,
    bool notify = true,
    bool shouldCache = true,
    CancelToken? cancelToken,
    void Function(int, int?)? onReceiveProgress,
  }) async {
    if (item.mediaType.value.isVideo) return;

    final ctx = NavigationHandler.instance.navContext;

    try {
      final bytes = await NetworkImageLoader.downloadAndCache(
        url: item.fileURL,
        cacheFolder: 'media',
        fileNameExtras: item.fileNameExtras,
        withCache: shouldCache,
        headers: await Tools.getFileCustomHeaders(booru, item: item),
        cancelToken: cancelToken,
        withCaptchaCheck: true,
        sendTimeout: null,
        receiveTimeout: null,
        chunkEvents: null,
        onCacheDetected: null,
        onReceiveProgress: onReceiveProgress,
      );

      await FlutterClipboard.copyImage(bytes);

      if (notify) {
        FlashElements.showSnackbar(
          context: ctx,
          title: Text(
            ctx.loc.copiedToClipboard,
            style: const TextStyle(fontSize: 20),
          ),
          content: Row(
            children: [
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                height: 64,
                child: ThumbnailBuild(
                  item: item,
                  handler: null,
                  selectable: false,
                  simple: true,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          sideColor: Colors.green,
          leadingIcon: Icons.copy,
          leadingIconColor: Colors.green,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e, s) {
      Logger.Inst().log(
        e,
        'ClipboardUtils',
        'copyImageToClipboard',
        null,
        s: s,
      );

      if (notify) {
        FlashElements.showSnackbar(
          context: ctx,
          title: Text(ctx.loc.error),
          sideColor: Colors.red,
          leadingIcon: Icons.error,
          leadingIconColor: Colors.red,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }
}
