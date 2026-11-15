import 'dart:math' as math;

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';

enum LoliDateTimePickerMode { dateTime, date, time }

enum LoliDateTimePickerSelectionMode { single, range }

typedef LoliDateTimePickerValidator = bool Function(List<DateTime> values);
typedef LoliSelectableDayPredicate = bool Function(DateTime day);

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker = firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _readableForeground(Color preferred, Color background) {
  if (_contrastRatio(preferred, background) >= 4.5) return preferred;
  return background.computeLuminance() > 0.179 ? Colors.black : Colors.white;
}

({Color background, Color foreground}) _calendarSelectionColors(ColorScheme scheme) {
  final candidates = [
    (background: scheme.secondary, foreground: scheme.onSecondary),
    (background: scheme.primary, foreground: scheme.onPrimary),
  ];
  for (final candidate in candidates) {
    if (_contrastRatio(candidate.background, scheme.surface) >= 3) {
      return (
        background: candidate.background,
        foreground: _readableForeground(candidate.foreground, candidate.background),
      );
    }
  }

  final background = scheme.onSurface;
  return (
    background: background,
    foreground: _readableForeground(scheme.surface, background),
  );
}

/// Reusable calendar and wheel-time picker.
///
/// Supports date-time, date-only, and time-only presentations, with either a
/// single value or a two-endpoint range. Values are controlled by [value] and
/// [onChanged], so the picker can be embedded in a page or any bottom sheet.
class LoliDateTimePicker extends StatefulWidget {
  const LoliDateTimePicker({
    required this.value,
    required this.onChanged,
    this.mode = LoliDateTimePickerMode.dateTime,
    this.selectionMode = LoliDateTimePickerSelectionMode.single,
    this.firstDate,
    this.lastDate,
    this.currentDate,
    this.selectableDayPredicate,
    this.firstDayOfWeek,
    this.minuteInterval = 1,
    this.use24HourFormat,
    this.dynamicCalendarRows = true,
    this.rangeBidirectional = true,
    this.timePickerHeight = 150,
    this.animationDuration = const Duration(milliseconds: 180),
    this.animationCurve = Curves.easeOutCubic,
    this.startLabel,
    this.endLabel,
    this.onDisplayedMonthChanged,
    super.key,
  }) : assert(
         minuteInterval > 0 && minuteInterval <= 30 && 60 % minuteInterval == 0,
         'minuteInterval must be a divisor of 60 between 1 and 30',
       ),
       assert(
         selectionMode == LoliDateTimePickerSelectionMode.range || value.length <= 1,
         'Single-value mode accepts at most one value',
       ),
       assert(value.length <= 2, 'The picker accepts at most two range endpoints');

  static const calendarKey = ValueKey('loli-date-time-calendar');

  final List<DateTime> value;
  final ValueChanged<List<DateTime>> onChanged;
  final LoliDateTimePickerMode mode;
  final LoliDateTimePickerSelectionMode selectionMode;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? currentDate;
  final LoliSelectableDayPredicate? selectableDayPredicate;
  final int? firstDayOfWeek;
  final int minuteInterval;

  /// Overrides the locale's preferred hour cycle when non-null.
  final bool? use24HourFormat;
  final bool dynamicCalendarRows;
  final bool rangeBidirectional;
  final double timePickerHeight;
  final Duration animationDuration;
  final Curve animationCurve;
  final String? startLabel;
  final String? endLabel;
  final ValueChanged<DateTime>? onDisplayedMonthChanged;

  bool get showsDate => mode != LoliDateTimePickerMode.time;
  bool get showsTime => mode != LoliDateTimePickerMode.date;

  @override
  State<LoliDateTimePicker> createState() => _LoliDateTimePickerState();
}

