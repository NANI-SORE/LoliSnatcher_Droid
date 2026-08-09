import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_overrides_page.dart';

void main() {
  setUpAll(() async {
    await LocaleSettings.instance.loadAllLocales();
    if (SettingsRegistry.instance.isEmpty) {
      registerAllSettings();
    }
    SettingsHandler.register();
    SearchHandler.register();
  });

  tearDownAll(() {
    SearchHandler.unregister();
    SettingsHandler.unregister();
  });

  testWidgets('booru editor opens overrides in the same tabbed page', (tester) async {
    final booru = Booru(
      'Example',
      BooruType.Gelbooru,
      '',
      'https://example.com',
      '',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: BooruEdit(
            booru,
            initialSection: BooruEditSection.overrides,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Per-booru Settings'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('new booru exposes non-autosaving draft overrides', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: BooruEdit(
            Booru('New', BooruType.Autodetect, '', '', ''),
            initialSection: BooruEditSection.overrides,
          ),
        ),
      ),
    );
    await tester.pump();

    final editor = tester.widget<BooruOverridesEditor>(find.byType(BooruOverridesEditor));
    expect(editor.autosave, isFalse);
    expect(editor.booruName, startsWith('__new_booru_draft_'));

    SX.enableDrawerMascot.state.setOverrideFor(editor.booruName, true, save: false);
    expect(SX.enableDrawerMascot.state.hasOverrideFor(editor.booruName), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(SX.enableDrawerMascot.state.hasOverrideFor(editor.booruName), isFalse);
  });
}
