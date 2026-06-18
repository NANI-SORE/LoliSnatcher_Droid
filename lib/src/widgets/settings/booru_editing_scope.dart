import 'package:flutter/widgets.dart';

/// InheritedWidget that provides the per-booru editing context.
///
/// Wrap a booru settings page in this so that setting widgets know which
/// booru's overrides are being edited. This avoids global mutable state on
/// the registry singleton, preventing bugs when multiple settings routes
/// are on the navigation stack.
///
/// Usage:
/// ```dart
/// BooruEditingScope(
///   booruName: booru.name,
///   child: Scaffold(...),
/// )
/// ```
///
/// Reading the scope:
/// ```dart
/// final editingBooru = BooruEditingScope.of(context);
/// if (editingBooru != null) { /* editing per-booru overrides */ }
/// ```
class BooruEditingScope extends InheritedWidget {
  const BooruEditingScope({
    required this.booruName,
    required super.child,
    this.autosave = true,
    super.key,
  });

  /// The name of the booru whose overrides are being edited.
  final String booruName;

  /// Whether changes in this scope should be saved immediately.
  final bool autosave;

  /// Returns the booru name being edited, or null if not inside a scope.
  static String? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BooruEditingScope>()?.booruName;
  }

  static bool autosaveOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BooruEditingScope>()?.autosave ?? true;
  }

  @override
  bool updateShouldNotify(BooruEditingScope oldWidget) {
    return booruName != oldWidget.booruName || autosave != oldWidget.autosave;
  }
}
