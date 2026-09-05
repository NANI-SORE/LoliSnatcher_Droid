import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lolisnatcher/src/pages/settings/language_page.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/setting_state.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/ok_button.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/settings/booru_editing_scope.dart';
import 'package:lolisnatcher/src/widgets/settings/setting_builder.dart';

/// Factory for [ThemeMode] settings (System/Light/Dark).
///
/// Renders as a [SettingsDropdown].
SettingDef<ThemeMode> themeModeSetting({
  required SettingKey key,
  required ThemeMode Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(ThemeMode oldValue, ThemeMode newValue)? onChanged,
}) {
  return SettingDef<ThemeMode>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v.name,
    valueFromJson: (json) {
      if (json is String) {
        for (final mode in ThemeMode.values) {
          if (mode.name == json) return mode;
        }
      }
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<ThemeMode>;
      return SettingBuilder<ThemeMode>(
        setting: s,
        builder: (ctx, value) => SettingsDropdown<ThemeMode>(
          title: localization.title(ctx),
          value: s.scopedValue(ctx),
          items: ThemeMode.values,
          itemTitleBuilder: (mode) => mode != null ? _themeModeName(ctx, mode) : '',
          itemBuilder: (mode) => _ThemeModeOption(
            mode: mode,
            label: mode != null ? _themeModeName(ctx, mode) : '',
          ),
          selectedItemBuilder: (mode) => _ThemeModeOption(
            mode: mode,
            label: mode != null ? _themeModeName(ctx, mode) : '',
          ),
          onChanged: (newValue) {
            if (newValue != null) s.setScopedValue(ctx, newValue);
          },
        ),
      );
    },
  );
}

String _themeModeName(BuildContext context, ThemeMode mode) {
  // Uses dynamic key lookup: settings.theme.system / settings.theme.light / settings.theme.dark
  return context.loc['settings.theme.${mode.name}'];
}

/// Factory for [AppLocale] settings (app language).
///
/// Renders as a [SettingsDropdown] showing native language names.
SettingDef<AppLocale?> localeSetting({
  required SettingKey key,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(AppLocale? oldValue, AppLocale? newValue)? onChanged,
}) {
  return SettingDef<AppLocale?>(
    key: key,
    getDefaultValue: () => null,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v?.name,
    valueFromJson: (json) {
      if (json is String) {
        return AppLocale.values.where((e) => e.name == json).firstOrNull;
      }
      return null;
    },
    widgetBuilder: (context, dynamic state) {
      return SettingsButton(
        name: localization.title(context),
        icon: const Icon(Icons.language),
        page: () => const LanguageSettingsPage(),
      );
    },
  );
}

/// Factory for [ThemeItem] settings (color theme selection).
///
/// Renders as a [SettingsDropdown] with theme name labels.
SettingDef<ThemeItem> themeSetting({
  required SettingKey key,
  required ThemeItem Function() getDefaultValue,
  required SettingLocalization localization,
  required List<ThemeItem> Function() getOptions,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(ThemeItem oldValue, ThemeItem newValue)? onChanged,
}) {
  return SettingDef<ThemeItem>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v.name,
    valueFromJson: (json) {
      if (json is String) {
        final options = getOptions();
        for (final theme in options) {
          if (theme.name == json) return theme;
        }
      }
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<ThemeItem>;
      return SettingBuilder<ThemeItem>(
        setting: s,
        builder: (ctx, value) => SettingsDropdown<ThemeItem>(
          title: localization.title(ctx),
          value: s.scopedValue(ctx),
          items: getOptions(),
          itemTitleBuilder: (item) => item?.locName(ctx) ?? '',
          itemBuilder: (item) => _ThemeItemOption(
            item: item,
            primaryColor: _themeOptionPrimaryColor(ctx, item),
            accentColor: _themeOptionAccentColor(ctx, item),
          ),
          selectedItemBuilder: (item) => _ThemeItemOption(
            item: item,
            primaryColor: _themeOptionPrimaryColor(ctx, item),
            accentColor: _themeOptionAccentColor(ctx, item),
          ),
          onChanged: (newValue) {
            if (newValue != null) s.setScopedValue(ctx, newValue);
          },
        ),
      );
    },
  );
}

