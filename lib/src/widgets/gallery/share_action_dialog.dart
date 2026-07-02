import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/share_action.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

typedef ShareActionCallback = FutureOr<void> Function();
typedef RememberShareActionCallback = FutureOr<void> Function(ShareAction action);

class ShareActionController {
  const ShareActionController({
    required this.currentAction,
    required this.postUrl,
    required this.postUrlWithTags,
    required this.fileUrl,
    required this.fileUrlWithTags,
    required this.file,
    required this.fileWithTags,
    this.hydrus,
    this.showPostUrlOptions = true,
    this.showTagOptions = true,
    this.showHydrusOption = false,
    this.onRememberAction,
  });

  final ShareAction currentAction;
  final ShareActionCallback postUrl;
  final ShareActionCallback postUrlWithTags;
  final ShareActionCallback fileUrl;
  final ShareActionCallback fileUrlWithTags;
  final ShareActionCallback file;
  final ShareActionCallback fileWithTags;
  final ShareActionCallback? hydrus;
  final bool showPostUrlOptions;
  final bool showTagOptions;
  final bool showHydrusOption;
  final RememberShareActionCallback? onRememberAction;

  Map<ShareAction, ShareActionCallback> get actions => {
    ShareAction.postUrl: postUrl,
    ShareAction.postUrlWithTags: postUrlWithTags,
    ShareAction.fileUrl: fileUrl,
    ShareAction.fileUrlWithTags: fileUrlWithTags,
    ShareAction.file: file,
    ShareAction.fileWithTags: fileWithTags,
    ShareAction.hydrus: ?hydrus,
  };

  Future<void> run(ShareAction action, BuildContext context) async {
    switch (_visibleActionFor(action, showTagOptions: showTagOptions)) {
      case ShareAction.postUrl:
        await postUrl();
        return;
      case ShareAction.postUrlWithTags:
        await postUrlWithTags();
        return;
      case ShareAction.fileUrl:
        await fileUrl();
        return;
      case ShareAction.fileUrlWithTags:
        await fileUrlWithTags();
        return;
      case ShareAction.file:
        await file();
        return;
      case ShareAction.fileWithTags:
        await fileWithTags();
        return;
      case ShareAction.hydrus:
        await hydrus?.call();
        return;
      case ShareAction.ask:
        showDialog(context);
        return;
    }
  }

  void showDialog(BuildContext context) {
    showShareActionDialog(
      context: context,
      currentAction: currentAction,
      actions: actions,
      showPostUrlOptions: showPostUrlOptions,
      showTagOptions: showTagOptions,
      showHydrusOption: showHydrusOption,
      onRememberAction: onRememberAction,
    );
  }
}