class _LoliDateTimePickerState extends State<LoliDateTimePicker> {
  late final FixedExtentScrollController hourController;
  late final FixedExtentScrollController minuteController;
  late final FixedExtentScrollController periodController;
  final Map<FixedExtentScrollController, int> wheelTargets = {};
  int activeRangeIndex = 0;
  bool controllersInitialized = false;
  late bool resolvedUse24HourFormat;

  DateTime get _fallbackValue => widget.currentDate ?? DateTime.now();

  DateTime get _activeValue {
    if (widget.value.isEmpty) return _fallbackValue;
    return widget.value[activeRangeIndex.clamp(0, widget.value.length - 1)];
  }

  int _hourItem(DateTime value) => resolvedUse24HourFormat ? value.hour : (value.hour + 11) % 12;

  int _minuteItem(DateTime value) => (value.minute / widget.minuteInterval).round().clamp(
    0,
    60 ~/ widget.minuteInterval - 1,
  );

  int _periodItem(DateTime value) => value.hour >= 12 ? 1 : 0;

  bool _resolveUse24HourFormat() {
    final override = widget.use24HourFormat;
    if (override != null) return override;
    final format = MaterialLocalizations.of(context).timeOfDayFormat();
    return hourFormat(of: format) != HourFormat.h;
  }

  int _nearestLoopedItem({required int current, required int value, required int itemCount}) {
    final currentValue = current % itemCount;
    var delta = value - currentValue;
    if (delta > itemCount / 2) {
      delta -= itemCount;
    } else if (delta < -itemCount / 2) {
      delta += itemCount;
    }
    return current + delta;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolved = _resolveUse24HourFormat();
    if (controllersInitialized) {
      if (resolvedUse24HourFormat != resolved) {
        resolvedUse24HourFormat = resolved;
        _syncTimeControllers();
      }
      return;
    }
    resolvedUse24HourFormat = resolved;
    final initial = _activeValue;
    hourController = FixedExtentScrollController(initialItem: _hourItem(initial));
    minuteController = FixedExtentScrollController(initialItem: _minuteItem(initial));
    periodController = FixedExtentScrollController(initialItem: _periodItem(initial));
    wheelTargets[hourController] = _hourItem(initial);
    wheelTargets[minuteController] = _minuteItem(initial);
    wheelTargets[periodController] = _periodItem(initial);
    controllersInitialized = true;
  }

  @override
  void didUpdateWidget(covariant LoliDateTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    resolvedUse24HourFormat = _resolveUse24HourFormat();
    if (activeRangeIndex >= widget.value.length) activeRangeIndex = widget.value.isEmpty ? 0 : widget.value.length - 1;
    _syncTimeControllers();
  }

  @override
  void dispose() {
    if (controllersInitialized) {
      hourController.dispose();
      minuteController.dispose();
      periodController.dispose();
    }
    super.dispose();
  }

