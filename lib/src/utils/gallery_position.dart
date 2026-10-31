import 'package:lolisnatcher/src/data/booru_item.dart';

/// Preserves a viewed item across filtering, including a temporarily empty list.
class GalleryPosition {
  GalleryPosition(List<BooruItem> items, int initialIndex) {
    _items = List.of(items);
    index = items.isEmpty ? 0 : initialIndex.clamp(0, items.length - 1);
    if (items.isNotEmpty) _anchor = items[index];
  }

  late List<BooruItem> _items;
  BooruItem? _anchor;
  int index = 0;
  BooruItem? get current => _empty || _items.isEmpty ? null : _items[index];

  void select(int value) {
    if (_items.isEmpty || value < 0 || value >= _items.length) return;
    index = value;
    _anchor = _items[index];
  }

  void update(List<BooruItem> items) {
    if (items.isEmpty) {
      // Retain the old list/anchor for a later reveal, but expose no current item.
      _empty = true;
      return;
    }
    var next = _anchor == null ? -1 : items.indexWhere((item) => item.key == _anchor!.key);
    if (next < 0 && _anchor?.postURL.isNotEmpty == true) {
      // Detail refresh may replace the object while keeping the same post.
      next = items.indexWhere((item) => item.postURL == _anchor!.postURL);
    }
    if (next < 0) {
      final positions = {for (var i = 0; i < items.length; i++) items[i].key: i};
      for (var i = index + 1; i < _items.length && next < 0; i++) {
        next = positions[_items[i].key] ?? -1;
      }
      for (var i = index - 1; i >= 0 && next < 0; i--) {
        next = positions[_items[i].key] ?? -1;
      }
    }
    index = next < 0 ? index.clamp(0, items.length - 1) : next;
    _items = List.of(items);
    _anchor = items[index];
    _empty = false;
  }

  bool _empty = false;
}
