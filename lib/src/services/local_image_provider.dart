import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_avif/flutter_avif.dart';

// Saved samples and legacy downloads can have the original's extension even
// when their bytes use another encoding. Read only the header, not the image.
Future<ImageProvider> localImageProvider(File file) async {
  final reader = await file.open();
  late final ImageProvider provider;
  try {
    final header = await reader.read(16);
    provider = isAvifFile(header) == AvifFileType.unknown ? FileImage(file) : FileAvifImage(file);
  } finally {
    await reader.close();
  }
  return provider;
}
