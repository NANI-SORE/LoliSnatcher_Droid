import 'package:flutter/widgets.dart';

import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/utils/tools.dart';

/// Owns the editable values and connection-test state for a booru form.
class BooruEditFormController {
  BooruEditFormController(Booru initialBooru, {required bool trustInitialConnection}) {
    name.text = initialBooru.name ?? '';
    url.text = initialBooru.baseURL ?? '';
    favicon.text = initialBooru.faviconURL ?? '';
    apiKey.text = initialBooru.apiKey ?? '';
    userId.text = initialBooru.userID ?? '';
    defaultTags.text = initialBooru.defTags ?? '';
    selectedType = BooruType.values.contains(initialBooru.type) ? initialBooru.type! : selectedType;
    if (trustInitialConnection && !selectedType.isAutodetect && url.text.trim().isNotEmpty) {
      markTestSuccessful(selectedType);
    }
  }

  final name = TextEditingController();
  final url = TextEditingController();
  final favicon = TextEditingController();
  final apiKey = TextEditingController();
  final userId = TextEditingController();
  final defaultTags = TextEditingController();

  BooruType selectedType = BooruType.Autodetect;
  BooruType? testedType;
  String? _successfulTestSignature;

  String testSignature({String? urlOverride, BooruType? typeOverride}) {
    return [
      (urlOverride ?? url.text).trim(),
      (typeOverride ?? selectedType).name,
      apiKey.text.trim(),
      userId.text.trim(),
    ].join('|');
  }

  void invalidateTestResult() {
    if (_successfulTestSignature == null || _successfulTestSignature == testSignature()) {
      return;
    }
    clearTestResult();
  }

  void markTestSuccessful(BooruType type) {
    testedType = type;
    selectedType = type;
    _successfulTestSignature = testSignature(typeOverride: type);
  }

  bool markTestSuccessfulIfCurrent(BooruType type, String testedSignature) {
    if (testSignature() != testedSignature) {
      clearTestResult();
      return false;
    }
    markTestSuccessful(type);
    return true;
  }

  void clearTestResult() {
    testedType = null;
    _successfulTestSignature = null;
  }

  bool get hasCurrentSuccessfulTest => testedType != null && _successfulTestSignature == testSignature();

  void sanitizeName() {
    name.text = Tools.sanitize(name.text).trim();
  }

  Booru toBooru({BooruType? type, String? tags}) {
    return Booru.withKey(
      name.text,
      type ?? selectedType,
      favicon.text,
      url.text,
      tags ?? defaultTags.text,
      apiKey.text.isEmpty ? null : apiKey.text,
      userId.text.isEmpty ? null : userId.text,
    );
  }

  void dispose() {
    name.dispose();
    url.dispose();
    favicon.dispose();
    apiKey.dispose();
    userId.dispose();
    defaultTags.dispose();
  }
}