Color? _themeOptionPrimaryColor(BuildContext context, ThemeItem? item) {
  return item?.name == 'Custom' ? SX.customPrimaryColor.state.scopedValue(context) : item?.primary;
}

Color? _themeOptionAccentColor(BuildContext context, ThemeItem? item) {
  return item?.name == 'Custom' ? SX.customAccentColor.state.scopedValue(context) : item?.accent;
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.label,
  });

  final ThemeMode? mode;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: switch (mode) {
            ThemeMode.dark => const Icon(Icons.dark_mode),
            ThemeMode.light => const Icon(Icons.light_mode),
            ThemeMode.system => Stack(
              alignment: Alignment.center,
              children: [
                ClipPath(
                  clipper: _SunClipper(),
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.light_mode),
                  ),
                ),
                ClipPath(
                  clipper: _MoonClipper(),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Icon(Icons.dark_mode),
                  ),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ThemeItemOption extends StatelessWidget {
  const _ThemeItemOption({
    required this.item,
    required this.primaryColor,
    required this.accentColor,
  });

  final ThemeItem? item;
  final Color? primaryColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    const double themeSize = 40;

    return Row(
      children: [
        Center(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white).withValues(
                  alpha: 0.6,
                ),
                width: 1,
              ),
              shape: BoxShape.rectangle,
              color: primaryColor,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipPath(
                    clipper: _ThemeLeftClipper(),
                    child: Container(
                      color: primaryColor,
                      height: themeSize,
                      width: themeSize,
                    ),
                  ),
                  ClipPath(
                    clipper: _ThemeRightClipper(),
                    child: Container(
                      color: accentColor,
                      height: themeSize,
                      width: themeSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            item?.locName(context) ?? '?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        switch (item?.name) {
          'Halloween' => const Padding(
            padding: EdgeInsets.only(left: 8),
            child: FaIcon(FontAwesomeIcons.ghost),
          ),
          'Custom' => const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.build),
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _SunClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height);
    path.lineTo(size.width * 0.37, size.height);
    path.lineTo(size.width * 0.37, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _MoonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width * 0.45, size.height);
    path.lineTo(size.width * 0.45, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _ThemeLeftClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height);
    path.lineTo(size.width * 0.7, size.height);
    path.lineTo(size.width * 0.3, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _ThemeRightClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width * 0.3, size.height);
    path.lineTo(size.width * 0.7, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Factory for font family settings.
///
/// Renders as a [SettingsButton] that opens a modal bottom sheet with font
/// selection (default fonts, extended fonts, and custom Google Font input).
SettingDef<String> fontFamilySetting({
  required SettingKey key,
  required String Function() getDefaultValue,
  required SettingLocalization localization,
  required List<String> Function() getOptions,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(String oldValue, String newValue)? onChanged,
}) {
  return SettingDef<String>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is String) return json;
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<String>;
      return _FontFamilySettingWidget(setting: s, localization: localization);
    },
  );
}

/// Factory for color picker settings.
///
/// Renders as a [SettingsButton] with a [ColorIndicator] that opens a
/// [ColorPicker] dialog from flex_color_picker.
SettingDef<Color?> colorPickerSetting({
  required SettingKey key,
  required Color? Function() getDefaultValue,
  required SettingLocalization localization,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(Color? oldValue, Color? newValue)? onChanged,
}) {
  return SettingDef<Color?>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    // ignore: deprecated_member_use
    valueToJson: (v) => v?.value,
    valueFromJson: (json) {
      if (json is int) return Color(json);
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<Color?>;
      return _ColorPickerSettingWidget(setting: s, localization: localization);
    },
  );
}

/// Factory for directory picker settings (Android SAF).
///
/// Renders as a [SettingsButton] showing the current path that opens the SAF
/// directory picker. Includes a reset button when a path is set.
SettingDef<String> directoryPickerSetting({
  required SettingKey key,
  required String Function() getDefaultValue,
  required SettingLocalization localization,
  required Future<String> Function() pickDirectory,
  required SettingAccessValidator<String> accessValidator,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(String oldValue, String newValue)? onChanged,
}) {
  return SettingDef<String>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    accessValidator: accessValidator,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is String) return json;
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<String>;
      return _DirectoryPickerSettingWidget(
        setting: s,
        localization: localization,
        pickDirectory: pickDirectory,
      );
    },
  );
}

