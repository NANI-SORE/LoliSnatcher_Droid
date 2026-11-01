import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/tag_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_edit_page.dart';
import 'package:lolisnatcher/src/pages/settings/booru_overrides_page.dart';
import 'package:lolisnatcher/src/widgets/root/theme_builder.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/preview/media_previews.dart';

Widget _buildTestApp(Widget home) {
  return TranslationProvider(
    child: MaterialApp(
      home: ThemeBuilder(child: home),
    ),
  );
}

void main() {
  setUpAll(() async {
    await LocaleSettings.instance.loadAllLocales();
    if (SettingsRegistry.instance.isEmpty) {
      registerAllSettings();
    }
    SearchHandler.register();
    TagHandler.register();
    SettingsHandler.register();
  });

  tearDownAll(() {
    SettingsHandler.unregister();
    TagHandler.unregister();
    SearchHandler.unregister();
  });

  setUp(() {
    // Use a typical phone surface so page-level layout follows the same
    // responsive path as the mobile application.
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.physicalSize = const Size(1080, 1920);
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('first-run language and theme controls use Flutter notifiers safely', (tester) async {
    await tester.pumpWidget(_buildTestApp(const Scaffold(body: MediaPreviews())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(loc.settings.language.title), findsWidgets);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
      _buildTestApp(
        BooruEdit.edit(
          booru,
          initialSection: BooruEditSection.overrides,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Overrides'), findsOneWidget);
    expect(find.text('Changes are saved automatically'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('new booru exposes non-autosaving draft overrides', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        BooruEdit.add(
          initialSection: BooruEditSection.overrides,
          initialOverrideCategory: SettingCategory.interface,
        ),
      ),
    );
    await tester.pump();

    final editor = tester.widget<BooruOverridesEditor>(find.byType(BooruOverridesEditor));
    expect(editor.autosave, isFalse);
    expect(editor.booruName, startsWith('__new_booru_draft_'));
    expect(find.byType(FloatingActionButton), findsOneWidget);

    SX.enableDrawerMascot.state.setOverrideFor(editor.booruName, true, save: false);
    expect(SX.enableDrawerMascot.state.hasOverrideFor(editor.booruName), isTrue);

    SX.portraitColumns.state.setOverrideFor(editor.booruName, 3, save: false);
    await tester.pump(const Duration(milliseconds: 350));
    final numeric = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is SettingsTextInput && widget.title == loc.settings.interface.previewColumnsPortrait,
      ),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(numeric, '7');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(SX.enableDrawerMascot.state.hasOverrideFor(editor.booruName), isFalse);
    expect(SX.portraitColumns.state.hasOverrideFor(editor.booruName), isFalse);
  });
}
