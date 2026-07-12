import 'package:flutter/material.dart' show Color, ThemeMode;

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/settings/app_alias.dart';
import 'package:lolisnatcher/src/data/settings/app_mode.dart';
import 'package:lolisnatcher/src/data/settings/button_position.dart';
import 'package:lolisnatcher/src/data/settings/hand_side.dart';
import 'package:lolisnatcher/src/data/settings/image_quality.dart';
import 'package:lolisnatcher/src/data/settings/mpv_hardware_decoding.dart';
import 'package:lolisnatcher/src/data/settings/mpv_video_output.dart';
import 'package:lolisnatcher/src/data/settings/preview_display_mode.dart';
import 'package:lolisnatcher/src/data/settings/preview_quality.dart';
import 'package:lolisnatcher/src/data/settings/proxy_type.dart';
import 'package:lolisnatcher/src/data/settings/scroll_direction.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/share_action.dart';
import 'package:lolisnatcher/src/data/settings/tab_page_restore_mode.dart';
import 'package:lolisnatcher/src/data/settings/vertical_position.dart';
import 'package:lolisnatcher/src/data/settings/video_backend_mode.dart';
import 'package:lolisnatcher/src/data/settings/video_cache_mode.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';

/// Centralized enum for all setting keys.
/// Prevents typos and enables IDE autocomplete.
///
/// Order within each section matches the registration order in [registerAllSettings],
/// which determines display order on auto-rendered settings pages.
enum SettingKey {
  // Interface
  portraitColumns,
  landscapeColumns,
  previewMode,
  previewDisplay,
  previewDisplayFallback,
  tabPageRestoreMode,
  defaultSavePageEnabled,
  appMode,
  handSide,
  showBottomSearchbar,
  useTopSearchbarInput,
  showSearchbarQuickActions,
  autofocusSearchbar,
  disableImageScaling,
  gifsAsThumbnails,

  // Viewer
  galleryMode,
  preloadCount,
  preloadHeight,
  preloadSizeLimit,
  autoHideImageBar,
  galleryBarPosition,
  galleryScrollDirection,
  zoomButtonPosition,
  changePageButtonsPosition,
  scrollGridButtonsPosition,
  shareAction,
  buttonOrder,
  disabledButtons,
  allowRotation,
  expandDetails,
  hideNotes,
  enableHeroTransitions,
  disableCustomPageTransitions,
  galleryAutoScrollTime,
  useVolumeButtonsForScroll,
  volumeButtonsScrollSpeed,

  // Video
  disableVideo,
  autoPlayEnabled,
  startVideosMuted,
  videoBackendMode,
  videoCacheMode,
  altVideoPlayerHwAccel,
  altVideoPlayerVO,
  altVideoPlayerHWDEC,

  // Theme
  theme,
  themeMode,
  isAmoled,
  useDynamicColor,
  customPrimaryColor,
  customAccentColor,
  fontFamily,
  enableDrawerMascot,
  drawerMascotPathOverride,

  // Cache & Storage
  thumbnailCache,
  mediaCache,
  cacheDuration,
  cacheSize,
  snatchMode,
  snatchCooldown,
  jsonWrite,
  extPathOverride,
  cacheStatsSlot,
  backupPath,
  syncVisibleOnNetwork,

  // Database
  dbEnabled,
  indexesEnabled,
  searchHistoryEnabled,
  tagTypeFetchEnabled,
  databaseActionsSlot,

  // Network
  customUserAgent,
  proxyType,
  proxyAddress,
  proxyUsername,
  proxyPassword,
  allowSelfSignedCerts,
  cookieManagerSlot,

  // Privacy & Filters
  filterHated,
  filterMarked,
  filterFavourites,
  filterSnatched,
  filterAi,
  useLockscreen,
  blurOnLeave,
  autoLockTimeout,
  incognitoKeyboard,

  // Tags
  defTags,
  hiddenTags,
  markedTags,

