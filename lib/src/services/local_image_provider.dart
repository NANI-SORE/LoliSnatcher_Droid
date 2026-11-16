import 'dart:io';

import 'package:dio/dio.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

import 'package:flutter/painting.dart';
import 'package:flutter_avif/flutter_avif.dart';

// Saved samples and legacy downloads can have the original's extension even
// when their bytes use another encoding. Read only the header, not the image.
Future<ImageProvider> localImageProvider(File file, {bool firstFrameOnly = false, CancelToken? cancelToken}) async {
  final reader = await file.open();
  late final ImageProvider provider;
  try {
    final header = await reader.read(16);
    provider = isAvifFile(header) == AvifFileType.unknown
        ? CustomNetworkImage(
            file.uri.toString(),
            localFilePath: file.path,
            firstFrameOnly: firstFrameOnly,
            cancelToken: cancelToken,
          )
        : CustomNetworkAvifImage(
            file.uri.toString(),
            localFilePath: file.path,
            firstFrameOnly: firstFrameOnly,
            cancelToken: cancelToken,
          );
  } finally {
    await reader.close();
  }
  return provider;
}
