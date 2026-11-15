import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

void main() {
  group('TabGroup color helpers', () {
    test('hex round-trips uppercase ARGB', () {
      const hex = '#FF1A73E8';
      final color = tabGroupColorFromHex(hex);
      expect(tabGroupColorToHex(color), equals(hex));
    });

    test('hex parsing accepts 6-digit RRGGBB as opaque', () {
      final color = tabGroupColorFromHex('1A73E8');
      expect(tabGroupColorToHex(color), equals('#FF1A73E8'));
    });

    test('hex parsing tolerates lowercase + leading hash', () {
      final color = tabGroupColorFromHex('#ff1a73e8');
      expect(tabGroupColorToHex(color), equals('#FF1A73E8'));
    });

    test('palette has 9 entries and all parse', () {
      expect(kTabGroupPaletteHexes.length, equals(9));
      expect(tabGroupPalette.length, equals(9));
      for (final hex in kTabGroupPaletteHexes) {
        expect(() => tabGroupColorFromHex(hex), returnsNormally);
      }
    });

    test('nextDefaultGroupColor cycles through palette', () {
      final palette = tabGroupPalette;
      expect(nextDefaultGroupColor(0), equals(palette[0]));
      expect(nextDefaultGroupColor(1), equals(palette[1]));
      expect(nextDefaultGroupColor(palette.length), equals(palette[0]));
      expect(nextDefaultGroupColor(palette.length + 3), equals(palette[3]));
    });
  });

  group('TabGroup JSON', () {
    test('toJson/fromJson round-trips name, color, collapsed', () {
      final g = TabGroup(
        id: 'group-id-1',
        name: 'Work',
        color: const Color(0xFF1A73E8),
        collapsed: true,
      );

      final json = g.toJson();
      expect(json['id'], equals('group-id-1'));
      expect(json['n'], equals('Work'));
      expect(json['c'], equals('#FF1A73E8'));
      expect(json['cl'], equals(true));

      final restored = TabGroup.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.id, equals('group-id-1'));
      expect(restored.name.value, equals('Work'));
      expect(tabGroupColorToHex(restored.color.value), equals('#FF1A73E8'));
      expect(restored.collapsed.value, isTrue);
    });

    test('toJson omits cl when false', () {
      final g = TabGroup(
        id: 'group-id-2',
        name: 'Play',
        color: const Color(0xFFD93025),
      );
      final json = g.toJson();
      expect(json.containsKey('cl'), isFalse);
    });

    test('fromJson defaults collapsed to false when absent', () {
      final restored = TabGroup.fromJson({
        'id': 'group-id-3',
        'n': 'Misc',
        'c': '#FF188038',
      });
      expect(restored, isNotNull);
      expect(restored!.collapsed.value, isFalse);
    });

    test('fromJson returns null on missing required keys', () {
      expect(TabGroup.fromJson({'n': 'Lonely', 'c': '#FF000000'}), isNull);
      expect(TabGroup.fromJson({'id': 'x', 'c': '#FF000000'}), isNull);
      expect(TabGroup.fromJson({'id': 'x', 'n': 'y'}), isNull);
    });

    test('fromJson returns null on malformed color', () {
      expect(
        TabGroup.fromJson({'id': 'x', 'n': 'y', 'c': 'not-a-hex'}),
        isNull,
      );
    });

    test('fromJsonList skips invalid entries silently', () {
      final list = [
        {'id': 'g1', 'n': 'A', 'c': '#FF111111'},
        {'n': 'B', 'c': '#FF222222'}, // missing id
        'not-a-map',
        {'id': 'g3', 'n': 'C', 'c': '#FF333333', 'cl': true},
      ];
      final groups = TabGroup.fromJsonList(list);
      expect(groups.length, equals(2));
      expect(groups[0].id, equals('g1'));
      expect(groups[1].id, equals('g3'));
      expect(groups[1].collapsed.value, isTrue);
    });

    test('TabGroup id is unique when not provided', () {
      final a = TabGroup(name: 'A', color: const Color(0xFF000000));
      final b = TabGroup(name: 'B', color: const Color(0xFF000000));
      expect(a.id, isNot(equals(b.id)));
      expect(a.id, isNotEmpty);
    });
  });

  group('TabBackup with groupId', () {
    test('toJson includes "g" key when groupId set, omits when null', () {
      final withGroup = TabBackup(
        tags: 'red',
        booru: 'gelbooru',
        groupId: 'group-xyz',
      );
      expect(withGroup.toJson()['g'], equals('group-xyz'));

      final noGroup = TabBackup(tags: 'red', booru: 'gelbooru');
      expect(noGroup.toJson().containsKey('g'), isFalse);
    });

    test('fromJson reads back groupId; defaults to null when absent', () {
      final restored = TabBackup.fromJson({
        't': 'red',
        'b': 'gelbooru',
        'g': 'group-xyz',
      });
      expect(restored, isNotNull);
      expect(restored!.groupId, equals('group-xyz'));

      final restoredNoGroup = TabBackup.fromJson({
        't': 'red',
        'b': 'gelbooru',
      });
      expect(restoredNoGroup, isNotNull);
      expect(restoredNoGroup!.groupId, isNull);
    });

    test('fromJsonList round-trips a v1 bare array', () {
      final v1 = jsonEncode([
        {'t': 'red', 'b': 'gelbooru'},
        {'t': 'blue', 'b': 'safebooru', 's': true},
      ]);
      final list = TabBackup.fromJsonList(v1);
      expect(list.length, equals(2));
      expect(list[0].tags, equals('red'));
      expect(list[1].selected, isTrue);
      expect(list[0].groupId, isNull);
    });
  });
}
