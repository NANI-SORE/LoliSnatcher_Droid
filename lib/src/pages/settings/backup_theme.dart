import 'package:flutter/material.dart';

class BackupControlsTheme extends StatelessWidget {
  const BackupControlsTheme({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final actionColor = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.38) : colors.secondary,
    );
    final filledForeground = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.38) : colors.onSecondary,
    );
    WidgetStateProperty<Color?> overlay(Color color) => WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return null;
      if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.12);
      }
      return states.contains(WidgetState.hovered) ? color.withValues(alpha: 0.08) : null;
    });
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: actionColor,
            iconColor: actionColor,
            overlayColor: overlay(colors.secondary),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: actionColor,
            iconColor: actionColor,
            overlayColor: overlay(colors.secondary),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.12) : colors.secondary,
            ),
            foregroundColor: filledForeground,
            iconColor: filledForeground,
            overlayColor: overlay(colors.onSecondary),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.38) : colors.onSurface,
            ),
            overlayColor: overlay(colors.onSurface),
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          iconColor: WidgetStateColor.resolveWith(
            (states) =>
                states.contains(WidgetState.disabled) ? colors.onSurface.withValues(alpha: 0.38) : colors.onSurface,
          ),
          selectedColor: colors.secondary,
        ),
        expansionTileTheme: theme.expansionTileTheme.copyWith(
          iconColor: colors.onSurface,
          collapsedIconColor: colors.onSurface,
          textColor: colors.onSurface,
          collapsedTextColor: colors.onSurface,
        ),
      ),
      child: child,
    );
  }
}

class BackupDropdown<T> extends StatelessWidget {
  const BackupDropdown({
    required this.initialValue,
    required this.decoration,
    required this.items,
    required this.onChanged,
    this.isExpanded = true,
    super.key,
  });

  final T initialValue;
  final InputDecoration decoration;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      isExpanded: isExpanded,
      decoration: decoration,
      items: items,
      onChanged: onChanged,
      dropdownColor: colors.surfaceContainerHigh,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: onChanged == null ? colors.onSurface.withValues(alpha: 0.38) : colors.onSurface,
      ),
      iconEnabledColor: colors.onSurface,
      iconDisabledColor: colors.onSurface.withValues(alpha: 0.38),
    );
  }
}
