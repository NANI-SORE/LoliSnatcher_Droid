abstract final class BackupPayloadLimits {
  static const maximumPackageBytes = 8 * 1024 * 1024 * 1024;
  static const maximumJsonBytes = 64 * 1024 * 1024;
  static const maximumManifestBytes = 1024 * 1024;
  static const maximumRecordBytes = 8 * 1024 * 1024;

  static int maximumEntryBytes(String fileName) => switch (fileName) {
    'manifest.json' => maximumManifestBytes,
    'store.db' || 'favourites.json' || 'snatched.json' => maximumPackageBytes,
    _ => maximumJsonBytes,
  };

  static void validateEntrySize(String fileName, int bytes) {
    if (bytes < 0 || bytes > maximumEntryBytes(fileName)) {
      throw FormatException('Backup entry exceeds its size limit: $fileName');
    }
  }

  static void validateRecordSize(int bytes) {
    if (bytes < 0 || bytes > maximumRecordBytes) {
      throw const FormatException('Backup record exceeds 8 MiB');
    }
  }
}
