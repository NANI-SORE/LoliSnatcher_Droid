class TabManagerSectionLayout {
  const TabManagerSectionLayout({
    required this.headerExtent,
    required this.tabCount,
    required this.collapsed,
  }) : assert(headerExtent >= 0, 'headerExtent must not be negative'),
       assert(tabCount >= 0, 'tabCount must not be negative');

  final double headerExtent;
  final int tabCount;
  final bool collapsed;
}

class _PositionedTabManagerSection {
  const _PositionedTabManagerSection({
    required this.startOffset,
    required this.itemStartOffset,
    required this.endOffset,
    required this.firstTabIndex,
    required this.tabCount,
    required this.collapsed,
  });

  final double startOffset;
  final double itemStartOffset;
  final double endOffset;
  final int firstTabIndex;
  final int tabCount;
  final bool collapsed;
}

/// Precomputed geometry for the tab manager's sectioned scroll view.
///
/// Building this is linear in the number of groups. Offset and tab-index
/// lookups are logarithmic, so scrollbar updates never scan thousands of tabs.
class TabManagerScrollMetrics {
  const TabManagerScrollMetrics._({
    required this._sections,
    required this._sectionOffsets,
    required this.itemExtent,
    required this.tabCount,
  });

  factory TabManagerScrollMetrics.build({
    required Iterable<TabManagerSectionLayout> sections,
    required double itemExtent,
  }) {
    assert(itemExtent > 0, 'itemExtent must be positive');

    final positionedSections = <_PositionedTabManagerSection>[];
    final sectionOffsets = <double>[];
    double offset = 0;
    int firstTabIndex = 0;

    for (final section in sections) {
      final startOffset = offset;
      sectionOffsets.add(startOffset);
      offset += section.headerExtent;
      final itemStartOffset = offset;

      if (!section.collapsed) {
        offset += section.tabCount * itemExtent;
      }

      if (section.tabCount > 0) {
        positionedSections.add(
          _PositionedTabManagerSection(
            startOffset: startOffset,
            itemStartOffset: itemStartOffset,
            endOffset: offset,
            firstTabIndex: firstTabIndex,
            tabCount: section.tabCount,
            collapsed: section.collapsed,
          ),
        );
      }

      firstTabIndex += section.tabCount;
    }

    return TabManagerScrollMetrics._(
      sections: positionedSections,
      sectionOffsets: sectionOffsets,
      itemExtent: itemExtent,
      tabCount: firstTabIndex,
    );
  }

  static const empty = TabManagerScrollMetrics._(
    sections: <_PositionedTabManagerSection>[],
    sectionOffsets: <double>[],
    itemExtent: 1,
    tabCount: 0,
  );

  final List<_PositionedTabManagerSection> _sections;
  final List<double> _sectionOffsets;
  final double itemExtent;
  final int tabCount;

  int get sectionCount => _sectionOffsets.length;

  /// Returns the exact scroll offset where a section's header begins.
  ///
  /// Empty and collapsed sections are retained because their headers remain
  /// valid navigation and drag/drop destinations.
  double offsetForSectionIndex(int sectionIndex) {
    if (_sectionOffsets.isEmpty) {
      return 0;
    }

    return _sectionOffsets[sectionIndex.clamp(0, _sectionOffsets.length - 1)];
  }

  /// Returns the section whose header or content contains [scrollOffset].
  ///
  /// This also covers empty and collapsed sections, allowing scroll UI to
  /// describe the active group even when there is no visible tab row.
  int sectionIndexForOffset(double scrollOffset) {
    if (_sectionOffsets.isEmpty) {
      return 0;
    }

    final target = scrollOffset < 0 ? 0.0 : scrollOffset;
    int low = 0;
    int high = _sectionOffsets.length - 1;
    int sectionIndex = 0;

    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (_sectionOffsets[middle] <= target) {
        sectionIndex = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    return sectionIndex;
  }

  int tabIndexForOffset(double scrollOffset) {
    if (_sections.isEmpty) {
      return 0;
    }

    final target = scrollOffset < 0 ? 0.0 : scrollOffset;
    int low = 0;
    int high = _sections.length - 1;
    int sectionIndex = _sections.length;

    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (_sections[middle].endOffset > target) {
        sectionIndex = middle;
        high = middle - 1;
      } else {
        low = middle + 1;
      }
    }

    if (sectionIndex == _sections.length) {
      final last = _sections.last;
      return last.firstTabIndex + last.tabCount - 1;
    }

    final section = _sections[sectionIndex];
    if (section.collapsed || target < section.itemStartOffset) {
      return section.firstTabIndex;
    }

    final localIndex = ((target - section.itemStartOffset) / itemExtent).floor().clamp(
      0,
      section.tabCount - 1,
    );
    return section.firstTabIndex + localIndex;
  }

  /// Returns the scroll offset for [tabIndex].
  ///
  /// When [keepHeaderVisible] is true, an expanded section's header extent is
  /// reserved above the row so a pinned header does not cover the target tab.
  double offsetForTabIndex(
    int tabIndex, {
    bool keepHeaderVisible = false,
  }) {
    if (_sections.isEmpty || tabCount == 0) {
      return 0;
    }

    final target = tabIndex.clamp(0, tabCount - 1);
    int low = 0;
    int high = _sections.length - 1;

    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      final section = _sections[middle];
      final sectionEndIndex = section.firstTabIndex + section.tabCount;

      if (target < section.firstTabIndex) {
        high = middle - 1;
      } else if (target >= sectionEndIndex) {
        low = middle + 1;
      } else if (section.collapsed) {
        return section.startOffset;
      } else {
        final itemOffset = section.itemStartOffset + (target - section.firstTabIndex) * itemExtent;
        if (!keepHeaderVisible) {
          return itemOffset;
        }
        final headerExtent = section.itemStartOffset - section.startOffset;
        return itemOffset - headerExtent;
      }
    }

    return 0;
  }
}

bool shouldAnimateTabManagerScroll({
  required double distance,
  required double viewportExtent,
}) {
  return viewportExtent > 0 && distance <= viewportExtent * 2;
}
