import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/proxy_type.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/utils/http_overrides.dart';
import 'package:lolisnatcher/src/widgets/settings/toolbar_button_order_widget.dart';

const legacyKeys = <String>{
  'previewMode',
  'previewDisplay',
  'previewDisplayFallback',
  'shareAction',
  'videoCacheMode',
  'galleryMode',
  'snatchMode',
  'galleryScrollDirection',
  'galleryBarPosition',
  'zoomButtonPosition',
  'changePageButtonsPosition',
  'scrollGridButtonsPosition',
  'videoBackendMode',
  'altVideoPlayerVO',
  'altVideoPlayerHWDEC',
  'proxyType',
  'defTags',
  'prefBooru',
  'extPathOverride',
  'drawerMascotPathOverride',
  'backupPath',
  'lastSyncIp',
  'lastSyncPort',
  'customUserAgent',
  'proxyAddress',
  'proxyUsername',
  'proxyPassword',
  'hiddenTags',
  'markedTags',
  'limit',
  'portraitColumns',
  'landscapeColumns',
  'preloadCount',
  'preloadHeight',
  'snatchCooldown',
  'volumeButtonsScrollSpeed',
  'galleryAutoScrollTime',
  'cacheSize',
  'autoLockTimeout',
  'mousewheelScrollSpeed',
  'preloadSizeLimit',
  'jsonWrite',
  'autoPlayEnabled',
  'loadingGif',
  'thumbnailCache',
  'mediaCache',
  'autoHideImageBar',
  'dbEnabled',
  'indexesEnabled',
  'searchHistoryEnabled',
  'filterHated',
  'filterMarked',
  'filterFavourites',
  'filterSnatched',
  'filterAi',
  'useVolumeButtonsForScroll',
  'shitDevice',
  'disableVideo',
  'enableDrawerMascot',
  'allowSelfSignedCerts',
  'disableImageScaling',
  'gifsAsThumbnails',
  'desktopListsDrag',
  'wakeLockEnabled',
  'tagTypeFetchEnabled',
  'downloadNotifications',
  'allowRotation',
  'enableHeroTransitions',
  'disableCustomPageTransitions',
  'incognitoKeyboard',
  'appAlias',
  'hideNotes',
  'startVideosMuted',
  'snatchOnFavourite',
  'favouriteOnSnatch',
  'disableVibration',
  'altVideoPlayerHwAccel',
  'showBottomSearchbar',
  'useTopSearchbarInput',
  'showSearchbarQuickActions',
  'autofocusSearchbar',
  'expandDetails',
  'usePredictiveBack',
  'useLockscreen',
  'blurOnLeave',
  'buttonOrder',
  'disabledButtons',
  'cacheDuration',
  'appMode',
  'handSide',
  'theme',
  'themeMode',
  'useDynamicColor',
  'isAmoled',
  'fontFamily',
  'locale',
  'customPrimaryColor',
  'customAccentColor',
};

