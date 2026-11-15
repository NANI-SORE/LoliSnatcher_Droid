import 'package:flutter/material.dart';
import 'package:lolisnatcher/gen/strings.g.dart';

@immutable
class ThemeItem {
  const ThemeItem({
    required this.name,
    required this.primary,
    required this.accent,
  });

  final String name;
  // Flutters Colors.color should be used instead of using Color(0xFFhexcolour) because it breaks the light/dark mode on the text and icons for some reason
  final Color? primary;
  final Color? accent;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ThemeItem && other.name == name;

  @override
  int get hashCode => name.hashCode;

  String locName(BuildContext context) => context.loc['settings.theme.${name.toLowerCase()}'];
}