  // Other
  prefBooru,
  limit,
  loadingGif,
  wakeLockEnabled,
  downloadNotifications,
  snatchOnFavourite,
  favouriteOnSnatch,
  disableVibration,
  desktopListsDrag,
  mousewheelScrollSpeed,
  locale,
  appAlias,
  usePredictiveBack,
  captureLogcat,
  useImageLogging,

  // Debug
  shitDevice,
  isDebug,
  showFps,
  showPerf,
  showImageStats,
  showVideoStats,
  ;

  /// JSON key for serialization.
  /// Matches the enum name by default (which matches existing keys for backwards compatibility).
  /// Override in the switch for any keys that differ.
  String get jsonKey {
    switch (this) {
      default:
        return name;
    }
  }

  /// Get the [SettingState] for this key from the registry.
  ///
  /// Usage: `SettingKey.portraitColumns.state<int>()`
  SettingState<T> state<T>() => SettingsRegistry.instance.get<T>(this)!;

  /// Get the current effective value for this key from the registry.
  ///
  /// This is the primary way for app code to read a setting value.
  /// Returns the per-booru override if one is active, otherwise the global value.
  ///
  /// Usage: `SettingKey.portraitColumns.value<int>()`
  T value<T>() => SettingsRegistry.instance.get<T>(this)!.value;
}

/// A typed setting key that carries its value type [T].
///
/// Provides type-safe [value] and [state] getters without needing
/// to specify the generic parameter at the call site.
///
/// Use via the [SK] class constants: `SK.showFps.value` instead of
/// `SettingKey.showFps.value<bool>()`.
class TypedKey<T> {
  const TypedKey(this.key);

  /// The underlying untyped enum key.
  final SettingKey key;

  /// Get the current effective value (considers per-booru overrides).
  T get value => SettingsRegistry.instance.get<T>(key)!.value;

  /// Get the mutable [SettingState] for this key.
  SettingState<T> get state => SettingsRegistry.instance.get<T>(key)!;
}

/// Type-safe shorthand for accessing settings.
///
/// Each constant carries its value type, so `.value` and `.state`
/// return the correct type without a generic parameter:
/// ```dart
/// SX.showFps.value       // bool
/// SX.portraitColumns.state // SettingState<int>
/// ```

// Using SX shorthand instead of SK because X is closer to S on the keyboard
abstract class SX {
  // Interface
  static const portraitColumns = TypedKey<int>(SettingKey.portraitColumns);
  static const landscapeColumns = TypedKey<int>(SettingKey.landscapeColumns);
  static const previewMode = TypedKey<PreviewQuality>(SettingKey.previewMode);
  static const previewDisplay = TypedKey<PreviewDisplayMode>(SettingKey.previewDisplay);
  static const previewDisplayFallback = TypedKey<PreviewDisplayMode>(SettingKey.previewDisplayFallback);
  static const tabPageRestoreMode = TypedKey<TabPageRestoreMode>(SettingKey.tabPageRestoreMode);
  static const defaultSavePageEnabled = TypedKey<bool>(SettingKey.defaultSavePageEnabled);
  static const appMode = TypedKey<AppMode>(SettingKey.appMode);
  static const handSide = TypedKey<HandSide>(SettingKey.handSide);
  static const showBottomSearchbar = TypedKey<bool>(SettingKey.showBottomSearchbar);
  static const useTopSearchbarInput = TypedKey<bool>(SettingKey.useTopSearchbarInput);
  static const showSearchbarQuickActions = TypedKey<bool>(SettingKey.showSearchbarQuickActions);
  static const autofocusSearchbar = TypedKey<bool>(SettingKey.autofocusSearchbar);
  static const disableImageScaling = TypedKey<bool>(SettingKey.disableImageScaling);
  static const gifsAsThumbnails = TypedKey<bool>(SettingKey.gifsAsThumbnails);

