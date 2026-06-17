import 'package:lolisnatcher/src/utils/logger.dart';

class BackupTransferLogger {
  const BackupTransferLogger._();

  static void info(String message, String callerClass, String callerFunction) {
    Logger.Inst().log(message, callerClass, callerFunction, LogTypes.backupTransferInfo);
  }

  static void error(
    Object error,
    String callerClass,
    String callerFunction, {
    StackTrace? stackTrace,
  }) {
    Logger.Inst().log(error, callerClass, callerFunction, LogTypes.exception, s: stackTrace);
  }
}