/// Factory for image/file picker settings (Android SAF).
///
/// Renders as a [SettingsButton] that opens the SAF file picker.
/// Shows current path as subtitle and a remove button when set.
SettingDef<String> filePickerSetting({
  required SettingKey key,
  required String Function() getDefaultValue,
  required SettingLocalization localization,
  required Future<String> Function() pickFile,
  required SettingAccessValidator<String> accessValidator,
  String Function(BuildContext context)? setButtonLabel,
  String Function(BuildContext context)? removeButtonLabel,
  Future<String> Function(BuildContext context, String path)? transformPickedPath,
  Future<void> Function(String path)? onRemove,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool supportsPerBooru = false,
  bool Function()? visibleWhen,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(String oldValue, String newValue)? onChanged,
}) {
  return SettingDef<String>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    supportsPerBooru: supportsPerBooru,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    accessValidator: accessValidator,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is String) return json;
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<String>;
      return _FilePickerSettingWidget(
        setting: s,
        localization: localization,
        pickFile: pickFile,
        setButtonLabel: setButtonLabel,
        removeButtonLabel: removeButtonLabel,
        transformPickedPath: transformPickedPath,
        onRemove: onRemove,
      );
    },
  );
}

/// Factory for boolean settings that require a confirmation dialog before enabling.
///
/// Shows a [SettingsToggle] that pops a confirmation dialog when the user
/// tries to enable the setting. Optionally applies cascading side effects.
SettingDef<bool> confirmBoolSetting({
  required SettingKey key,
  required bool Function() getDefaultValue,
  required SettingLocalization localization,
  required Widget Function(BuildContext context) buildDialogContent,
  void Function()? onConfirmed,
  List<SettingCategory> categories = const [],
  List<SettingSubcategory> subcategories = const [],
  bool isDeviceSpecific = false,
  bool Function()? visibleWhen,
  SettingWidgetConfig? widgetConfig,
  List<SettingKey>? dependsOn,
  bool Function([BuildContext? context])? enabledWhen,
  void Function(bool oldValue, bool newValue)? onChanged,
}) {
  return SettingDef<bool>(
    key: key,
    getDefaultValue: getDefaultValue,
    localization: localization,
    categories: categories,
    subcategories: subcategories,
    isDeviceSpecific: isDeviceSpecific,
    visibleWhen: visibleWhen,
    dependsOn: dependsOn,
    enabledWhen: enabledWhen,
    onChanged: onChanged,
    valueToJson: (v) => v,
    valueFromJson: (json) {
      if (json is bool) return json;
      if (json is String) {
        if (json == 'true') return true;
        if (json == 'false') return false;
      }
      return getDefaultValue();
    },
    widgetBuilder: (context, dynamic state) {
      final s = state as SettingState<bool>;
      return _ConfirmBoolSettingWidget(
        setting: s,
        localization: localization,
        widgetConfig: widgetConfig,
        enabledWhen: enabledWhen,
        buildDialogContent: buildDialogContent,
        onConfirmed: onConfirmed,
      );
    },
  );
}

// ============================================
// STATEFUL WIDGET IMPLEMENTATIONS
// ============================================

// --- Font Family Picker ---

class _FontFamilySettingWidget extends StatelessWidget {
  const _FontFamilySettingWidget({
    required this.setting,
    required this.localization,
  });

  final SettingState<String> setting;
  final SettingLocalization localization;

  static TextStyle? _getFontStyle(String font) {
    if (font == 'System') return null;
    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<String>(
      setting: setting,
      builder: (ctx, value) {
        final scopedVal = setting.scopedValue(ctx);
        return SettingsButton(
          name: localization.title(ctx),
          subtitle: Text(
            scopedVal == 'System' ? ctx.loc.settings.theme.systemDefault : scopedVal,
            style: _getFontStyle(scopedVal),
          ),
          icon: const Icon(Icons.font_download),
          trailingIcon: scopedVal == setting.resetValue(ctx)
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setting.resetScoped(ctx),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
          action: () => _showFontPicker(ctx),
        );
      },
    );
  }

