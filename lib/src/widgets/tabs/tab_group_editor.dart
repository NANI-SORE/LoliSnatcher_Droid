import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/utils/theme_colors.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

typedef TabGroupEdit = ({String name, Color color});

class TabGroupEditor extends StatefulWidget {
  const TabGroupEditor({
    required this.title,
    required this.actionLabel,
    required this.actionIcon,
    required this.initialColor,
    this.initialName = '',
    super.key,
  });

  final String title;
  final String actionLabel;
  final IconData actionIcon;
  final Color initialColor;
  final String initialName;

  @override
  State<TabGroupEditor> createState() => _TabGroupEditorState();
}

class _TabGroupEditorState extends State<TabGroupEditor> {
  final _focus = FocusNode();
  bool _showValidation = false;
  late final TextEditingController _name;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _color = widget.initialColor;
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    // SettingsTextInput renders validator results as errorText rather than
    // registering a Form validator, so submission must check the value too.
    if (_name.text.trim().isEmpty) {
      setState(() => _showValidation = true);
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop<TabGroupEdit>((name: _name.text.trim(), color: _color));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDialog(
      title: Text(widget.title),
      contentItems: [
        SettingsTextInput(
          title: context.loc.tabs.groups.groupName,
          titleAsLabel: true,
          controller: _name,
          focusNode: _focus,
          drawBottomBorder: false,
          margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          autofocus: true,
          clearable: true,
          textInputAction: TextInputAction.done,
          validator: (value) =>
              !_showValidation || value?.trim().isNotEmpty == true ? null : context.loc.tabs.groups.nameRequired,
          onChanged: (_) {
            if (_showValidation) setState(() {});
          },
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(context.loc.tabs.groups.groupColor, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TabGroupColorPicker(selectedColor: _color, onChanged: (color) => setState(() => _color = color)),
        ),
      ],
      actionButtons: [
        const CancelButton(withIcon: true),
        ElevatedButton.icon(onPressed: _submit, icon: Icon(widget.actionIcon), label: Text(widget.actionLabel)),
      ],
    );
  }
}

class TabGroupColorPicker extends StatelessWidget {
  const TabGroupColorPicker({required this.selectedColor, required this.onChanged, super.key});

  final Color selectedColor;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tabGroupPalette.map((color) {
        final selected = color.toARGB32() == selectedColor.toARGB32();
        final hex = tabGroupColorToHex(color);
        final label = context.loc.tabs.groups.colorNames[hex] ?? hex;
        final foreground = ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
        return Semantics(
          label: label,
          button: true,
          selected: selected,
          onTap: () => onChanged(color),
          excludeSemantics: true,
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => onChanged(color),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? contrastingThemeColor(
                                Theme.of(context).colorScheme,
                                background: color,
                                adjacentBackground:
                                    Theme.of(context).dialogTheme.backgroundColor ??
                                    Theme.of(context).colorScheme.surfaceContainerHigh,
                              )
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected ? Icon(Icons.check, size: 18, color: foreground) : null,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
