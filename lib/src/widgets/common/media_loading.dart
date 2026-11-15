import 'package:flutter/material.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/tag_filter_evaluation.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/animated_progress_indicator.dart';
import 'package:lolisnatcher/src/widgets/common/bordered_text.dart';
import 'package:lolisnatcher/src/widgets/common/loading_progress.dart';
import 'package:lolisnatcher/src/widgets/image/image_viewer.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tag_filter_query_text.dart';

// TODO redesign

class MediaLoading extends StatefulWidget {
  const MediaLoading({
    required this.item,
    required this.hasProgress,
    required this.isFromCache,
    required this.isDone,
    required this.isStopped,
    required this.isViewed,
    required this.total,
    required this.received,
    required this.startedAt,
    required this.onRestart,
    required this.onStop,
    this.isTooBig = false,
    this.stopReason,
    this.stopDetails,
    this.filterEvaluation = const TagFilterEvaluation.empty(),
    this.onFilterDetailsTap,
    super.key,
  });

  final BooruItem item;

  final bool hasProgress;
  final bool isFromCache;
  final bool isDone;

  final bool isTooBig;
  final bool isStopped;
  final ViewerStopReason? stopReason;
  final String? stopDetails;
  final TagFilterEvaluation filterEvaluation;
  final VoidCallback? onFilterDetailsTap;
  final bool isViewed;

  final ValueNotifier<int> total;
  final ValueNotifier<int> received;
  final ValueNotifier<int> startedAt;

  final void Function()? onRestart;
  final void Function()? onStop;

  @override
  State<MediaLoading> createState() => _MediaLoadingState();
}

class _MediaLoadingState extends State<MediaLoading> {
  String _getStopReasonDescription(BuildContext context, ViewerStopReason? reason) {
    if (reason == null) return '';
    return switch (reason) {
      ViewerStopReason.user => context.loc.media.loading.stopReasons.stoppedByUser,
      ViewerStopReason.error => context.loc.media.loading.stopReasons.loadingError,
      ViewerStopReason.tooBig => context.loc.media.loading.stopReasons.fileIsTooBig,
      ViewerStopReason.hidden => context.loc.media.loading.stopReasons.hiddenByFilters,
      ViewerStopReason.blurred => context.loc.media.loading.stopReasons.blurredByFilters,
      ViewerStopReason.videoError => context.loc.media.loading.stopReasons.videoError,
      ViewerStopReason.reset => '',
    };
  }

  Widget _buildStopDescription(BuildContext context) {
    final blockingMatches = widget.stopReason?.isFiltered == true
        ? widget.filterEvaluation.blockingMatches.toList(growable: false)
        : const <TagFilterRuleMatch>[];
    const visibleRuleLimit = 5;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: blockingMatches.isNotEmpty ? .start : .center,
      children: [
        if (widget.stopReason != null)
          LoadingText(
            text: _getStopReasonDescription(context, widget.stopReason),
            fontSize: 20,
            withBorder: widget.stopReason?.isFiltered == true,
          ),
        if (blockingMatches.isNotEmpty)
          for (final match in blockingMatches.take(visibleRuleLimit))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TagFilterQueryText(
                query: match.rule.query.trim(),
                prefix: match.rule.hasDistinctName ? '${match.rule.displayName} — ' : '',
                matchedTags: match.matchedTags,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            )
        else if (widget.stopDetails?.isNotEmpty == true)
          LoadingText(
            text: widget.stopDetails!,
            fontSize: 18,
            withBorder: widget.stopReason?.isFiltered == true,
          ),
        if (blockingMatches.length > visibleRuleLimit)
          LoadingText(
            text: '+${blockingMatches.length - visibleRuleLimit}',
            fontSize: 18,
            withBorder: widget.stopReason?.isFiltered == true,
          ),
      ],
    );
    if (widget.stopReason?.isFiltered != true || widget.onFilterDetailsTap == null) return content;

