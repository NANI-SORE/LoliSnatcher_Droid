class BackupFileNaming {
  const BackupFileNaming._();

  static const currentAppSlug = 'lolisnatcher';
  static const supportedAppSlugs = {
    currentAppSlug,
    'boorusnatcher',
  };
  static const extension = 'lsbackup';
  // Keep Android document providers from appending .zip to the custom extension.
  static const mimeType = 'application/octet-stream';

  static bool isPackageFileName(String fileName) {
    final lowerName = fileName.toLowerCase();
    return lowerName.endsWith('.$extension') || lowerName.endsWith('.$extension.zip');
  }

  static String get currentFormatId => '$currentAppSlug-backup';

  static Set<String> get supportedFormatIds => {
    for (final slug in supportedAppSlugs) '$slug-backup',
  };

  static bool isSupportedFormatId(Object? value) {
    return supportedFormatIds.contains(value?.toString());
  }

  static String packageFileName(DateTime time) {
    return '$currentAppSlug-${_timestamp(time)}.$extension';
  }

  static String autoFileStem(DateTime time) {
    return '$currentAppSlug-auto-${_timestamp(time)}';
  }

  static String updateAutoFileStem({
    required DateTime time,
    required String versionName,
    required int buildNumber,
  }) {
    final safeVersion = versionName.replaceAll(RegExp('[^a-zA-Z0-9._+-]'), '_');
    return '$currentAppSlug-update-$safeVersion+$buildNumber-${_timestamp(time)}';
  }

  static bool isNormalAutoBackupPath(String path) => autoBackupTime(path, isUpdate: false) != null;

  static bool isUpdateAutoBackupPath(String path) {
    return autoBackupTime(path, isUpdate: true) != null;
  }

  /// Match only a generated filename, never a parent directory or a manual backup.
  /// The timestamp also gives SAF providers a reliable ordering independent of version strings.
  static DateTime? autoBackupTime(String path, {required bool isUpdate}) {
    final name = path.replaceAll(r'\', '/').split('/').last;
    final slugs = supportedAppSlugs.map(RegExp.escape).join('|');
    final kind = isUpdate ? r'update-[a-zA-Z0-9._+-]+\+\d+' : 'auto';
    final pattern = RegExp(
      '^($slugs)-$kind-(\\d{4}-\\d{2}-\\d{2})T(\\d{2})-(\\d{2})-(\\d{2})(\\.\\d{3}(?:\\d{3})?)?(Z?)\\.$extension(?:\\.zip)?\$',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(name);
    if (match == null) return null;
    final date = '${match[2]}T${match[3]}:${match[4]}:${match[5]}${match[6] ?? ''}${match[7]!.toUpperCase()}';
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return null;
    // DateTime.parse normalizes overflow components; do not claim such filenames.
    final expected = '${match[2]}T${match[3]}-${match[4]}-${match[5]}';
    if (!_timestamp(parsed).startsWith(expected)) return null;
    return parsed;
  }

  static String get transferPackageFileName => '$currentAppSlug-transfer.$extension';

  static String _timestamp(DateTime time) {
    return time.toIso8601String().replaceAll(':', '-');
  }
}
