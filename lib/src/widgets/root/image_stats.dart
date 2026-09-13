import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';

import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/services/image_memory_manager.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

class ImageStats extends StatefulWidget {
  const ImageStats({
    required this.child,
    this.width = 110,
    this.height = 160,
    this.isEnabled = true,
    this.align,
    super.key,
  });

  /// Toggle the stats on/off, there should be no performance cost when the widget is off.
  final bool isEnabled;

  /// Width of widget in px
  final double width;

  /// Height of widget in px
  final double height;

  /// A child to be displayed under the Stats
  final Widget child;

  /// Where to align the stats relative to the child
  final Alignment? align;

  @override
  State<ImageStats> createState() => _ImageStatsState();
}

class _ImageStatsState extends State<ImageStats> {
  int _lastCalcTime = 0;
  late Ticker _ticker;
  // double _ticks = 0;
  final ValueNotifier<int> _totalLive = ValueNotifier(0);
  final ValueNotifier<int> _totalPending = ValueNotifier(0);
  final ValueNotifier<int> _totalAll = ValueNotifier(0);
  final ValueNotifier<int> _cacheSize = ValueNotifier(0);
  final ValueNotifier<int> _cacheMax = ValueNotifier(0);
  final ValueNotifier<String> _admission = ValueNotifier('');
  final ValueNotifier<String> _downloads = ValueNotifier('');
  final ValueNotifier<int> _rejected = ValueNotifier(0);
  final ValueNotifier<int> _reserved = ValueNotifier(0);
  final ValueNotifier<int?> _rss = ValueNotifier(null);
  // final bool _shouldRepaint = false;
  int sampleTimeMs = 500;

  int get nowMs => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_handleTick);
    updateValues();
    if (widget.isEnabled) _ticker.start();
    _lastCalcTime = nowMs;
  }

  @override
  void didUpdateWidget(ImageStats oldWidget) {
    final isEnabled = widget.isEnabled;

    if (oldWidget.isEnabled != isEnabled) {
      isEnabled ? _ticker.start() : _ticker.stop();
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _totalLive.dispose();
    _totalPending.dispose();
    _totalAll.dispose();
    _cacheSize.dispose();
    _cacheMax.dispose();
    _admission.dispose();
    _downloads.dispose();
    _rejected.dispose();
    _reserved.dispose();
    _rss.dispose();
    super.dispose();
  }

  void updateValues() {
    _totalLive.value = PaintingBinding.instance.imageCache.liveImageCount;
    _totalPending.value = PaintingBinding.instance.imageCache.pendingImageCount;
    _totalAll.value = PaintingBinding.instance.imageCache.currentSize;
    _cacheSize.value = PaintingBinding.instance.imageCache.currentSizeBytes;
    _cacheMax.value = PaintingBinding.instance.imageCache.maximumSizeBytes;
    final memory = ImageMemoryManager.instance;
    _reserved.value = memory.retainedBytes;
    _admission.value = 'Decode: ${memory.activeDecodeCount} / ${memory.queuedDecodeCount}';
    _downloads.value = 'DLs: ${memory.activeDownloadCount} / ${memory.queuedDownloadCount}';
    _rejected.value = memory.rejectedCount;
    _rss.value = ProcessInfo.currentRss;
  }

  void _handleTick(Duration d) {
    if (!widget.isEnabled) {
      _lastCalcTime = nowMs;
      return;
    }
    // Tick
    // _ticks++;
    // Calculate
    if (nowMs - _lastCalcTime > sampleTimeMs) {
      final int remainder = nowMs - _lastCalcTime - sampleTimeMs;
      _lastCalcTime = nowMs - remainder;
      // _ticks = 0;
      updateValues();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = (context.theme.textTheme.bodySmall ?? DefaultTextStyle.of(context).style).copyWith(
      color: context.theme.colorScheme.onSurface,
    );

    return Material(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            widget.child,
            if (widget.isEnabled)
              IgnorePointer(
                child: Align(
                  alignment: widget.align ?? Alignment.topLeft,
                  child: Container(
                    width: widget.width,
                    height: widget.height,
                    color: Colors.white.withValues(alpha: 0.8),
                    child: RepaintBoundary(
                      child: ListenableBuilder(
                        listenable: Listenable.merge(
                          [
                            _totalLive,
                            _totalPending,
                            _totalAll,
                            _cacheSize,
                            _cacheMax,
                            _reserved,
                            _admission,
                            _downloads,
                            _rejected,
                            _rss,
                          ],
                        ),
                        builder: (context, child) => Column(
                          mainAxisSize: .min,
                          crossAxisAlignment: .start,
                          children: [
                            Text(
                              context.loc.imageStats.live(count: _totalLive.value),
                              style: style,
                            ),
                            Text(
                              context.loc.imageStats.pending(count: _totalPending.value),
                              style: style,
                            ),
                            Text(
                              context.loc.imageStats.total(count: _totalAll.value),
                              style: style,
                            ),
                            Text(
                              context.loc.imageStats.size(size: Tools.formatBytes(_cacheSize.value, 0)),
                              style: style,
                            ),
                            Text(
                              context.loc.imageStats.max(max: Tools.formatBytes(_cacheMax.value, 0)),
                              style: style,
                            ),
                            Text(
                              'Res: ${Tools.formatBytes(_reserved.value, 0)}',
                              style: style,
                            ),
                            Text(
                              _admission.value,
                              style: style,
                            ),
                            Text(
                              _downloads.value,
                              style: style,
                            ),
                            Text(
                              'Reject: ${_rejected.value}',
                              style: style,
                            ),
                            if (_rss.value != null)
                              Text(
                                'RSS: ${Tools.formatBytes(_rss.value!, 0)}',
                                style: style,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
