class BackupFileNaming {
  const BackupFileNaming._();

  static const currentAppSlug = 'lolisnatcher';
  static const supportedAppSlugs = {
    currentAppSlug,
    'boorusnatcher',
  };
  static const extension = 'lsbackup';

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
    return '$currentAppSlug-update-$versionName+$buildNumber-${_timestamp(time)}';
  }

  static bool isUpdateAutoBackupPath(String path) {
    final lowerPath = path.toLowerCase();
    return supportedAppSlugs.any((slug) => lowerPath.contains('$slug-update-')) && lowerPath.endsWith('.$extension');
  }

  static String get transferPackageFileName => '$currentAppSlug-transfer.$extension';

  static String _timestamp(DateTime time) {
    return time.toIso8601String().replaceAll(':', '-');
  }
}
