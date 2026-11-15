import 'package:flutter/material.dart';

/// Keeps an outline visible, preferring its own color, then theme accents.
Color contrastingThemeColor(
  ColorScheme scheme, {
  required Color background,
  Color? preferred,
  Color? adjacentBackground,
}) {
  final surface = Color.alphaBlend(scheme.surface, scheme.brightness == Brightness.dark ? Colors.black : Colors.white);
  final backgrounds = [
    Color.alphaBlend(background, surface),
    if (adjacentBackground != null) Color.alphaBlend(adjacentBackground, surface),
  ];

  double contrast(Color color) {
    return backgrounds
        .map((background) {
          final foregroundLuminance = Color.alphaBlend(color, background).computeLuminance();
          final backgroundLuminance = background.computeLuminance();
          final lighter = foregroundLuminance > backgroundLuminance ? foregroundLuminance : backgroundLuminance;
          final darker = foregroundLuminance < backgroundLuminance ? foregroundLuminance : backgroundLuminance;
          return (lighter + 0.05) / (darker + 0.05);
        })
        .reduce((a, b) => a < b ? a : b);
  }

  for (final color in [?preferred, scheme.primary, scheme.secondary, scheme.onSurface]) {
    if (contrast(color) >= 3) return color;
  }
  return contrast(Colors.black) >= contrast(Colors.white) ? Colors.black : Colors.white;
}
