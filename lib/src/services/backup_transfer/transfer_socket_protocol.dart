import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/secure_transfer_connection.dart';

abstract final class TransferProtocol {
  static const version = SecureTransferConnection.protocolVersion;
  static const capabilities = ['sha256', 'requestId', 'importAck', 'authenticatedEncryption', 'verificationPhrase'];
  static const maxFrameBytes = 64 * 1024;
  static const maxPackageBytes = 8 * 1024 * 1024 * 1024;
  static const idleTimeout = Duration(seconds: 30);
  static const approvalTimeout = Duration(minutes: 2);
  static const importTimeout = Duration(minutes: 30);

  static void validatePeer(Map<String, dynamic> frame) {
    final supported = frame['capabilities'];
    if (frame['protocol'] is! int ||
        frame['protocol'] != version ||
        supported is! List ||
        !capabilities.every(supported.contains)) {
      throw FormatException(loc.settings.backupAndTransfer.unsupportedTransferProtocol);
    }
  }

  static bool validRequestId(Object? value) => value is String && RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(value);

  static void validateSize(int length) {
    if (length <= 0 || length > maxPackageBytes) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
  }
}

class TransferSocketConnection extends SecureTransferConnection {
  TransferSocketConnection(super.socket);
}
