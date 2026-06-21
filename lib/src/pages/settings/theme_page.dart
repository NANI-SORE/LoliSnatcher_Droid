import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/common/ok_button.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';
import 'package:lolisnatcher/src/pages/settings/booru_overrides_page.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/utils/debouncer.dart';
import 'package:lolisnatcher/src/utils/extensions.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

extension ThemeModeExt on ThemeMode {
  String locName(BuildContext context) => context.loc['settings.theme.$name'];
}

class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late ThemeItem theme;
  late ThemeMode themeMode;
  late bool useDynamicColor;
  late bool isAmoled;
  late String fontFamily;
  late bool enableMascot;
  late String mascotPathOverride;
  late Color? primaryPickerColor; // Color for picker shown in Card on the screen.
  late Color? accentPickerColor; // Color for picker in dialog using onChanged

  bool needToWriteMascot = false;
  int currentSdk = 0;

  @override
  void initState() {
    super.initState();
    // Read global values, not effective values — this page edits globals.
    // Using .value would pick up per-booru overrides from the active booru
    // and then write them back as globals on save.
    theme = SX.theme.state.globalValue;
    themeMode = SX.themeMode.state.globalValue;
    useDynamicColor = SX.useDynamicColor.state.globalValue;
    isAmoled = SX.isAmoled.state.globalValue;
    fontFamily = SX.fontFamily.state.globalValue;
    enableMascot = SX.enableDrawerMascot.state.globalValue;
    mascotPathOverride = SX.drawerMascotPathOverride.state.globalValue;
    primaryPickerColor = SX.customPrimaryColor.state.globalValue;
    accentPickerColor = SX.customAccentColor.state.globalValue;

    checkSdk();
  }

  Future<void> checkSdk() async {
    if (Platform.isAndroid) {
      currentSdk = await ServiceHandler.getAndroidSDKVersion();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    Debounce.cancel('theme_change');
    super.dispose();
  }

  /// Write all local state to the registry and save to disk.
  Future<void> _saveToRegistry({bool restate = false}) async {
    SX.theme.state.globalValue = theme;
    SX.themeMode.state.globalValue = themeMode;
    SX.useDynamicColor.state.globalValue = useDynamicColor;
    SX.isAmoled.state.globalValue = isAmoled;
    SX.fontFamily.state.globalValue = fontFamily;
    SX.enableDrawerMascot.state.globalValue = enableMascot;
    SX.customPrimaryColor.state.globalValue = primaryPickerColor;
    SX.customAccentColor.state.globalValue = accentPickerColor;

    // Mascot path: write the image file first if needed
    if (needToWriteMascot) {
      if (mascotPathOverride.isNotEmpty) {
        mascotPathOverride = await ImageWriter().writeMascotImage(mascotPathOverride);
        needToWriteMascot = false;
      }
    }
    SX.drawerMascotPathOverride.state.globalValue = mascotPathOverride;

    await settingsHandler.saveSettings(restate: restate);
  }

  /// Called on pop — just ensures final save happens (no-op if debounce already saved).
  Future<void> _onPopInvoked(_, _) async {
    Debounce.cancel('theme_change');
    await _saveToRegistry();
  }

  Future<void> updateTheme({bool withRestate = false}) async {
    // instantly do local restate
    setState(() {});

    // save after a debounce so the theme updates live
    Debounce.debounce(
      tag: 'theme_change',
      callback: () async {
        await _saveToRegistry(restate: withRestate);
        setState(() {});
      },
      duration: const Duration(milliseconds: 500),
    );
  }

  TextStyle? _getFontStyle(String font) {
    if (font == 'System') return null;

    try {
      return GoogleFonts.getFont(font);
    } catch (_) {
      return null;
    }
  }

  Future<void> _showFontPicker() async {
    final List<String> defaultFonts = [
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
              currentFont: fontFamily,
              defaultFonts: defaultFonts,
              onFontSelected: (String font) {
                fontFamily = font;
                updateTheme(withRestate: true);
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

  void _openActiveBooruThemeOverrides(String booruName) {
    for (final booru in settingsHandler.booruList) {
      if (booru.name == booruName) {
        SettingsPageOpen(
          context: context,
          page: (_) => BooruOverridesPage(
            booru: booru,
            initialCategory: SettingCategory.theme,
          ),
        ).open();
        return;
      }
    }
  }

  Widget _buildOverrideWarning(BuildContext context) {
    final currentBooru = SettingsRegistry.instance.currentBooruName;
    if (currentBooru == null) return const SizedBox.shrink();

    // Check if any theme-related setting has a per-booru override for the active booru
    final themeKeys = [
      SX.theme,
      SX.themeMode,
      SX.isAmoled,
      SX.useDynamicColor,
      SX.customPrimaryColor,
      SX.customAccentColor,
    ];
    final hasOverride = themeKeys.any((k) => k.state.hasOverrideFor(currentBooru));
    if (!hasOverride) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openActiveBooruThemeOverrides(currentBooru),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onTertiaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.loc.settings.activeBooruThemeOverrides(
                      booru: currentBooru,
                    ),
                    style: TextStyle(
                      color: colorScheme.onTertiaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onTertiaryContainer,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> colorPickerDialog(Color startColor, void Function(Color) onChange) async {
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
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        longPressMenu: true,
      ),
      materialNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorNameTextStyle: Theme.of(context).textTheme.bodySmall,
      colorCodeTextStyle: Theme.of(context).textTheme.bodyMedium,
      colorCodePrefixStyle: Theme.of(context).textTheme.bodySmall,
      selectedPickerTypeColor: Theme.of(context).colorScheme.primary,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: true,
        ColorPickerType.custom: true,
        ColorPickerType.wheel: true,
      },
      actionButtons: const ColorPickerActionButtons(
        // okButton: true,
        okIcon: Icons.save,
        dialogOkButtonType: ColorPickerActionButtonType.elevated,
        // closeButton: true,
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
    // Build theme from local (global) state so the page visually reflects
    // the global theme being edited, not a per-booru override.
    final localThemeItem = theme.name == 'Custom'
        ? ThemeItem(name: 'Custom', primary: primaryPickerColor, accent: accentPickerColor)
        : theme;
    final themeHandler = ThemeHandler(
      theme: localThemeItem,
      themeMode: themeMode,
      isAmoled: isAmoled,
      fontFamily: fontFamily,
      context: context,
    );

    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Theme(
        data: themeHandler.getTheme(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: SettingsAppBar(title: context.loc.settings.theme.title),
          body: Center(
            child: ListView(
              children: [
                _buildOverrideWarning(context),
                SettingsOptionsList(
                  value: themeMode,
                  items: ThemeMode.values,
                  onChanged: (ThemeMode? newValue) {
                    themeMode = newValue!;
                    updateTheme();
                  },
                  title: context.loc.settings.theme.themeMode,
                  itemTitleBuilder: (item) => item?.locName(context) ?? '?',
                  itemLeadingBuilder: (ThemeMode? item) {
                    const double size = 40;

                    return SizedBox(
                      width: size,
                      height: size,
                      child: switch (item) {
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
                    );
                  },
                ),
                if (themeMode == ThemeMode.system || themeMode == ThemeMode.dark)
                  SettingsToggle(
                    value: isAmoled,
                    onChanged: (bool newValue) {
                      isAmoled = newValue;
                      updateTheme();
                    },
                    title: context.loc.settings.theme.blackBg,
                  ),
                if (currentSdk >= 31)
                  SettingsToggle(
                    value: useDynamicColor,
                    onChanged: (bool newValue) {
                      useDynamicColor = newValue;
                      updateTheme();
                    },
                    title: context.loc.settings.theme.useDynamicColor,
                    subtitle: Platform.isAndroid ? Text(context.loc.settings.theme.android12PlusOnly) : null,
                  ),
                if (!useDynamicColor)
                  SettingsDropdown<ThemeItem>(
                    value: theme,
                    items: getThemeOptions(),
                    onChanged: (ThemeItem? newValue) {
                      if (newValue != null) {
                        theme = newValue;
                        updateTheme(withRestate: true);
                      }
                    },
                    title: context.loc.settings.theme.theme,
                    itemTitleBuilder: (ThemeItem? item) => item?.locName(context) ?? '',
                    itemBuilder: (ThemeItem? value) {
                      final Color? primary = value?.name == 'Custom' ? primaryPickerColor : value?.primary;
                      final Color? accent = value?.name == 'Custom' ? accentPickerColor : value?.accent;

                      const double themeSize = 40;

                      return Row(
                        children: [
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                                          .withValues(alpha: 0.6),
                                  width: 1,
                                ),
                                shape: BoxShape.rectangle,
                                color: primary,
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
                                        color: primary,
                                        height: themeSize,
                                        width: themeSize,
                                      ),
                                    ),
                                    ClipPath(
                                      clipper: _ThemeRightClipper(),
                                      child: Container(
                                        color: accent,
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
                          Text(
                            value?.locName(context) ?? '?',
                          ),
                          switch (value?.name) {
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
                    },
                  ),
                if (theme.name == 'Custom' && !useDynamicColor)
                  SettingsButton(
                    name: context.loc.settings.theme.primaryColor,
                    subtitle: Text(
                      '${ColorTools.materialNameAndCode(primaryPickerColor!)} '
                      'aka ${ColorTools.nameThatColor(primaryPickerColor!)}',
                    ),
                    action: () async {
                      // Store current color before we open the dialog.
                      final Color colorBeforeDialog = primaryPickerColor!;
                      // Wait for the picker to close, if dialog was dismissed,
                      // then restore the color we had before it was opened.

                      if (!await colorPickerDialog(
                        primaryPickerColor!,
                        (Color newColor) {
                          primaryPickerColor = newColor;
                          updateTheme();
                        },
                      )) {
                        primaryPickerColor = colorBeforeDialog;
                        await updateTheme();
                      }
                    },
                    trailingIcon: ColorIndicator(
                      width: 44,
                      height: 44,
                      hasBorder: true,
                      borderRadius: 4,
                      borderColor: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                          .withValues(alpha: 0.6),
                      color: primaryPickerColor!,
                    ),
                  ),
                if (theme.name == 'Custom' && !useDynamicColor)
                  SettingsButton(
                    name: context.loc.settings.theme.secondaryColor,
                    subtitle: Text(
                      '${ColorTools.materialNameAndCode(accentPickerColor!)} '
                      'aka ${ColorTools.nameThatColor(accentPickerColor!)}',
                    ),
                    action: () async {
                      // Store current color before we open the dialog.
                      final Color colorBeforeDialog = accentPickerColor!;
                      // Wait for the picker to close, if dialog was dismissed,
                      // then restore the color we had before it was opened.

                      if (!await colorPickerDialog(
                        accentPickerColor!,
                        (Color newColor) {
                          accentPickerColor = newColor;
                          updateTheme();
                        },
                      )) {
                        accentPickerColor = colorBeforeDialog;
                        await updateTheme();
                      }
                    },
                    trailingIcon: ColorIndicator(
                      width: 44,
                      height: 44,
                      hasBorder: true,
                      borderRadius: 4,
                      borderColor: (Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white)
                          .withValues(alpha: 0.6),
                      color: accentPickerColor!,
                    ),
                  ),
                if (theme.name == 'Custom' && !useDynamicColor)
                  SettingsButton(
                    name: context.loc.reset,
                    icon: const Icon(Icons.refresh),
                    action: () {
                      final defaultTheme = getDefaultTheme();
                      primaryPickerColor = defaultTheme.primary;
                      accentPickerColor = defaultTheme.accent;
                      updateTheme();
                    },
                  ),
                const SettingsButton(name: '', enabled: false),
                SettingsButton(
                  name: context.loc.settings.theme.fontFamily,
                  subtitle: Text(
                    fontFamily == 'System' ? context.loc.settings.theme.systemDefault : fontFamily,
                    style: _getFontStyle(fontFamily),
                  ),
                  icon: const Icon(Icons.font_download),
                  trailingIcon: fontFamily == 'System'
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                fontFamily = 'System';
                                updateTheme();
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                  action: _showFontPicker,
                ),
                const SettingsButton(name: '', enabled: false),
                SettingsToggle(
                  value: enableMascot,
                  onChanged: (bool newValue) {
                    enableMascot = newValue;
                    updateTheme();
                  },
                  title: context.loc.settings.theme.enableDrawerMascot,
                ),
                SettingsButton(
                  name: context.loc.settings.theme.setCustomMascot,
                  subtitle: mascotPathOverride.isEmpty
                      ? null
                      : Text('${context.loc.settings.theme.currentMascotPath}: $mascotPathOverride'),
                  icon: const Icon(Icons.image_search_outlined),
                  action: () async {
                    mascotPathOverride = await ServiceHandler.getImageSAFUri();
                    needToWriteMascot = true;
                    setState(() {});
                  },
                ),
                if (mascotPathOverride.isNotEmpty)
                  SettingsButton(
                    name: context.loc.settings.theme.removeCustomMascot,
                    icon: const Icon(Icons.delete_forever),
                    action: () async {
                      final File file = File(mascotPathOverride);
                      if (await file.exists()) {
                        await file.delete();
                      }
                      mascotPathOverride = '';
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
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

  // Extended list of popular Google Fonts
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
    // Auto-expand if current font is from extended list or is a custom font
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

    // First check if it's in the default fonts
    final defaultStyle = widget.getFontStyle(font);
    if (defaultStyle != null) return defaultStyle;

    // Extended fonts
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
              // +1 for "View more fonts" (when collapsed) or "Custom font" (when expanded)
              itemCount: fontsToShow.length + 1,
              itemBuilder: (context, index) {
                // "View more fonts" button (when collapsed)
                if (!showAllFonts && index == fontsToShow.length) {
                  return ListTile(
                    leading: const Icon(Icons.expand_more),
                    title: Text(context.loc.settings.theme.viewMoreFonts),
                    onTap: () => setState(() => showAllFonts = true),
                  );
                }

                // "Custom font" option (when expanded, at the end)
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
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
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
                    style: fontStyle?.copyWith(
                      fontSize: 14,
                    ),
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
  const _CustomFontDialog({
    required this.controller,
  });

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
