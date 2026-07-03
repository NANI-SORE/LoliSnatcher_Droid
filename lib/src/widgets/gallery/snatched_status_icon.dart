import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/services/offline_media_resolver.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/widgets/common/pulse_widget.dart';

class SnatchedStatusIcon extends StatefulWidget {
  const SnatchedStatusIcon({
    required this.item,
    required this.booru,
    super.key,
  });

  final BooruItem item;
  final Booru booru;

  @override
  State<SnatchedStatusIcon> createState() => _SnatchedStatusIconState();
}

class _SnatchedStatusIconState extends State<SnatchedStatusIcon> {
  @override
  Widget build(BuildContext context) {
    return SavedMediaStatusIcon(
      item: widget.item,
      booru: widget.booru,
      size: Theme.of(context).buttonTheme.height / 2.1,
    );
  }
}

class SavedMediaStatusIcon extends StatefulWidget {
  const SavedMediaStatusIcon({
    required this.item,
    required this.booru,
    this.size = 14,
    this.existsColor = Colors.green,
    this.missingColor = Colors.white,
    super.key,
  });

  final BooruItem item;
  final Booru booru;
  final double size;
  final Color existsColor;
  final Color missingColor;

  @override
  State<SavedMediaStatusIcon> createState() => _SavedMediaStatusIconState();
}

class _SavedMediaStatusIconState extends State<SavedMediaStatusIcon> {
  bool fileExists = false, running = false;

  @override
  void initState() {
    super.initState();
    fileExistsCheck();
  }

  Future<void> fileExistsCheck() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!running && mounted) {
        running = true;
        setState(() {});
      }
    });

    final sourceBooru = OfflineMediaResolver.instance.resolveSourceBooru(
      widget.item,
      fallback: widget.booru,
    );
    if (sourceBooru == null) {
      _finishCheck(false);
      return;
    }

    final imageWriter = ImageWriter();
    final fileNames = OfflineMediaResolver.instance.filenameCandidates(widget.item, sourceBooru);
    if (fileNames.isEmpty) {
      _finishCheck(false);
      return;
    }

    final String extPath = SX.extPathOverride.value;
    if (extPath.isNotEmpty) {
      fileExists = false;
      for (final fileName in fileNames) {
        if (await SAFFileCache.instance.existsFile(extPath, fileName)) {
          fileExists = true;
          break;
        }
      }
    } else {
      await imageWriter.setPaths();
      fileExists = false;
      for (final fileName in fileNames) {
        if (await File('${imageWriter.path}$fileName').exists()) {
          fileExists = true;
          break;
        }
      }
    }

    _finishCheck(fileExists);
  }

  void _finishCheck(bool exists) {
    fileExists = exists;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        running = false;
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant SavedMediaStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item != widget.item || oldWidget.booru != widget.booru) {
      fileExists = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
      fileExistsCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PulseWidget(
      enabled: running,
      child: Icon(
        Icons.save_alt,
        size: widget.size,
        color: fileExists ? widget.existsColor : widget.missingColor,
      ),
    );
  }
}
