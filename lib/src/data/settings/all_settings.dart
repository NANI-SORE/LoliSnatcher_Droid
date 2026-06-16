import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/settings/app_alias.dart';
import 'package:lolisnatcher/src/data/settings/app_mode.dart';
import 'package:lolisnatcher/src/data/settings/button_position.dart';
import 'package:lolisnatcher/src/data/settings/gallery_button.dart';
import 'package:lolisnatcher/src/data/settings/hand_side.dart';
import 'package:lolisnatcher/src/data/settings/image_quality.dart';
import 'package:lolisnatcher/src/data/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/src/data/settings/mpv_video_output.dart';
import 'package:lolisnatcher/src/data/settings/preview_display_mode.dart';
import 'package:lolisnatcher/src/data/settings/preview_quality.dart';
import 'package:lolisnatcher/src/data/settings/proxy_type.dart';
import 'package:lolisnatcher/src/data/settings/scroll_direction.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_enum.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/share_action.dart';
import 'package:lolisnatcher/src/data/settings/special_settings.dart';
import 'package:lolisnatcher/src/data/settings/tab_page_restore_mode.dart';
import 'package:lolisnatcher/src/data/settings/typed_settings.dart';
import 'package:lolisnatcher/src/data/settings/vertical_position.dart';
import 'package:lolisnatcher/src/data/settings/video_backend_mode.dart';
import 'package:lolisnatcher/src/data/settings/video_cache_mode.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/local_auth_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/pages/settings/tags_filters_page.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/utils/http_overrides.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/confirm_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/cache_stats_widget.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_builder.dart';
import 'package:lolisnatcher/src/widgets/settings/toolbar_button_order_widget.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_video_player.dart';

/// Helper to create an [enumSetting] for enums using the [SettingsEnum] mixin.
///
/// Reduces boilerplate since all SettingsEnum types follow the same pattern:
/// - `toJson()` for serialization
/// - `locName` for display
/// - `fromString()` for deserialization
SettingDef<T> settingsEnumSetting<T extends Enum>({
  required SettingKey key,
  required T Function() getDefaultValue,
  required SettingLocalization localization,
  required List<T> values,
  required T Function(String name) fromString,
  String Function(BuildContext, T)? enumLocName,
  Widget? Function(BuildContext context, T? value)? itemLeadingBuilder,
  EnumDisplayMode displayMode = EnumDisplayMode.dropdown,
  List<SettingCategory> categories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool isSearchable = true,
  bool Function()? visibleWhen,
  bool Function()? searchVisibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(T oldValue, T newValue)? onChanged,
}) {
  return enumSetting<T>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    values: values,
    fromString: fromString,
    enumToJson: (v) => (v as SettingsEnum).toJson(),
    enumLocName: enumLocName ?? (ctx, v) => (v as SettingsEnum).locName,
    itemLeadingBuilder: itemLeadingBuilder,
    displayMode: displayMode,
    categories: categories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    isSearchable: isSearchable,
    visibleWhen: visibleWhen,
    searchVisibleWhen: searchVisibleWhen,
    widgetConfig: widgetConfig,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
  );
}

/// Shorthand to read a setting's current value from the registry.
/// When [context] is provided and the setting supports per-booru overrides,
/// reads the scoped value (override for the booru being edited, if any).
T _val<T>(SettingKey key, [BuildContext? context]) {
  final state = SettingsRegistry.instance.get<T>(key)!;
  if (context != null) return state.scopedValue(context);
  return state.value;
}

/// Human-readable label for cache duration options.
String _cacheDurationLabel(BuildContext context, Duration d) {
  switch (d) {
    case Duration.zero:
      return context.loc.settings.cache.neverDeleteDuration;
    default:
      return d.format();
  }
}

/// Available theme options for the theme picker.
/// Shared between [registerAllSettings] and [ThemePage].
List<ThemeItem> getThemeOptions() => [
  ThemeItem(name: 'Pink', primary: Colors.pink[200], accent: Colors.pink[600]),
  ThemeItem(name: 'Purple', primary: Colors.deepPurple[600], accent: Colors.deepPurple[800]),
  ThemeItem(name: 'Blue', primary: Colors.lightBlue, accent: Colors.lightBlue[600]),
  ThemeItem(name: 'Teal', primary: Colors.teal, accent: Colors.teal[600]),
  ThemeItem(name: 'Red', primary: Colors.red[700], accent: Colors.red[800]),
  ThemeItem(name: 'Green', primary: Colors.green, accent: Colors.green[700]),
  const ThemeItem(name: 'Halloween', primary: Color(0xFF0B192C), accent: Color(0xFFEB5E28)),
  const ThemeItem(name: 'Custom', primary: null, accent: null),
];

/// Default theme value.
ThemeItem getDefaultTheme() => ThemeItem(name: 'Pink', primary: Colors.pink[200], accent: Colors.pink[600]);