  void _syncTimeControllers() {
    final value = _activeValue;
    final targets = <FixedExtentScrollController, ({int value, int itemCount})>{
      hourController: (value: _hourItem(value), itemCount: resolvedUse24HourFormat ? 24 : 12),
      minuteController: (value: _minuteItem(value), itemCount: 60 ~/ widget.minuteInterval),
      periodController: (value: _periodItem(value), itemCount: 2),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final entry in targets.entries) {
        final current = entry.key.hasClients ? entry.key.selectedItem : wheelTargets[entry.key] ?? entry.value.value;
        final target = _nearestLoopedItem(
          current: current,
          value: entry.value.value,
          itemCount: entry.value.itemCount,
        );
        wheelTargets[entry.key] = target;
        if (entry.key.hasClients && entry.key.selectedItem != target) entry.key.jumpToItem(target);
      }
    });
  }

  DateTime _withTime(DateTime date, DateTime time) => DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );

  void _datesChanged(List<DateTime> dates) {
    final values = <DateTime>[];
    for (var index = 0; index < dates.length; index++) {
      if (widget.mode == LoliDateTimePickerMode.date) {
        values.add(DateUtils.dateOnly(dates[index]));
      } else {
        final previousTime = index < widget.value.length ? widget.value[index] : _fallbackValue;
        values.add(_withTime(dates[index], previousTime));
      }
    }
    if (widget.selectionMode == LoliDateTimePickerSelectionMode.range && values.length > 1) {
      activeRangeIndex = 1;
    } else {
      activeRangeIndex = 0;
    }
    widget.onChanged(values);
    _syncTimeControllers();
  }

  void _timeChanged({int? hourItem, int? minuteItem, int? periodItem}) {
    final values = [...widget.value];
    if (values.isEmpty) values.add(_fallbackValue);
    while (values.length <= activeRangeIndex) {
      values.add(values.last.add(const Duration(hours: 1)));
    }
    final current = values[activeRangeIndex];
    final currentPeriod = periodItem ?? _periodItem(current);
    final int hour;
    if (resolvedUse24HourFormat) {
      hour = hourItem ?? current.hour;
    } else {
      final displayHour = (hourItem ?? _hourItem(current)) + 1;
      hour = displayHour % 12 + currentPeriod * 12;
    }
    final minute = (minuteItem ?? _minuteItem(current)) * widget.minuteInterval;
    values[activeRangeIndex] = DateTime(current.year, current.month, current.day, hour, minute);
    widget.onChanged(values);
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required List<String> labels,
    required int selectedIndex,
    required String keyPrefix,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void handlePointerSignal(PointerSignalEvent event) {
      if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
      final current = wheelTargets[controller] ?? controller.selectedItem;
      final next = current + (event.scrollDelta.dy > 0 ? 1 : -1);
      GestureBinding.instance.pointerSignalResolver.register(event, (resolvedEvent) {
        wheelTargets[controller] = next;
        controller.animateToItem(
          next,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
        );
        resolvedEvent.respond(allowPlatformDefault: false);
      });
    }

    return CupertinoPicker(
      scrollController: controller,
      looping: true,
      itemExtent: 44,
      useMagnifier: true,
      magnification: 1.08,
      squeeze: 1.1,
      selectionOverlay: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.secondary.withValues(alpha: 0.45)),
        ),
      ),
      onSelectedItemChanged: (value) {
        wheelTargets[controller] = controller.selectedItem;
        onChanged(value);
      },
      children: List.generate(labels.length, (index) {
        final selected = index == selectedIndex;
        final selectedColor = theme.brightness == Brightness.dark ? Colors.white : Colors.black;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: handlePointerSignal,
          child: Center(
            child: Text(
              key: ValueKey('loli-date-time-$keyPrefix-$index'),
              labels[index],
              style: theme.textTheme.titleLarge?.copyWith(
                color: selected ? selectedColor : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _rangeSelector() {
    if (widget.selectionMode != LoliDateTimePickerSelectionMode.range || widget.value.length < 2) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment(
            value: 0,
            icon: const Icon(Icons.first_page),
            label: Text(widget.startLabel ?? context.loc.rangeStart),
          ),
          ButtonSegment(
            value: 1,
            icon: const Icon(Icons.last_page),
            label: Text(widget.endLabel ?? context.loc.rangeEnd),
          ),
        ],
        selected: {activeRangeIndex},
        onSelectionChanged: (selection) {
          setState(() => activeRangeIndex = selection.first);
          _syncTimeControllers();
        },
      ),
    );
  }

  Widget _calendar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectionColors = _calendarSelectionColors(scheme);
    final selectedBackground = selectionColors.background;
    final selectedForeground = selectionColors.foreground;
    final firstDate = DateUtils.dateOnly(widget.firstDate ?? DateTime(1900));
    final lastDate = DateUtils.dateOnly(widget.lastDate ?? DateTime(2200));
    final currentDate = DateUtils.dateOnly(widget.currentDate ?? DateTime.now());
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final animationDuration = animationsDisabled ? Duration.zero : widget.animationDuration;
    final locale = Localizations.localeOf(context);

    Widget interactiveCell({
      required String label,
      required TextStyle? textStyle,
      required BoxDecoration? decoration,
      required bool isSelected,
      required bool isDisabled,
      double? width,
      double? height,
      bool button = false,
    }) {
      return _InteractiveCalendarCell(
        label: label,
        textStyle: textStyle,
        decoration: decoration,
        isSelected: isSelected,
        isDisabled: isDisabled,
        accent: selectedBackground,
        selectedForeground: selectedForeground,
        surface: scheme.surface,
        duration: animationDuration,
        curve: widget.animationCurve,
        width: width,
        height: height,
        button: button,
      );
    }

    final calendar = CalendarDatePicker2(
      key: LoliDateTimePicker.calendarKey,
      config: CalendarDatePicker2Config(
        calendarType: widget.selectionMode == LoliDateTimePickerSelectionMode.single
            ? CalendarDatePicker2Type.single
            : CalendarDatePicker2Type.range,
        firstDate: firstDate,
        lastDate: lastDate,
        currentDate: currentDate,
        calendarViewMode: CalendarDatePicker2Mode.day,
        dynamicCalendarRows: widget.dynamicCalendarRows,
        rangeBidirectional: widget.rangeBidirectional,
        firstDayOfWeek: widget.firstDayOfWeek,
        selectableDayPredicate: widget.selectableDayPredicate,
        selectedDayHighlightColor: selectedBackground,
        selectedDayTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: selectedForeground,
          fontWeight: FontWeight.w700,
        ),
        selectedRangeHighlightColor: selectedBackground.withValues(alpha: 0.18),
        selectedRangeDayTextStyle: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        dayTextStyle: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        disabledDayTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.3),
        ),
        todayTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: selectedBackground,
          fontWeight: FontWeight.w700,
        ),
        weekdayLabelTextStyle: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        controlsTextStyle: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
        monthTextStyle: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        selectedMonthTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: selectedForeground,
          fontWeight: FontWeight.w700,
        ),
        disabledMonthTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.3),
        ),
        yearTextStyle: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        selectedYearTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: selectedForeground,
          fontWeight: FontWeight.w700,
        ),
        disabledYearTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.3),
        ),
        lastMonthIcon: Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
        nextMonthIcon: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        customModePickerIcon: Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
        // Cell splashes are painted by _CalendarCellSplashPainter so their
        // appearance does not depend on which Material hosts the picker.
        daySplashColor: Colors.transparent,
        dayBorderRadius: BorderRadius.circular(12),
        monthBorderRadius: BorderRadius.circular(12),
        yearBorderRadius: BorderRadius.circular(12),
        dayBuilder:
            ({
              required DateTime date,
              TextStyle? textStyle,
              BoxDecoration? decoration,
              bool? isSelected,
              bool? isDisabled,
              bool? isToday,
            }) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: interactiveCell(
                        label: MaterialLocalizations.of(context).formatDecimal(date.day),
                        textStyle: textStyle,
                        decoration: decoration,
                        isSelected: isSelected ?? false,
                        isDisabled: isDisabled ?? false,
                      ),
                    ),
                  ),
                ],
              );
            },
        monthBuilder:
            ({
              required int month,
              TextStyle? textStyle,
              BoxDecoration? decoration,
              bool? isSelected,
              bool? isDisabled,
              bool? isCurrentMonth,
            }) {
              return Center(
                child: interactiveCell(
                  label: getLocaleShortMonthFormat(locale).format(DateTime(2000, month)),
                  textStyle: textStyle,
                  decoration: decoration,
                  isSelected: isSelected ?? false,
                  isDisabled: isDisabled ?? false,
                  width: 72,
                  height: 36,
                  button: true,
                ),
              );
            },
        yearBuilder:
            ({
              required int year,
              TextStyle? textStyle,
              BoxDecoration? decoration,
              bool? isSelected,
              bool? isDisabled,
              bool? isCurrentYear,
            }) {
              return Center(
                child: interactiveCell(
                  label: year.toString(),
                  textStyle: textStyle,
                  decoration: decoration,
                  isSelected: isSelected ?? false,
                  isDisabled: isDisabled ?? false,
                  width: 72,
                  height: 36,
                  button: true,
                ),
              );
            },
      ),
      value: widget.value,
      onDisplayedMonthChanged: widget.onDisplayedMonthChanged,
      onValueChanged: _datesChanged,
    );

    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: animationDuration,
      curve: widget.animationCurve,
      child: Theme(
        data: theme.copyWith(
          hoverColor: selectedBackground.withValues(alpha: 0.12),
          focusColor: selectedBackground.withValues(alpha: 0.16),
          highlightColor: selectedBackground.withValues(alpha: 0.12),
          splashColor: selectedBackground.withValues(alpha: 0.18),
        ),
        child: calendar,
      ),
    );
  }

  Widget _timePicker() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = _activeValue;
    final minuteLabels = List.generate(
      60 ~/ widget.minuteInterval,
      (index) => (index * widget.minuteInterval).toString().padLeft(2, '0'),
    );
    final hourLabels = resolvedUse24HourFormat
        ? List.generate(24, (index) => index.toString().padLeft(2, '0'))
        : List.generate(12, (index) => (index + 1).toString());
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          _rangeSelector(),
          SizedBox(
            height: widget.timePickerHeight,
            child: Row(
              children: [
                Expanded(
                  child: _wheel(
                    controller: hourController,
                    labels: hourLabels,
                    selectedIndex: _hourItem(value),
                    keyPrefix: 'hour',
                    onChanged: (index) => _timeChanged(hourItem: index),
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Center(child: Text(':', style: theme.textTheme.headlineSmall)),
                ),
                Expanded(
                  child: _wheel(
                    controller: minuteController,
                    labels: minuteLabels,
                    selectedIndex: _minuteItem(value),
                    keyPrefix: 'minute',
                    onChanged: (index) => _timeChanged(minuteItem: index),
                  ),
                ),
                if (!resolvedUse24HourFormat) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _wheel(
                      controller: periodController,
                      labels: const ['AM', 'PM'],
                      selectedIndex: _periodItem(value),
                      keyPrefix: 'period',
                      onChanged: (index) => _timeChanged(periodItem: index),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showsDate) _calendar(),
        if (widget.showsDate && widget.showsTime) const SizedBox(height: 12),
        if (widget.showsTime) _timePicker(),
      ],
    );
  }
}

