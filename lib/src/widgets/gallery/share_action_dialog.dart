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
  bool rememberChoice = false;
  bool includeTags =
      showTagOptions &&
      {
        ShareAction.postUrlWithTags,
        ShareAction.fileUrlWithTags,
        ShareAction.fileWithTags,
      }.contains(currentAction);
  showDialog(
    context: context,
    builder: (dialogContext) {
      final bool showRememberChoice = currentAction.isAsk && onRememberAction != null;
      final ShareAction visibleCurrentAction = _visibleActionFor(
        currentAction,
        showTagOptions: showTagOptions,
      );

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> onActionSelected(ShareAction action) async {
            if (rememberChoice) await onRememberAction?.call(action);
          }

          final choices = [
            if (showPostUrlOptions)
              (
                action: includeTags ? ShareAction.postUrlWithTags : ShareAction.postUrl,
                icon: CupertinoIcons.link,
                title: dialogContext.loc.viewer.appBar.postURL,
              ),
            (
              action: includeTags ? ShareAction.fileUrlWithTags : ShareAction.fileUrl,
              icon: Icons.link,
              title: dialogContext.loc.viewer.appBar.fileURL,
            ),
            (
              action: includeTags ? ShareAction.fileWithTags : ShareAction.file,
              icon: Icons.file_present,
              title: dialogContext.loc.viewer.appBar.file,
            ),
            if (showHydrusOption)
              (
                action: ShareAction.hydrus,
                icon: Icons.cloud_upload_outlined,
                title: dialogContext.loc.viewer.appBar.hydrus,
              ),
          ];
          return SettingsDialog(
            title: Text(dialogContext.loc.viewer.appBar.whatToShare),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            contentItems: [
              for (final choice in choices)
                _ShareActionTile(
                  action: choice.action,
                  currentAction: visibleCurrentAction,
                  icon: Icon(choice.icon),
                  title: choice.title,
                  onSelected: onActionSelected,
                  onTap: actions[choice.action],
                ),
              if (showTagOptions)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.loc.settings.downloads.includeTags),
                  value: includeTags,
                  onChanged: (value) => setDialogState(() => includeTags = value ?? false),
                ),
              if (showRememberChoice)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(dialogContext.loc.viewer.appBar.rememberMyChoice),
                  value: rememberChoice,
                  onChanged: (value) => setDialogState(() => rememberChoice = value ?? false),
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
      padding: const EdgeInsets.only(bottom: 6),
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
                if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
                Navigator.of(context).pop();
                await onSelected?.call(action);
                await onTap!();
              },
        leading: icon,
        title: Text(title),
      ),
    );
  }
}