/// Register all application settings with the [SettingsRegistry].
///
/// Call once at app startup before loading settings from disk.
/// Registration order within each category determines display order on auto-rendered pages.
void registerAllSettings() {
  final registry = SettingsRegistry.instance;

  // ============================================
  // INTERFACE
  // ============================================

  registry.register(
    intSetting(
      key: .portraitColumns,
      getDefaultValue: () => 2,
      min: 1,
      max: 100,
      step: 1,
      categories: [SettingCategory.interface, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.previewColumnsPortrait,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .landscapeColumns,
      getDefaultValue: () => 4,
      min: 1,
      max: 100,
      step: 1,
      categories: [SettingCategory.interface, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.previewColumnsLandscape,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<PreviewQuality>(
      key: .previewMode,
      getDefaultValue: () => PreviewQuality.defaultValue,
      values: PreviewQuality.values,
      fromString: PreviewQuality.fromString,
      displayMode: EnumDisplayMode.optionsList,
      categories: [SettingCategory.interface, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.previewQuality,
      ),
      widgetConfig: SettingWidgetConfig(
        helpDialog: (ctx) => SettingsDialog(
          title: Text(ctx.loc.settings.interface.previewQuality),
          contentItems: [
            Text(ctx.loc.settings.interface.previewQualityHelp),
            Text(ctx.loc.settings.interface.previewQualityHelpSample),
            Text(ctx.loc.settings.interface.previewQualityHelpThumbnail),
            const Text(' '),
            Text(ctx.loc.settings.interface.previewQualityHelpNote),
          ],
        ),
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<PreviewDisplayMode>(
      key: .previewDisplay,
      getDefaultValue: () => PreviewDisplayMode.defaultValue,
      values: PreviewDisplayMode.values,
      fromString: PreviewDisplayMode.fromString,
      displayMode: EnumDisplayMode.optionsList,
      enumLocName: (ctx, v) =>
          v.locName +
          switch (v) {
            .square => ' (1:1)',
            .rectangle => ' (9:16)',
            _ => '',
          },
      itemLeadingBuilder: (ctx, v) {
        if (v == null) return null;
        return switch (v) {
          .square => const Icon(Icons.crop_square_outlined),
          .rectangle => Transform.rotate(
            angle: pi / 2,
            child: const Icon(Icons.crop_16_9),
          ),
          .staggered => const Icon(Icons.dashboard_outlined),
        };
      },
      categories: [SettingCategory.interface],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.previewDisplay,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<PreviewDisplayMode>(
      key: .previewDisplayFallback,
      getDefaultValue: () => PreviewDisplayMode.defaultValue,
      values: PreviewDisplayMode.values.where((e) => e != PreviewDisplayMode.staggered).toList(),
      fromString: PreviewDisplayMode.fromString,
      categories: [SettingCategory.interface],
      supportsPerBooru: true,
      dependsOn: [.previewDisplay],
      enabledWhen: ([BuildContext? context]) =>
          _val<PreviewDisplayMode>(.previewDisplay, context) == PreviewDisplayMode.staggered,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.previewDisplayFallback,
        subtitle: (ctx) => ctx.loc.settings.interface.previewDisplayFallbackHelp,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting(
      key: .tabPageRestoreMode,
      getDefaultValue: () => TabPageRestoreMode.defaultValue,
      values: TabPageRestoreMode.values,
      fromString: TabPageRestoreMode.fromString,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.tabPageRestoreMode,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .defaultSavePageEnabled,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.saveTabViewedPageByDefault,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<AppMode>(
      key: .appMode,
      getDefaultValue: () => AppMode.defaultValue,
      values: AppMode.values,
      fromString: AppMode.fromString,
      // categories: [SettingCategory.interface], // TODO reenable when desktop is redesigned
      categories: [],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.appUIMode,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<HandSide>(
      key: .handSide,
      getDefaultValue: () => HandSide.defaultValue,
      values: HandSide.values,
      fromString: HandSide.fromString,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.handSide,
        helpText: (ctx) => ctx.loc.settings.interface.handSideHelp,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showBottomSearchbar,
      getDefaultValue: () => true,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.showSearchBarInPreviewGrid,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .useTopSearchbarInput,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.moveInputToTopInSearchView,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showSearchbarQuickActions,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.searchViewQuickActionsPanel,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .autofocusSearchbar,
      getDefaultValue: () => true,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.searchViewInputAutofocus,
      ),
    ),
  );

  registry.register(
    confirmBoolSetting(
      key: .disableImageScaling,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface, SettingCategory.performance],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.dontScaleImages,
        subtitle: (ctx) => ctx.loc.settings.interface.dontScaleImagesSubtitle,
      ),
      widgetConfig: const SettingWidgetConfig(
        leadingIcon: Icon(Icons.close_fullscreen),
      ),
      buildDialogContent: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.interface.dontScaleImagesWarningTitle),
        contentItems: [
          Text(
            ctx.loc.settings.interface.dontScaleImagesWarning,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            ctx.loc.settings.interface.dontScaleImagesWarningMsg,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
        actionButtons: const [
          CancelButton(withIcon: true),
          ConfirmButton(withIcon: true),
        ],
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .gifsAsThumbnails,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      dependsOn: [.disableImageScaling],
      enabledWhen: ([BuildContext? context]) => _val<bool>(.disableImageScaling, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.gifThumbnails,
        subtitle: (ctx) => ctx.loc.settings.interface.gifThumbnailsRequires,
      ),
      widgetConfig: const SettingWidgetConfig(
        leadingIcon: Icon(Icons.gif),
      ),
    ),
  );

  // ============================================
  // VIEWER
  // ============================================

  registry.register(
    settingsEnumSetting<ImageQuality>(
      key: .galleryMode,
      getDefaultValue: () => ImageQuality.defaultValue,
      values: ImageQuality.values,
      fromString: ImageQuality.fromString,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.imageQuality,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .preloadCount,
      getDefaultValue: () => 1,
      min: 0,
      max: 4,
      step: 1,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.preloadAmount,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .preloadHeight,
      getDefaultValue: () => 4096 * 4,
      min: 0,
      max: 2000000000,
      step: 1024,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.preloadHeightLimit,
        subtitle: (ctx) => ctx.loc.settings.viewer.preloadHeightLimitSubtitle,
      ),
    ),
  );

  registry.register(
    doubleSetting(
      key: .preloadSizeLimit,
      getDefaultValue: () => 0.2,
      min: 0,
      max: double.infinity,
      step: 0.1,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.preloadSizeLimit,
        subtitle: (ctx) => ctx.loc.settings.viewer.preloadSizeLimitSubtitle,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .autoHideImageBar,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.hideToolbarWhenOpeningViewer,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<VerticalPosition>(
      key: .galleryBarPosition,
      getDefaultValue: () => VerticalPosition.defaultValue,
      values: VerticalPosition.values,
      fromString: VerticalPosition.fromString,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.viewerToolbarPosition,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<UiScrollDirection>(
      key: .galleryScrollDirection,
      getDefaultValue: () => UiScrollDirection.defaultValue,
      values: UiScrollDirection.values,
      fromString: UiScrollDirection.fromString,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.viewerScrollDirection,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<ButtonPosition>(
      key: .zoomButtonPosition,
      getDefaultValue: () => ButtonPosition.defaultValue,
      values: ButtonPosition.values,
      fromString: ButtonPosition.fromString,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.zoomButtonPosition,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<ButtonPosition>(
      key: .changePageButtonsPosition,
      getDefaultValue: () => ButtonPosition.defaultValueDesktopOnly,
      values: ButtonPosition.values,
      fromString: ButtonPosition.fromString,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.changePageButtonsPosition,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<ButtonPosition>(
      key: .scrollGridButtonsPosition,
      getDefaultValue: () => ButtonPosition.defaultValueDesktopOnly,
      values: ButtonPosition.values,
      fromString: ButtonPosition.fromString,
      categories: [SettingCategory.interface],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.scrollPreviewsButtonsPosition,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<ShareAction>(
      key: .shareAction,
      getDefaultValue: () => ShareAction.defaultValue,
      values: ShareAction.values,
      fromString: ShareAction.fromString,
      categories: [SettingCategory.viewer],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.defaultShareAction,
      ),
      widgetConfig: SettingWidgetConfig(
        helpDialog: (ctx) => SettingsDialog(
          title: Text(ctx.loc.settings.viewer.shareActions),
          contentItems: [
            Text(ctx.loc.settings.viewer.shareActionsAsk),
            Text(ctx.loc.settings.viewer.shareActionsPostURL),
            Text(ctx.loc.settings.viewer.shareActionsFileURL),
            Text(ctx.loc.settings.viewer.shareActionsPostURLFileURLFileWithTags),
            Text(ctx.loc.settings.viewer.shareActionsFile),
            if (SettingsHandler.instance.hasHydrus) Text(ctx.loc.settings.viewer.shareActionsHydrus),
            const Text(''),
            Text(ctx.loc.settings.viewer.shareActionsNoteIfFileSavedInCache),
            const Text(''),
            Text(ctx.loc.settings.viewer.shareActionsTip),
          ],
        ),
      ),
    ),
  );

  registry.register(
    SettingDef<List<String>>(
      key: .buttonOrder,
      getDefaultValue: () => GalleryButton.values.map((b) => b.toJson()).toList(),
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.toolbarButtonsOrder,
      ),
      valueToJson: (v) => v,
      valueFromJson: (json) {
        // Handle CSV string or JSON array input
        List<dynamic> raw;
        if (json is List) {
          raw = json;
        } else if (json is String && json.isNotEmpty) {
          raw = json.split(',');
        } else {
          return GalleryButton.values.map((b) => b.toJson()).toList();
        }

        // Parse valid buttons, ignoring unrecognized values
        final parsed = raw.whereType<String>().map(GalleryButton.fromString).whereType<GalleryButton>().toList();

        // Append any buttons not present in parsed list (future-proofing)
        for (final button in GalleryButton.values) {
          if (!parsed.contains(button)) {
            parsed.add(button);
          }
        }

        return parsed.map((b) => b.toJson()).toList();
      },
      widgetBuilder: (context, dynamic state) {
        return const ToolbarButtonOrderWidget();
      },
    ),
  );

  registry.register(
    SettingDef<List<String>>(
      key: .disabledButtons,
      getDefaultValue: () => <String>[],
      categories: [SettingCategory.viewer],
      // No widget builder: managed by the toolbar editor attached to buttonOrder.
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.buttonsOrder,
      ),
      valueToJson: (v) => v,
      valueFromJson: (json) {
        if (json is! List) return <String>[];

        // Parse valid buttons, filtering to only disableable ones
        return json
            .whereType<String>()
            .map(GalleryButton.fromString)
            .whereType<GalleryButton>()
            .where((b) => b.canBeDisabled)
            .map((b) => b.toJson())
            .toList();
      },
    ),
  );

  registry.register(
    boolSetting(
      key: .allowRotation,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.enableRotation,
        subtitle: (ctx) => ctx.loc.settings.viewer.enableRotationSubtitle,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .expandDetails,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.expandDetailsByDefault,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .hideNotes,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.hideTranslationNotesByDefault,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .enableHeroTransitions,
      getDefaultValue: () => true,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.viewerOpenCloseAnimation,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .disableCustomPageTransitions,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer, SettingCategory.performance],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.viewerPageChangeAnimation,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .galleryAutoScrollTime,
      getDefaultValue: () => 4000,
      min: 100,
      max: 100000,
      step: 100,
      categories: [SettingCategory.viewer],
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.slideshowDurationInMs,
        helpText: (ctx) => ctx.loc.settings.viewer.slideshowWIPNote,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .useVolumeButtonsForScroll,
      getDefaultValue: () => false,
      categories: [SettingCategory.viewer],
      isDeviceSpecific: true,
      onChanged: (_, newValue) => ServiceHandler.setVolumeButtons(!newValue),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.useVolumeButtonsForScrolling,
      ),
      widgetConfig: SettingWidgetConfig(
        helpDialog: (ctx) => SettingsDialog(
          title: Text(ctx.loc.settings.viewer.volumeButtonsScrolling),
          contentItems: [
            Text(ctx.loc.settings.viewer.volumeButtonsScrollingHelp),
            const Text(''),
            Text(ctx.loc.settings.viewer.volumeButtonsVolumeDown),
            Text(ctx.loc.settings.viewer.volumeButtonsVolumeUp),
            const Text(''),
            Text(ctx.loc.settings.viewer.volumeButtonsInViewer),
            Text(ctx.loc.settings.viewer.volumeButtonsToolbarVisible),
            Text(ctx.loc.settings.viewer.volumeButtonsToolbarHidden),
          ],
        ),
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .volumeButtonsScrollSpeed,
      getDefaultValue: () => 200,
      min: 0,
      max: 1000000,
      step: 10,
      categories: [SettingCategory.viewer],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.volumeButtonsScrollSpeed,
      ),
    ),
  );

  // ============================================
  // VIDEO
  // ============================================

  registry.register(
    boolSetting(
      key: .disableVideo,
      getDefaultValue: () => false,
      categories: [SettingCategory.video, SettingCategory.performance],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.disableVideos,
        helpText: (ctx) => ctx.loc.settings.video.disableVideosHelp,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .autoPlayEnabled,
      getDefaultValue: () => true,
      categories: [SettingCategory.video, SettingCategory.performance],
      supportsPerBooru: true,
      dependsOn: [.disableVideo],
      enabledWhen: ([BuildContext? context]) => !_val<bool>(.disableVideo, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.autoplayVideos,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .startVideosMuted,
      getDefaultValue: () => false,
      categories: [SettingCategory.video],
      supportsPerBooru: true,
      dependsOn: [.disableVideo],
      enabledWhen: ([BuildContext? context]) => !_val<bool>(.disableVideo, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.startVideosMuted,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<VideoBackendMode>(
      key: .videoBackendMode,
      getDefaultValue: () => VideoBackendMode.defaultValue,
      values: VideoBackendMode.allowedValues,
      fromString: VideoBackendMode.fromString,
      categories: [SettingCategory.video],
      isDeviceSpecific: true,
      dependsOn: [.disableVideo],
      enabledWhen: ([BuildContext? context]) => !_val<bool>(.disableVideo, context),
      onChanged: (_, newValue) {
        switch (newValue) {
          case VideoBackendMode.normal:
            MediaKitVideoPlayer.registerNative();
            break;
          case VideoBackendMode.mpv:
            MediaKitVideoPlayer.registerWith();
            break;
          case VideoBackendMode.mdk:
            fvp.registerWith();
            break;
        }
      },
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.videoPlayerBackend,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<VideoCacheMode>(
      key: .videoCacheMode,
      getDefaultValue: () => VideoCacheMode.defaultValue,
      values: VideoCacheMode.values,
      fromString: VideoCacheMode.fromString,
      categories: [SettingCategory.video],
      dependsOn: [.disableVideo, .videoBackendMode],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.disableVideo, context) &&
          _val<VideoBackendMode>(.videoBackendMode, context) != VideoBackendMode.normal,
      displayMode: EnumDisplayMode.optionsList,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.videoCacheMode,
        subtitle: (ctx) =>
            'Videos on some Boorus may not work correctly (i.e. endless loading) when using Stream video cache mode. '
            'In that case try using Cache mode. Otherwise player will retry with Cache mode automatically if video is '
            'in initial buffering state for 10+ seconds and video file size is less than 25mb',
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .altVideoPlayerHwAccel,
      getDefaultValue: () => true,
      categories: [SettingCategory.video],
      isDeviceSpecific: true,
      dependsOn: [.disableVideo, .videoBackendMode],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.disableVideo, context) &&
          _val<VideoBackendMode>(.videoBackendMode, context) != VideoBackendMode.normal,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.mpvUseHardwareAcceleration,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<MpvVideoOutput>(
      key: .altVideoPlayerVO,
      getDefaultValue: () => MpvVideoOutput.defaultValue,
      values: MpvVideoOutput.values,
      fromString: MpvVideoOutput.fromString,
      categories: [SettingCategory.video],
      isDeviceSpecific: true,
      dependsOn: [.disableVideo, .videoBackendMode],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.disableVideo, context) &&
          _val<VideoBackendMode>(.videoBackendMode, context) == VideoBackendMode.mpv,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.mpvVO,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<MpvHardwareDecoding>(
      key: .altVideoPlayerHWDEC,
      getDefaultValue: () => MpvHardwareDecoding.defaultValue,
      values: MpvHardwareDecoding.values,
      fromString: MpvHardwareDecoding.fromString,
      categories: [SettingCategory.video],
      isDeviceSpecific: true,
      dependsOn: [.disableVideo, .videoBackendMode],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.disableVideo, context) &&
          _val<VideoBackendMode>(.videoBackendMode, context) == VideoBackendMode.mpv,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.video.mpvHWDEC,
      ),
    ),
  );

  // ============================================
  // THEME
  // ============================================

  registry.register(
    themeSetting(
      key: .theme,
      getDefaultValue: getDefaultTheme,
      getOptions: getThemeOptions,
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.useDynamicColor],
      enabledWhen: ([BuildContext? context]) => !_val<bool>(.useDynamicColor, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.theme,
      ),
    ),
  );

  registry.register(
    themeModeSetting(
      key: .themeMode,
      getDefaultValue: () => ThemeMode.dark,
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.themeMode,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .isAmoled,
      getDefaultValue: () => false,
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.themeMode],
      enabledWhen: ([BuildContext? context]) {
        final mode = _val<ThemeMode>(.themeMode, context);
        return mode == ThemeMode.system || mode == ThemeMode.dark;
      },
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.blackBg,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .useDynamicColor,
      getDefaultValue: () => false,
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.useDynamicColor,
      ),
    ),
  );

  registry.register(
    colorPickerSetting(
      key: .customPrimaryColor,
      getDefaultValue: () => Colors.pink[200],
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.useDynamicColor, .theme],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.useDynamicColor, context) && _val<ThemeItem>(.theme, context).name == 'Custom',
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.primaryColor,
      ),
    ),
  );

  registry.register(
    colorPickerSetting(
      key: .customAccentColor,
      getDefaultValue: () => Colors.pink[600],
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.useDynamicColor, .theme],
      enabledWhen: ([BuildContext? context]) =>
          !_val<bool>(.useDynamicColor, context) && _val<ThemeItem>(.theme, context).name == 'Custom',
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.secondaryColor,
      ),
    ),
  );

  registry.register(
    fontFamilySetting(
      key: .fontFamily,
      getDefaultValue: () => 'System',
      getOptions: () => ['System'], // Populated dynamically at runtime
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.fontFamily,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .enableDrawerMascot,
      getDefaultValue: () => false,
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.enableDrawerMascot,
      ),
    ),
  );

  registry.register(
    filePickerSetting(
      key: .drawerMascotPathOverride,
      getDefaultValue: () => '',
      categories: [SettingCategory.theme],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      visibleWhen: () => Platform.isAndroid,
      pickFile: ServiceHandler.getImageSAFUri,
      setButtonLabel: (ctx) => ctx.loc.settings.theme.setCustomMascot,
      removeButtonLabel: (ctx) => ctx.loc.settings.theme.removeCustomMascot,
      onRemove: (path) async {
        if (path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      },
      onChanged: (oldValue, newValue) async {
        if (newValue.isNotEmpty) {
          // Write mascot image to app directory
          final writtenPath = await ImageWriter().writeMascotImage(newValue);
          final state = SettingsRegistry.instance.get<String>(.drawerMascotPathOverride);
          if (state != null && writtenPath != newValue) {
            state.globalValue = writtenPath;
          }
        }
      },
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.theme.currentMascotPath,
      ),
    ),
  );

  // ============================================
  // CACHE & STORAGE
  // ============================================

  registry.register(
    settingsEnumSetting<ImageQuality>(
      key: .snatchMode,
      getDefaultValue: () => ImageQuality.defaultValue,
      values: ImageQuality.values,
      fromString: ImageQuality.fromString,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.snatchQuality,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .snatchCooldown,
      getDefaultValue: () => 250,
      min: 0,
      max: 10000,
      step: 50,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.snatchCooldown,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .downloadNotifications,
      getDefaultValue: () => true,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.showDownloadNotifications,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .snatchOnFavourite,
      getDefaultValue: () => false,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.snatchItemsOnFavouriting,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, color: Colors.red),
            Icon(Icons.arrow_right_alt_rounded),
            Icon(Icons.save),
          ],
        ),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .favouriteOnSnatch,
      getDefaultValue: () => false,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.favouriteItemsOnSnatching,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.save),
            Icon(Icons.arrow_right_alt_rounded),
            Icon(Icons.favorite, color: Colors.red),
          ],
        ),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .jsonWrite,
      getDefaultValue: () => false,
      categories: [SettingCategory.cache],
      supportsPerBooru: true,
      dependsOn: [.extPathOverride],
      enabledWhen: ([BuildContext? context]) =>
          !Platform.isAndroid || _val<String>(.extPathOverride, context).isNotEmpty,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.writeImageDataOnSave,
        subtitle: Platform.isAndroid ? (ctx) => ctx.loc.settings.cache.requiresCustomStorageDirectory : null,
      ),
    ),
  );

  registry.register(
    directoryPickerSetting(
      key: .extPathOverride,
      getDefaultValue: () => '',
      categories: [SettingCategory.cache],
      isDeviceSpecific: true,
      visibleWhen: () => Platform.isAndroid,
      pickDirectory: ServiceHandler.setExtDir,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.setStorageDirectory,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .thumbnailCache,
      getDefaultValue: () => true,
      categories: [SettingCategory.cache],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.cachePreviews,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .mediaCache,
      getDefaultValue: () => true,
      categories: [SettingCategory.cache],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.cacheMedia,
      ),
    ),
  );

  registry.register(
    durationSetting(
      key: .cacheDuration,
      getDefaultValue: () => Duration.zero,
      categories: [SettingCategory.cache],
      isDeviceSpecific: true,
      options: const [
        Duration.zero,
        Duration(minutes: 30),
        Duration(hours: 1),
        Duration(hours: 6),
        Duration(hours: 12),
        Duration(days: 1),
        Duration(days: 2),
        Duration(days: 7),
        Duration(days: 30),
      ],
      durationLocName: _cacheDurationLabel,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.deleteCacheAfter,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .cacheSize,
      getDefaultValue: () => 3,
      min: 0,
      max: 50,
      step: 1,
      categories: [SettingCategory.cache],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.cache.cacheSizeLimit,
      ),
    ),
  );

  registry.register(
    widgetSlot(
      key: .cacheStatsSlot,
      categories: [SettingCategory.cache],
      builder: (context) => const CacheStatsWidget(),
    ),
  );

  registry.register(
    directoryPickerSetting(
      key: .backupPath,
      getDefaultValue: () => '',
      categories: [SettingCategory.backup],
      isDeviceSpecific: true,
      visibleWhen: () => Platform.isAndroid,
      pickDirectory: ServiceHandler.getSAFDirectoryAccess,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.backupAndRestore.selectBackupDir,
      ),
    ),
  );

  // ============================================
  // DATABASE
  // ============================================

  registry.register(
    boolSetting(
      key: .dbEnabled,
      getDefaultValue: () => true,
      categories: [SettingCategory.database],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.database.enableDatabase,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .indexesEnabled,
      getDefaultValue: () => false,
      categories: [SettingCategory.database],
      isDeviceSpecific: true,
      dependsOn: [.dbEnabled],
      enabledWhen: ([BuildContext? context]) => _val<bool>(.dbEnabled, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.database.enableIndexing,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .searchHistoryEnabled,
      getDefaultValue: () => true,
      categories: [SettingCategory.database],
      isDeviceSpecific: true,
      dependsOn: [.dbEnabled],
      enabledWhen: ([BuildContext? context]) => _val<bool>(.dbEnabled, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.database.enableSearchHistory,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .tagTypeFetchEnabled,
      getDefaultValue: () => true,
      categories: [SettingCategory.database],
      dependsOn: [.dbEnabled],
      enabledWhen: ([BuildContext? context]) => _val<bool>(.dbEnabled, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.database.enableTagTypeFetching,
      ),
    ),
  );

  // ============================================
  // NETWORK
  // ============================================

  registry.register(
    boolSetting(
      key: .allowSelfSignedCerts,
      getDefaultValue: () => false,
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      onChanged: (_, _) => initProxy(),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.network.enableSelfSignedSSLCertificates,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<ProxyType>(
      key: .proxyType,
      getDefaultValue: () => ProxyType.defaultValue,
      values: ProxyType.values,
      fromString: ProxyType.fromString,
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      // The installed callback reads effective settings dynamically. Re-run
      // initialization only to refresh the OS proxy address for system mode.
      onChanged: (_, _) => initProxy(),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.network.proxy,
        subtitle: (ctx) => ctx.loc.settings.network.proxySubtitle,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .proxyAddress,
      getDefaultValue: () => '',
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.proxyType],
      enabledWhen: ([BuildContext? context]) {
        final t = _val<ProxyType>(.proxyType, context);
        return t != ProxyType.direct && t != ProxyType.system;
      },
      onChanged: (_, _) => initProxy(),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.address,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .proxyUsername,
      getDefaultValue: () => '',
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.proxyType],
      enabledWhen: ([BuildContext? context]) {
        final t = _val<ProxyType>(.proxyType, context);
        return t != ProxyType.direct && t != ProxyType.system;
      },
      onChanged: (_, _) => initProxy(),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.username,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .proxyPassword,
      getDefaultValue: () => '',
      obscureable: true,
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      dependsOn: [.proxyType],
      enabledWhen: ([BuildContext? context]) {
        final t = _val<ProxyType>(.proxyType, context);
        return t != ProxyType.direct && t != ProxyType.system;
      },
      onChanged: (_, _) => initProxy(),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.password,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .customUserAgent,
      getDefaultValue: () => '',
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      supportsPerBooru: true,
      pasteable: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.network.customUserAgent,
        helpText: (ctx) => ctx.loc.settings.network.keepEmptyForDefault,
      ),
      widgetConfig: SettingWidgetConfig(
        helpDialog: (ctx) => SettingsDialog(
          title: Text(ctx.loc.settings.network.customUserAgentTitle),
          contentItems: [
            Text(ctx.loc.settings.network.keepEmptyForDefault),
            Text(ctx.loc.settings.network.defaultUserAgent(agent: Tools.appUserAgent)),
            Text(ctx.loc.settings.network.userAgentUsedOnRequests),
            Text(ctx.loc.settings.network.valueSavedAfterLeaving),
          ],
        ),
      ),
    ),
  );

  // ============================================
  // TAGS & FILTERS
  // ============================================

  registry.register(
    boolSetting(
      key: .filterHated,
      getDefaultValue: () => false,
      categories: [SettingCategory.tagsFilters],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.itemFilters.removeHidden,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Icon(CupertinoIcons.eye_slash),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .filterMarked,
      getDefaultValue: () => false,
      categories: [SettingCategory.tagsFilters],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.itemFilters.removeMarked,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Icon(Icons.star, color: Colors.yellow),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .filterFavourites,
      getDefaultValue: () => false,
      categories: [SettingCategory.tagsFilters],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.itemFilters.removeFavourited,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Icon(Icons.favorite, color: Colors.red),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .filterSnatched,
      getDefaultValue: () => false,
      categories: [SettingCategory.tagsFilters],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.itemFilters.removeSnatched,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: Icon(Icons.file_download_outlined),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .filterAi,
      getDefaultValue: () => false,
      categories: [SettingCategory.tagsFilters],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.itemFilters.removeAI,
      ),
      widgetConfig: const SettingWidgetConfig(
        trailingIcon: FaIcon(FontAwesomeIcons.robot, size: 20),
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .useLockscreen,
      getDefaultValue: () => false,
      categories: [SettingCategory.privacy],
      isDeviceSpecific: true,
      visibleWhen: () => LocalAuthHandler.instance.isSupportedPlatform,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.privacy.appLock,
        subtitle: (ctx) => ctx.loc.settings.privacy.appLockMsg,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .blurOnLeave,
      getDefaultValue: () => false,
      categories: [SettingCategory.privacy],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.privacy.bluronLeave,
        subtitle: (ctx) => ctx.loc.settings.privacy.bluronLeaveMsg,
      ),
    ),
  );

  registry.register(
    intSetting(
      key: .autoLockTimeout,
      getDefaultValue: () => 120,
      min: 0,
      max: 2147483647,
      step: 10,
      categories: [SettingCategory.privacy],
      isDeviceSpecific: true,
      dependsOn: [.useLockscreen],
      enabledWhen: ([BuildContext? context]) => _val<bool>(.useLockscreen, context),
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.privacy.autoLockAfter,
        subtitle: (ctx) => ctx.loc.settings.privacy.autoLockAfterTip,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .incognitoKeyboard,
      getDefaultValue: () => false,
      categories: [SettingCategory.privacy],
      isDeviceSpecific: true,
      visibleWhen: () => Platform.isAndroid,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.privacy.incognitoKeyboard,
        subtitle: (ctx) => ctx.loc.settings.privacy.incognitoKeyboardMsg,
      ),
    ),
  );

  // ============================================
  // TAGS
  // ============================================

  registry.register(
    stringSetting(
      key: .defTags,
      getDefaultValue: () => 'rating:safe',
      categories: [SettingCategory.booru],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.booru.defaultTags,
      ),
    ),
  );

  registry.register(
    stringListSetting(
      key: .hiddenTags,
      getDefaultValue: () => <String>[],
      categories: [SettingCategory.tagsFilters],
      legacyJsonKeys: const ['hatedTags'],
      navigateTo: () => const TagsFiltersPage(),
      icon: Icons.visibility_off,
      localization: SettingLocalization(
        title: (ctx) => 'Hidden Tags',
      ),
    ),
  );

  registry.register(
    stringListSetting(
      key: .markedTags,
      getDefaultValue: () => <String>[],
      categories: [SettingCategory.tagsFilters],
      legacyJsonKeys: const ['lovedTags'],
      navigateTo: () => const TagsFiltersPage(),
      icon: Icons.star,
      localization: SettingLocalization(
        title: (ctx) => 'Marked Tags',
      ),
    ),
  );

  // ============================================
  // OTHER
  // ============================================

  registry.register(
    SettingDef<String>(
      key: .prefBooru,
      getDefaultValue: () => '',
      categories: [SettingCategory.booru],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.booru.changeDefaultBooru,
      ),
      valueToJson: (v) => v,
      valueFromJson: (json) => json is String ? json : '',
      widgetBuilder: (context, dynamic state) {
        final s = state as SettingState<String>;
        final settingsHandler = SettingsHandler.instance;
        return SettingBuilder<String>(
          setting: s,
          builder: (ctx, value) {
            final booruList = settingsHandler.booruList;
            final selectedBooru = booruList.where((b) => b.name == value).firstOrNull ?? booruList.firstOrNull;
            return SettingsBooruDropdown(
              value: selectedBooru,
              onChanged: (Booru? newValue) {
                s.value = newValue?.name ?? '';
                settingsHandler.sortBooruList();
              },
              title: ctx.loc.settings.booru.changeDefaultBooru,
            );
          },
        );
      },
    ),
  );

  registry.register(
    intSetting(
      key: .limit,
      getDefaultValue: () => Constants.defaultItemLimit,
      min: 10,
      max: 100,
      step: 10,
      categories: [SettingCategory.booru],
      supportsPerBooru: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.booru.itemsPerPage,
      ),
      onScopedChanged: (oldV, newV, booruName) {
        if (oldV != newV) {
          SearchHandler.instance.invalidateSavedPages(booruName: booruName);
        }
      },
    ),
  );

  registry.register(
    boolSetting(
      key: .loadingGif,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.kannaLoadingGif,
      ),
    ),
  );

  registry.register(
    confirmBoolSetting(
      key: .shitDevice,
      getDefaultValue: () => false,
      categories: [SettingCategory.performance],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.performance.lowPerformanceMode,
        subtitle: (ctx) => ctx.loc.settings.performance.lowPerformanceModeSubtitle,
      ),
      widgetConfig: SettingWidgetConfig(
        trailingIcon: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: ctx,
                builder: (dialogCtx) => SettingsDialog(
                  title: Text(dialogCtx.loc.settings.performance.lowPerformanceModeDialogTitle),
                  contentItems: [
                    Text(dialogCtx.loc.settings.performance.lowPerformanceModeDialogDisablesDetailed),
                    Text(dialogCtx.loc.settings.performance.lowPerformanceModeDialogDisablesResourceIntensive),
                    const Text(''),
                    Text(dialogCtx.loc.settings.performance.lowPerformanceModeDialogSetsOptimal),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      buildDialogContent: (ctx) => SettingsDialog(
        title: Text(ctx.loc.settings.performance.lowPerformanceModeDialogTitle),
        contentItems: [
          Text(ctx.loc.settings.performance.lowPerformanceModeDialogDisablesDetailed),
          Text(ctx.loc.settings.performance.lowPerformanceModeDialogDisablesResourceIntensive),
          const Text(''),
          Text(ctx.loc.settings.performance.lowPerformanceModeDialogSetsOptimal),
          ...[
            ctx.loc.settings.interface.previewQuality,
            ctx.loc.settings.viewer.imageQuality,
            ctx.loc.settings.interface.previewColumnsPortrait,
            ctx.loc.settings.interface.previewColumnsLandscape,
            ctx.loc.settings.viewer.preloadAmount,
            ctx.loc.settings.viewer.preloadSizeLimit,
            ctx.loc.settings.viewer.preloadHeightLimit,
            ctx.loc.settings.interface.dontScaleImages,
            ctx.loc.settings.performance.autoplayVideos,
          ].map((s) => Text('- $s')),
        ],
        actionButtons: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.onSurface),
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(ctx.loc.cancel),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.onSurface),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(ctx.loc.confirm),
          ),
        ],
      ),
      onConfirmed: () {
        // Cascade low-perf mode settings
        final reg = SettingsRegistry.instance;
        reg.get<PreviewQuality>(.previewMode)?.value = PreviewQuality.thumbnail;
        reg.get<ImageQuality>(.galleryMode)?.value = ImageQuality.sample;
        reg.get<int>(.portraitColumns)?.value = 2;
        reg.get<int>(.landscapeColumns)?.value = 4;
        reg.get<int>(.preloadCount)?.value = 0;
        reg.get<double>(.preloadSizeLimit)?.value = 0.2;
        reg.get<int>(.preloadHeight)?.value = 8192;
        reg.get<bool>(.autoPlayEnabled)?.value = false;
        reg.get<bool>(.disableImageScaling)?.value = false;
      },
    ),
  );

  registry.register(
    boolSetting(
      key: .wakeLockEnabled,
      getDefaultValue: () => true,
      categories: [SettingCategory.performance],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.viewer.preventDeviceFromSleeping,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .disableVibration,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.disableVibration,
        subtitle: (ctx) => ctx.loc.settings.interface.disableVibrationSubtitle,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .desktopListsDrag,
      getDefaultValue: () => false,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      visibleWhen: () => PlatformExt.isDesktop,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.debug.enableDragScrollOnListsDesktopOnly,
      ),
    ),
  );

  registry.register(
    doubleSetting(
      key: .mousewheelScrollSpeed,
      getDefaultValue: () => 10.0,
      min: 0.1,
      max: 100,
      step: 0.5,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      visibleWhen: () => PlatformExt.isDesktop,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.mouseWheelScrollModifier,
      ),
    ),
  );

  registry.register(
    localeSetting(
      key: .locale,
      categories: [SettingCategory.language],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.language.title,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .lastSyncIp,
      getDefaultValue: () => '',
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.sync.ipAddress,
      ),
    ),
  );

  registry.register(
    stringSetting(
      key: .lastSyncPort,
      getDefaultValue: () => '',
      categories: [SettingCategory.network],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.sync.port,
      ),
    ),
  );

  registry.register(
    settingsEnumSetting<AppAlias>(
      key: .appAlias,
      getDefaultValue: () => AppAlias.defaultValue,
      values: AppAlias.values,
      fromString: AppAlias.fromString,
      categories: [SettingCategory.privacy],
      isDeviceSpecific: true,
      visibleWhen: () => Platform.isAndroid,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.privacy.appDisplayName,
        subtitle: (ctx) => ctx.loc.settings.privacy.appDisplayNameDescription,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .usePredictiveBack,
      getDefaultValue: () => true,
      categories: [SettingCategory.interface],
      isDeviceSpecific: true,
      visibleWhen: () => Platform.isAndroid,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.interface.usePredictiveBack,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .captureLogcat,
      getDefaultValue: () => false,
      categories: [SettingCategory.logging],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.logging.captureLogcat,
        subtitle: (ctx) => ctx.loc.settings.logging.captureLogcatDescription,
      ),
    ),
  );

  // ============================================
  // DEBUG
  // ============================================

  registry.register(
    boolSetting(
      key: .isDebug,
      getDefaultValue: () => kDebugMode,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      isSearchable: false,
      localization: SettingLocalization(
        title: (ctx) => 'Debug Mode',
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showFps,
      getDefaultValue: () => false,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      isTransient: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.debug.showFPSGraph,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showPerf,
      getDefaultValue: () => false,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      isTransient: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.debug.showPerformanceGraph,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showImageStats,
      getDefaultValue: () => false,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      isTransient: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.debug.showImageStats,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .showVideoStats,
      getDefaultValue: () => false,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      isTransient: true,
      localization: SettingLocalization(
        title: (ctx) => ctx.loc.settings.debug.showVideoStats,
      ),
    ),
  );

  registry.register(
    boolSetting(
      key: .useImageLogging,
      getDefaultValue: () => false,
      categories: [SettingCategory.debug],
      isDeviceSpecific: true,
      localization: SettingLocalization(
        title: (ctx) => 'Use image logging',
      ),
    ),
  );
}
