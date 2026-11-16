import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lolisnatcher/src/services/backup_transfer/secure_transfer_connection.dart';

void main() {
  Future<(TransferRecordCipher, TransferRecordCipher)> pair() async {
    final secret = SecretKey(List.generate(32, (i) => i));
    final hash = List.generate(32, (i) => 31 - i);
    return (
      await TransferRecordCipher.derive(sharedSecret: secret, transcriptHash: hash, sender: true),
      await TransferRecordCipher.derive(sharedSecret: secret, transcriptHash: hash, sender: false),
    );
  }

  test('directional authenticated records reject reflection, tampering and replay', () async {
    final (sender, receiver) = await pair();
    try {
      final wire = await sender.seal([1, 2, 3], kind: 0);
      await expectLater(sender.open(wire, kind: 0), throwsA(isA<SecretBoxAuthenticationError>()));
      final tampered = Uint8List.fromList(wire)..[10] ^= 1;
      await expectLater(receiver.open(tampered, kind: 0), throwsA(isA<SecretBoxAuthenticationError>()));
      expect(await receiver.open(wire, kind: 0), [1, 2, 3]);
      await expectLater(receiver.open(wire, kind: 0), throwsFormatException);
      expect(await sender.open(await receiver.seal([4], kind: 1), kind: 1), [4]);
    } finally {
      sender.dispose();
      receiver.dispose();
    }
  });

  test('record size, kind and sequence boundaries reject invalid input', () async {
    final (sender, receiver) = await pair();
    try {
      await expectLater(sender.seal([], kind: 0), throwsFormatException);
      await expectLater(
        sender.seal(List.filled(TransferRecordCipher.maximumPlaintext + 1, 0), kind: 1),
        throwsFormatException,
      );
      final first = await sender.seal([1], kind: 1);
      final second = await sender.seal([2], kind: 1);
      await expectLater(receiver.open(second, kind: 1), throwsFormatException);
      await expectLater(receiver.open(first, kind: 0), throwsFormatException);
      expect(await receiver.open(first, kind: 1), [1]);
      expect(await receiver.open(second, kind: 1), [2]);
    } finally {
      sender.dispose();
      receiver.dispose();
    }
  });

  test('loopback peers complete protocol 5 commitment and derive identical verification phrase', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = server.first;
    final client = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final socket = await accepted;
    final sender = SecureTransferConnection(socket);
    final receiver = SecureTransferConnection(client);
    try {
      await Future.wait([sender.establishAsSender(), receiver.establishAsReceiver()])
          .timeout(const Duration(seconds: 10));
      expect(SecureTransferConnection.protocolVersion, 5);
      expect(sender.verificationPhrase, receiver.verificationPhrase);
      expect(sender.verificationPhrase, isNotEmpty);
    } finally {
      socket.destroy();
      client.destroy();
      await server.close();
    }
  });
}
