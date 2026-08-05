import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/widgets/common/loli_date_time_picker.dart';

@immutable
class TagFilterAvailabilityChange {
  const TagFilterAvailabilityChange({required this.enabled, this.disabledUntil});

  final bool enabled;
  final DateTime? disabledUntil;
}

Future<TagFilterAvailabilityChange?> showTagFilterSuspensionSheet(
  BuildContext context, {
  bool showReenable = true,
}) async {
  final value = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (sheetContext) {
      final loc = sheetContext.loc.settings.itemFilters;
      final options = <(String, String, IconData)>[
        ('15m', loc.minutesPlural(count: 15), Icons.timer_outlined),
        ('30m', loc.minutesPlural(count: 30), Icons.timer_outlined),
        ('1h', loc.hoursPlural(count: 1), Icons.schedule),
        ('6h', loc.hoursPlural(count: 6), Icons.schedule),
        ('12h', loc.hoursPlural(count: 12), Icons.schedule),
        ('1d', loc.daysPlural(count: 1), Icons.today_outlined),
        ('1w', loc.weeksPlural(count: 1), Icons.date_range_outlined),
        ('custom', loc.customDuration, Icons.edit_calendar_outlined),
        ('off', loc.indefinitely, Icons.all_inclusive),
        if (showReenable) ('on', loc.reenable, Icons.play_arrow_rounded),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(loc.disableFor, style: Theme.of(sheetContext).textTheme.titleLarge),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, index) {
                final option = options[index];
                return ListTile(
                  leading: Icon(option.$3),
                  title: Text(option.$2),
                  onTap: () => Navigator.of(sheetContext).pop(option.$1),
                );
              },
            ),
          ),
        ],
      );
    },
  );
  if (value == null) return null;
  if (value == 'on') return const TagFilterAvailabilityChange(enabled: true);
  if (value == 'off') return const TagFilterAvailabilityChange(enabled: false);
  if (value == 'custom') {
    final until = await showTagFilterCustomUntilSheet(context);
    return until == null ? null : TagFilterAvailabilityChange(enabled: true, disabledUntil: until);
  }
  final duration = switch (value) {
    '15m' => const Duration(minutes: 15),
    '30m' => const Duration(minutes: 30),
    '1h' => const Duration(hours: 1),
    '6h' => const Duration(hours: 6),
    '12h' => const Duration(hours: 12),
    '1d' => const Duration(days: 1),
    '1w' => const Duration(days: 7),
    _ => null,
  };
  return duration == null
      ? null
      : TagFilterAvailabilityChange(
          enabled: true,
          disabledUntil: DateTime.now().toUtc().add(duration),
        );
}

Future<DateTime?> showTagFilterCustomUntilSheet(BuildContext context) async {
  final now = DateTime.now();
  final values = await showLoliDateTimePickerSheet(
    context,
    title: context.loc.settings.itemFilters.customDuration,
    initialValue: [now.add(const Duration(hours: 1))],
    mode: LoliDateTimePickerMode.dateTime,
    selectionMode: LoliDateTimePickerSelectionMode.single,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
    validator: (values) => values.single.isAfter(now),
  );
  return values?.single.toUtc();
}
