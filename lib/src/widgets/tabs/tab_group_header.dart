import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/tab_group.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/delete_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

const double tabGroupHeaderHeight = 52;

class TabGroupHeader extends StatelessWidget {
  const TabGroupHeader({
    required this.group,
    required this.tabsInGroupCount,
    required this.onToggleCollapse,
    required this.onMenuTap,
    this.onPreviousGroup,
    this.onNextGroup,
    super.key,
  });

  final TabGroup group;
  final int tabsInGroupCount;
  final VoidCallback onToggleCollapse;
  final VoidCallback onMenuTap;
  final VoidCallback? onPreviousGroup;
  final VoidCallback? onNextGroup;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final color = group.color.value;
      final name = group.name.value;
      final collapsed = group.collapsed.value;
      final scheme = Theme.of(context).colorScheme;

      final header = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Material(
          color: Color.alphaBlend(color.withValues(alpha: 0.15), scheme.surface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: color, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggleCollapse,
            child: SizedBox(
              height: tabGroupHeaderHeight - 8,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more, size: 20, color: scheme.onSurface),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, right: 2),
                    child: Text(
                      '$tabsInGroupCount',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  if (onPreviousGroup != null || onNextGroup != null) ...[
                    _GroupNavigationButton(
                      icon: Icons.keyboard_arrow_up,
                      onPressed: onPreviousGroup,
                    ),
                    _GroupNavigationButton(
                      icon: Icons.keyboard_arrow_down,
                      onPressed: onNextGroup,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: context.loc.tabs.groups.groupActions,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: onMenuTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      return LongPressDraggable<TabGroup>(
        data: group,
        axis: Axis.vertical,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 220,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: 0.3), scheme.surface),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 3)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: header),
        child: header,
      );
    });
  }
}

/// Sentinel for "ungrouped" header in the tab manager. When [onToggleCollapse]
/// is provided the whole header becomes a tappable collapse toggle, mirroring
/// [TabGroupHeader].
class TabGroupUngroupedHeader extends StatelessWidget {
  const TabGroupUngroupedHeader({
    required this.tabsInUngroupedCount,
    this.collapsed = false,
    this.onToggleCollapse,
    this.onPreviousGroup,
    this.onNextGroup,
    super.key,
  });

  final int tabsInUngroupedCount;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onPreviousGroup;
  final VoidCallback? onNextGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.5);

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          if (onToggleCollapse != null) ...[
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more, size: 18, color: muted),
            ),
            const SizedBox(width: 4),
          ],
          Icon(Icons.folder_outlined, size: 16, color: muted),
          const SizedBox(width: 6),
          Text(
            context.loc.tabs.groups.ungrouped,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$tabsInUngroupedCount',
            style: TextStyle(
              fontSize: 13,
              color: muted,
            ),
          ),
          if (onPreviousGroup != null || onNextGroup != null) ...[
            const Spacer(),
            _GroupNavigationButton(
              icon: Icons.keyboard_arrow_up,
              onPressed: onPreviousGroup,
            ),
            _GroupNavigationButton(
              icon: Icons.keyboard_arrow_down,
              onPressed: onNextGroup,
            ),
          ],
        ],
      ),
    );

    if (onToggleCollapse == null) {
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggleCollapse,
        child: row,
      ),
    );
  }
}

class _GroupNavigationButton extends StatelessWidget {
  const _GroupNavigationButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      visualDensity: VisualDensity.compact,
      splashRadius: 16,
      onPressed: onPressed,
    );
  }
}

/// Renders the 9-color palette picker as a 3-column grid of color swatches.
class TabGroupColorPicker extends StatelessWidget {
  const TabGroupColorPicker({
    required this.selectedColor,
    required this.onChanged,
    super.key,
  });

  final Color selectedColor;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = tabGroupPalette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: palette.map((c) {
        final selected = c.toARGB32() == selectedColor.toARGB32();
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(c),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
          ),
        );
      }).toList(),
    );
  }
}