  // Viewer
  static const galleryMode = TypedKey<ImageQuality>(SettingKey.galleryMode);
  static const preloadCount = TypedKey<int>(SettingKey.preloadCount);
  static const preloadHeight = TypedKey<int>(SettingKey.preloadHeight);
  static const preloadSizeLimit = TypedKey<double>(SettingKey.preloadSizeLimit);
  static const autoHideImageBar = TypedKey<bool>(SettingKey.autoHideImageBar);
  static const galleryBarPosition = TypedKey<VerticalPosition>(SettingKey.galleryBarPosition);
  static const galleryScrollDirection = TypedKey<UiScrollDirection>(SettingKey.galleryScrollDirection);
  static const zoomButtonPosition = TypedKey<ButtonPosition>(SettingKey.zoomButtonPosition);
  static const changePageButtonsPosition = TypedKey<ButtonPosition>(SettingKey.changePageButtonsPosition);
  static const scrollGridButtonsPosition = TypedKey<ButtonPosition>(SettingKey.scrollGridButtonsPosition);
  static const shareAction = TypedKey<ShareAction>(SettingKey.shareAction);
  static const buttonOrder = TypedKey<List<String>>(SettingKey.buttonOrder);
  static const disabledButtons = TypedKey<List<String>>(SettingKey.disabledButtons);
  static const allowRotation = TypedKey<bool>(SettingKey.allowRotation);
  static const expandDetails = TypedKey<bool>(SettingKey.expandDetails);
  static const hideNotes = TypedKey<bool>(SettingKey.hideNotes);
  static const enableHeroTransitions = TypedKey<bool>(SettingKey.enableHeroTransitions);
  static const disableCustomPageTransitions = TypedKey<bool>(SettingKey.disableCustomPageTransitions);
  static const galleryAutoScrollTime = TypedKey<int>(SettingKey.galleryAutoScrollTime);
  static const useVolumeButtonsForScroll = TypedKey<bool>(SettingKey.useVolumeButtonsForScroll);
  static const volumeButtonsScrollSpeed = TypedKey<int>(SettingKey.volumeButtonsScrollSpeed);

  // Video
  static const disableVideo = TypedKey<bool>(SettingKey.disableVideo);
  static const autoPlayEnabled = TypedKey<bool>(SettingKey.autoPlayEnabled);
  static const startVideosMuted = TypedKey<bool>(SettingKey.startVideosMuted);
  static const videoBackendMode = TypedKey<VideoBackendMode>(SettingKey.videoBackendMode);
  static const videoCacheMode = TypedKey<VideoCacheMode>(SettingKey.videoCacheMode);
  static const altVideoPlayerHwAccel = TypedKey<bool>(SettingKey.altVideoPlayerHwAccel);
  static const altVideoPlayerVO = TypedKey<MpvVideoOutput>(SettingKey.altVideoPlayerVO);
  static const altVideoPlayerHWDEC = TypedKey<MpvHardwareDecoding>(SettingKey.altVideoPlayerHWDEC);

  // Theme
  static const theme = TypedKey<ThemeItem>(SettingKey.theme);
  static const themeMode = TypedKey<ThemeMode>(SettingKey.themeMode);
  static const isAmoled = TypedKey<bool>(SettingKey.isAmoled);
  static const useDynamicColor = TypedKey<bool>(SettingKey.useDynamicColor);
  static const customPrimaryColor = TypedKey<Color?>(SettingKey.customPrimaryColor);
  static const customAccentColor = TypedKey<Color?>(SettingKey.customAccentColor);
  static const fontFamily = TypedKey<String>(SettingKey.fontFamily);
  static const enableDrawerMascot = TypedKey<bool>(SettingKey.enableDrawerMascot);
  static const drawerMascotPathOverride = TypedKey<String>(SettingKey.drawerMascotPathOverride);

  // Cache & Storage
  static const thumbnailCache = TypedKey<bool>(SettingKey.thumbnailCache);
  static const mediaCache = TypedKey<bool>(SettingKey.mediaCache);
  static const cacheDuration = TypedKey<Duration>(SettingKey.cacheDuration);
  static const cacheSize = TypedKey<int>(SettingKey.cacheSize);
  static const snatchMode = TypedKey<ImageQuality>(SettingKey.snatchMode);
  static const snatchCooldown = TypedKey<int>(SettingKey.snatchCooldown);
  static const jsonWrite = TypedKey<bool>(SettingKey.jsonWrite);
  static const extPathOverride = TypedKey<String>(SettingKey.extPathOverride);
  static const backupPath = TypedKey<String>(SettingKey.backupPath);
  static const syncVisibleOnNetwork = TypedKey<bool>(SettingKey.syncVisibleOnNetwork);

