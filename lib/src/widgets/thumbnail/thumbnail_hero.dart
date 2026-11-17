import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Keeps a thumbnail mounted while its already decoded image flies between routes.
class ThumbnailHero extends StatefulWidget {
  const ThumbnailHero({required this.tag, required this.child, super.key})
    : isViewerPreview = false,
      keepFlightImage = false,
      obscureFlightImage = false;

  const ThumbnailHero.preview({
    required this.tag,
    required this.child,
    required this.keepFlightImage,
    this.obscureFlightImage = false,
    super.key,
  }) : isViewerPreview = true;

  final Object tag;
  final Widget child;
  final bool isViewerPreview;
  final bool keepFlightImage;
  final bool obscureFlightImage;

  @override
  State<ThumbnailHero> createState() => _ThumbnailHeroState();
}

class _ThumbnailHeroState extends State<ThumbnailHero> {
  final _childKey = GlobalKey();
  _ThumbnailSnapshot? _flightImage;

  void _holdFlightImage(_ThumbnailSnapshot snapshot) {
    final image = snapshot.clone();
    final tag = widget.tag;
    // The shuttle is built in the overlay. Update the destination after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.keepFlightImage || widget.tag != tag) {
        image.dispose();
        return;
      }
      setState(() {
        _releaseFlightImage();
        _flightImage = image;
      });
    });
  }

  void _releaseFlightImage() {
    final image = _flightImage;
    _flightImage = null;
    if (image != null) WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  void didUpdateWidget(ThumbnailHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.keepFlightImage || widget.tag != oldWidget.tag) _releaseFlightImage();
  }

  @override
  void dispose() {
    _releaseFlightImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tag,
      // Hero uses a different subtree for placeholders. Preserve the image's
      // state and stream instead of disposing and loading it at each endpoint.
      placeholderBuilder: (context, size, child) => child,
      // The grid supplies the flight in both directions. A cold viewer preview
      // has no decoded pixels of its own yet.
      flightShuttleBuilder: widget.isViewerPreview
          ? null
          : (context, animation, direction, from, to) => _ThumbnailFlight(
              key: UniqueKey(),
              source: _childKey,
              destination: direction == HeroFlightDirection.push
                  ? to.findAncestorStateOfType<_ThumbnailHeroState>()
                  : null,
              fit: direction == HeroFlightDirection.push ? BoxFit.contain : BoxFit.cover,
              fallback: widget.child,
            ),
      child: KeyedSubtree(
        key: _childKey,
        child: widget.isViewerPreview
            ? Stack(
                fit: StackFit.expand,
                children: [
                  _flightImage?.build(BoxFit.contain, obscure: widget.obscureFlightImage) ?? const SizedBox.shrink(),
                  widget.child,
                ],
              )
            : widget.child,
      ),
    );
  }
}

class _ThumbnailFlight extends StatefulWidget {
  const _ThumbnailFlight({
    required this.source,
    required this.destination,
    required this.fit,
    required this.fallback,
    super.key,
  });

  final GlobalKey source;
  final _ThumbnailHeroState? destination;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<_ThumbnailFlight> createState() => _ThumbnailFlightState();
}

class _ThumbnailFlightState extends State<_ThumbnailFlight> {
  _ThumbnailSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _ThumbnailSnapshot.capture(widget.source.currentContext);
    final snapshot = _snapshot;
    if (snapshot != null) widget.destination?._holdFlightImage(snapshot);
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _snapshot?.build(
        widget.fit,
        obscure: widget.destination?.widget.obscureFlightImage ?? false,
      ) ??
      widget.fallback;
}

class _ThumbnailSnapshot {
  _ThumbnailSnapshot(this.image, this.raw, this.filters);

  final ui.Image image;
  final RawImage raw;
  final List<ui.ImageFilter> filters;

  static _ThumbnailSnapshot? capture(BuildContext? context) {
    RawImage? source;
    var filters = <ui.ImageFilter>[];
    void visit(Element element, List<ui.ImageFilter> ancestors) {
      final child = element.widget;
      final next = child is ImageFiltered && child.enabled ? [...ancestors, child.imageFilter] : ancestors;
      if (child is RawImage && child.image != null) {
        // The optional low quality image is painted before the main image.
        source = child;
        filters = next;
      }
      element.visitChildren((element) => visit(element, next));
    }

    if (context is Element) visit(context, const []);
    final raw = source;
    if (raw == null) return null;

    // Clone only the handle, not the pixels. The flight owns it independently
    // of the grid's notifiers, animation frames and route lifetime.
    return _ThumbnailSnapshot(raw.image!.clone(), raw, filters);
  }

  _ThumbnailSnapshot clone() => _ThumbnailSnapshot(image.clone(), raw, filters);

  void dispose() => image.dispose();

  Widget build(BoxFit fit, {bool obscure = false}) {
    Widget snapshot = RawImage(
      image: image,
      scale: raw.scale,
      width: double.infinity,
      height: double.infinity,
      fit: fit,
      alignment: raw.alignment,
      color: raw.color,
      colorBlendMode: raw.colorBlendMode,
      repeat: raw.repeat,
      centerSlice: raw.centerSlice,
      matchTextDirection: raw.matchTextDirection,
      invertColors: raw.invertColors,
      filterQuality: raw.filterQuality,
      isAntiAlias: raw.isAntiAlias,
    );
    // Preserve the actual blur filters as well as pixelated decoded images.
    for (final filter in filters.reversed) {
      snapshot = ImageFiltered(imageFilter: filter, child: snapshot);
    }
    // A reveal in the grid does not reveal the viewer. Its current policy also
    // applies to the retained pixels, including changes after the flight.
    if (obscure) {
      snapshot = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: ui.TileMode.decal),
        child: snapshot,
      );
    }
    return snapshot;
  }
}
