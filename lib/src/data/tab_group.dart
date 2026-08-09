import 'dart:ui';

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

class TabGroup {
  TabGroup({
    required String name,
    required Color color,
    String? id,
    bool collapsed = false,
  }) : id = id ?? const Uuid().v4(),
       name = name.obs,
       color = color.obs,
       collapsed = collapsed.obs;

  final String id;
  final Rx<String> name;
  final Rx<Color> color;
  final RxBool collapsed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'n': name.value,
    'c': tabGroupColorToHex(color.value),
    if (collapsed.value) 'cl': true,
  };

  static TabGroup? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final name = json['n'] as String?;
      final colorHex = json['c'] as String?;
      if (id == null || name == null || colorHex == null) {
        return null;
      }

      return TabGroup(
        id: id,
        name: name,
        color: tabGroupColorFromHex(colorHex),
        collapsed: (json['cl'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static List<TabGroup> fromJsonList(List<dynamic> list) {
    final out = <TabGroup>[];
    final seenIds = <String>{};
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        final g = TabGroup.fromJson(entry);
        if (g != null && g.id.trim().isNotEmpty && seenIds.add(g.id)) {
          out.add(g);
        }
      }
    }
    return out;
  }

  @override
  String toString() =>
      'TabGroup(id: $id, name: ${name.value}, color: ${tabGroupColorToHex(color.value)}, collapsed: ${collapsed.value})';
}

String tabGroupColorToHex(Color color) {
  final argb = color.toARGB32();
  return '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

Color tabGroupColorFromHex(String hex) {
  var cleaned = hex.replaceFirst('#', '');
  if (cleaned.length == 6) {
    cleaned = 'FF$cleaned';
  }
  final value = int.parse(cleaned, radix: 16);
  return Color.fromARGB(
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  );
}

const List<String> kTabGroupPaletteHexes = [
  '#FF5F6368', // grey
  '#FFD93025', // red
  '#FFE8710A', // orange
  '#FFF9AB00', // yellow
  '#FF188038', // green
  '#FF007B83', // cyan
  '#FF1A73E8', // blue
  '#FF8430CE', // purple
  '#FFD01884', // pink
];

List<Color> get tabGroupPalette => kTabGroupPaletteHexes.map(tabGroupColorFromHex).toList(growable: false);

Color nextDefaultGroupColor(int existingGroupCount) {
  final palette = tabGroupPalette;
  return palette[existingGroupCount.abs() % palette.length];
}