/// Dialog to create a new group. Returns the created group's id, or null if
/// cancelled.
Future<String?> showCreateTabGroupDialog(BuildContext context) async {
  final searchHandler = SearchHandler.instance;
  final defaultColor = nextDefaultGroupColor(searchHandler.tabGroups.length);
  final nameController = TextEditingController();
  Color color = defaultColor;

  String? createdId;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return SettingsDialog(
            title: Text(context.loc.tabs.groups.newGroupTitle),
            contentItems: [
              SettingsTextInput(
                title: context.loc.tabs.groups.groupName,
                titleAsLabel: true,
                controller: nameController,
                drawBottomBorder: false,
                margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                autofocus: true,
                clearable: true,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(context.loc.tabs.groups.groupColor, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TabGroupColorPicker(
                  selectedColor: color,
                  onChanged: (c) => setState(() => color = c),
                ),
              ),
            ],
            actionButtons: [
              const CancelButton(withIcon: true),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(context.loc.tabs.groups.create),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final group = searchHandler.createGroup(name: name, color: color);
                  createdId = group.id;
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    },
  );

  return createdId;
}

/// Dialog to edit an existing group's name and color.
Future<void> showEditTabGroupDialog(BuildContext context, String groupId) async {
  final searchHandler = SearchHandler.instance;
  final group = searchHandler.groupById(groupId);
  if (group == null) return;

  final nameController = TextEditingController(text: group.name.value);
  Color color = group.color.value;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return SettingsDialog(
            title: Text(context.loc.tabs.groups.editGroup),
            contentItems: [
              SettingsTextInput(
                title: context.loc.tabs.groups.groupName,
                titleAsLabel: true,
                controller: nameController,
                drawBottomBorder: false,
                margin: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                autofocus: true,
                clearable: true,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(context.loc.tabs.groups.groupColor, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TabGroupColorPicker(
                  selectedColor: color,
                  onChanged: (c) => setState(() => color = c),
                ),
              ),
            ],
            actionButtons: [
              const CancelButton(withIcon: true),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: Text(context.loc.tabs.groups.save),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) searchHandler.renameGroup(groupId, name);
                  searchHandler.recolorGroup(groupId, color);
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    },
  );
}

/// Confirm-and-delete dialog. The user picks whether to also delete contained
/// tabs.
Future<void> showDeleteTabGroupDialog(BuildContext context, String groupId) async {
  final searchHandler = SearchHandler.instance;
  final group = searchHandler.groupById(groupId);
  if (group == null) return;

  bool alsoDeleteTabs = false;
  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final tabsInGroup = searchHandler.tabs.where((t) => t.groupId.value == groupId).length;
          return SettingsDialog(
            title: Text(context.loc.tabs.groups.deleteGroupNamed(name: group.name.value)),
            contentItems: [
              if (tabsInGroup > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text(context.loc.tabs.groups.tabsInGroup(count: tabsInGroup)),
                ),
              if (tabsInGroup > 0)
                SettingsToggle(
                  title: context.loc.tabs.groups.deleteWithTabs,
                  subtitle: Text(context.loc.tabs.groups.otherwiseBecomeUngrouped),
                  value: alsoDeleteTabs,
                  onChanged: (v) => setState(() => alsoDeleteTabs = v),
                  drawBottomBorder: false,
                ),
            ],
            actionButtons: [
              const CancelButton(withIcon: true),
              DeleteButton(
                withIcon: true,
                action: () {
                  searchHandler.deleteGroup(groupId, deleteTabs: alsoDeleteTabs);
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    },
  );
}

/// Bottom-sheet menu shown when ⋯ is tapped on a group header.
Future<void> showTabGroupActionsSheet(BuildContext context, String groupId) async {
  final group = SearchHandler.instance.groupById(groupId);
  if (group == null) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(context.loc.tabs.groups.renameRecolor),
              onTap: () {
                Navigator.of(context).pop();
                showEditTabGroupDialog(context, groupId);
              },
            ),
            ListTile(
              leading: Icon(group.collapsed.value ? Icons.unfold_more : Icons.unfold_less),
              title: Text(group.collapsed.value ? context.loc.tabs.groups.expand : context.loc.tabs.groups.collapse),
              onTap: () {
                Navigator.of(context).pop();
                SearchHandler.instance.toggleGroupCollapsed(groupId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(context.loc.tabs.groups.deleteGroup, style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(context).pop();
                showDeleteTabGroupDialog(context, groupId);
              },
            ),
          ],
        ),
      );
    },
  );
}
