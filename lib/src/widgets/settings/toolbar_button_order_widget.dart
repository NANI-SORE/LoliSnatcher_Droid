import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/gallery_button.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

/// Self-contained widget for reordering and toggling viewer toolbar buttons.
///
/// Reads from and writes directly to [SX.buttonOrder] and
/// [SX.disabledButtons]. Changes are saved by the settings autosave layer.
class ToolbarButtonOrderWidget extends StatefulWidget {
  const ToolbarButtonOrderWidget({super.key});

  @override
  State<ToolbarButtonOrderWidget> createState() => _ToolbarButtonOrderWidgetState();
}

class _ToolbarButtonOrderWidgetState extends State<ToolbarButtonOrderWidget> {
  late final List<GalleryButton> buttonOrder;
  late final List<GalleryButton> disabledButtons;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    buttonOrder = SX.buttonOrder.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
    disabledButtons = SX.disabledButtons.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
    SX.buttonOrder.state.effectiveNotifier.addListener(_syncFromSettings);
    SX.disabledButtons.state.effectiveNotifier.addListener(_syncFromSettings);
  }

  @override
  void dispose() {
    SX.buttonOrder.state.effectiveNotifier.removeListener(_syncFromSettings);
    SX.disabledButtons.state.effectiveNotifier.removeListener(_syncFromSettings);
    super.dispose();
  }

  void _commit() {
    _isCommitting = true;
    try {
      SX.buttonOrder.state.value = buttonOrder.map((button) => button.toJson()).toList();
      SX.disabledButtons.state.value = disabledButtons.map((button) => button.toJson()).toList();
    } finally {
      _isCommitting = false;
    }
  }

  void _syncFromSettings() {
    if (_isCommitting) {
      return;
    }
    final newOrder = SX.buttonOrder.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
    final newDisabled = SX.disabledButtons.value.map(GalleryButton.fromString).whereType<GalleryButton>().toList();
    if (listEquals(buttonOrder, newOrder) && listEquals(disabledButtons, newDisabled)) {
      return;
    }
    setState(() {
      buttonOrder
        ..clear()
        ..addAll(newOrder);
      disabledButtons
        ..clear()
        ..addAll(newDisabled);
    });
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
                  _commit();
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
                            _setButtonEnabled(button, !isActive);
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

                              _setButtonEnabled(button, !isActive);
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
                _commit();
              });
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _setButtonEnabled(GalleryButton button, bool enabled) {
    if (button.isInfo) return;
    setState(() {
      if (enabled) {
        disabledButtons.remove(button);
      } else if (!disabledButtons.contains(button)) {
        disabledButtons.add(button);
      }
      _commit();
    });
  }
}
