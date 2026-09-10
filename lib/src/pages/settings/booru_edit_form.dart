import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_alikes_handler.dart';
import 'package:lolisnatcher/src/boorus/gelbooru_handler.dart';
import 'package:lolisnatcher/src/boorus/hydrus_handler.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_form_controller.dart';
import 'package:lolisnatcher/src/utils/content_policy.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/html.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/tag_search_query_editor_page.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class BooruEditForm extends StatelessWidget {
  const BooruEditForm({
    required this.initialBooru,
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final Booru initialBooru;
  final BooruEditFormController controller;
  final VoidCallback onChanged;

  void _onConnectionChanged() {
    controller.invalidateTestResult();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          SettingsTextInput(
            controller: controller.name,
            title: context.loc.settings.booruEditor.booruName,
            onChanged: (_) => onChanged(),
            clearable: true,
            pasteable: true,
            enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
          ),
          SettingsTextInput(
            controller: controller.url,
            title: context.loc.settings.booruEditor.booruUrl,
            onChanged: (_) {
              controller.invalidateTestResult();
              if (controller.url.text.isEmpty) {
                controller.favicon.text = initialBooru.type == null ? '' : initialBooru.faviconURL ?? '';
                controller.testedType = initialBooru.type;
                controller.selectedType = initialBooru.type ?? BooruType.Autodetect;
              }
              onChanged();
            },
            inputType: TextInputType.url,
            clearable: true,
            pasteable: true,
            enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
          ),
          if (PlatformExt.hasWebviewSupport && ContentPolicy.canOpenWebview)
            SettingsButton(
              name: context.loc.settings.webview.openWebview,
              subtitle: Text(context.loc.settings.webview.openWebviewTip),
              icon: const Icon(Icons.public),
              action: () {
                if (controller.url.text.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => InAppWebviewView(initialUrl: controller.url.text),
                    ),
                  );
                }
              },
            ),
          SettingsDropdown(
            value: controller.selectedType,
            items: BooruType.dropDownValues,
            onChanged: (BooruType? newValue) {
              controller.selectedType = newValue ?? BooruType.values.first;
              _onConnectionChanged();
            },
            title: context.loc.settings.booruEditor.booruType,
            itemTitleBuilder: (BooruType? type) => type?.alias ?? '',
            expendableByScroll: true,
            searchable: true,
            searchCheck: (searchText, item) =>
                item.name.toLowerCase().contains(searchText) || item.alias.toLowerCase().contains(searchText),
          ),
          SettingsTextInput(
            controller: controller.favicon,
            title: context.loc.settings.booruEditor.booruFavicon,
            hintText: context.loc.settings.booruEditor.booruFaviconPlaceholder,
            onChanged: (_) => onChanged(),
            inputType: TextInputType.url,
            enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
            trailingIcon: SizedBox(
              height: 24,
              width: 24,
              child: BooruFavicon(
                null,
                customFaviconUrl: controller.favicon.text,
                size: 24,
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final useDraftBooru = !controller.selectedType.isAutodetect && controller.url.text.isNotEmpty;
              return TagSearchBox(
                controller: controller.defaultTags,
                title: context.loc.settings.booruEditor.booruDefTags,
                onChanged: (_, _) => onChanged(),
                hintText: context.loc.settings.booruEditor.booruDefTagsPlaceholder,
                booru: useDraftBooru
                    ? Booru(
                        'Temp',
                        controller.selectedType,
                        '',
                        controller.url.text,
                        controller.favicon.text,
                      )
                    : null,
                allowMultipleTags: true,
                readOnlyPreview: useDraftBooru,
                clearable: true,
              );
            },
          ),
          if (_shouldShowInstructions(context))
            Container(
              margin: const EdgeInsets.fromLTRB(10, 16, 10, 16),
              width: double.infinity,
              child: LoliHtml(_instructions(context)),
            ),
          if (controller.selectedType == BooruType.Hydrus)
            _HydrusAccessKeyWidget(
              urlController: controller.url,
              apiKeyController: controller.apiKey,
              onApiKeyChanged: _onConnectionChanged,
            ),
          SettingsTextInput(
            controller: controller.userId,
            onChanged: (_) => _onConnectionChanged(),
            title: _userIdTitle(context),
            clearable: true,
            pasteable: true,
            drawTopBorder: true,
            enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
          ),
          SettingsTextInput(
            controller: controller.apiKey,
            onChanged: (_) => _onConnectionChanged(),
            title: _apiKeyTitle(context),
            pasteable: true,
            clearable: true,
            obscureable: true,
            enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
          ),
          if (_showAuthInputs) ...[
            SettingsTextInput(
              controller: controller.authLogin,
              onChanged: (_) => _onConnectionChanged(),
              title: context.loc.login,
              hintText: context.loc.login,
              clearable: true,
              pasteable: true,
              drawTopBorder: true,
              enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
            ),
            SettingsTextInput(
              controller: controller.authPassword,
              onChanged: (_) => _onConnectionChanged(),
              title: context.loc.password,
              hintText: context.loc.password,
              clearable: true,
              pasteable: true,
              drawTopBorder: true,
              obscureable: true,
              enableIMEPersonalizedLearning: !SX.incognitoKeyboard.value,
            ),
          ],
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
        ],
      ),
    );
  }

  bool get _showAuthInputs {
    final host = Uri.tryParse(controller.url.text)?.host.toLowerCase() ?? controller.url.text.toLowerCase();
    return host.contains('gelbooru.com') || host.contains('rule34.xxx');
  }

  String _apiKeyTitle(BuildContext context) {
    switch (controller.selectedType) {
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
      case BooruType.R34Hentai:
      case BooruType.InkBunny:
        return context.loc.password;
      default:
        return context.loc.apiKey;
    }
  }

  String _userIdTitle(BuildContext context) {
    switch (controller.selectedType) {
      case BooruType.Sankaku:
      case BooruType.IdolSankaku:
      case BooruType.Danbooru:
      case BooruType.R34Hentai:
        return context.loc.login;
      default:
        return context.loc.userId;
    }
  }

  String _instructions(BuildContext context) {
    switch (controller.selectedType) {
      case BooruType.Autodetect:
      case BooruType.Gelbooru:
      case BooruType.GelbooruAlike:
        if (controller.url.text.contains('gelbooru.com')) {
          return GelbooruHandler.credentialsWarningText;
        }
        if (controller.url.text.contains('rule34.xxx')) {
          return GelbooruAlikesHandler.r34xxxCredentialsWarningText;
        }
        break;
      case BooruType.Hydrus:
        return '';
      default:
        break;
    }
    return context.loc.settings.booruEditor.booruDefaultInstructions;
  }

  bool _shouldShowInstructions(BuildContext context) {
    final instructions = _instructions(context);
    return instructions.trim().isNotEmpty && ContentPolicy.isBooruAllowed(controller.toBooru());
  }
}

