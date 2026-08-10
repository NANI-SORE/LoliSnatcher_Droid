import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/image/booru_favicon.dart';
import 'package:lolisnatcher/src/widgets/preview/shimmer_builder.dart';

void main() {
  setUpAll(() {
    if (SettingsRegistry.instance.isEmpty) {
      registerAllSettings();
    }
  });

  setUp(BooruFavicon.debugClearProviderCache);

  testWidgets('empty custom favicon uses the placeholder without loading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BooruFavicon(null, customFaviconUrl: '  '),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(CupertinoIcons.question), findsOneWidget);
    expect(find.byType(Shimmer), findsNothing);
    expect(BooruFavicon.debugCachedProviderCount, 0);
  });
}
