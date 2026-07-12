import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/image/custom_network_image.dart';

enum _ImageCompareMode {
  split,
  slider,
  fade,
  flicker,
  difference,
  heatmap,
  data,
}

enum _DifferenceColorMode {
  raw,
  warm,
  luma,
}

enum _CompareBackground {
  black,
  white,
}

enum _RenderedPreviewSide {
  first,
  second,
}

bool get _isHeatmapModeSupported => ui.ImageFilter.isShaderFilterSupported;

List<_ImageCompareMode> _availableCompareModes({required bool imageModesAvailable}) {
  if (!imageModesAvailable) {
    return const [_ImageCompareMode.data];
  }

  return [
    _ImageCompareMode.split,
    _ImageCompareMode.slider,
    _ImageCompareMode.fade,
    _ImageCompareMode.flicker,
    _ImageCompareMode.difference,
    if (_isHeatmapModeSupported) _ImageCompareMode.heatmap,
    _ImageCompareMode.data,
  ];
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
  Future<ImageProvider>? _firstProviderFuture;
  Future<ImageProvider>? _secondProviderFuture;

  _ImageCompareMode mode = _ImageCompareMode.split;
  bool syncZoom = true;
  bool syncingControllers = false;
  double stackSplit = 0.5;
  double stackOpacity = 1;
  double flickerIntervalMs = 500;
  Axis stackAxis = Axis.horizontal;
  _DifferenceColorMode differenceColorMode = _DifferenceColorMode.raw;
  _CompareBackground compareBackground = _CompareBackground.black;
  _RenderedPreviewSide? renderedPreviewSide;
  bool dataOnlyDifferences = false;
  bool imagesSwapped = false;
  bool controlsVisible = true;
  bool flickerShowSecond = false;
  Timer? flickerTimer;

  BooruItem get firstItem => imagesSwapped ? widget.second : widget.first;
  BooruItem get secondItem => imagesSwapped ? widget.first : widget.second;
  Booru get firstBooru => imagesSwapped ? widget.secondBooru : widget.firstBooru;
  Booru get secondBooru => imagesSwapped ? widget.firstBooru : widget.secondBooru;
  bool get imageModesAvailable =>
      widget.first.mediaType.value.isImageOrAnimation && widget.second.mediaType.value.isImageOrAnimation;
  Future<ImageProvider> get _firstSourceProviderFuture =>
      _firstProviderFuture ??= _buildCompareImageProvider(widget.first, widget.firstBooru);
  Future<ImageProvider> get _secondSourceProviderFuture =>
      _secondProviderFuture ??= _buildCompareImageProvider(widget.second, widget.secondBooru);
  Future<ImageProvider> get firstProviderFuture =>
      imagesSwapped ? _secondSourceProviderFuture : _firstSourceProviderFuture;
  Future<ImageProvider> get secondProviderFuture =>
      imagesSwapped ? _firstSourceProviderFuture : _secondSourceProviderFuture;

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
      if (source == firstController &&
          (mode == _ImageCompareMode.slider || mode == _ImageCompareMode.split) &&
          mounted) {
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
    final availableModes = _availableCompareModes(imageModesAvailable: imageModesAvailable);
    final effectiveMode = !availableModes.contains(mode)
        ? availableModes.first
        : mode == _ImageCompareMode.heatmap && !_isHeatmapModeSupported
        ? _ImageCompareMode.difference
        : mode;
    final appBarForeground = _foregroundForCompareBackground(context, effectiveMode, compareBackground);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: appBarForeground,
        iconTheme: IconThemeData(color: appBarForeground),
        actionsIconTheme: IconThemeData(color: appBarForeground),
        title: _ImageCompareResolutionTitle(
          first: firstItem,
          second: secondItem,
          color: appBarForeground,
        ),
        actions: [
          IconButton(
            tooltip: controlsVisible ? context.loc.hide : context.loc.show,
            icon: Icon(
              controlsVisible ? Icons.visibility_off : Icons.visibility,
              color: appBarForeground,
            ),
            onPressed: () {
              setState(() {
                controlsVisible = !controlsVisible;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (effectiveMode) {
              _ImageCompareMode.split => _sideBySideView(context),
              _ImageCompareMode.slider => _stackView(context),
              _ImageCompareMode.fade => _opacityView(context),
              _ImageCompareMode.flicker => _flickerView(context),
              _ImageCompareMode.difference => _renderedCompareView(context, _RenderedCompareMode.difference),
              _ImageCompareMode.heatmap => _renderedCompareView(context, _RenderedCompareMode.heatmap),
              _ImageCompareMode.data => _dataCompareView(context),
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: controlsVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOutCubic,
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: _CompareControls(
                    mode: effectiveMode,
                    availableModes: availableModes,
                    firstItem: firstItem,
                    firstBooru: firstBooru,
                    secondItem: secondItem,
                    secondBooru: secondBooru,
                    syncZoom: syncZoom,
                    stackOpacity: stackOpacity,
                    flickerIntervalMs: flickerIntervalMs,
                    flickerShowSecond: flickerShowSecond,
                    stackAxis: stackAxis,
                    differenceColorMode: differenceColorMode,
                    compareBackground: compareBackground,
                    dataOnlyDifferences: dataOnlyDifferences,
                    onResetView: _resetViewAndControls,
                    onSwapImages: () {
                      setState(() {
                        imagesSwapped = !imagesSwapped;
                      });
                    },
                    onModeChanged: (value) {
                      if (!availableModes.contains(value)) {
                        return;
                      }
                      setState(() {
                        if (value == _ImageCompareMode.heatmap && !_isHeatmapModeSupported) {
                          return;
                        }
                        mode = value;
                        _resetTransforms();
                        _resetModeControls();
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
                    onCompareBackgroundChanged: (value) {
                      setState(() {
                        compareBackground = value;
                      });
                    },
                    onDataOnlyDifferencesChanged: (value) {
                      setState(() {
                        dataOnlyDifferences = value;
                      });
                    },
                  ),
                ),
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
      _resetModeControls();
      _syncFlickerTimer();
    });
  }

  void _resetModeControls() {
    syncZoom = true;
    stackSplit = 0.5;
    stackOpacity = 1;
    flickerIntervalMs = 500;
    flickerShowSecond = false;
    stackAxis = Axis.horizontal;
    differenceColorMode = _DifferenceColorMode.raw;
    compareBackground = _CompareBackground.black;
    renderedPreviewSide = null;
    dataOnlyDifferences = false;
  }

  void _toggleControls() {
    setState(() {
      controlsVisible = !controlsVisible;
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

  double _topOverlayInset(BuildContext context) {
    return MediaQuery.paddingOf(context).top + 8;
  }

  double _bottomControlsInset(BuildContext context) {
    if (!controlsVisible) {
      return MediaQuery.paddingOf(context).bottom;
    }

    final isCompact = MediaQuery.sizeOf(context).width < _CompareControls.compactWidthBreakpoint;
    return MediaQuery.paddingOf(context).bottom +
        (isCompact ? _CompareControls.compactHeight : _CompareControls.height);
  }

  Widget _sideBySideView(BuildContext context) {
    final first = Expanded(
      child: _InteractiveCompareImage(
        item: firstItem,
        booru: firstBooru,
        providerFuture: firstProviderFuture,
        controller: firstController,
        onTap: _toggleControls,
      ),
    );
    final second = Expanded(
      child: _InteractiveCompareImage(
        item: secondItem,
        booru: secondBooru,
        providerFuture: secondProviderFuture,
        controller: secondController,
        onTap: _toggleControls,
      ),
    );
    final divider = stackAxis == Axis.horizontal
        ? VerticalDivider(width: 1, color: Theme.of(context).dividerColor)
        : Divider(height: 1, color: Theme.of(context).dividerColor);

    return Flex(
      direction: stackAxis,
      children: [
        first,
        divider,
        second,
      ],
    );
  }

  Widget _stackView(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = stackAxis == Axis.horizontal;
        final mainExtent = isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final topInset = _topOverlayInset(context).clamp(0.0, constraints.maxHeight);
        final bottomInset = _bottomControlsInset(context).clamp(0.0, constraints.maxHeight);
        final safeTop = math.min(topInset, constraints.maxHeight);
        final safeBottom = math.max(safeTop, constraints.maxHeight - bottomInset);
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
              onTap: _toggleControls,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CompareImage(
                      item: secondItem,
                      booru: secondBooru,
                      providerFuture: secondProviderFuture,
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
                              item: firstItem,
                              booru: firstBooru,
                              providerFuture: firstProviderFuture,
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
                topInset: safeTop,
                bottomInset: constraints.maxHeight - safeBottom,
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
              top: isHorizontal ? safeTop : transformedHandleOffset - 48,
              right: isHorizontal ? null : 0,
              bottom: isHorizontal ? constraints.maxHeight - safeBottom : null,
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
          onTap: _toggleControls,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CompareImage(
                  item: firstItem,
                  booru: firstBooru,
                  providerFuture: firstProviderFuture,
                ),
                _CompareImage(
                  item: secondItem,
                  booru: secondBooru,
                  providerFuture: secondProviderFuture,
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
          onTap: _toggleControls,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CompareImage(
                  item: firstItem,
                  booru: firstBooru,
                  providerFuture: firstProviderFuture,
                ),
                _CompareImage(
                  item: secondItem,
                  booru: secondBooru,
                  providerFuture: secondProviderFuture,
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
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) {
            setState(() {
              renderedPreviewSide = details.localPosition.dx < constraints.maxWidth / 2
                  ? _RenderedPreviewSide.first
                  : _RenderedPreviewSide.second;
            });
          },
          onLongPressEnd: (_) {
            setState(() {
              renderedPreviewSide = null;
            });
          },
          onLongPressCancel: () {
            setState(() {
              renderedPreviewSide = null;
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _DoubleTapInteractiveViewer(
                controller: firstController,
                onTap: _toggleControls,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _RenderedCompareView(
                        firstItem: firstItem,
                        firstBooru: firstBooru,
                        firstProviderFuture: firstProviderFuture,
                        secondItem: secondItem,
                        secondBooru: secondBooru,
                        secondProviderFuture: secondProviderFuture,
                        mode: renderMode,
                        differenceColorMode: differenceColorMode,
                        background: compareBackground,
                        badgeBottomInset: _bottomControlsInset(context),
                      ),
                      if (renderedPreviewSide != null)
                        IgnorePointer(
                          child: _CompareImage(
                            item: renderedPreviewSide == _RenderedPreviewSide.first ? firstItem : secondItem,
                            booru: renderedPreviewSide == _RenderedPreviewSide.first ? firstBooru : secondBooru,
                            providerFuture: renderedPreviewSide == _RenderedPreviewSide.first
                                ? firstProviderFuture
                                : secondProviderFuture,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dataCompareView(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight + 12;
    final bottomPadding = _bottomControlsInset(context) + 16;
    final firstDetails = _ItemDataDetails(item: firstItem, booru: firstBooru);
    final secondDetails = _ItemDataDetails(item: secondItem, booru: secondBooru);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final metadata = _MetadataComparison(
            first: firstDetails,
            second: secondDetails,
            onlyDifferences: dataOnlyDifferences,
          );
          final tags = _TagsComparison(
            first: firstItem,
            second: secondItem,
            onlyDifferences: dataOnlyDifferences,
          );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: metadata),
                          const SizedBox(width: 12),
                          Expanded(child: tags),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          metadata,
                          const SizedBox(height: 12),
                          tags,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CompareControls extends StatelessWidget {
  const _CompareControls({
    required this.mode,
    required this.availableModes,
    required this.firstItem,
    required this.firstBooru,
    required this.secondItem,
    required this.secondBooru,
    required this.syncZoom,
    required this.stackOpacity,
    required this.flickerIntervalMs,
    required this.flickerShowSecond,
    required this.stackAxis,
    required this.differenceColorMode,
    required this.compareBackground,
    required this.dataOnlyDifferences,
    required this.onResetView,
    required this.onSwapImages,
    required this.onModeChanged,
    required this.onSyncZoomChanged,
    required this.onStackOpacityChanged,
    required this.onFlickerIntervalChanged,
    required this.onStackAxisChanged,
    required this.onDifferenceColorModeChanged,
    required this.onCompareBackgroundChanged,
    required this.onDataOnlyDifferencesChanged,
  });

  static const double height = 64;
  static const double compactHeight = 112;
  static const double compactWidthBreakpoint = 520;

  final _ImageCompareMode mode;
  final List<_ImageCompareMode> availableModes;
  final BooruItem firstItem;
  final Booru firstBooru;
  final BooruItem secondItem;
  final Booru secondBooru;
  final bool syncZoom;
  final double stackOpacity;
  final double flickerIntervalMs;
  final bool flickerShowSecond;
  final Axis stackAxis;
  final _DifferenceColorMode differenceColorMode;
  final _CompareBackground compareBackground;
  final bool dataOnlyDifferences;
  final VoidCallback onResetView;
  final VoidCallback onSwapImages;
  final ValueChanged<_ImageCompareMode> onModeChanged;
  final ValueChanged<bool> onSyncZoomChanged;
  final ValueChanged<double> onStackOpacityChanged;
  final ValueChanged<double> onFlickerIntervalChanged;
  final ValueChanged<Axis> onStackAxisChanged;
  final ValueChanged<_DifferenceColorMode> onDifferenceColorModeChanged;
  final ValueChanged<_CompareBackground> onCompareBackgroundChanged;
  final ValueChanged<bool> onDataOnlyDifferencesChanged;

  @override
  Widget build(BuildContext context) {
    final selectedMode = availableModes.contains(mode) ? mode : availableModes.first;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < compactWidthBreakpoint;
          final primaryControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeDropdown(
                mode: selectedMode,
                modes: availableModes,
                width: isCompact ? 190 : 190,
                onModeChanged: onModeChanged,
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Reset',
                icon: const Icon(Icons.restart_alt),
                onPressed: onResetView,
              ),
              const SizedBox(width: 4),
              _SwapImagesButton(
                firstItem: firstItem,
                firstBooru: firstBooru,
                secondItem: secondItem,
                secondBooru: secondBooru,
                onPressed: onSwapImages,
              ),
            ],
          );
          final secondaryControls = SizedBox(
            width: _secondaryControlWidth(context, isCompact, constraints.maxWidth),
            height: 48,
            child: Center(child: _secondaryControl(context, isCompact)),
          );

          return SizedBox(
            height: (isCompact ? compactHeight : height) + bottomPadding,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: isCompact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ScrollableControls(child: primaryControls),
                        const SizedBox(height: 4),
                        _ScrollableControls(child: secondaryControls),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: _ScrollableControls(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                primaryControls,
                                const SizedBox(width: 12),
                                secondaryControls,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  double _secondaryControlWidth(
    BuildContext context,
    bool isCompact,
    double availableWidth,
  ) {
    return switch (mode) {
      _ImageCompareMode.split => 240,
      _ImageCompareMode.slider => 140,
      _ImageCompareMode.fade => isCompact ? availableWidth - 24 : 220,
      _ImageCompareMode.flicker => isCompact ? availableWidth - 24 : 220,
      _ImageCompareMode.difference => isCompact ? availableWidth - 24 : 450,
      _ImageCompareMode.heatmap => 210,
      _ImageCompareMode.data => 64,
    };
  }

  Widget _secondaryControl(BuildContext context, bool isCompact) {
    return switch (mode) {
      _ImageCompareMode.split => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterChip(
            selected: syncZoom,
            tooltip: context.loc.settings.downloads.compareZoomSync,
            label: const Icon(Icons.zoom_in),
            onSelected: onSyncZoomChanged,
          ),
          const SizedBox(width: 8),
          _AxisToggle(
            selected: stackAxis,
            onChanged: onStackAxisChanged,
          ),
        ],
      ),
      _ImageCompareMode.slider => _AxisToggle(
        selected: stackAxis,
        onChanged: onStackAxisChanged,
      ),
      _ImageCompareMode.fade => Slider(
        value: stackOpacity,
        onChanged: onStackOpacityChanged,
      ),
      _ImageCompareMode.flicker => Row(
        children: [
          const Icon(Icons.timer_outlined),
          SizedBox(
            width: 32,
            child: Text(
              flickerShowSecond ? '2' : '1',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
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
      _ImageCompareMode.difference => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<_DifferenceColorMode>(
            segments: const [
              ButtonSegment(
                value: _DifferenceColorMode.raw,
                tooltip: 'Raw',
                icon: _DifferenceModeSwatch(colors: [Colors.red, Colors.green, Colors.blue]),
              ),
              ButtonSegment(
                value: _DifferenceColorMode.warm,
                tooltip: 'Warm',
                icon: _DifferenceModeSwatch(colors: [Colors.red, Colors.orange, Colors.yellow]),
              ),
              ButtonSegment(
                value: _DifferenceColorMode.luma,
                tooltip: 'Luma',
                icon: _DifferenceModeSwatch(colors: [Colors.black54, Colors.grey, Colors.white]),
              ),
            ],
            selected: {differenceColorMode},
            onSelectionChanged: (value) => onDifferenceColorModeChanged(value.first),
          ),
          const SizedBox(width: 8),
          _BackgroundToggle(
            selected: compareBackground,
            onChanged: onCompareBackgroundChanged,
          ),
        ],
      ),
      _ImageCompareMode.heatmap => _BackgroundToggle(
        selected: compareBackground,
        onChanged: onCompareBackgroundChanged,
      ),
      _ImageCompareMode.data => FilterChip(
        selected: dataOnlyDifferences,
        tooltip: 'Differences only',
        label: const Icon(Icons.filter_alt),
        onSelected: onDataOnlyDifferencesChanged,
      ),
    };
  }
}

class _ScrollableControls extends StatelessWidget {
  const _ScrollableControls({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
  }
}

class _SwapImagesButton extends StatelessWidget {
  const _SwapImagesButton({
    required this.firstItem,
    required this.firstBooru,
    required this.secondItem,
    required this.secondBooru,
    required this.onPressed,
  });

  final BooruItem firstItem;
  final Booru firstBooru;
  final BooruItem secondItem;
  final Booru secondBooru;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Swap',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
            width: 82,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 5,
                  child: _CompareOrderThumbnail(
                    item: firstItem,
                    booru: firstBooru,
                  ),
                ),
                Positioned(
                  right: 5,
                  child: _CompareOrderThumbnail(
                    item: secondItem,
                    booru: secondBooru,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.swap_horiz, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompareOrderThumbnail extends StatefulWidget {
  const _CompareOrderThumbnail({
    required this.item,
    required this.booru,
  });

  final BooruItem item;
  final Booru booru;

  @override
  State<_CompareOrderThumbnail> createState() => _CompareOrderThumbnailState();
}

class _CompareOrderThumbnailState extends State<_CompareOrderThumbnail> {
  late Future<ImageProvider> providerFuture = _buildCompareThumbnailProvider(widget.item, widget.booru);

  @override
  void didUpdateWidget(covariant _CompareOrderThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item != widget.item || oldWidget.booru != widget.booru) {
      providerFuture = _buildCompareThumbnailProvider(widget.item, widget.booru);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 30,
        height: 38,
        child: FutureBuilder<ImageProvider>(
          future: providerFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            return Image(
              image: snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image, size: 16),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ItemDataDetails {
  const _ItemDataDetails({
    required this.item,
    required this.booru,
  });

  final BooruItem item;
  final Booru booru;

  List<({String label, String? value})> get rows {
    return [
      (label: 'Booru', value: booru.name),
      (label: 'Server ID', value: item.serverId),
      (label: 'Post URL', value: item.postURL),
      (label: 'File URL', value: item.fileURL),
      (label: 'Sample URL', value: item.sampleURL),
      (label: 'Thumbnail URL', value: item.thumbnailURL),
      (label: 'File type', value: item.fileExt),
      (label: 'Media type', value: item.mediaType.value.name),
      (label: 'File size', value: item.fileSize == null ? null : Tools.formatBytes(item.fileSize!, 2)),
      (label: 'File resolution', value: _formatDimensions(item.fileWidth, item.fileHeight)),
      (label: 'Sample resolution', value: _formatDimensions(item.sampleWidth, item.sampleHeight)),
      (label: 'Preview resolution', value: _formatDimensions(item.previewWidth, item.previewHeight)),
      (label: 'Rating', value: item.rating),
      (label: 'Score', value: item.score),
      (label: 'Uploader ID', value: item.uploaderId),
      (label: 'Uploader', value: item.uploaderName),
      (label: 'Post date', value: item.postDate),
      (label: 'MD5', value: item.md5String),
      (label: 'Sources', value: item.sources?.where((source) => source.trim().isNotEmpty).join('\n')),
      (label: 'Description', value: item.description),
      (label: 'Notes', value: item.hasNotes?.toString()),
      (label: 'Comments', value: item.hasComments?.toString()),
    ];
  }
}

class _MetadataComparison extends StatelessWidget {
  const _MetadataComparison({
    required this.first,
    required this.second,
    required this.onlyDifferences,
  });

  final _ItemDataDetails first;
  final _ItemDataDetails second;
  final bool onlyDifferences;

  @override
  Widget build(BuildContext context) {
    final firstRows = first.rows;
    final secondRows = second.rows;
    final visibleIndexes = [
      for (var i = 0; i < firstRows.length; i++)
        if (!onlyDifferences ||
            _normalizeCompareValue(firstRows[i].value) != _normalizeCompareValue(secondRows[i].value))
          i,
    ];

    return _CompareDataPanel(
      title: 'Item data',
      child: Column(
        children: [
          if (visibleIndexes.isEmpty)
            const _EmptyCompareText()
          else
            for (final i in visibleIndexes)
              _MetadataComparisonRow(
                label: firstRows[i].label,
                first: firstRows[i].value,
                second: secondRows[i].value,
              ),
        ],
      ),
    );
  }
}

class _MetadataComparisonRow extends StatelessWidget {
  const _MetadataComparisonRow({
    required this.label,
    required this.first,
    required this.second,
  });

  final String label;
  final String? first;
  final String? second;

  @override
  Widget build(BuildContext context) {
    final normalizedFirst = _normalizeCompareValue(first);
    final normalizedSecond = _normalizeCompareValue(second);
    final isSame = normalizedFirst == normalizedSecond;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.45)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  isSame ? Icons.check : Icons.compare_arrows,
                  size: 18,
                  color: isSame ? colorScheme.primary : colorScheme.error,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MetadataValue(value: normalizedFirst, isDifferent: !isSame),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetadataValue(value: normalizedSecond, isDifferent: !isSame),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataValue extends StatelessWidget {
  const _MetadataValue({
    required this.value,
    required this.isDifferent,
  });

  final String value;
  final bool isDifferent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDifferent ? colorScheme.errorContainer.withValues(alpha: 0.32) : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          value,
          minLines: 1,
          style: TextStyle(
            color: isDifferent ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _TagsComparison extends StatelessWidget {
  const _TagsComparison({
    required this.first,
    required this.second,
    required this.onlyDifferences,
  });

  final BooruItem first;
  final BooruItem second;
  final bool onlyDifferences;

  @override
  Widget build(BuildContext context) {
    final comparison = _compareTags(first, second);
    final hasDifferences = comparison.onlyFirst.isNotEmpty || comparison.onlySecond.isNotEmpty;

    return _CompareDataPanel(
      title: 'Tags',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onlyDifferences && !hasDifferences)
            const _EmptyCompareText()
          else ...[
            if (!onlyDifferences) ...[
              _TagGroup(title: 'Common (${comparison.common.length})', tags: comparison.common),
              const SizedBox(height: 12),
            ],
            _TagGroup(title: 'Only first (${comparison.onlyFirst.length})', tags: comparison.onlyFirst),
            const SizedBox(height: 12),
            _TagGroup(title: 'Only second (${comparison.onlySecond.length})', tags: comparison.onlySecond),
          ],
        ],
      ),
    );
  }
}

class _EmptyCompareText extends StatelessWidget {
  const _EmptyCompareText();

  @override
  Widget build(BuildContext context) {
    return Text(
      'None',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({
    required this.title,
    required this.tags,
  });

  final String title;
  final List<_ComparableTag> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        if (tags.isEmpty)
          Text(
            'None',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          )
        else
          ..._groupTagsByType(tags).entries.map(
            (entry) => _TagTypeGroup(
              type: entry.key,
              tags: entry.value,
            ),
          ),
      ],
    );
  }
}

class _TagTypeGroup extends StatelessWidget {
  const _TagTypeGroup({
    required this.type,
    required this.tags,
  });

  final TagType type;
  final List<_ComparableTag> tags;

  @override
  Widget build(BuildContext context) {
    final typeColor = type.getColour();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${type.locName} (${tags.length})',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: typeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text(tag.name),
                  labelStyle: TextStyle(
                    color: tag.color,
                    fontSize: 12,
                    fontWeight: tag.color == null ? FontWeight.normal : FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tag.color?.withValues(alpha: 0.16),
                  side: BorderSide(color: tag.color ?? Theme.of(context).dividerColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareDataPanel extends StatelessWidget {
  const _CompareDataPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ComparableTag {
  const _ComparableTag({
    required this.name,
    required this.type,
    required this.color,
  });

  final String name;
  final TagType type;
  final Color? color;
}

({List<_ComparableTag> common, List<_ComparableTag> onlyFirst, List<_ComparableTag> onlySecond}) _compareTags(
  BooruItem first,
  BooruItem second,
) {
  final firstTags = _tagMap(first);
  final secondTags = _tagMap(second);
  final firstKeys = firstTags.keys.toSet();
  final secondKeys = secondTags.keys.toSet();

  List<_ComparableTag> selectTags(Iterable<String> keys, Map<String, _ComparableTag> source) {
    return keys.map((key) => source[key]!).toList()..sort(_compareComparableTags);
  }

  return (
    common: selectTags(firstKeys.intersection(secondKeys), firstTags),
    onlyFirst: selectTags(firstKeys.difference(secondKeys), firstTags),
    onlySecond: selectTags(secondKeys.difference(firstKeys), secondTags),
  );
}

Map<String, _ComparableTag> _tagMap(BooruItem item) {
  final tagHandler = TagHandler.instance;
  return {
    for (final tag in item.tagsList) tag.fullString.toLowerCase(): _comparableTag(tag, tagHandler),
  };
}

_ComparableTag _comparableTag(Tag tag, TagHandler tagHandler) {
  final cachedType = tag.tagType.isNone ? tagHandler.getTag(tag.fullString).tagType : tag.tagType;
  final type = tag.tagType.isNone && !cachedType.isNone ? cachedType : tag.tagType;

  return _ComparableTag(
    name: tag.fullString,
    type: type,
    color: type.getColour(),
  );
}

int _compareComparableTags(_ComparableTag a, _ComparableTag b) {
  final typeComparison = _tagTypeSortOrder(a.type).compareTo(_tagTypeSortOrder(b.type));
  if (typeComparison != 0) {
    return typeComparison;
  }

  return a.name.compareTo(b.name);
}

Map<TagType, List<_ComparableTag>> _groupTagsByType(List<_ComparableTag> tags) {
  final grouped = <TagType, List<_ComparableTag>>{};
  for (final tag in tags) {
    grouped.putIfAbsent(tag.type, () => []).add(tag);
  }

  final sortedEntries = grouped.entries.toList()
    ..sort((a, b) => _tagTypeSortOrder(a.key).compareTo(_tagTypeSortOrder(b.key)));

  return {
    for (final entry in sortedEntries) entry.key: entry.value..sort(_compareComparableTags),
  };
}

int _tagTypeSortOrder(TagType type) {
  return switch (type) {
    TagType.artist => 0,
    TagType.character => 1,
    TagType.copyright => 2,
    TagType.species => 3,
    TagType.meta => 4,
    TagType.none => 5,
  };
}

String _normalizeCompareValue(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty || normalized == 'null') {
    return '-';
  }

  return normalized;
}

String? _formatDimensions(double? width, double? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }

  return '${width.round()}x${height.round()}';
}

class _DifferenceModeSwatch extends StatelessWidget {
  const _DifferenceModeSwatch({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
          gradient: LinearGradient(colors: colors),
        ),
      ),
    );
  }
}

class _BackgroundToggle extends StatelessWidget {
  const _BackgroundToggle({
    required this.selected,
    required this.onChanged,
  });

  final _CompareBackground selected;
  final ValueChanged<_CompareBackground> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_CompareBackground>(
      segments: const [
        ButtonSegment(
          value: _CompareBackground.black,
          tooltip: 'Black',
          icon: Icon(Icons.dark_mode),
        ),
        ButtonSegment(
          value: _CompareBackground.white,
          tooltip: 'White',
          icon: Icon(Icons.light_mode),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({
    required this.mode,
    required this.modes,
    required this.width,
    required this.onModeChanged,
  });

  final _ImageCompareMode mode;
  final List<_ImageCompareMode> modes;
  final double width;
  final ValueChanged<_ImageCompareMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
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
              return modes.map((mode) {
                return _CompareModeDropdownItem(mode: mode);
              }).toList();
            },
            items: modes.map((mode) {
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
    );
  }
}

class _AxisToggle extends StatelessWidget {
  const _AxisToggle({
    required this.selected,
    required this.onChanged,
  });

  final Axis selected;
  final ValueChanged<Axis> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<Axis>(
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
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
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
      _ImageCompareMode.data => Icons.dataset,
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
      _ImageCompareMode.data => context.loc.settings.downloads.compareData,
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
    required this.topInset,
    required this.bottomInset,
    required this.onTap,
  });

  final Axis axis;
  final bool isBeforeViewport;
  final double topInset;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    final icon = isHorizontal
        ? (isBeforeViewport ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right)
        : (isBeforeViewport ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down);

    return Positioned(
      left: isHorizontal ? (isBeforeViewport ? 12 : null) : 0,
      right: isHorizontal ? (!isBeforeViewport ? 12 : null) : 0,
      top: isHorizontal ? topInset : (isBeforeViewport ? topInset + 12 : null),
      bottom: isHorizontal ? bottomInset : (!isBeforeViewport ? bottomInset + 12 : null),
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
    required this.onTap,
  });

  final TransformationController controller;
  final Widget child;
  final VoidCallback onTap;

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
      onTap: widget.onTap,
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

class _ImageCompareResolutionTitle extends StatelessWidget {
  const _ImageCompareResolutionTitle({
    required this.first,
    required this.second,
    required this.color,
  });

  final BooruItem first;
  final BooruItem second;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final firstResolution = _formatResolution(first);
    final secondResolution = _formatResolution(second);
    if (firstResolution == null && secondResolution == null) {
      return const SizedBox.shrink();
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '${firstResolution ?? '?'}  /  ${secondResolution ?? '?'}',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ).copyWith(color: color),
      ),
    );
  }
}

Color _foregroundForCompareBackground(BuildContext context, _ImageCompareMode mode, _CompareBackground background) {
  if (mode == _ImageCompareMode.data) {
    return Theme.of(context).colorScheme.onSurface;
  }

  final isRenderedMode = mode == _ImageCompareMode.difference || mode == _ImageCompareMode.heatmap;
  if (isRenderedMode && background == _CompareBackground.white) {
    return Colors.black;
  }

  return Colors.white;
}

String? _formatResolution(BooruItem item) {
  final width = item.fileWidth ?? item.sampleWidth ?? item.previewWidth;
  final height = item.fileHeight ?? item.sampleHeight ?? item.previewHeight;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }

  return '${width.round()}x${height.round()}';
}

class _InteractiveCompareImage extends StatelessWidget {
  const _InteractiveCompareImage({
    required this.item,
    required this.booru,
    required this.providerFuture,
    required this.controller,
    required this.onTap,
  });

  final BooruItem item;
  final Booru booru;
  final Future<ImageProvider> providerFuture;
  final TransformationController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _DoubleTapInteractiveViewer(
          controller: controller,
          onTap: onTap,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: _CompareImage(
              item: item,
              booru: booru,
              providerFuture: providerFuture,
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
    required this.firstProviderFuture,
    required this.secondItem,
    required this.secondBooru,
    required this.secondProviderFuture,
    required this.mode,
    required this.differenceColorMode,
    required this.background,
    required this.badgeBottomInset,
  });

  final BooruItem firstItem;
  final Booru firstBooru;
  final Future<ImageProvider> firstProviderFuture;
  final BooruItem secondItem;
  final Booru secondBooru;
  final Future<ImageProvider> secondProviderFuture;
  final _RenderedCompareMode mode;
  final _DifferenceColorMode differenceColorMode;
  final _CompareBackground background;
  final double badgeBottomInset;

  @override
  State<_RenderedCompareView> createState() => _RenderedCompareViewState();
}

class _RenderedCompareViewState extends State<_RenderedCompareView> {
  late Future<({ui.Image first, ui.Image second, ui.Image? heatmap, double? matchPercent})> imagesFuture =
      _loadImages();

  @override
  void didUpdateWidget(covariant _RenderedCompareView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstItem != widget.firstItem ||
        oldWidget.firstBooru != widget.firstBooru ||
        oldWidget.firstProviderFuture != widget.firstProviderFuture ||
        oldWidget.secondItem != widget.secondItem ||
        oldWidget.secondBooru != widget.secondBooru ||
        oldWidget.secondProviderFuture != widget.secondProviderFuture ||
        oldWidget.mode != widget.mode) {
      imagesFuture = _loadImages();
    }
  }

  Future<({ui.Image first, ui.Image second, ui.Image? heatmap, double? matchPercent})> _loadImages() async {
    final firstProvider = await widget.firstProviderFuture;
    final secondProvider = await widget.secondProviderFuture;
    final first = await _resolveImage(firstProvider);
    final second = await _resolveImage(secondProvider);

    if (widget.mode == _RenderedCompareMode.heatmap) {
      final heatmap = await _buildHeatmapImage(first, second);
      return (
        first: first,
        second: second,
        heatmap: heatmap.image,
        matchPercent: heatmap.matchPercent,
      );
    }

    return (
      first: first,
      second: second,
      heatmap: null,
      matchPercent: await _calculateMatchPercent(first, second),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<({ui.Image first, ui.Image second, ui.Image? heatmap, double? matchPercent})>(
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

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _RenderedComparePainter(
                  first: snapshot.data!.first,
                  second: snapshot.data!.second,
                  heatmap: snapshot.data!.heatmap,
                  mode: widget.mode,
                  differenceColorMode: widget.differenceColorMode,
                  background: widget.background,
                ),
              ),
              if (snapshot.data!.matchPercent != null)
                Positioned(
                  left: 16,
                  bottom: widget.badgeBottomInset + 16,
                  child: _MatchPercentBadge(matchPercent: snapshot.data!.matchPercent!),
                ),
            ],
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
    required this.background,
  });

  final ui.Image first;
  final ui.Image second;
  final ui.Image? heatmap;
  final _RenderedCompareMode mode;
  final _DifferenceColorMode differenceColorMode;
  final _CompareBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    _drawCompareBackground(canvas, bounds, background);

    switch (mode) {
      case _RenderedCompareMode.difference:
        final firstDestination = _containedDestination(first, size);
        final secondDestination = _containedDestination(second, size);
        final comparisonBounds = firstDestination.intersect(secondDestination);
        if (comparisonBounds.isEmpty) {
          return;
        }

        canvas.saveLayer(comparisonBounds, _differenceLayerPaint(differenceColorMode));
        canvas.clipRect(comparisonBounds);
        _drawImageToDestination(
          canvas,
          first,
          firstDestination,
          Paint()..filterQuality = FilterQuality.high,
        );
        _drawImageToDestination(
          canvas,
          second,
          secondDestination,
          Paint()
            ..filterQuality = FilterQuality.high
            ..blendMode = BlendMode.difference,
        );
        canvas.restore();
      case _RenderedCompareMode.heatmap:
        final heatmapImage = heatmap;
        if (heatmapImage == null) {
          return;
        }
        _drawContainedImage(
          canvas,
          heatmapImage,
          size,
          Paint()..filterQuality = FilterQuality.high,
        );
    }
  }

  void _drawContainedImage(
    Canvas canvas,
    ui.Image image,
    Size size,
    Paint paint,
  ) {
    _drawImageToDestination(
      canvas,
      image,
      _containedDestination(image, size),
      paint,
    );
  }

  Rect _containedDestination(ui.Image image, Size size) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      size,
    );

    return Alignment.center.inscribe(fitted.destination, Offset.zero & size);
  }

  void _drawImageToDestination(Canvas canvas, ui.Image image, Rect destination, Paint paint) {
    final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

    canvas.drawImageRect(image, source, destination, paint);
  }

  @override
  bool shouldRepaint(covariant _RenderedComparePainter oldDelegate) {
    return oldDelegate.first != first ||
        oldDelegate.second != second ||
        oldDelegate.heatmap != heatmap ||
        oldDelegate.mode != mode ||
        oldDelegate.differenceColorMode != differenceColorMode ||
        oldDelegate.background != background;
  }
}

class _MatchPercentBadge extends StatelessWidget {
  const _MatchPercentBadge({required this.matchPercent});

  final double matchPercent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '${matchPercent.toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

void _drawCompareBackground(Canvas canvas, Rect bounds, _CompareBackground background) {
  switch (background) {
    case _CompareBackground.black:
      canvas.drawRect(bounds, Paint()..color = Colors.black);
    case _CompareBackground.white:
      canvas.drawRect(bounds, Paint()..color = Colors.white);
  }
}

Paint _differenceLayerPaint(_DifferenceColorMode colorMode) {
  return switch (colorMode) {
    _DifferenceColorMode.raw =>
      Paint()
        ..colorFilter = const ColorFilter.matrix([
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0.299,
          0.587,
          0.114,
          0,
          0,
        ]),
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
          0.299,
          0.587,
          0.114,
          0,
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
          0.299,
          0.587,
          0.114,
          0,
          0,
        ]),
  };
}

Future<({ui.Image image, double matchPercent})> _buildHeatmapImage(ui.Image first, ui.Image second) async {
  final firstBytes = await first.toByteData(format: ui.ImageByteFormat.rawRgba);
  final secondBytes = await second.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (firstBytes == null || secondBytes == null) {
    throw StateError('Unable to read image pixels for heatmap comparison');
  }

  final (:width, :height, :firstList, :secondList) = _comparisonPixelData(
    first: first,
    second: second,
    firstBytes: firstBytes,
    secondBytes: secondBytes,
  );
  final output = Uint8List(width * height * 4);
  double intensitySum = 0;

  for (var y = 0; y < height; y++) {
    final firstY = ((y + 0.5) * first.height / height) - 0.5;
    final secondY = ((y + 0.5) * second.height / height) - 0.5;

    for (var x = 0; x < width; x++) {
      final firstX = ((x + 0.5) * first.width / width) - 0.5;
      final secondX = ((x + 0.5) * second.width / width) - 0.5;
      final firstPixel = _sampleRgbaBilinear(firstList, first.width, first.height, firstX, firstY);
      final secondPixel = _sampleRgbaBilinear(secondList, second.width, second.height, secondX, secondY);
      final outputOffset = (y * width + x) * 4;

      final redDelta = (firstPixel.$1 - secondPixel.$1).abs();
      final greenDelta = (firstPixel.$2 - secondPixel.$2).abs();
      final blueDelta = (firstPixel.$3 - secondPixel.$3).abs();
      final alphaDelta = (firstPixel.$4 - secondPixel.$4).abs();
      final distance =
          ((redDelta * redDelta * 0.299) +
              (greenDelta * greenDelta * 0.587) +
              (blueDelta * blueDelta * 0.114) +
              (alphaDelta * alphaDelta * 0.25)) /
          (255 * 255 * 1.25);
      final intensity = distance.clamp(0.0, 1.0);
      intensitySum += intensity;
      final color = _heatmapColor(intensity);

      output[outputOffset] = color.$1;
      output[outputOffset + 1] = color.$2;
      output[outputOffset + 2] = color.$3;
      output[outputOffset + 3] = intensity < 0.015 ? 0 : 255;
    }

    if (y % 32 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  return (
    image: ui.decodeImageFromPixelsSync(output, width, height, ui.PixelFormat.rgba8888),
    matchPercent: (1 - (intensitySum / (width * height))).clamp(0.0, 1.0) * 100,
  );
}

Future<double> _calculateMatchPercent(ui.Image first, ui.Image second) async {
  final firstBytes = await first.toByteData(format: ui.ImageByteFormat.rawRgba);
  final secondBytes = await second.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (firstBytes == null || secondBytes == null) {
    throw StateError('Unable to read image pixels for match comparison');
  }

  final (:width, :height, :firstList, :secondList) = _comparisonPixelData(
    first: first,
    second: second,
    firstBytes: firstBytes,
    secondBytes: secondBytes,
  );
  double intensitySum = 0;

  for (var y = 0; y < height; y++) {
    final firstY = ((y + 0.5) * first.height / height) - 0.5;
    final secondY = ((y + 0.5) * second.height / height) - 0.5;

    for (var x = 0; x < width; x++) {
      final firstX = ((x + 0.5) * first.width / width) - 0.5;
      final secondX = ((x + 0.5) * second.width / width) - 0.5;
      final firstPixel = _sampleRgbaBilinear(firstList, first.width, first.height, firstX, firstY);
      final secondPixel = _sampleRgbaBilinear(secondList, second.width, second.height, secondX, secondY);
      final redDelta = (firstPixel.$1 - secondPixel.$1).abs();
      final greenDelta = (firstPixel.$2 - secondPixel.$2).abs();
      final blueDelta = (firstPixel.$3 - secondPixel.$3).abs();
      final alphaDelta = (firstPixel.$4 - secondPixel.$4).abs();
      intensitySum +=
          ((redDelta * redDelta * 0.299) +
              (greenDelta * greenDelta * 0.587) +
              (blueDelta * blueDelta * 0.114) +
              (alphaDelta * alphaDelta * 0.25)) /
          (255 * 255 * 1.25);
    }

    if (y % 32 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  return (1 - (intensitySum / (width * height))).clamp(0.0, 1.0) * 100;
}

({
  int width,
  int height,
  Uint8List firstList,
  Uint8List secondList,
})
_comparisonPixelData({
  required ui.Image first,
  required ui.Image second,
  required ByteData firstBytes,
  required ByteData secondBytes,
}) {
  const maxSide = 4096;
  const maxPixels = 6 * 1024 * 1024;
  final sourceWidth = math.max(first.width, second.width);
  final sourceHeight = math.max(first.height, second.height);
  final sideScale = maxSide / math.max(sourceWidth, sourceHeight);
  final pixelScale = math.sqrt(maxPixels / (sourceWidth * sourceHeight));
  final scale = math.min(1, math.min(sideScale, pixelScale));

  return (
    width: math.max(1, (sourceWidth * scale).round()),
    height: math.max(1, (sourceHeight * scale).round()),
    firstList: firstBytes.buffer.asUint8List(),
    secondList: secondBytes.buffer.asUint8List(),
  );
}

(double, double, double, double) _sampleRgbaBilinear(Uint8List pixels, int width, int height, double x, double y) {
  final x0 = x.floor().clamp(0, width - 1);
  final y0 = y.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);
  final tx = (x - x0).clamp(0.0, 1.0);
  final ty = (y - y0).clamp(0.0, 1.0);

  final topLeft = (y0 * width + x0) * 4;
  final topRight = (y0 * width + x1) * 4;
  final bottomLeft = (y1 * width + x0) * 4;
  final bottomRight = (y1 * width + x1) * 4;

  double channel(int offset) {
    final top = pixels[topLeft + offset] * (1 - tx) + pixels[topRight + offset] * tx;
    final bottom = pixels[bottomLeft + offset] * (1 - tx) + pixels[bottomRight + offset] * tx;
    return top * (1 - ty) + bottom * ty;
  }

  return (
    channel(0),
    channel(1),
    channel(2),
    channel(3),
  );
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
    required this.providerFuture,
    this.opacity = 1,
    this.drawBackground = true,
  });

  final BooruItem item;
  final Booru booru;
  final Future<ImageProvider> providerFuture;
  final double opacity;
  final bool drawBackground;

  @override
  State<_CompareImage> createState() => _CompareImageState();
}

class _CompareImageState extends State<_CompareImage> {
  late Future<ImageProvider> providerFuture = widget.providerFuture;
  Object? imageLoadError;

  @override
  void didUpdateWidget(covariant _CompareImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.providerFuture != widget.providerFuture) {
      providerFuture = widget.providerFuture;
      imageLoadError = null;
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
              if (imageLoadError != null) {
                return _CompareImageError(
                  details: imageLoadError.toString(),
                );
              }

              return Image(
                image: snapshot.data!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  final expectedBytes = loadingProgress.expectedTotalBytes;
                  final progress = expectedBytes == null ? null : loadingProgress.cumulativeBytesLoaded / expectedBytes;

                  return Center(
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(value: progress),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && imageLoadError == null) {
                      setState(() {
                        imageLoadError = error;
                      });
                    }
                  });
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
  final isAvif = url.contains('.avif');

  return isAvif
      ? CustomNetworkAvifImage(
          url,
          headers: headers,
          withCache: SX.mediaCache.value,
          cacheFolder: 'media',
          fileNameExtras: item.fileNameExtras,
          withCaptchaCheck: true,
        )
      : CustomNetworkImage(
          url,
          headers: headers,
          withCache: SX.mediaCache.value,
          cacheFolder: 'media',
          fileNameExtras: item.fileNameExtras,
          withCaptchaCheck: true,
        );
}

Future<ImageProvider> _buildCompareThumbnailProvider(BooruItem item, Booru booru) async {
  final url = item.thumbnailURL.isNotEmpty ? item.thumbnailURL : item.sampleURL;
  if (url.trim().isEmpty) {
    throw StateError('No thumbnail URL found for selected item');
  }

  final headers = await Tools.getFileCustomHeaders(
    booru,
    item: item,
    checkForReferer: true,
  );

  return CustomNetworkImage(
    url,
    headers: headers,
    withCache: SX.thumbnailCache.value,
    cacheFolder: 'thumbnails',
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
