import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

enum _ImageCompareMode {
  split,
  slider,
  fade,
  flicker,
  difference,
  heatmap,
}

enum _DifferenceColorMode {
  raw,
  warm,
  luma,
}

Future<void> showImageCompareDialog(
  BuildContext context,
  BooruItem first,
  BooruItem second, {
  required Booru firstBooru,
  required Booru secondBooru,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ImageComparePage(
        first: first,
        second: second,
        firstBooru: firstBooru,
        secondBooru: secondBooru,
      ),
    ),
  );
}

class _ImageComparePage extends StatefulWidget {
  const _ImageComparePage({
    required this.first,
    required this.second,
    required this.firstBooru,
    required this.secondBooru,
  });

  final BooruItem first;
  final BooruItem second;
  final Booru firstBooru;
  final Booru secondBooru;

  @override
  State<_ImageComparePage> createState() => _ImageComparePageState();
}

class _ImageComparePageState extends State<_ImageComparePage> {
  final TransformationController firstController = TransformationController();
  final TransformationController secondController = TransformationController();

  _ImageCompareMode mode = _ImageCompareMode.split;
  bool syncZoom = true;
  bool syncingControllers = false;
  double stackSplit = 0.5;
  double stackOpacity = 1;
  double flickerIntervalMs = 500;
  Axis stackAxis = Axis.horizontal;
  _DifferenceColorMode differenceColorMode = _DifferenceColorMode.raw;
  bool imagesSwapped = false;
  bool flickerShowSecond = false;
  Timer? flickerTimer;

  BooruItem get firstItem => imagesSwapped ? widget.second : widget.first;
  BooruItem get secondItem => imagesSwapped ? widget.first : widget.second;
  Booru get firstBooru => imagesSwapped ? widget.secondBooru : widget.firstBooru;
  Booru get secondBooru => imagesSwapped ? widget.firstBooru : widget.secondBooru;

  @override
  void initState() {
    super.initState();
    firstController.addListener(() => _syncController(firstController, secondController));
    secondController.addListener(() => _syncController(secondController, firstController));
  }

  @override
  void dispose() {
    flickerTimer?.cancel();
    firstController.dispose();
    secondController.dispose();
    super.dispose();
  }

