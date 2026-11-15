import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/widgets/settings/setting_chrome_scope.dart';

/// Keeps the option label, source overrides and its controls together.
class FilterOptionTile extends StatelessWidget {
  const FilterOptionTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.timerAction,
    super.key,
  });

  final String title;
  final Widget icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final Widget? timerAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overrides = SettingChromeScope.chipOf(context);
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (timerAction != null) ...[timerAction!, const SizedBox(width: 8)],
        Semantics(
          label: title,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 340 || MediaQuery.textScalerOf(context).scale(14) > 18;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 12),
                    child: ExcludeSemantics(
                      child: IconTheme(
                        data: IconThemeData(color: theme.colorScheme.onSurfaceVariant, size: 22),
                        child: icon,
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onChanged(!value),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                subtitle!,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          if (overrides != null) Padding(padding: const EdgeInsets.only(top: 6), child: overrides),
                        ],
                      ),
                    ),
                  ),
                  if (!stacked) ...[const SizedBox(width: 12), controls],
                ],
              ),
              if (stacked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(alignment: Alignment.centerRight, child: controls),
                ),
            ],
          ),
        );
      },
    );
  }
}
