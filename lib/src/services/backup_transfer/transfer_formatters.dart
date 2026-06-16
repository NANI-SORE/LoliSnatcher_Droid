class TransferFormatters {
  const TransferFormatters._();

  static String bytes(num bytes) {
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return '$seconds';
  }

  static String time(DateTime time) {
    return [
      time.hour.toString().padLeft(2, '0'),
      time.minute.toString().padLeft(2, '0'),
      time.second.toString().padLeft(2, '0'),
    ].join(':');
  }

  static String dateTime(DateTime time) {
    final date = [
      time.day.toString().padLeft(2, '0'),
      time.month.toString().padLeft(2, '0'),
      time.year.toString().padLeft(4, '0'),
    ].join('.');
    return '$date ${TransferFormatters.time(time)}';
  }
}
