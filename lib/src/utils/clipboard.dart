import 'dart:convert';
import 'dart:io';

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
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20),
      ),
      content: subtitle?.isEmpty == true
          ? const SizedBox.shrink()
          : Text(
              subtitle ?? text,
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
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
    bool rethrowErrors = false,
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

      if (notify && !(e is DioException && CancelToken.isCancel(e))) {
        FlashElements.showSnackbar(
          context: ctx,
          title: Text(ctx.loc.error),
          sideColor: Colors.red,
          leadingIcon: Icons.error,
          leadingIconColor: Colors.red,
          duration: const Duration(seconds: 2),
        );
      }

      if (rethrowErrors) {
        rethrow;
      }
    }
  }

  static Future<void> copyImageFileToClipboard(
    String path,
    BooruItem item, {
    bool notify = true,
    bool rethrowErrors = false,
  }) async {
    final ctx = NavigationHandler.instance.navContext;

    try {
      if (Platform.isWindows) {
        final encodedPath = base64Encode(utf8.encode(path));
        final script =
            '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$path = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$encodedPath'))
\$image = [System.Drawing.Image]::FromFile(\$path)
try {
  [System.Windows.Forms.Clipboard]::SetImage(\$image)
} finally {
  \$image.Dispose()
}
''';

        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-STA',
            '-Command',
            script,
          ],
        );

        if (result.exitCode != 0) {
          throw ProcessException(
            'powershell.exe',
            ['-NoProfile', '-STA', '-Command', script],
            '${result.stderr}'.trim(),
            result.exitCode,
          );
        }
      } else {
        await FlutterClipboard.copyImage(await File(path).readAsBytes());
      }

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
        'copyImageFileToClipboard',
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

      if (rethrowErrors) {
        rethrow;
      }
    }
  }
}
