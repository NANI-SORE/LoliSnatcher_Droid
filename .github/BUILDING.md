# Building LoliSnatcher from Source

This guide covers how to build LoliSnatcher locally for development and testing.

## Prerequisites

### Flutter SDK

See `pubspec.yaml` for currently used Flutter SDK version

1. Install Flutter following the [official guide](https://docs.flutter.dev/get-started/install)
2. Verify installation:
   ```bash
   flutter --version
   flutter doctor
   ```

### Dart SDK

See `pubspec.yaml` for currently used Dart SDK version

## Clone and Setup

```bash
# Clone the repository
git clone https://github.com/NO-ob/LoliSnatcher_Droid.git
cd LoliSnatcher_Droid

# Install dependencies
flutter pub get
```

## Build Commands

### Android

```bash
# Build APK for manual install
sh ./build.sh
```

Output locations:
- APK: `build/app/outputs/flutter-apk/LoliSnatcher_[version]_[build]_[arch]_[store/github/test].apk`

## Running in Debug Mode

```bash
# Run app on connected device/emulator
flutter run

# Run on specific device
flutter devices              # List available devices
flutter run -d <device_id>   # Run on specific device
```

## Code Generation

Some features (i.e. localization changes) require code generation. Run after modifying relevant files:

```bash
# Generate Dart localizations and the native iOS string catalog
dart run ./loc_build.dart

# Regenerate automatically while editing translation JSON
dart run ./loc_build.dart --watch

# Generate only native iOS resources, or check them without writing (CI)
dart run ./loc_build.dart --ios-only
dart run ./loc_build.dart --check-ios

# General build runner (if needed)
dart run build_runner build
```

Native iOS permission text lives in the `ios(ignoreUnused)` section of `assets/i18n/*.json`, using exact Info.plist keys such as `NSFaceIDUsageDescription`. Add translations there, including new locales, rather than editing native resource files. Missing keys fall back to English. Use plain text without Slang parameters, links or plural objects; the system displays these strings outside Flutter. The `ignoreUnused` modifier keeps Slang's unused-key analysis from treating native-only text as unused. Slang's `(OUTDATED)` markers become “needs review” entries in the native catalog, and `@` translator comments are ignored. Locale filenames determine native language tags (`ru-RU.json` becomes `ru-RU`).

`loc_build.dart` generates `ios/Runner/InfoPlist.xcstrings`. Xcode 15 or later compiles this catalog into native localized resources. The shared Runner scheme regenerates it before build planning, using Xcode's configured Flutter SDK. This covers normal Xcode and Flutter iOS builds and lets Xcode plan new language resources immediately. A target script checks freshness and fails the build if generation was skipped or failed. Builds that bypass the scheme must run `--ios-only` first. These hooks skip Dart/Slang generation. Unchanged output is left untouched. Full Dart generation uses the same Dart executable that launched the script. Run `flutter pub get` before generating on a fresh checkout. Commit the generated catalog and Dart files with translation changes.

Keep the permission keys declared in `ios/Runner/Info.plist`; the catalog supplies their localized values. Native permission prompts use the device/app language selected by iOS, independently of the language selected inside Flutter.

## IDE Setup

### VS Code

1. Install [Flutter](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter) and [Dart](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code) extensions
2. Open the project folder
3. VS Code will detect Flutter project automatically
4. Use `F5` to run/debug

## Additional Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Documentation](https://dart.dev/guides)
- [Our Discord](https://discord.gg/yD47ANdEXW) for help