    final colorScheme = Theme.of(context).colorScheme;
    final overlayActionColor = colorScheme.primary.computeLuminance() >= 0.1 ? colorScheme.primary : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onFilterDetailsTap,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.85,
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: overlayActionColor.withValues(alpha: 0.85),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: content),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: overlayActionColor.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: overlayActionColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool isVisible = false;
  late LoadingProgressTracker _progressTracker;

  @override
  void initState() {
    super.initState();
    _progressTracker = _createProgressTracker();
  }

  LoadingProgressTracker _createProgressTracker() {
    return LoadingProgressTracker(
      total: widget.total,
      received: widget.received,
      startedAt: widget.startedAt,
      debounceTag: 'loading_media_progress_${widget.item.hashCode}',
      onChanged: updateState,
      progressDebounceDuration: const Duration(milliseconds: 200),
      completedDebounceDuration: Duration.zero,
      periodicRefreshInterval: const Duration(milliseconds: 500),
      shouldRefresh: () => !widget.isDone,
    );
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MediaLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item)) {
      _progressTracker.dispose();
      _progressTracker = _createProgressTracker();
      return;
    }

    _progressTracker.updateSources(
      total: widget.total,
      received: widget.received,
      startedAt: widget.startedAt,
    );
  }

  @override
  void dispose() {
    _progressTracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int nowMils = DateTime.now().millisecondsSinceEpoch;
    final LoadingProgressSnapshot progress = _progressTracker.snapshot(
      hasProgress: widget.hasProgress,
      nowMillis: nowMils,
    );
    final int sinceStart = progress.sinceStartMillis;
    final bool showLoading = !widget.isDone && (widget.isStopped || (widget.isViewed && sinceStart > 999));
    // delay showing loading info a bit, so we don't clutter interface for fast loading files

    // return buildElement(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
      opacity: showLoading ? 1 : 0,
      onEnd: () {
        isVisible = showLoading;
        updateState();
      },
      child: buildElement(context, progress),
    );
  }

  Widget buildElement(BuildContext context, LoadingProgressSnapshot progress) {
    if (widget.isDone && !isVisible) {
      //  Don't do or render anything after file is loaded and widget faded out
      return const SizedBox.shrink();
    }

    final bool hasProgressData = progress.hasProgressData;
    final int expectedBytes = progress.receivedBytes;
    final int totalBytes = progress.totalBytes;
    final double percentDone = progress.percentDone;

    if (SX.shitDevice.value) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: widget.isStopped
              ? [
                  _buildStopDescription(context),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.play_arrow,
                      size: 40,
                      color: Colors.blue,
                    ),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(Colors.black54),
                      fixedSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
                    ),
                    label: LoadingText(
                      text: (widget.isTooBig || widget.stopReason?.isFiltered == true)
                          ? context.loc.media.loading.loadAnyway
                          : context.loc.media.loading.restartLoading,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                    onPressed: () {
                      widget.onRestart?.call();
                    },
                  ),
                ]
              : [
                  Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 48,
                          width: 48,
                          child: CircularProgressIndicator(
                            value: percentDone == 0 ? null : percentDone,
                          ),
                        ),
                        Text(
                          '${(percentDone * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (percentDone < 1)
                    ElevatedButton.icon(
                      icon: Icon(
                        Icons.stop,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(Colors.black54),
                        fixedSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
                      ),
                      label: LoadingText(
                        text: context.loc.media.loading.stopLoading,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () {
                        widget.onStop?.call();
                      },
                    ),
                ],
        ),
      );
    }

    final String loadedSize = hasProgressData ? Tools.formatBytes(expectedBytes, 1) : '';
    final String expectedSize = hasProgressData ? Tools.formatBytes(totalBytes, 1) : '';

    final bool isVideo = widget.item.mediaType.value.isVideo;

    String percentDoneText = '';
    if (hasProgressData) {
      if (isVideo) {
        percentDoneText = (percentDone == 1)
            ? context.loc.media.loading.rendering
            : '${(percentDone * 100).toStringAsFixed(2)}%';
      } else {
        percentDoneText = (percentDone == 1)
            ? (widget.isFromCache
                  ? context.loc.media.loading.loadingAndRenderingFromCache
                  : context.loc.media.loading.rendering)
            : '${(percentDone * 100).toStringAsFixed(2)}%';
      }
    } else {
      if (isVideo) {
        percentDoneText = widget.isFromCache
            ? context.loc.media.loading.loadingFromCache
            : context.loc.media.loading.buffering;
      } else {
        percentDoneText = widget.isDone
            ? context.loc.media.loading.rendering
            : (widget.isFromCache ? context.loc.media.loading.loadingFromCache : context.loc.media.loading.loading);
      }
    }

    final String filesizeText = (hasProgressData && percentDone < 1) ? '$loadedSize / $expectedSize' : '';

    final int expectedSpeed = progress.speedBytesPerSecond;
    final String expectedSpeedText = (hasProgressData && percentDone < 1)
        ? '${Tools.formatBytes(expectedSpeed, 1)}/s'
        : '';

    final double expectedTime = hasProgressData ? progress.estimatedSecondsRemaining : 0;
    final String expectedTimeText = (hasProgressData && expectedTime > 0 && percentDone < 1)
        ? '~${expectedTime.toStringAsFixed(1)} s'
        : '';

    final int sinceStartSeconds = (progress.sinceStartMillis / 1000).floor();
    final String sinceStartText = (!widget.isDone && (percentDone < 1 || widget.isFromCache))
        ? context.loc.media.loading.startedSecondsAgo(seconds: sinceStartSeconds)
        : '';

    final bool isMovedBelow = SX.previewMode.value.isSample && widget.stopReason?.isFiltered != true;

    // print('$percentDone | $percentDoneText');

    if (!widget.isViewed) {
      // Do the calculations, but don't render anything if not viewed
      return const SizedBox.shrink();
    }

    List<Widget> children = [];
    if (widget.isStopped) {
      children = [
        _buildStopDescription(context),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(
            Icons.play_arrow,
            size: 40,
            color: Colors.blue,
          ),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(Colors.black54),
            fixedSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
          ),
          label: LoadingText(
            text: (widget.isTooBig || widget.stopReason?.isFiltered == true)
                ? context.loc.media.loading.loadAnyway
                : context.loc.media.loading.restartLoading,
            fontSize: 16,
            color: Colors.blue,
          ),
          onPressed: () {
            widget.onRestart?.call();
          },
        ),
        if (isMovedBelow) const SizedBox(height: 60),
      ];
    } else {
      if (SX.loadingGif.value) {
        children = [
          const Center(child: Image(image: AssetImage('assets/images/loading.gif'))),
          const SizedBox(height: 30),
          LoadingText(
            text: percentDoneText,
            fontSize: 18,
          ),
        ];
      } else {
        children = [
          LoadingText(
            text: percentDoneText,
            fontSize: 18,
          ),
          LoadingText(
            text: filesizeText,
            fontSize: 16,
          ),
          LoadingText(
            text: expectedSpeedText,
            fontSize: 14,
          ),
          LoadingText(
            text: expectedTimeText,
            fontSize: 14,
          ),
          LoadingText(
            text: sinceStartText,
            fontSize: 14,
          ),
          const SizedBox(height: 10),
          if (percentDone < 1)
            ElevatedButton.icon(
              icon: Icon(
                Icons.stop,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.black54),
                fixedSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
              ),
              label: LoadingText(
                text: context.loc.media.loading.stopLoading,
                fontSize: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                widget.onStop?.call();
              },
            ),
          if (isMovedBelow) const SizedBox(height: 60),
        ];
      }
    }

    final Widget progressIndicator = percentDone == 0
        ? const LinearProgressIndicator()
        : AnimatedProgressIndicator(
            value: percentDone,
            animationDuration: const Duration(milliseconds: 100),
            indicatorStyle: IndicatorStyle.linear,
            valueColor: Theme.of(context).progressIndicatorTheme.color?.withValues(alpha: 0.66),
            minHeight: 6,
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RepaintBoundary(
          child: RotatedBox(
            quarterTurns: -1,
            child: progressIndicator,
          ),
        ),
        //
        //
        Expanded(
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
              child: Column(
                // move loading info lower if preview is of sample quality (except when item is hidden)
                mainAxisAlignment: isMovedBelow ? MainAxisAlignment.end : MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
        //
        //
        RepaintBoundary(
          child: RotatedBox(
            quarterTurns: percentDone != 0 ? -1 : 1,
            child: progressIndicator,
          ),
        ),
      ],
    );
  }
}

class LoadingText extends StatelessWidget {
  const LoadingText({
    required this.text,
    required this.fontSize,
    this.color = Colors.white,
    this.withBorder = true,
    super.key,
  });

  final String text;
  final double fontSize;
  final Color color;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final widget = Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
      ),
    );

    if (withBorder) {
      return BorderedText(
        key: ValueKey<String>(text),
        strokeWidth: 3,
        child: widget,
      );
    }

    return widget;
  }
}