  Future<void> _showFontPicker(BuildContext context) async {
    const List<String> defaultFonts = [
      'System',
      'Roboto',
      'Open Sans',
      'Lato',
      'Montserrat',
      'Oswald',
      'Raleway',
      'Poppins',
      'Nunito',
      'Ubuntu',
      'Merriweather',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return _FontPickerSheet(
              currentFont: setting.scopedValue(context),
              defaultFonts: defaultFonts,
              onFontSelected: (String font) {
                setting.setScopedValue(context, font);
                Navigator.of(ctx).pop();
              },
              getFontStyle: _getFontStyle,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.currentFont,
    required this.defaultFonts,
    required this.onFontSelected,
    required this.getFontStyle,
    required this.scrollController,
  });

  final String currentFont;
  final List<String> defaultFonts;
  final ValueChanged<String> onFontSelected;
  final TextStyle? Function(String) getFontStyle;
  final ScrollController scrollController;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  String selectedFont = 'System';
  late bool showAllFonts;

  static const List<String> extendedFonts = [
    'Playfair Display',
    'Source Sans 3',
    'Noto Sans',
    'Inter',
    'Quicksand',
    'Work Sans',
    'Fira Sans',
    'Josefin Sans',
    'Cabin',
    'Karla',
    'Libre Baskerville',
    'Inconsolata',
    'Source Code Pro',
    'Space Mono',
    'JetBrains Mono',
    'Crimson Text',
    'Bitter',
    'Archivo',
    'Rubik',
    'Comfortaa',
  ];

  @override
  void initState() {
    super.initState();
    selectedFont = widget.currentFont;
    final isCustomFont =
        !widget.defaultFonts.contains(selectedFont) &&
        !extendedFonts.contains(selectedFont) &&
        selectedFont != 'System';
    showAllFonts = extendedFonts.contains(selectedFont) || isCustomFont;
  }

  Future<void> _showCustomFontDialog(BuildContext context) async {
    final initialText =
        !widget.defaultFonts.contains(selectedFont) && !extendedFonts.contains(selectedFont) && selectedFont != 'System'
        ? selectedFont
        : '';
    final controller = TextEditingController(text: initialText);

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _CustomFontDialog(controller: controller),
    );

    if (result != null && result.isNotEmpty) {
      widget.onFontSelected(result);
    }
  }

