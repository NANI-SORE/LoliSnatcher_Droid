import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/image_quality.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';

/// Source-specific preferences captured once when a download starts.
class DownloadPolicy {
  DownloadPolicy.forBooru(Booru booru)
    : quality = SX.snatchMode.valueForBooru(booru.name),
      writeJson = SX.jsonWrite.valueForBooru(booru.name);

  final ImageQuality quality;
  final bool writeJson;

  String urlFor(BooruItem item) => quality.isSample && item.sampleURL.isNotEmpty ? item.sampleURL : item.fileURL;
}
