import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/theme_item.dart';
import 'package:lolisnatcher/src/handlers/theme_handler.dart';

class ThemeBuilder extends StatelessWidget {
  const ThemeBuilder({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DebouncedListenableBuilder(
      immediateListenables: [
        SX.theme.state.effectiveNotifier,
        SX.themeMode.state.effectiveNotifier,
        SX.isAmoled.state.effectiveNotifier,
        SX.useDynamicColor.state.effectiveNotifier,
        SX.fontFamily.state.effectiveNotifier,
      ],
      debouncedListenables: [
        SX.customPrimaryColor.state.effectiveNotifier,
        SX.customAccentColor.state.effectiveNotifier,
      ],
      builder: (context, _) {
        final ThemeItem theme = SX.theme.value.name == 'Custom'
            ? ThemeItem(
                name: 'Custom',
                primary: SX.customPrimaryColor.value,
                accent: SX.customAccentColor.value,
              )
            : SX.theme.value;

        final ThemeHandler themeHandler = ThemeHandler(
          theme: theme,
          themeMode: SX.themeMode.value,
          isAmoled: SX.isAmoled.value,
          fontFamily: SX.fontFamily.value,
          context: context,
        );

        return Theme(
          data: themeHandler.isDark ? themeHandler.darkTheme() : themeHandler.lightTheme(),
          child: child,
        );
      },
    );
  }
}

class DebouncedListenableBuilder extends StatefulWidget {
  const DebouncedListenableBuilder({
    required this.immediateListenables,
    required this.debouncedListenables,
    required this.builder,
    this.duration = const Duration(milliseconds: 120),
    super.key,
  });

  final List<Listenable> immediateListenables;
  final List<Listenable> debouncedListenables;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Duration duration;

  @override
  State<DebouncedListenableBuilder> createState() => _DebouncedListenableBuilderState();
}

class _DebouncedListenableBuilderState extends State<DebouncedListenableBuilder> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _addListeners();
  }

  @override
  void didUpdateWidget(DebouncedListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _removeListeners(oldWidget);
    _addListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeListeners(widget);
    super.dispose();
  }

  void _addListeners() {
    for (final listenable in widget.immediateListenables) {
      listenable.addListener(_notifyImmediately);
    }
    for (final listenable in widget.debouncedListenables) {
      listenable.addListener(_notifyDebounced);
    }
  }

  void _removeListeners(DebouncedListenableBuilder source) {
    for (final listenable in source.immediateListenables) {
      listenable.removeListener(_notifyImmediately);
    }
    for (final listenable in source.debouncedListenables) {
      listenable.removeListener(_notifyDebounced);
    }
  }

  void _notifyImmediately() {
    _debounce?.cancel();
    if (mounted) {
      setState(() {});
    }
  }

  void _notifyDebounced() {
    _debounce?.cancel();
    _debounce = Timer(widget.duration, () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, null);
}
