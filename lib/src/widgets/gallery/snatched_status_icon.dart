import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
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
  int _checkGeneration = 0;
  int? _lookupKey;

  int get _currentLookupKey => Object.hash(
    widget.item,
    widget.item.fileURL,
    widget.item.postURL,
    widget.item.savedFileName,
    widget.booru,
    widget.booru.baseURL,
    SX.extPathOverride.value,
  );

  @override
  void initState() {
    super.initState();
    fileExistsCheck();
  }

  Future<void> fileExistsCheck() async {
    final generation = ++_checkGeneration;
    _lookupKey = _currentLookupKey;
    final item = widget.item;
    final booru = widget.booru;
    final storagePath = SX.extPathOverride.value;
    running = true;
    fileExists = false;
    bool exists = false;
    try {
      final resolver = OfflineMediaResolver.instance;
      final sourceBooru = resolver.resolveSourceBooru(item, fallback: booru);
      if (sourceBooru == null) return;
      final fileNames = resolver.filenameCandidates(item, sourceBooru);
      if (fileNames.isEmpty) return;

      if (Platform.isAndroid && storagePath.isNotEmpty) {
        for (final fileName in fileNames) {
          final found = await SAFFileCache.instance.existsFile(storagePath, fileName);
          if (!_isCurrentCheck(generation)) return;
          if (found) {
            exists = true;
            break;
          }
        }
      } else {
        final directory = storagePath.isNotEmpty ? storagePath : await ServiceHandler.getPicturesDir();
        if (!_isCurrentCheck(generation)) return;
        for (final fileName in fileNames) {
          try {
            final file = File.fromUri(Directory(directory).uri.resolveUri(Uri(path: fileName)));
            final found = await file.exists() && await file.length() > 0;
            if (!_isCurrentCheck(generation)) return;
            if (found) {
              exists = true;
              break;
            }
          } catch (_) {
            if (!_isCurrentCheck(generation)) return;
          }
        }
      }
    } catch (_) {
      // A revoked permission or inaccessible directory means the saved file is unavailable.
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrentCheck(generation)) return;
        setState(() {
          fileExists = exists;
          running = false;
        });
      });
    }
  }

  bool _isCurrentCheck(int generation) => mounted && generation == _checkGeneration && _lookupKey == _currentLookupKey;

  @override
  void didUpdateWidget(covariant SavedMediaStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lookupKey != _currentLookupKey) fileExistsCheck();
  }

  @override
  void dispose() {
    _checkGeneration++;
    super.dispose();
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
