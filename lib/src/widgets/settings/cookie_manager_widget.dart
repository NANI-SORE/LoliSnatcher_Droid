import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

/// Self-contained widget for managing cookies per booru.
///
/// Shows a booru selector, lists cookies for the selected booru,
/// and provides buttons to delete individual cookies or all cookies.
class CookieManagerWidget extends StatefulWidget {
  const CookieManagerWidget({super.key});

  @override
  State<CookieManagerWidget> createState() => _CookieManagerWidgetState();
}

class _CookieManagerWidgetState extends State<CookieManagerWidget> {
  Booru? selectedBooru;
  List<Cookie> selectedBooruCookies = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SettingsButton(name: '', enabled: false),
        SettingsButton(
          name: context.loc.settings.network.cookieCleaner,
          icon: const Icon(Icons.cookie_rounded),
        ),
        SettingsBooruDropdown(
          value: selectedBooru,
          nullable: true,
          onChanged: (newValue) async {
            selectedBooru = newValue;
            if (newValue != null) {
              selectedBooruCookies = await CookieManager.instance(
                webViewEnvironment: webViewEnvironment,
              ).getCookies(url: WebUri(selectedBooru!.baseURL!));
              if (Platform.isWindows) {
                selectedBooruCookies.addAll(globalWindowsCookies[selectedBooru!.baseURL!] ?? []);
              }
            } else {
              selectedBooruCookies = [];
            }
            setState(() {});
          },
          title: context.loc.booru,
          subtitle: Text(context.loc.settings.network.selectBooruToClearCookies),
        ),
        if (selectedBooruCookies.isNotEmpty) ...[
          SettingsButton(
            name: context.loc.settings.network.cookiesFor(booruName: selectedBooru?.name ?? ''),
            enabled: false,
          ),
          for (final Cookie cookie in selectedBooruCookies) ...[
            SettingsButton(
              name:
                  '${cookie.name} = ${cookie.value}${cookie.expiresDate != null ? '\nExpires: ${DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!)}' : ''}',
              action: () async {
                final bool res = await CookieManager.instance(webViewEnvironment: webViewEnvironment).deleteCookie(
                  url: WebUri(selectedBooru!.baseURL!),
                  name: cookie.name,
                );
                globalWindowsCookies[selectedBooru!.baseURL!]?.remove(cookie);

                if (!res) {
                  Logger.Inst().log(
                    'Failed to delete cookie',
                    'CookieManagerWidget',
                    'deleteCookie',
                    LogTypes.exception,
                    s: StackTrace.current,
                  );
                  FlashElements.showSnackbar(
                    context: context,
                    title: Text(context.loc.error),
                  );
                  return;
                }

                selectedBooruCookies.removeAt(selectedBooruCookies.indexOf(cookie));
                setState(() {});
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(context.loc.settings.network.cookieDeleted(cookieName: cookie.name)),
                );
              },
            ),
          ],
        ],
        SettingsButton(
          name: selectedBooru != null
              ? context.loc.settings.network.clearCookiesFor(booruName: selectedBooru!.name!)
              : context.loc.settings.network.clearCookies,
          icon: const Icon(
            Icons.delete_forever,
            color: Colors.red,
          ),
          action: () async {
            if (selectedBooru != null) {
              final bool res = await CookieManager.instance(
                webViewEnvironment: webViewEnvironment,
              ).deleteCookies(url: WebUri(selectedBooru!.baseURL!));
              globalWindowsCookies[selectedBooru!.baseURL!]?.clear();

              if (!res) {
                Logger.Inst().log(
                  'Failed to delete cookies',
                  'CookieManagerWidget',
                  'deleteCookies',
                  LogTypes.exception,
                  s: StackTrace.current,
                );
                FlashElements.showSnackbar(
                  context: context,
                  title: Text(context.loc.error),
                );
                return;
              }

              FlashElements.showSnackbar(
                context: context,
                title: Text(
                  context.loc.settings.network.cookiesForBooruDeleted(booruName: selectedBooru?.name ?? ''),
                ),
              );
            } else {
              await CookieManager.instance(webViewEnvironment: webViewEnvironment).deleteAllCookies();
              globalWindowsCookies.clear();
              FlashElements.showSnackbar(
                context: context,
                title: Text(context.loc.settings.network.allCookiesDeleted),
              );
            }

            selectedBooru = null;
            selectedBooruCookies.clear();
            setState(() {});
          },
        ),
      ],
    );
  }
}
