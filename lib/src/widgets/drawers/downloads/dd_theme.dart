import 'package:flutter/material.dart';

// User-selected accents are not necessarily readable on drawer/card surfaces.
ThemeData downloadDrawerTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  final background = colors.surface;
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  Color readable(Color preferred, Color surface) {
    if (contrast(preferred, surface) >= 4.5) return preferred;
    return contrast(Colors.white, surface) > contrast(Colors.black, surface) ? Colors.white : Colors.black;
  }

  final foreground = readable(colors.onSurface, background);
  final accent = readable(colors.primary, background);
  final error = readable(
    ColorScheme.fromSeed(seedColor: colors.primary, brightness: colors.brightness).error,
    background,
  );
  final enabledColor = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.disabled) ? foreground.withValues(alpha: .38) : accent,
  );
  return theme.copyWith(
    colorScheme: colors.copyWith(primary: accent, onSurface: foreground, error: error),
    textTheme: theme.textTheme.apply(bodyColor: foreground, displayColor: foreground),
    iconTheme: theme.iconTheme.copyWith(color: foreground),
    iconButtonTheme: IconButtonThemeData(
      style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
        foregroundColor: enabledColor,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        foregroundColor: enabledColor,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? null : accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? null : readable(colors.onPrimary, accent),
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? null : readable(colors.onPrimary, accent),
        ),
      ),
    ),
    cardTheme: theme.cardTheme.copyWith(color: background, surfaceTintColor: Colors.transparent),
    chipTheme: theme.chipTheme.copyWith(
      backgroundColor: background,
      selectedColor: colors.secondaryContainer,
      labelStyle: theme.textTheme.labelLarge?.copyWith(color: foreground),
      secondaryLabelStyle: theme.textTheme.labelLarge?.copyWith(
        color: readable(colors.onSecondaryContainer, colors.secondaryContainer),
      ),
      checkmarkColor: readable(colors.onSecondaryContainer, colors.secondaryContainer),
    ),
    progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
      color: accent,
      linearTrackColor: foreground.withValues(alpha: .12),
      circularTrackColor: foreground.withValues(alpha: .12),
    ),
  );
}
