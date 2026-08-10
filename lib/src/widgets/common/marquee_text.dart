import 'package:flutter/material.dart';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:fast_marquee/fast_marquee.dart';

// Based on code from: https://github.com/nt4f04uNd/nt4f04unds_widgets/blob/f14e448d23d347f17c05549972e638d61cf300b4/lib/src/widgets/marquee.dart

class MarqueeText extends StatelessWidget {
  const MarqueeText({
    required this.text,
    this.style,
    this.velocity = 45.0,
    this.curve = Curves.linear,
    this.blankSpace = 50.0,
    this.startPadding = 0.0,
    this.startAfter = const Duration(milliseconds: 1000),
    this.pauseAfterRound = const Duration(milliseconds: 1500),
    this.isExpanded = true,
    this.reverse = false,
    this.allowDownscale = true,
    this.fadingEdgeStartFraction = 0,
    this.fadingEdgeEndFraction = 0.15,
    super.key,
  }) : textSpan = null;

  const MarqueeText.rich({
    required this.textSpan,
    this.style,
    this.velocity = 45.0,
    this.curve = Curves.linear,
    this.blankSpace = 50.0,
    this.startPadding = 0.0,
    this.startAfter = const Duration(milliseconds: 1000),
    this.pauseAfterRound = const Duration(milliseconds: 1500),
    this.isExpanded = true,
    this.reverse = false,
    this.allowDownscale = true,
    this.fadingEdgeStartFraction = 0,
    this.fadingEdgeEndFraction = 0.15,
    super.key,
  }) : text = null;

  final String? text;
  final TextStyle? style;
  final TextSpan? textSpan;
  final double velocity;
  final Curve curve;
  final double blankSpace;
  final double startPadding;
  final Duration startAfter;
  final Duration pauseAfterRound;
  final bool isExpanded;
  final bool reverse;
  final bool allowDownscale;
  final double fadingEdgeStartFraction;
  final double fadingEdgeEndFraction;

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(child: innerBox(context));

    if (isExpanded) {
      return Expanded(child: child);
    }

    return child;
  }

  Widget innerBox(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final usedStyle = (style ?? defaultStyle).copyWith(
      height: 1,
    );
    final double fontSize = usedStyle.fontSize ?? 16;

    // Presets avoid auto_size_text_plus' exact floating-point modulo check for
    // minFontSize/stepGranularity (for example, 18.7 / 0.1).
    final presetFontSizes = allowDownscale ? _fontSizePresets(fontSize) : [fontSize];

    if (textSpan != null) {
      return Container(
        alignment: Alignment.centerLeft,
        child: AutoSizeText.rich(
          textSpan!,
          presetFontSizes: presetFontSizes,
          maxLines: 1,
          style: usedStyle,
          overflowReplacement: Marquee.rich(
            textSpan: textSpan,
            blankSpace: blankSpace,
            curve: curve,
            velocity: velocity,
            startPadding: startPadding,
            fadingEdgeStartFraction: fadingEdgeStartFraction,
            fadingEdgeEndFraction: fadingEdgeEndFraction,
            reverse: reverse,
            showFadingOnlyWhenScrolling: false,
            startAfter: startAfter,
            pauseAfterRound: pauseAfterRound,
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.centerLeft,
      child: AutoSizeText(
        text!,
        presetFontSizes: presetFontSizes,
        maxLines: 1,
        style: usedStyle,
        overflowReplacement: Marquee(
          text: text,
          blankSpace: blankSpace,
          curve: curve,
          velocity: velocity,
          startPadding: startPadding,
          fadingEdgeStartFraction: fadingEdgeStartFraction,
          fadingEdgeEndFraction: fadingEdgeEndFraction,
          reverse: reverse,
          showFadingOnlyWhenScrolling: false,
          startAfter: startAfter,
          pauseAfterRound: pauseAfterRound,
          style: usedStyle,
        ),
      ),
    );
  }

  List<double> _fontSizePresets(double maxFontSize) {
    const step = 0.1;
    final minFontSize = maxFontSize * 0.85;
    final presets = <double>[maxFontSize];

    for (var size = maxFontSize - step; size > minFontSize; size -= step) {
      presets.add(size);
    }
    presets.add(minFontSize);

    return presets;
  }
}