void main() {
  final registry = SettingsRegistry.instance;

  setUpAll(() {
    if (registry.isEmpty) {
      registerAllSettings();
    }
  });

  setUp(() {
    registry.setCurrentBooru(null);
    registry.resetAll();
    for (final state in registry.perBooruSettings) {
      state.clearAllOverrides();
    }
  });

  test('registers every canonical pre-migration setting', () {
    final registeredJsonKeys = registry.all
        .where((state) => !state.def.isWidgetSlot && !state.def.isTransient)
        .map((state) => state.def.jsonKey)
        .toSet();

    expect(registeredJsonKeys, containsAll(legacyKeys));
    for (final key in legacyKeys) {
      expect(
        registry.all.where((state) => state.def.jsonKey == key),
        hasLength(1),
        reason: '$key must have exactly one canonical definition',
      );
    }
  });

  test('loads legacy tag aliases and writes canonical keys', () {
    registry.loadFromJson({
      'hatedTags': ['legacy_hidden'],
      'lovedTags': ['legacy_marked'],
    });

    expect(SX.hiddenTags.value, ['legacy_hidden']);
    expect(SX.markedTags.value, ['legacy_marked']);

    final json = registry.toJson();
    expect(json['hiddenTags'], ['legacy_hidden']);
    expect(json['markedTags'], ['legacy_marked']);
    expect(json, isNot(contains('hatedTags')));
    expect(json, isNot(contains('lovedTags')));
  });

  test('canonical keys take precedence over legacy aliases', () {
    registry.loadFromJson({
      'hiddenTags': ['canonical'],
      'hatedTags': ['legacy'],
    });

    expect(SX.hiddenTags.value, ['canonical']);
  });

  test('invalid persisted numeric values fall back to defaults', () {
    registry.loadFromJson({
      'portraitColumns': 0,
      'preloadCount': 99,
      'preloadSizeLimit': -1,
    });

    expect(SX.portraitColumns.value, SX.portraitColumns.state.defaultValue);
    expect(SX.preloadCount.value, SX.preloadCount.state.defaultValue);
    expect(SX.preloadSizeLimit.value, SX.preloadSizeLimit.state.defaultValue);

    SX.portraitColumns.state.value = 0;
    expect(SX.portraitColumns.value, 1);
  });

  test('restores legacy device-specific settings', () {
    const keys = {
      SettingKey.showBottomSearchbar,
      SettingKey.useTopSearchbarInput,
      SettingKey.showSearchbarQuickActions,
      SettingKey.autofocusSearchbar,
      SettingKey.expandDetails,
    };

    expect(
      keys.every((key) => registry.get<dynamic>(key)!.def.isDeviceSpecific),
      isTrue,
    );
  });

  test('theme settings retain per-booru override support', () {
    const keys = {
      SettingKey.theme,
      SettingKey.themeMode,
      SettingKey.isAmoled,
      SettingKey.useDynamicColor,
      SettingKey.customPrimaryColor,
      SettingKey.customAccentColor,
      SettingKey.fontFamily,
      SettingKey.enableDrawerMascot,
      SettingKey.drawerMascotPathOverride,
    };

    expect(
      keys.every((key) => registry.get<dynamic>(key)!.def.supportsPerBooru),
      isTrue,
    );
  });

  test('proxy directive follows active booru overrides immediately', () {
    SX.proxyType.state.globalValue = ProxyType.direct;
    SX.proxyAddress.state.globalValue = '';
    SX.proxyUsername.state.globalValue = '';
    SX.proxyPassword.state.globalValue = '';

    SX.proxyType.state.setOverrideFor('A', ProxyType.http);
    SX.proxyAddress.state.setOverrideFor('A', 'proxy-a.example:8080');

    SX.proxyType.state.setOverrideFor('B', ProxyType.socks5);
    SX.proxyAddress.state.setOverrideFor('B', 'proxy-b.example:1080');
    SX.proxyUsername.state.setOverrideFor('B', 'user');
    SX.proxyPassword.state.setOverrideFor('B', 'password');

    registry.setCurrentBooru('A');
    expect(getProxyDirective(), 'PROXY proxy-a.example:8080; DIRECT');

    registry.setCurrentBooru('B');
    expect(
      getProxyDirective(),
      'SOCKS5 user:password@proxy-b.example:1080; DIRECT',
    );

    registry.setCurrentBooru(null);
    expect(getProxyDirective(), 'DIRECT');
  });

  testWidgets('toolbar ordering has one inline editor and no recursive page', (tester) async {
    final definition = SX.buttonOrder.state.def;
    expect(definition.widgetBuilder, isNotNull);

    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    final widget = definition.widgetBuilder!(
      tester.element(find.byType(SizedBox)),
      SX.buttonOrder.state,
    );
    expect(widget, isA<ToolbarButtonOrderWidget>());
  });

  test('effective-value side effects fire once and skip persisted loads', () {
    final changes = <(bool, bool)>[];
    final state = SettingState<bool>(
      SettingDef<bool>(
        key: SettingKey.captureLogcat,
        getDefaultValue: () => false,
        localization: const SettingLocalization(title: _testTitle),
        valueToJson: (value) => value,
        valueFromJson: (json) => json is bool ? json : false,
        supportsPerBooru: true,
        onChanged: (oldValue, newValue) => changes.add((oldValue, newValue)),
      ),
    );

    expect(state.effectiveNotifier.value, isFalse);
    registry.setCurrentBooru('A');
    state.setOverrideFor('A', true);
    expect(changes, [(false, true)]);

    state.setOverrideFor('B', false);
    expect(changes, hasLength(1));

    registry.setCurrentBooru('B');
    expect(changes, [(false, true), (true, false)]);

    state.removeOverrideFor('B');
    expect(changes, hasLength(2));

    state.loadFromJson(true);
    expect(changes, hasLength(2));
  });
}

String _testTitle(_) => 'Test';