  // Database
  static const dbEnabled = TypedKey<bool>(SettingKey.dbEnabled);
  static const indexesEnabled = TypedKey<bool>(SettingKey.indexesEnabled);
  static const searchHistoryEnabled = TypedKey<bool>(SettingKey.searchHistoryEnabled);
  static const tagTypeFetchEnabled = TypedKey<bool>(SettingKey.tagTypeFetchEnabled);

  // Network
  static const customUserAgent = TypedKey<String>(SettingKey.customUserAgent);
  static const proxyType = TypedKey<ProxyType>(SettingKey.proxyType);
  static const proxyAddress = TypedKey<String>(SettingKey.proxyAddress);
  static const proxyUsername = TypedKey<String>(SettingKey.proxyUsername);
  static const proxyPassword = TypedKey<String>(SettingKey.proxyPassword);
  static const allowSelfSignedCerts = TypedKey<bool>(SettingKey.allowSelfSignedCerts);

  // Privacy & Filters
  static const filterHated = TypedKey<bool>(SettingKey.filterHated);
  static const filterMarked = TypedKey<bool>(SettingKey.filterMarked);
  static const filterFavourites = TypedKey<bool>(SettingKey.filterFavourites);
  static const filterSnatched = TypedKey<bool>(SettingKey.filterSnatched);
  static const filterAi = TypedKey<bool>(SettingKey.filterAi);
  static const useLockscreen = TypedKey<bool>(SettingKey.useLockscreen);
  static const blurOnLeave = TypedKey<bool>(SettingKey.blurOnLeave);
  static const autoLockTimeout = TypedKey<int>(SettingKey.autoLockTimeout);
  static const incognitoKeyboard = TypedKey<bool>(SettingKey.incognitoKeyboard);

  // Tags
  static const defTags = TypedKey<String>(SettingKey.defTags);
  static const hiddenTags = TypedKey<List<String>>(SettingKey.hiddenTags);
  static const markedTags = TypedKey<List<String>>(SettingKey.markedTags);

  // Other
  static const prefBooru = TypedKey<String>(SettingKey.prefBooru);
  static const limit = TypedKey<int>(SettingKey.limit);
  static const loadingGif = TypedKey<bool>(SettingKey.loadingGif);
  static const wakeLockEnabled = TypedKey<bool>(SettingKey.wakeLockEnabled);
  static const downloadNotifications = TypedKey<bool>(SettingKey.downloadNotifications);
  static const snatchOnFavourite = TypedKey<bool>(SettingKey.snatchOnFavourite);
  static const favouriteOnSnatch = TypedKey<bool>(SettingKey.favouriteOnSnatch);
  static const disableVibration = TypedKey<bool>(SettingKey.disableVibration);
  static const desktopListsDrag = TypedKey<bool>(SettingKey.desktopListsDrag);
  static const mousewheelScrollSpeed = TypedKey<double>(SettingKey.mousewheelScrollSpeed);
  static const locale = TypedKey<AppLocale?>(SettingKey.locale);
  static const appAlias = TypedKey<AppAlias>(SettingKey.appAlias);
  static const usePredictiveBack = TypedKey<bool>(SettingKey.usePredictiveBack);
  static const captureLogcat = TypedKey<bool>(SettingKey.captureLogcat);
  static const useImageLogging = TypedKey<bool>(SettingKey.useImageLogging);

  // Debug
  static const shitDevice = TypedKey<bool>(SettingKey.shitDevice);
  static const isDebug = TypedKey<bool>(SettingKey.isDebug);
  static const showFps = TypedKey<bool>(SettingKey.showFps);
  static const showPerf = TypedKey<bool>(SettingKey.showPerf);
  static const showImageStats = TypedKey<bool>(SettingKey.showImageStats);
  static const showVideoStats = TypedKey<bool>(SettingKey.showVideoStats);
}
