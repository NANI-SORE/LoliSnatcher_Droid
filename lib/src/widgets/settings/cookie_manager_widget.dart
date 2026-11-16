import 'package:flutter/material.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/webview_cookies.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

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
  bool busy = false;

  void showError(Object error, StackTrace stack) {
    Logger.Inst().log(error.toString(), 'CookieManagerWidget', 'cookies', LogTypes.exception, s: stack);
    if (mounted) FlashElements.showSnackbar(context: context, title: Text(context.loc.error));
  }

  Future<void> selectBooru(Booru? booru) async {
    if (busy) return;
    setState(() {
      selectedBooru = booru;
      selectedBooruCookies = [];
      busy = true;
    });
    try {
      final cookies = booru == null ? <Cookie>[] : await WebviewCookies.forSite(Uri.parse(booru.baseURL!));
      if (mounted) setState(() => selectedBooruCookies = cookies);
    } catch (e, s) {
      showError(e, s);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteCookies({Cookie? cookie}) async {
    if (busy) return;
    final booru = selectedBooru;
    setState(() => busy = true);
    try {
      final uri = booru == null ? null : Uri.parse(booru.baseURL!);
      final bool deleted;
      if (uri == null) {
        deleted = await WebviewCookies.clearAll();
      } else if (cookie != null) {
        deleted = await WebviewCookies.delete(uri, cookie);
      } else {
        deleted = await WebviewCookies.clearSite(uri);
      }
      final remaining = uri == null ? <Cookie>[] : await WebviewCookies.forSite(uri);
      if (!mounted) return;
      setState(() => selectedBooruCookies = remaining);
      if (!deleted) throw StateError('Cookies remain after deletion');
      FlashElements.showSnackbar(
        context: context,
        title: Text(
          cookie != null
              ? context.loc.settings.network.cookieDeleted(cookieName: cookie.name)
              : booru != null
              ? context.loc.settings.network.cookiesForBooruDeleted(booruName: booru.name ?? '')
              : context.loc.settings.network.allCookiesDeleted,
        ),
      );
    } catch (e, s) {
      showError(e, s);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
          onChanged: busy ? null : selectBooru,
          title: context.loc.booru,
          subtitle: Text(context.loc.settings.network.selectBooruToClearCookies),
        ),
        if (busy) const LinearProgressIndicator(),
        if (selectedBooruCookies.isNotEmpty) ...[
          SettingsButton(
            name: context.loc.settings.network.cookiesFor(booruName: selectedBooru?.name ?? ''),
            enabled: false,
          ),
          for (final Cookie cookie in selectedBooruCookies) ...[
            SettingsButton(
              name:
                  '${cookie.name} = ${cookie.value}${cookie.expiresDate != null ? '\nExpires: ${DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!)}' : ''}',
              enabled: !busy,
              action: () => deleteCookies(cookie: cookie),
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
          enabled: !busy,
          action: deleteCookies,
        ),
      ],
    );
  }
}