void showShareActionDialog({
  required BuildContext context,
  required ShareAction currentAction,
  required Map<ShareAction, ShareActionCallback> actions,
  bool showPostUrlOptions = true,
  bool showTagOptions = true,
  bool showHydrusOption = false,
  RememberShareActionCallback? onRememberAction,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      bool rememberChoice = false;
      final bool showRememberChoice = currentAction.isAsk && onRememberAction != null;
      final ShareAction visibleCurrentAction = _visibleActionFor(
        currentAction,
        showTagOptions: showTagOptions,
      );

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> onActionSelected(ShareAction action) async {
            if (rememberChoice) {
              await onRememberAction?.call(action);
            }
          }

          return SettingsDialog(
            title: Text(dialogContext.loc.viewer.appBar.whatToShare),
            contentItems: [
              const SizedBox(height: 15),
              Column(
                children: [
                  if (showPostUrlOptions) ...[
                    _ShareActionTile(
                      action: ShareAction.postUrl,
                      currentAction: visibleCurrentAction,
                      icon: const Icon(CupertinoIcons.link),
                      title: dialogContext.loc.viewer.appBar.postURL,
                      onSelected: onActionSelected,
                      onTap: actions[ShareAction.postUrl],
                    ),
                    if (showTagOptions)
                      _ShareActionTile(
                        action: ShareAction.postUrlWithTags,
                        currentAction: visibleCurrentAction,
                        icon: const _TagOverlayIcon(child: Icon(CupertinoIcons.link)),
                        title: dialogContext.loc.viewer.appBar.postURLWithTags,
                        onSelected: onActionSelected,
                        onTap: actions[ShareAction.postUrlWithTags],
                      ),
                  ],
                  _ShareActionTile(
                    action: ShareAction.fileUrl,
                    currentAction: visibleCurrentAction,
                    icon: const Icon(CupertinoIcons.link),
                    title: dialogContext.loc.viewer.appBar.fileURL,
                    onSelected: onActionSelected,
                    onTap: actions[ShareAction.fileUrl],
                  ),
                  if (showTagOptions)
                    _ShareActionTile(
                      action: ShareAction.fileUrlWithTags,
                      currentAction: visibleCurrentAction,
                      icon: const _TagOverlayIcon(child: Icon(CupertinoIcons.link)),
                      title: dialogContext.loc.viewer.appBar.fileURLWithTags,
                      onSelected: onActionSelected,
                      onTap: actions[ShareAction.fileUrlWithTags],
                    ),
                  _ShareActionTile(
                    action: ShareAction.file,
                    currentAction: visibleCurrentAction,
                    icon: const Icon(Icons.file_present),
                    title: dialogContext.loc.viewer.appBar.file,
                    onSelected: onActionSelected,
                    onTap: actions[ShareAction.file],
                  ),
                  if (showTagOptions)
                    _ShareActionTile(
                      action: ShareAction.fileWithTags,
                      currentAction: visibleCurrentAction,
                      icon: const _TagOverlayIcon(child: Icon(Icons.file_present)),
                      title: dialogContext.loc.viewer.appBar.fileWithTags,
                      onSelected: onActionSelected,
                      onTap: actions[ShareAction.fileWithTags],
                    ),
                  if (showHydrusOption)
                    _ShareActionTile(
                      action: ShareAction.hydrus,
                      currentAction: visibleCurrentAction,
                      icon: const Icon(Icons.file_present),
                      title: dialogContext.loc.viewer.appBar.hydrus,
                      onSelected: onActionSelected,
                      onTap: actions[ShareAction.hydrus],
                    ),
                ],
              ),
              if (showRememberChoice)
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 15),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                    ),
                    onTap: () {
                      setDialogState(() {
                        rememberChoice = !rememberChoice;
                      });
                    },
                    leading: Checkbox(
                      value: rememberChoice,
                      onChanged: (value) {
                        setDialogState(() {
                          rememberChoice = value ?? false;
                        });
                      },
                    ),
                    title: Text(dialogContext.loc.viewer.appBar.rememberMyChoice),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

ShareAction _visibleActionFor(
  ShareAction action, {
  required bool showTagOptions,
}) {
  if (showTagOptions) return action;

  return switch (action) {
    ShareAction.postUrlWithTags => ShareAction.postUrl,
    ShareAction.fileUrlWithTags => ShareAction.fileUrl,
    ShareAction.fileWithTags => ShareAction.file,
    _ => action,
  };
}

class _ShareActionTile extends StatelessWidget {
  const _ShareActionTile({
    required this.action,
    required this.currentAction,
    required this.icon,
    required this.title,
    required this.onTap,
    this.onSelected,
  });

  final ShareAction action;
  final ShareAction currentAction;
  final Widget icon;
  final String title;
  final ShareActionCallback? onTap;
  final RememberShareActionCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: Theme.of(context).colorScheme.secondary,
            width: currentAction == action ? 3 : 1,
          ),
        ),
        onTap: onTap == null
            ? null
            : () async {
                await onSelected?.call(action);
                Navigator.of(context).pop();
                await onTap!();
              },
        leading: icon,
        title: Text(title),
      ),
    );
  }
}

class _TagOverlayIcon extends StatelessWidget {
  const _TagOverlayIcon({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        const Positioned(
          bottom: -10,
          right: -10,
          child: Icon(CupertinoIcons.tag, size: 14),
        ),
      ],
    );
  }
}
