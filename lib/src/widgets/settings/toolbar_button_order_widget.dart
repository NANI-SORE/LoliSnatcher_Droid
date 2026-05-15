import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/gallery_button.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Self-contained widget for reordering and toggling viewer toolbar buttons.
///
/// Reads from and writes directly to [SettingsHandler.buttonOrder] and
/// [SettingsHandler.disabledButtons]. Changes are committed when the parent
/// page pops and calls `saveSettings()`.
class ToolbarButtonOrderWidget extends StatefulWidget {
  const ToolbarButtonOrderWidget({super.key});

  @override
  State<ToolbarButtonOrderWidget> createState() => _ToolbarButtonOrderWidgetState();
}

class _ToolbarButtonOrderWidgetState extends State<ToolbarButtonOrderWidget> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late final List<GalleryButton> buttonOrder;
  late final List<GalleryButton> disabledButtons;

  @override
  void initState() {
    super.initState();
    buttonOrder = SX.buttonOrder.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
    disabledButtons = SX.disabledButtons.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
  }

  @override
  void dispose() {
    SX.buttonOrder.state.value = buttonOrder.map((b) => b.name).toList();
    SX.disabledButtons.state.value = disabledButtons.map((b) => b.name).toList();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color baseColor = Theme.of(context).colorScheme.secondary;
    final Color oddItemColor = baseColor.withValues(alpha: 0.25);
    final Color evenItemColor = baseColor.withValues(alpha: 0.15);

    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(child: Text(context.loc.settings.viewer.toolbarButtonsOrder)),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                setState(() {
                  buttonOrder.clear();
                  buttonOrder.addAll(
                    SX.buttonOrder.state.defaultValue.map(GalleryButton.fromString).whereType<GalleryButton>(),
                  );
                  disabledButtons.clear();
                  disabledButtons.addAll(
                    SX.disabledButtons.state.defaultValue.map(GalleryButton.fromString).whereType<GalleryButton>(),
                  );
                });
              },
            ),
            IconButton(
              icon: Icon(
                Icons.help_outline,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return SettingsDialog(
                      title: Text(context.loc.settings.viewer.buttonsOrder),
                      contentItems: [
                        Text(context.loc.settings.viewer.longPressToChangeItemOrder),
                        Text(context.loc.settings.viewer.atLeast4ButtonsVisibleOnToolbar),
                        Text(context.loc.settings.viewer.otherButtonsWillGoIntoOverflow),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: borderWidth,
          ),
        ),
        collapsedShape: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: borderWidth,
          ),
        ),
        iconColor: Theme.of(context).colorScheme.onSurface,
        children: [
          ReorderableListView(
            padding: const EdgeInsets.fromLTRB(0, 5, 0, 5),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            children: [
              for (int index = 0; index < buttonOrder.length; index++)
                ReorderableDelayedDragStartListener(
                  key: ValueKey('item-${buttonOrder[index]}'),
                  index: index,
                  child: Builder(
                    builder: (context) {
                      final button = buttonOrder[index];
                      final title = button.locName;

                      final bool isInfo = button.isInfo;

                      final bool isActive = !disabledButtons.contains(button) || isInfo;

                      return ListTile(
                        onTap: () {
                          if (!isInfo) {
                            setState(() {
                              if (isActive) {
                                disabledButtons.add(button);
                              } else {
                                disabledButtons.remove(button);
                              }
                            });
                          }

                          FlashElements.showSnackbar(
                            context: context,
                            title: Text(
                              context.loc.settings.viewer.longPressToMoveItems,
                              style: const TextStyle(fontSize: 20),
                            ),
                            key: 'toolbar-button-order',
                            isKeyUnique: true,
                            leadingIcon: Icons.warning_amber,
                            leadingIconColor: Colors.yellow,
                            sideColor: Colors.yellow,
                          );
                        },
                        key: Key('item-${button.name}'),
                        minTileHeight: 64,
                        tileColor: index.isOdd ? oddItemColor : evenItemColor,
                        title: Text(title),
                        subtitle: switch (button) {
                          .externalPlayer => Text(context.loc.settings.viewer.onlyForVideos),
                          _ => null,
                        },
                        leading: Opacity(
                          opacity: isInfo ? 0.5 : 1,
                          child: Checkbox(
                            key: Key('checkbox-${button.name}'),
                            value: isActive,
                            onChanged: (_) {
                              if (isInfo) {
                                FlashElements.showSnackbar(
                                  title: Text(
                                    context.loc.settings.viewer.thisButtonCannotBeDisabled,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                if (isActive) {
                                  disabledButtons.add(button);
                                } else {
                                  disabledButtons.remove(button);
                                }
                              });
                            },
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              switch (button) {
                                .snatch => Icons.save,
                                .favourite => Icons.favorite,
                                .info => Icons.info,
                                .share => Icons.share,
                                .select => Icons.check_box,
                                .open => Icons.public,
                                .autoscroll => Icons.play_arrow,
                                .reloadnoscale => Icons.refresh,
                                .toggleQuality => Icons.high_quality,
                                .externalPlayer => Icons.exit_to_app,
                                .imageSearch => Icons.image_search_rounded,
                              },
                            ),
                            ReorderableDragStartListener(
                              key: Key('draghandle-#${buttonOrder[index]}'),
                              index: index,
                              child: const IconButton(
                                onPressed: null,
                                icon: Icon(Icons.drag_handle),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
            onReorderItem: (int oldIndex, int newIndex) {
              setState(() {
                final item = buttonOrder.removeAt(oldIndex);
                buttonOrder.insert(newIndex, item);
              });
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