class _HydrusAccessKeyWidget extends StatelessWidget {
  const _HydrusAccessKeyWidget({
    required this.urlController,
    required this.apiKeyController,
    required this.onApiKeyChanged,
  });

  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final VoidCallback onApiKeyChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(10),
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final hydrus = HydrusHandler(
                Booru('Hydrus', BooruType.Hydrus, 'Hydrus', urlController.text, ''),
                5,
              );
              final accessKey = await hydrus.getAccessKey();
              if (!context.mounted) return;
              if (accessKey.isNotEmpty) {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyRequestedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Icons.warning_amber,
                  leadingIconColor: Colors.yellow,
                  sideColor: Colors.yellow,
                );
                apiKeyController.text = accessKey;
                onApiKeyChanged();
              } else {
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(
                    context.loc.settings.booruEditor.accessKeyFailedTitle,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Text(
                    context.loc.settings.booruEditor.accessKeyFailedMsg,
                    style: const TextStyle(fontSize: 16),
                  ),
                  leadingIcon: Icons.warning_amber,
                  leadingIconColor: Colors.red,
                  sideColor: Colors.red,
                );
              }
            },
            child: Text(context.loc.settings.booruEditor.getHydrusApiKey),
          ),
        ),
        Container(
          margin: const EdgeInsets.all(10),
          width: double.infinity,
          child: Text(context.loc.settings.booruEditor.hydrusInstructions),
        ),
      ],
    );
  }
}