  void _syncController(TransformationController source, TransformationController target) {
    if (!syncZoom || syncingControllers || mode != _ImageCompareMode.split) {
      if (source == firstController && mode == _ImageCompareMode.slider && mounted) {
        setState(() {});
      }
      return;
    }

    syncingControllers = true;
    target.value = source.value;
    syncingControllers = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (mode) {
              _ImageCompareMode.split => _sideBySideView(context),
              _ImageCompareMode.slider => _stackView(context),
              _ImageCompareMode.fade => _opacityView(context),
              _ImageCompareMode.flicker => _flickerView(context),
              _ImageCompareMode.difference => _renderedCompareView(context, _RenderedCompareMode.difference),
              _ImageCompareMode.heatmap => _renderedCompareView(context, _RenderedCompareMode.heatmap),
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _CompareControls(
                mode: mode,
                syncZoom: syncZoom,
                stackOpacity: stackOpacity,
                flickerIntervalMs: flickerIntervalMs,
                stackAxis: stackAxis,
                differenceColorMode: differenceColorMode,
                onResetView: _resetViewAndControls,
                onSwapImages: () {
                  setState(() {
                    imagesSwapped = !imagesSwapped;
                  });
                },
                onModeChanged: (value) {
                  setState(() {
                    mode = value;
                    _resetTransforms();
                    _syncFlickerTimer();
                  });
                },
                onSyncZoomChanged: (value) {
                  setState(() {
                    syncZoom = value;
                    if (syncZoom) {
                      _syncSecondControllerToFirst();
                    }
                  });
                },
                onStackOpacityChanged: (value) {
                  setState(() {
                    stackOpacity = value;
                  });
                },
                onFlickerIntervalChanged: (value) {
                  setState(() {
                    flickerIntervalMs = value;
                    _syncFlickerTimer();
                  });
                },
                onStackAxisChanged: (value) {
                  setState(() {
                    stackAxis = value;
                  });
                },
                onDifferenceColorModeChanged: (value) {
                  setState(() {
                    differenceColorMode = value;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetViewAndControls() {
    setState(() {
      _resetTransforms();
      syncZoom = true;
      stackSplit = 0.5;
      stackOpacity = 1;
      flickerIntervalMs = 500;
      flickerShowSecond = false;
      stackAxis = Axis.horizontal;
      differenceColorMode = _DifferenceColorMode.raw;
      _syncFlickerTimer();
    });
  }

  void _resetTransforms() {
    syncingControllers = true;
    firstController.value = Matrix4.identity();
    secondController.value = Matrix4.identity();
    syncingControllers = false;
  }

  void _syncSecondControllerToFirst() {
    syncingControllers = true;
    secondController.value = firstController.value;
    syncingControllers = false;
  }

  void _syncFlickerTimer() {
    flickerTimer?.cancel();
    flickerTimer = null;
    flickerShowSecond = false;

    if (mode != _ImageCompareMode.flicker) {
      return;
    }

    flickerTimer = Timer.periodic(Duration(milliseconds: flickerIntervalMs.round()), (timer) {
      if (!mounted || mode != _ImageCompareMode.flicker) {
        timer.cancel();
        return;
      }

      setState(() {
        flickerShowSecond = !flickerShowSecond;
      });
    });
  }

  void _centerStackHandle({
    required bool isHorizontal,
    required double childHandleOffset,
    required double viewportMainExtent,
  }) {
    final matrix = Matrix4.copy(firstController.value);
    final handlePosition = isHorizontal
        ? MatrixUtils.transformPoint(matrix, Offset(childHandleOffset, 0)).dx
        : MatrixUtils.transformPoint(matrix, Offset(0, childHandleOffset)).dy;
    final delta = viewportMainExtent / 2 - handlePosition;

    if (isHorizontal) {
      matrix.setEntry(0, 3, matrix.getTranslation().x + delta);
    } else {
      matrix.setEntry(1, 3, matrix.getTranslation().y + delta);
    }

    firstController.value = matrix;
  }

  Widget _sideBySideView(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InteractiveCompareImage(
            item: firstItem,
            booru: firstBooru,
            controller: firstController,
          ),
        ),
        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: _InteractiveCompareImage(
            item: secondItem,
            booru: secondBooru,
            controller: secondController,
          ),
        ),
      ],
    );
  }

  Widget _stackView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = stackAxis == Axis.horizontal;
        final mainExtent = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final childHandleOffset = mainExtent * stackSplit;
        final transformedHandleOffset = isHorizontal
            ? MatrixUtils.transformPoint(firstController.value, Offset(childHandleOffset, 0)).dx
            : MatrixUtils.transformPoint(firstController.value, Offset(0, childHandleOffset)).dy;
        final isHandleBeforeViewport = transformedHandleOffset < 0;
        final isHandleAfterViewport = transformedHandleOffset > mainExtent;
        final isHandleOffscreen = isHandleBeforeViewport || isHandleAfterViewport;
        void updateSplit(Offset localPosition) {
          final inverseMatrix = Matrix4.copy(firstController.value)..invert();
          final childPosition = MatrixUtils.transformPoint(inverseMatrix, localPosition);
          setState(() {
            final position = isHorizontal ? childPosition.dx : childPosition.dy;
            stackSplit = (position / mainExtent).clamp(0.02, 0.98);
          });
        }

        void updateSplitFromGlobal(Offset globalPosition) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          updateSplit(box.globalToLocal(globalPosition));
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _DoubleTapInteractiveViewer(
              controller: firstController,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CompareImage(
                      item: firstItem,
                      booru: firstBooru,
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      right: isHorizontal ? null : 0,
                      bottom: isHorizontal ? 0 : null,
                      width: isHorizontal ? childHandleOffset : null,
                      height: isHorizontal ? null : childHandleOffset,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: isHorizontal ? Alignment.centerLeft : Alignment.topCenter,
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                          maxHeight: constraints.maxHeight,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            child: _CompareImage(
                              item: secondItem,
                              booru: secondBooru,
                              drawBackground: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isHandleOffscreen)
              _StackHandleOffscreenMarker(
                axis: stackAxis,
                isBeforeViewport: isHandleBeforeViewport,
                onTap: () {
                  _centerStackHandle(
                    isHorizontal: isHorizontal,
                    childHandleOffset: childHandleOffset,
                    viewportMainExtent: mainExtent,
                  );
                },
              ),
            Positioned(
              left: isHorizontal ? transformedHandleOffset : 0,
              top: isHorizontal ? 0 : transformedHandleOffset,
              right: isHorizontal ? null : 0,
              bottom: isHorizontal ? 0 : null,
              child: SizedBox(
                width: isHorizontal ? 1 : null,
                height: isHorizontal ? null : 1,
                child: CustomPaint(
                  painter: _DifferenceDividerPainter(),
                ),
              ),
            ),
            Positioned(
              left: isHorizontal ? transformedHandleOffset - 48 : 0,
              top: isHorizontal ? 0 : transformedHandleOffset - 48,
              right: isHorizontal ? null : 0,
              bottom: isHorizontal ? 0 : null,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) => updateSplitFromGlobal(details.globalPosition),
                onPanStart: (details) => updateSplitFromGlobal(details.globalPosition),
                onPanUpdate: (details) => updateSplitFromGlobal(details.globalPosition),
                child: SizedBox(
                  width: isHorizontal ? 96 : null,
                  height: isHorizontal ? null : 96,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 36,
                        height: 64,
                        child: RotatedBox(
                          quarterTurns: isHorizontal ? 0 : 1,
                          child: const Icon(Icons.drag_indicator, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _opacityView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _DoubleTapInteractiveViewer(
          controller: firstController,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CompareImage(
                  item: firstItem,
                  booru: firstBooru,
                ),
                _CompareImage(
                  item: secondItem,
                  booru: secondBooru,
                  opacity: stackOpacity,
                  drawBackground: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _flickerView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _DoubleTapInteractiveViewer(
          controller: firstController,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CompareImage(
                  item: firstItem,
                  booru: firstBooru,
                ),
                _CompareImage(
                  item: secondItem,
                  booru: secondBooru,
                  opacity: flickerShowSecond ? 1 : 0,
                  drawBackground: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _renderedCompareView(BuildContext context, _RenderedCompareMode renderMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _DoubleTapInteractiveViewer(
          controller: firstController,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: _RenderedCompareView(
              firstItem: firstItem,
              firstBooru: firstBooru,
              secondItem: secondItem,
              secondBooru: secondBooru,
              mode: renderMode,
              differenceColorMode: differenceColorMode,
            ),
          ),
        );
      },
    );
  }
}

class _CompareControls extends StatelessWidget {
  const _CompareControls({
    required this.mode,
    required this.syncZoom,
    required this.stackOpacity,
    required this.flickerIntervalMs,
    required this.stackAxis,
    required this.differenceColorMode,
    required this.onResetView,
    required this.onSwapImages,
    required this.onModeChanged,
    required this.onSyncZoomChanged,
    required this.onStackOpacityChanged,
    required this.onFlickerIntervalChanged,
    required this.onStackAxisChanged,
    required this.onDifferenceColorModeChanged,
  });

  final _ImageCompareMode mode;
  final bool syncZoom;
  final double stackOpacity;
  final double flickerIntervalMs;
  final Axis stackAxis;
  final _DifferenceColorMode differenceColorMode;
  final VoidCallback onResetView;
  final VoidCallback onSwapImages;
  final ValueChanged<_ImageCompareMode> onModeChanged;
  final ValueChanged<bool> onSyncZoomChanged;
  final ValueChanged<double> onStackOpacityChanged;
  final ValueChanged<double> onFlickerIntervalChanged;
  final ValueChanged<Axis> onStackAxisChanged;
  final ValueChanged<_DifferenceColorMode> onDifferenceColorModeChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
      child: SizedBox(
        height: 64,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 190,
                height: 48,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_ImageCompareMode>(
                      value: mode,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down),
                      selectedItemBuilder: (context) {
                        return _ImageCompareMode.values.map((mode) {
                          return _CompareModeDropdownItem(mode: mode);
                        }).toList();
                      },
                      items: _ImageCompareMode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: _CompareModeDropdownItem(mode: mode),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          onModeChanged(value);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Reset',
                icon: const Icon(Icons.restart_alt),
                onPressed: onResetView,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                onPressed: onSwapImages,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                height: 48,
                child: Center(child: _secondaryControl(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryControl(BuildContext context) {
    return switch (mode) {
      _ImageCompareMode.split => FilterChip(
        selected: syncZoom,
        tooltip: context.loc.settings.downloads.compareZoomSync,
        label: const Icon(Icons.zoom_in),
        onSelected: onSyncZoomChanged,
      ),
      _ImageCompareMode.slider => SegmentedButton<Axis>(
        segments: const [
          ButtonSegment(
            value: Axis.horizontal,
            icon: Icon(Icons.swap_horiz),
          ),
          ButtonSegment(
            value: Axis.vertical,
            icon: Icon(Icons.swap_vert),
          ),
        ],
        selected: {stackAxis},
        onSelectionChanged: (value) => onStackAxisChanged(value.first),
      ),
      _ImageCompareMode.fade => Slider(
        value: stackOpacity,
        onChanged: onStackOpacityChanged,
      ),
      _ImageCompareMode.flicker => Row(
        children: [
          const Icon(Icons.timer_outlined),
          Expanded(
            child: Slider(
              value: flickerIntervalMs,
              min: 100,
              max: 2000,
              divisions: 19,
              onChanged: onFlickerIntervalChanged,
            ),
          ),
        ],
      ),
      _ImageCompareMode.difference => SegmentedButton<_DifferenceColorMode>(
        segments: const [
          ButtonSegment(
            value: _DifferenceColorMode.raw,
            tooltip: 'Raw',
            icon: Icon(Icons.tonality),
          ),
          ButtonSegment(
            value: _DifferenceColorMode.warm,
            tooltip: 'Warm',
            icon: Icon(Icons.gradient),
          ),
          ButtonSegment(
            value: _DifferenceColorMode.luma,
            tooltip: 'Luma',
            icon: Icon(Icons.monochrome_photos),
          ),
        ],
        selected: {differenceColorMode},
        onSelectionChanged: (value) => onDifferenceColorModeChanged(value.first),
      ),
      _ImageCompareMode.heatmap => const SizedBox.shrink(),
    };
  }
}

class _CompareModeDropdownItem extends StatelessWidget {
  const _CompareModeDropdownItem({required this.mode});

  final _ImageCompareMode mode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_modeIcon),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _modeLabel(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  IconData get _modeIcon {
    return switch (mode) {
      _ImageCompareMode.split => Icons.view_column,
      _ImageCompareMode.slider => Icons.compare,
      _ImageCompareMode.fade => Icons.opacity,
      _ImageCompareMode.flicker => Icons.bolt,
      _ImageCompareMode.difference => Icons.difference,
      _ImageCompareMode.heatmap => Icons.local_fire_department,
    };
  }

  String _modeLabel(BuildContext context) {
    return switch (mode) {
      _ImageCompareMode.split => context.loc.settings.downloads.compareSplit,
      _ImageCompareMode.slider => context.loc.settings.downloads.compareSlider,
      _ImageCompareMode.fade => context.loc.settings.downloads.compareFade,
      _ImageCompareMode.flicker => context.loc.settings.downloads.compareFlicker,
      _ImageCompareMode.difference => context.loc.settings.downloads.compareDifference,
      _ImageCompareMode.heatmap => context.loc.settings.downloads.compareHeatmap,
    };
  }
}

class _DifferenceDividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.grey.shade400);
  }

  @override
  bool shouldRepaint(covariant _DifferenceDividerPainter oldDelegate) => false;
}

class _StackHandleOffscreenMarker extends StatelessWidget {
  const _StackHandleOffscreenMarker({
    required this.axis,
    required this.isBeforeViewport,
    required this.onTap,
  });

  final Axis axis;
  final bool isBeforeViewport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    final icon = isHorizontal
        ? (isBeforeViewport ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right)
        : (isBeforeViewport ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down);

    return Positioned(
      left: isHorizontal && isBeforeViewport ? 12 : null,
      right: isHorizontal && !isBeforeViewport ? 12 : null,
      top: isHorizontal ? 0 : (isBeforeViewport ? 12 : null),
      bottom: isHorizontal ? 0 : (!isBeforeViewport ? 96 : null),
      child: Center(
        child: Material(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoubleTapInteractiveViewer extends StatefulWidget {
  const _DoubleTapInteractiveViewer({
    required this.controller,
    required this.child,
  });

  final TransformationController controller;
  final Widget child;

  @override
  State<_DoubleTapInteractiveViewer> createState() => _DoubleTapInteractiveViewerState();
}

class _DoubleTapInteractiveViewerState extends State<_DoubleTapInteractiveViewer> {
  Offset? doubleTapPosition;

  void _handleDoubleTap() {
    final currentScale = widget.controller.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      widget.controller.value = Matrix4.identity();
      return;
    }

    final position = doubleTapPosition ?? Offset.zero;
    const scale = 2.5;
    widget.controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, position.dx * (1 - scale))
      ..setEntry(1, 3, position.dy * (1 - scale));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) {
        doubleTapPosition = details.localPosition;
      },
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        constrained: false,
        transformationController: widget.controller,
        minScale: 0.25,
        maxScale: 8,
        child: widget.child,
      ),
    );
  }
}

class _InteractiveCompareImage extends StatelessWidget {
  const _InteractiveCompareImage({
    required this.item,
    required this.booru,
    required this.controller,
  });

  final BooruItem item;
  final Booru booru;
  final TransformationController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _DoubleTapInteractiveViewer(
          controller: controller,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: _CompareImage(
              item: item,
              booru: booru,
            ),
          ),
        );
      },
    );
  }
}

enum _RenderedCompareMode { difference, heatmap }

class _RenderedCompareView extends StatefulWidget {
  const _RenderedCompareView({
    required this.firstItem,
    required this.firstBooru,
    required this.secondItem,
    required this.secondBooru,
    required this.mode,
    required this.differenceColorMode,
  });

  final BooruItem firstItem;
  final Booru firstBooru;
  final BooruItem secondItem;
  final Booru secondBooru;
  final _RenderedCompareMode mode;
  final _DifferenceColorMode differenceColorMode;

  @override
  State<_RenderedCompareView> createState() => _RenderedCompareViewState();
}

class _RenderedCompareViewState extends State<_RenderedCompareView> {
  late Future<({ui.Image first, ui.Image second, ui.Image? heatmap})> imagesFuture = _loadImages();

  @override
  void didUpdateWidget(covariant _RenderedCompareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstItem != widget.firstItem ||
        oldWidget.firstBooru != widget.firstBooru ||
        oldWidget.secondItem != widget.secondItem ||
        oldWidget.secondBooru != widget.secondBooru ||
        (oldWidget.mode != widget.mode && widget.mode == _RenderedCompareMode.heatmap)) {
      imagesFuture = _loadImages();
    }
  }

  Future<({ui.Image first, ui.Image second, ui.Image? heatmap})> _loadImages() async {
    final firstProvider = await _buildCompareImageProvider(widget.firstItem, widget.firstBooru);
    final secondProvider = await _buildCompareImageProvider(widget.secondItem, widget.secondBooru);
    final first = await _resolveImage(firstProvider);
    final second = await _resolveImage(secondProvider);

    return (
      first: first,
      second: second,
      heatmap: widget.mode == _RenderedCompareMode.heatmap ? await _buildHeatmapImage(first, second) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<({ui.Image first, ui.Image second, ui.Image? heatmap})>(
        future: imagesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _CompareImageError(
              details: snapshot.error.toString(),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return CustomPaint(
            painter: _RenderedComparePainter(
              first: snapshot.data!.first,
              second: snapshot.data!.second,
              heatmap: snapshot.data!.heatmap,
              mode: widget.mode,
              differenceColorMode: widget.differenceColorMode,
            ),
          );
        },
      ),
    );
  }
}

class _RenderedComparePainter extends CustomPainter {
  const _RenderedComparePainter({
    required this.first,
    required this.second,
    required this.heatmap,
    required this.mode,
    required this.differenceColorMode,
  });

  final ui.Image first;
  final ui.Image second;
  final ui.Image? heatmap;
  final _RenderedCompareMode mode;
  final _DifferenceColorMode differenceColorMode;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = Colors.black);

    switch (mode) {
      case _RenderedCompareMode.difference:
        canvas.saveLayer(bounds, _differenceLayerPaint(differenceColorMode));
        _drawContainedImage(canvas, first, size, Paint());
        _drawContainedImage(canvas, second, size, Paint()..blendMode = BlendMode.difference);
        canvas.restore();
      case _RenderedCompareMode.heatmap:
        final heatmapImage = heatmap;
        if (heatmapImage == null) {
          return;
        }
        _drawContainedImage(canvas, heatmapImage, size, Paint()..filterQuality = FilterQuality.none);
    }
  }

