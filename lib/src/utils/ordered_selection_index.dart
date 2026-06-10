class OrderedSelectionIndex<T> {
  final Map<T, int> _indices = Map.identity();

  bool get isNotEmpty => _indices.isNotEmpty;

  int? indexOf(T item) => _indices[item];

  void update(Iterable<T> items) {
    _indices
      ..clear()
      ..addEntries(
        items.indexed.map((entry) => MapEntry(entry.$2, entry.$1)),
      );
  }
}