  TextStyle? _getExtendedFontStyle(String font) {
    if (font == 'System') {
      return context.isDark ? ThemeData.dark().textTheme.bodyMedium : ThemeData.light().textTheme.bodyMedium;
    }

    final defaultStyle = widget.getFontStyle(font);
    if (defaultStyle != null) return defaultStyle;

    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return defaultStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> fontsToShow = showAllFonts ? [...widget.defaultFonts, ...extendedFonts] : widget.defaultFonts;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                context.loc.settings.theme.fontFamily,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            controller: widget.scrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: fontsToShow.length + 1,
              itemBuilder: (context, index) {
                if (!showAllFonts && index == fontsToShow.length) {
                  return ListTile(
                    leading: const Icon(Icons.expand_more),
                    title: Text(context.loc.settings.theme.viewMoreFonts),
                    onTap: () => setState(() => showAllFonts = true),
                  );
                }

                if (showAllFonts && index == fontsToShow.length) {
                  final isCustomSelected =
                      !widget.defaultFonts.contains(selectedFont) &&
                      !extendedFonts.contains(selectedFont) &&
                      selectedFont != 'System';

                  return ListTile(
                    leading: isCustomSelected ? const Icon(Icons.check) : const SizedBox(width: 24),
                    title: Text(context.loc.settings.theme.customFont),
                    subtitle: Text(context.loc.settings.theme.customFontSubtitle),
                    trailing: const Icon(Icons.edit),
                    selectedTileColor: Theme.of(context).colorScheme.secondary,
                    selectedColor: Theme.of(context).colorScheme.onSecondary,
                    selected: isCustomSelected,
                    onTap: () => _showCustomFontDialog(context),
                  );
                }

                final font = fontsToShow[index];
                final isSelected = font == selectedFont;
                final fontStyle = _getExtendedFontStyle(font);

                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: isSelected ? const Icon(Icons.check) : const SizedBox(width: 24),
                    title: Text(
                      font == 'System' ? context.loc.settings.theme.systemDefault : font,
                      style: fontStyle?.copyWith(fontSize: 16),
                    ),
                    selectedTileColor: Theme.of(context).colorScheme.secondary,
                    selectedColor: Theme.of(context).colorScheme.onSecondary,
                    selected: isSelected,
                    onTap: () => setState(() => selectedFont = font),
                  ),
                );
              },
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final fontStyle = _getExtendedFontStyle(selectedFont);

            String text = context.loc.settings.theme.fontPreviewText;
            if (SX.locale.value == null
                ? PlatformDispatcher.instance.locale.languageCode != 'en'
                : SX.locale.value != AppLocale.en) {
              text =
                  '${LocaleSettings.instance.translationMap[AppLocale.en]?.settings.theme.fontPreviewText}\n\n${context.loc.settings.theme.fontPreviewText}';
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    spacing: 12,
                    children: [
                      const Icon(Icons.check),
                      Expanded(
                        child: Text(
                          selectedFont == 'System' ? context.loc.settings.theme.systemDefault : selectedFont,
                          style: fontStyle?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    text,
                    style: fontStyle?.copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => widget.onFontSelected(selectedFont),
                    child: Text(context.loc.tabs.filters.apply),
                  ),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomFontDialog extends StatefulWidget {
  const _CustomFontDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_CustomFontDialog> createState() => _CustomFontDialogState();
}

class _CustomFontDialogState extends State<_CustomFontDialog> {
  String _previewText = '';
  TextStyle? _previewStyle;
  bool _fontError = false;

  @override
  void initState() {
    super.initState();
    _previewText = widget.controller.text;
    _updatePreview(_previewText);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text.trim();
    if (text != _previewText) {
      _previewText = text;
      _updatePreview(text);
    }
  }

  void _updatePreview(String fontName) {
    if (fontName.isEmpty) {
      setState(() {
        _previewStyle = null;
        _fontError = false;
      });
      return;
    }

    try {
      final style = GoogleFonts.getFont(fontName);
      setState(() {
        _previewStyle = style;
        _fontError = false;
      });
    } catch (_) {
      setState(() {
        _previewStyle = null;
        _fontError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.loc.settings.theme.customFont),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: context.loc.settings.theme.fontName,
              hintText: 'Noto Sans',
              errorText: _fontError ? context.loc.settings.theme.fontNotFound : null,
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty && !_fontError) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          const SizedBox(height: 12),
          if (_previewStyle != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(
                builder: (context) {
                  String text = context.loc.settings.theme.fontPreviewText;
                  if (SX.locale.value == null
                      ? PlatformDispatcher.instance.locale.languageCode != 'en'
                      : SX.locale.value != AppLocale.en) {
                    text =
                        '${LocaleSettings.instance.translationMap[AppLocale.en]?.settings.theme.fontPreviewText}\n\n${context.loc.settings.theme.fontPreviewText}';
                  }

                  return Text(
                    text,
                    style: _previewStyle?.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: () {
              launchUrlString(
                'https://fonts.google.com/',
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(
              context.loc.settings.theme.customFontHint,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
      actions: [
        const CancelButton(withIcon: true),
        OkButton(
          withIcon: true,
          action: _fontError || widget.controller.text.trim().isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(widget.controller.text.trim());
                },
        ),
      ],
    );
  }
}

// --- Color Picker ---

class _ColorPickerSettingWidget extends StatelessWidget {
  const _ColorPickerSettingWidget({
    required this.setting,
    required this.localization,
  });

  final SettingState<Color?> setting;
  final SettingLocalization localization;

  Future<bool> _showColorPicker(BuildContext context, Color startColor, void Function(Color) onChange) {
    return ColorPicker(
      color: startColor,
      onColorChanged: onChange,
      width: 40,
      height: 40,
      borderRadius: 4,
      spacing: 5,
      runSpacing: 5,
      wheelDiameter: 300,
      heading: Text(
        context.loc.settings.theme.selectColor,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subheading: Text(
        context.loc.settings.theme.selectedColorAndShades,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      wheelSubheading: Text(
        context.loc.settings.theme.selectedColorAndShades,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      showMaterialName: true,
      showColorName: true,
      showColorCode: true,
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(longPressMenu: true),
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorCodeTextStyle: Theme.of(context).textTheme.bodyMedium,
      colorCodePrefixStyle: Theme.of(context).textTheme.bodySmall,
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
      hasBorder: true,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: true,
        ColorPickerType.custom: false,
        ColorPickerType.wheel: true,
      },
      pickerTypeLabels: <ColorPickerType, String>{
        ColorPickerType.both: context.loc.settings.theme.colors,
        ColorPickerType.bw: context.loc.settings.theme.blackAndWhite,
        ColorPickerType.wheel: context.loc.settings.theme.wheel,
      },
      actionButtons: const ColorPickerActionButtons(
        okIcon: Icons.save,
        dialogOkButtonType: ColorPickerActionButtonType.elevated,
        closeIcon: Icons.keyboard_return_rounded,
        dialogCancelButtonType: ColorPickerActionButtonType.elevated,
        dialogActionIcons: true,
        dialogActionButtons: true,
      ),
    ).showPickerDialog(
      context,
      constraints: BoxConstraints(
        minHeight: 480,
        minWidth: 300,
        maxWidth: min(MediaQuery.sizeOf(context).width * 0.9, 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<Color?>(
      setting: setting,
      builder: (ctx, value) {
        final color = setting.scopedValue(ctx) ?? setting.defaultValue ?? Colors.blue;
        return SettingsButton(
          name: localization.title(ctx),
          subtitle: Text(
            '${ColorTools.materialNameAndCode(color)} '
            'aka ${ColorTools.nameThatColor(color)}',
          ),
          action: () async {
            final colorBefore = color;
            if (!await _showColorPicker(
              ctx,
              color,
              (Color newColor) => setting.setScopedValue(ctx, newColor, debounceSave: true),
            )) {
              setting.setScopedValue(ctx, colorBefore);
            }
          },
          trailingIcon: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              if (color != setting.resetValue(ctx))
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setting.resetScoped(ctx),
                ),
              ColorIndicator(
                width: 44,
                height: 44,
                hasBorder: true,
                borderRadius: 4,
                borderColor: (Theme.of(ctx).brightness == Brightness.light ? Colors.black : Colors.white).withValues(
                  alpha: 0.6,
                ),
                color: color,
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Directory Picker ---

class _DirectoryPickerSettingWidget extends StatelessWidget {
  const _DirectoryPickerSettingWidget({
    required this.setting,
    required this.localization,
    required this.pickDirectory,
  });

  final SettingState<String> setting;
  final SettingLocalization localization;
  final Future<String> Function() pickDirectory;

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<String>(
      setting: setting,
      builder: (ctx, value) {
        final scopedVal = setting.scopedValue(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsButton(
              name: localization.title(ctx),
              subtitle: scopedVal.isEmpty ? null : Text(ctx.loc.settings.cache.currentPath(path: scopedVal)),
              icon: const Icon(Icons.folder_outlined),
              action: () async {
                if (Platform.isAndroid) {
                  final String newPath = await pickDirectory();
                  if (newPath.isNotEmpty) {
                    setting.setScopedValue(ctx, newPath);
                  }
                } else {
                  FlashElements.showSnackbar(
                    context: ctx,
                    title: Text(
                      ctx.loc.settings.cache.errorExclamation,
                      style: const TextStyle(fontSize: 20),
                    ),
                    content: Text(
                      ctx.loc.settings.cache.notAvailableForPlatform,
                      style: const TextStyle(fontSize: 16),
                    ),
                    leadingIcon: Icons.error_outline,
                    leadingIconColor: Colors.red,
                    sideColor: Colors.red,
                  );
                }
              },
            ),
            if (scopedVal.isNotEmpty)
              SettingsButton(
                name: ctx.loc.settings.cache.resetStorageDirectory,
                icon: const Icon(Icons.refresh),
                action: () => setting.setScopedValue(ctx, ''),
              ),
          ],
        );
      },
    );
  }
}

// --- File Picker ---

class _FilePickerSettingWidget extends StatelessWidget {
  const _FilePickerSettingWidget({
    required this.setting,
    required this.localization,
    required this.pickFile,
    this.setButtonLabel,
    this.removeButtonLabel,
    this.transformPickedPath,
    this.onRemove,
  });

  final SettingState<String> setting;
  final SettingLocalization localization;
  final Future<String> Function() pickFile;
  final String Function(BuildContext context)? setButtonLabel;
  final String Function(BuildContext context)? removeButtonLabel;
  final Future<String> Function(BuildContext context, String path)? transformPickedPath;
  final Future<void> Function(String path)? onRemove;

  Future<void> _removePreviousFile(String path, {required bool autosave, required String? booruName}) async {
    if (path.isEmpty || onRemove == null) return;
    if (autosave) {
      // Keep the previous file until the replacement preference is durable.
      final settingsHandler = SettingsHandler.instance;
      if (booruName == null) {
        await settingsHandler.saveSettings(restate: false);
      } else {
        final booru = settingsHandler.booruList.where((booru) => booru.name == booruName).firstOrNull;
        if (booru == null || !await settingsHandler.saveBooru(booru, onlySave: true)) return;
      }
    }
    await onRemove!(path);
  }

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<String>(
      setting: setting,
      builder: (ctx, value) {
        final scopedVal = setting.scopedValue(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsButton(
              name: setButtonLabel?.call(ctx) ?? localization.title(ctx),
              subtitle: scopedVal.isEmpty ? null : Text('${localization.title(ctx)}: $scopedVal'),
              icon: const Icon(Icons.image_search_outlined),
              action: () async {
                final oldPath = setting.scopedValue(ctx);
                final booruName = setting.def.supportsPerBooru ? BooruEditingScope.of(ctx) : null;
                final ownsPath = booruName == null || setting.hasScopedOverride(ctx);
                final autosave = booruName == null || BooruEditingScope.autosaveOf(ctx);
                final selectedPath = await pickFile();
                if (!ctx.mounted) return;
                if (selectedPath.isNotEmpty) {
                  final path = transformPickedPath == null
                      ? selectedPath
                      : await transformPickedPath!(ctx, selectedPath);
                  if (!ctx.mounted) {
                    if (transformPickedPath != null) await onRemove?.call(path);
                    return;
                  }
                  if (path.isNotEmpty) {
                    setting.setScopedValue(ctx, path);
                    if (ownsPath && oldPath != path) {
                      await _removePreviousFile(oldPath, autosave: autosave, booruName: booruName);
                    }
                  }
                }
              },
            ),
            if (scopedVal.isNotEmpty)
              SettingsButton(
                name: removeButtonLabel?.call(ctx) ?? ctx.loc.reset,
                icon: const Icon(Icons.delete_forever),
                action: () async {
                  final oldPath = setting.scopedValue(ctx);
                  final booruName = setting.def.supportsPerBooru ? BooruEditingScope.of(ctx) : null;
                  final ownsPath = booruName == null || setting.hasScopedOverride(ctx);
                  final autosave = booruName == null || BooruEditingScope.autosaveOf(ctx);
                  setting.setScopedValue(ctx, '');
                  if (ownsPath) {
                    await _removePreviousFile(oldPath, autosave: autosave, booruName: booruName);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

// --- Confirm Bool (toggle with confirmation dialog) ---

class _ConfirmBoolSettingWidget extends StatelessWidget {
  const _ConfirmBoolSettingWidget({
    required this.setting,
    required this.localization,
    required this.buildDialogContent,
    this.widgetConfig,
    this.enabledWhen,
    this.onConfirmed,
  });

  final SettingState<bool> setting;
  final SettingLocalization localization;
  final SettingWidgetConfig? widgetConfig;
  final bool Function([BuildContext? context])? enabledWhen;
  final Widget Function(BuildContext context) buildDialogContent;
  final void Function()? onConfirmed;

  @override
  Widget build(BuildContext context) {
    return SettingBuilder<bool>(
      setting: setting,
      builder: (ctx, value) => SettingsToggle(
        title: localization.title(ctx),
        subtitle: localization.subtitle != null ? Text(localization.subtitle!(ctx)) : null,
        value: setting.scopedValue(ctx),
        defaultValue: setting.resetValue(ctx),
        onReset: () => setting.resetScoped(ctx),
        enabled: enabledWhen?.call(ctx) ?? true,
        leadingIcon: widgetConfig?.leadingIcon,
        trailingIcon: widgetConfig?.trailingIcon,
        onChanged: (newValue) async {
          if (newValue) {
            // Show confirmation dialog before enabling
            final res = await showDialog<bool>(
              context: ctx,
              builder: buildDialogContent,
            );
            if (res != true) return;
            onConfirmed?.call();
          }
          setting.setScopedValue(ctx, newValue);
        },
      ),
    );
  }
}