  void _drawContainedImage(Canvas canvas, ui.Image image, Size size, Paint paint) {
    final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      size,
    );
    final destination = Alignment.center.inscribe(fitted.destination, Offset.zero & size);

    canvas.drawImageRect(image, source, destination, paint);
  }

  @override
  bool shouldRepaint(covariant _RenderedComparePainter oldDelegate) {
    return oldDelegate.first != first ||
        oldDelegate.second != second ||
        oldDelegate.heatmap != heatmap ||
        oldDelegate.mode != mode ||
        oldDelegate.differenceColorMode != differenceColorMode;
  }
}

Paint _differenceLayerPaint(_DifferenceColorMode colorMode) {
  return switch (colorMode) {
    _DifferenceColorMode.raw => Paint(),
    _DifferenceColorMode.warm =>
      Paint()
        ..colorFilter = const ColorFilter.matrix([
          1.7,
          1.7,
          1.7,
          0,
          0,
          0.55,
          0.55,
          0.55,
          0,
          0,
          0.04,
          0.04,
          0.04,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    _DifferenceColorMode.luma =>
      Paint()
        ..colorFilter = const ColorFilter.matrix([
          0.299,
          0.587,
          0.114,
          0,
          0,
          0.299,
          0.587,
          0.114,
          0,
          0,
          0.299,
          0.587,
          0.114,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
  };
}

Future<ui.Image> _buildHeatmapImage(ui.Image first, ui.Image second) async {
  final firstBytes = await first.toByteData(format: ui.ImageByteFormat.rawRgba);
  final secondBytes = await second.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (firstBytes == null || secondBytes == null) {
    throw StateError('Unable to read image pixels for heatmap comparison');
  }

  const maxSide = 1024;
  final firstAspect = first.width / first.height;
  final secondAspect = second.width / second.height;
  final comparisonAspect = (firstAspect + secondAspect) / 2;
  final width = comparisonAspect >= 1 ? maxSide : (maxSide * comparisonAspect).round().clamp(1, maxSide);
  final height = comparisonAspect >= 1 ? (maxSide / comparisonAspect).round().clamp(1, maxSide) : maxSide;
  final output = Uint8List(width * height * 4);
  final firstList = firstBytes.buffer.asUint8List();
  final secondList = secondBytes.buffer.asUint8List();

  for (var y = 0; y < height; y++) {
    final firstY = ((y + 0.5) * first.height / height).floor().clamp(0, first.height - 1);
    final secondY = ((y + 0.5) * second.height / height).floor().clamp(0, second.height - 1);

    for (var x = 0; x < width; x++) {
      final firstX = ((x + 0.5) * first.width / width).floor().clamp(0, first.width - 1);
      final secondX = ((x + 0.5) * second.width / width).floor().clamp(0, second.width - 1);
      final firstOffset = (firstY * first.width + firstX) * 4;
      final secondOffset = (secondY * second.width + secondX) * 4;
      final outputOffset = (y * width + x) * 4;

      final redDelta = (firstList[firstOffset] - secondList[secondOffset]).abs();
      final greenDelta = (firstList[firstOffset + 1] - secondList[secondOffset + 1]).abs();
      final blueDelta = (firstList[firstOffset + 2] - secondList[secondOffset + 2]).abs();
      final alphaDelta = (firstList[firstOffset + 3] - secondList[secondOffset + 3]).abs();
      final distance =
          ((redDelta * redDelta * 0.299) +
              (greenDelta * greenDelta * 0.587) +
              (blueDelta * blueDelta * 0.114) +
              (alphaDelta * alphaDelta * 0.25)) /
          (255 * 255 * 1.25);
      final intensity = distance.clamp(0.0, 1.0);
      final color = _heatmapColor(intensity);

      output[outputOffset] = color.$1;
      output[outputOffset + 1] = color.$2;
      output[outputOffset + 2] = color.$3;
      output[outputOffset + 3] = 255;
    }
  }

  return ui.decodeImageFromPixelsSync(output, width, height, ui.PixelFormat.rgba8888);
}

(int, int, int) _heatmapColor(double intensity) {
  if (intensity < 0.015) {
    return (0, 0, 0);
  }

  final value = intensity.clamp(0.0, 1.0);
  if (value < 0.25) {
    final t = value / 0.25;
    return (0, (80 + 120 * t).round(), (120 + 135 * t).round());
  }
  if (value < 0.5) {
    final t = (value - 0.25) / 0.25;
    return (0, 200 + (55 * t).round(), (255 * (1 - t)).round());
  }
  if (value < 0.75) {
    final t = (value - 0.5) / 0.25;
    return ((255 * t).round(), 255, 0);
  }

  final t = (value - 0.75) / 0.25;
  return (255, (255 * (1 - t)).round(), 0);
}

Future<ui.Image> _resolveImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completer.complete(info.image);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);

  return completer.future;
}

class _CompareImage extends StatefulWidget {
  const _CompareImage({
    required this.item,
    required this.booru,
    this.opacity = 1,
    this.drawBackground = true,
  });

  final BooruItem item;
  final Booru booru;
  final double opacity;
  final bool drawBackground;

  @override
  State<_CompareImage> createState() => _CompareImageState();
}

class _CompareImageState extends State<_CompareImage> {
  late Future<ImageProvider> providerFuture = _buildCompareImageProvider(widget.item, widget.booru);

  @override
  void didUpdateWidget(covariant _CompareImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item != widget.item || oldWidget.booru != widget.booru) {
      providerFuture = _buildCompareImageProvider(widget.item, widget.booru);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.drawBackground ? Colors.black : Colors.transparent,
      child: Align(
        alignment: Alignment.center,
        child: Opacity(
          opacity: widget.opacity,
          child: FutureBuilder<ImageProvider>(
            future: providerFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _CompareImageError(
                  details: snapshot.error.toString(),
                );
              }
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }

              return Image(
                image: snapshot.data!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return _CompareImageError(
                    details: error.toString(),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<ImageProvider> _buildCompareImageProvider(BooruItem item, Booru booru) async {
  final url = item.fileURL.isNotEmpty ? item.fileURL : item.sampleURL;
  if (url.trim().isEmpty) {
    throw StateError('No image URL found for selected item');
  }
  final headers = await Tools.getFileCustomHeaders(
    booru,
    item: item,
    checkForReferer: true,
  );
  final settingsHandler = SettingsHandler.instance;
  final isAvif = url.contains('.avif');

  return isAvif
      ? CustomNetworkAvifImage(
          url,
          headers: headers,
          withCache: settingsHandler.mediaCache,
          cacheFolder: 'media',
          fileNameExtras: item.fileNameExtras,
          withCaptchaCheck: true,
        )
      : CustomNetworkImage(
          url,
          headers: headers,
          withCache: settingsHandler.mediaCache,
          cacheFolder: 'media',
          fileNameExtras: item.fileNameExtras,
          withCaptchaCheck: true,
        );
}

class _CompareImageError extends StatelessWidget {
  const _CompareImageError({
    required this.details,
  });

  final String details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, size: 48, color: Colors.white70),
          const SizedBox(height: 12),
          SelectableText(
            details,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