class _InteractiveCalendarCell extends StatefulWidget {
  const _InteractiveCalendarCell({
    required this.label,
    required this.textStyle,
    required this.decoration,
    required this.isSelected,
    required this.isDisabled,
    required this.accent,
    required this.selectedForeground,
    required this.surface,
    required this.duration,
    required this.curve,
    required this.button,
    this.width,
    this.height,
  });

  final String label;
  final TextStyle? textStyle;
  final BoxDecoration? decoration;
  final bool isSelected;
  final bool isDisabled;
  final Color accent;
  final Color selectedForeground;
  final Color surface;
  final Duration duration;
  final Curve curve;
  final bool button;
  final double? width;
  final double? height;

  @override
  State<_InteractiveCalendarCell> createState() => _InteractiveCalendarCellState();
}

class _InteractiveCalendarCellState extends State<_InteractiveCalendarCell> with SingleTickerProviderStateMixin {
  late final AnimationController rippleController;
  Offset? rippleOrigin;
  bool hovered = false;
  bool pressed = false;

  @override
  void initState() {
    super.initState();
    rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    rippleController.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (widget.isDisabled || hovered == value) return;
    setState(() => hovered = value);
  }

  void _pointerDown(PointerDownEvent event) {
    if (widget.isDisabled) return;
    setState(() {
      pressed = true;
      rippleOrigin = event.localPosition;
    });
    if (widget.duration != Duration.zero) rippleController.forward(from: 0);
  }

  void _pointerEnded() {
    if (widget.isDisabled || !pressed) return;
    setState(() => pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const BoxDecoration();
    final borderRadius = (baseDecoration.borderRadius ?? BorderRadius.circular(12)).resolve(
      Directionality.of(context),
    );
    final baseColor = baseDecoration.color ?? Colors.transparent;
    final interactionColor = widget.isSelected ? widget.selectedForeground : widget.accent;
    final Color background;
    if (widget.isDisabled) {
      background = baseColor;
    } else if (pressed) {
      background = Color.alphaBlend(
        interactionColor.withValues(alpha: widget.isSelected ? 0.20 : 0.24),
        widget.isSelected ? baseColor : widget.surface,
      );
    } else if (hovered) {
      background = Color.alphaBlend(
        interactionColor.withValues(alpha: widget.isSelected ? 0.12 : 0.14),
        widget.isSelected ? baseColor : widget.surface,
      );
    } else {
      background = baseColor;
    }

    final BoxBorder? interactionBorder;
    if (widget.isDisabled) {
      interactionBorder = baseDecoration.border;
    } else if (pressed || hovered || widget.isSelected) {
      interactionBorder = Border.all(
        color: interactionColor.withValues(alpha: pressed ? 0.95 : 0.72),
        width: pressed ? 2 : 1.5,
      );
    } else {
      interactionBorder = baseDecoration.border;
    }

    final cell = MouseRegion(
      cursor: widget.isDisabled ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _pointerEnded();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _pointerDown,
        onPointerUp: (_) => _pointerEnded(),
        onPointerCancel: (_) => _pointerEnded(),
        child: AnimatedScale(
          scale: pressed ? 0.97 : (hovered ? 1.02 : 1),
          duration: widget.duration,
          curve: widget.curve,
          child: AnimatedContainer(
            duration: widget.duration,
            curve: widget.curve,
            decoration: baseDecoration.copyWith(
              color: background,
              border: interactionBorder,
              borderRadius: borderRadius,
              boxShadow: hovered && !widget.isDisabled
                  ? [
                      BoxShadow(
                        color: interactionColor.withValues(alpha: 0.16),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Semantics(
                    selected: widget.isSelected,
                    enabled: !widget.isDisabled,
                    button: widget.button,
                    child: Text(widget.label, style: widget.textStyle),
                  ),
                ),
                if (!widget.isDisabled)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: rippleController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _CalendarCellSplashPainter(
                            origin: rippleOrigin,
                            progress: rippleController.value,
                            held: pressed,
                            color: widget.accent,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return SizedBox(width: widget.width, height: widget.height, child: cell);
  }
}

class _CalendarCellSplashPainter extends CustomPainter {
  const _CalendarCellSplashPainter({
    required this.origin,
    required this.progress,
    required this.held,
    required this.color,
  });

  final Offset? origin;
  final double progress;
  final bool held;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (origin == null || progress <= 0 || size.isEmpty) return;
    final horizontalRadius = math.max(origin!.dx, size.width - origin!.dx);
    final verticalRadius = math.max(origin!.dy, size.height - origin!.dy);
    final maximumRadius = math.sqrt(horizontalRadius * horizontalRadius + verticalRadius * verticalRadius);
    final expansion = Curves.easeOutCubic.transform(progress);
    final releaseOpacity = held ? 1.0 : (1 - progress).clamp(0.0, 1.0);
    canvas.drawCircle(
      origin!,
      maximumRadius * expansion,
      Paint()..color = color.withValues(alpha: 0.24 * releaseOpacity),
    );
  }

  @override
  bool shouldRepaint(covariant _CalendarCellSplashPainter oldDelegate) {
    return origin != oldDelegate.origin ||
        progress != oldDelegate.progress ||
        held != oldDelegate.held ||
        color != oldDelegate.color;
  }
}

Future<List<DateTime>?> showLoliDateTimePickerSheet(
  BuildContext context, {
  required String title,
  List<DateTime> initialValue = const [],
  LoliDateTimePickerMode mode = LoliDateTimePickerMode.dateTime,
  LoliDateTimePickerSelectionMode selectionMode = LoliDateTimePickerSelectionMode.single,
  DateTime? firstDate,
  DateTime? lastDate,
  DateTime? currentDate,
  LoliSelectableDayPredicate? selectableDayPredicate,
  int? firstDayOfWeek,
  int minuteInterval = 1,
  bool? use24HourFormat,
  bool rangeBidirectional = true,
  String? startLabel,
  String? endLabel,
  LoliDateTimePickerValidator? validator,
}) {
  return showModalBottomSheet<List<DateTime>>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 700),
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LoliDateTimePickerSheet(
      title: title,
      initialValue: initialValue,
      mode: mode,
      selectionMode: selectionMode,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: currentDate,
      selectableDayPredicate: selectableDayPredicate,
      firstDayOfWeek: firstDayOfWeek,
      minuteInterval: minuteInterval,
      use24HourFormat: use24HourFormat,
      rangeBidirectional: rangeBidirectional,
      startLabel: startLabel,
      endLabel: endLabel,
      validator: validator,
    ),
  );
}

class _LoliDateTimePickerSheet extends StatefulWidget {
  const _LoliDateTimePickerSheet({
    required this.title,
    required this.initialValue,
    required this.mode,
    required this.selectionMode,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.selectableDayPredicate,
    required this.firstDayOfWeek,
    required this.minuteInterval,
    required this.use24HourFormat,
    required this.rangeBidirectional,
    required this.startLabel,
    required this.endLabel,
    required this.validator,
  });

  final String title;
  final List<DateTime> initialValue;
  final LoliDateTimePickerMode mode;
  final LoliDateTimePickerSelectionMode selectionMode;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? currentDate;
  final LoliSelectableDayPredicate? selectableDayPredicate;
  final int? firstDayOfWeek;
  final int minuteInterval;
  final bool? use24HourFormat;
  final bool rangeBidirectional;
  final String? startLabel;
  final String? endLabel;
  final LoliDateTimePickerValidator? validator;

  @override
  State<_LoliDateTimePickerSheet> createState() => _LoliDateTimePickerSheetState();
}

class _LoliDateTimePickerSheetState extends State<_LoliDateTimePickerSheet> {
  late List<DateTime> value;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue.isNotEmpty) {
      value = [...widget.initialValue];
    } else {
      final now = widget.currentDate ?? DateTime.now();
      value = [now];
      if (widget.selectionMode == LoliDateTimePickerSelectionMode.range) {
        value.add(
          widget.mode == LoliDateTimePickerMode.date
              ? now.add(const Duration(days: 1))
              : now.add(const Duration(hours: 1)),
        );
      }
    }
  }

  bool get canConfirm {
    final expectedLength = widget.selectionMode == LoliDateTimePickerSelectionMode.single ? 1 : 2;
    return value.length == expectedLength && (widget.validator?.call(value) ?? true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(widget.title, style: theme.textTheme.titleLarge),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: LoliDateTimePicker(
                    value: value,
                    onChanged: (updated) => setState(() => value = updated),
                    mode: widget.mode,
                    selectionMode: widget.selectionMode,
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    currentDate: widget.currentDate,
                    selectableDayPredicate: widget.selectableDayPredicate,
                    firstDayOfWeek: widget.firstDayOfWeek,
                    minuteInterval: widget.minuteInterval,
                    use24HourFormat: widget.use24HourFormat,
                    rangeBidirectional: widget.rangeBidirectional,
                    startLabel: widget.startLabel,
                    endLabel: widget.endLabel,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.loc.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canConfirm ? () => Navigator.of(context).pop(value) : null,
                      icon: const Icon(Icons.check),
                      label: Text(context.loc.confirm),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
