import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// Keep the channel usable from the isolated pure-Dart security test package.
// ignore: always_use_package_imports
import 'transfer_verification_phrase.dart';

class TransferRecordCipher {
  TransferRecordCipher._(this._sendKey, this._receiveKey);

  static const maximumPlaintext = 64 * 1024;
  static const maximumWireBytes = maximumPlaintext + 25;
  static const _maximumSequence = 0xffffffff;
  static final _algorithm = AesGcm.with256bits();
  final SecretKey _sendKey;
  final SecretKey _receiveKey;
  int _sendSequence = 0;
  int _receiveSequence = 0;

  static Future<TransferRecordCipher> derive({
    required SecretKey sharedSecret,
    required List<int> transcriptHash,
    required bool sender,
  }) async {
    if (transcriptHash.length != 32) {
      throw const FormatException('Invalid secure transfer transcript');
    }
    final kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final salt = transcriptHash;
    final sending = await kdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(
        'LoliSnatcher transfer ${SecureTransferConnection.protocolVersion} server-to-client AES-256-GCM',
      ),
    );
    try {
      final receiving = await kdf.deriveKey(
        secretKey: sharedSecret,
        nonce: salt,
        info: utf8.encode(
          'LoliSnatcher transfer ${SecureTransferConnection.protocolVersion} client-to-server AES-256-GCM',
        ),
      );
      return TransferRecordCipher._(sender ? sending : receiving, sender ? receiving : sending);
    } catch (_) {
      sending.destroy();
      rethrow;
    }
  }

  Future<Uint8List> seal(List<int> bytes, {required int kind}) async {
    if (bytes.isEmpty || bytes.length > maximumPlaintext || kind < 0 || kind > 1) {
      throw const FormatException('Invalid secure transfer record');
    }
    if (_sendSequence > _maximumSequence) throw StateError('Secure transfer counter exhausted');
    // Reserve before the first await; a nonce must never be reused.
    final sequence = _sendSequence++;
    final header = ByteData(9)
      ..setUint8(0, kind)
      ..setUint64(1, sequence, Endian.big);
    final nonce = ByteData(12)..setUint64(4, sequence, Endian.big);
    final box = await _algorithm.encrypt(
      bytes,
      secretKey: _sendKey,
      nonce: nonce.buffer.asUint8List(),
      aad: header.buffer.asUint8List(),
    );
    return Uint8List.fromList([...header.buffer.asUint8List(), ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> open(Uint8List bytes, {required int kind}) async {
    if (bytes.length < 26 || bytes.length > maximumWireBytes) {
      throw const FormatException('Invalid encrypted record length');
    }
    final header = ByteData.sublistView(bytes, 0, 9);
    final sequence = header.getUint64(1, Endian.big);
    if (_receiveSequence > _maximumSequence || header.getUint8(0) != kind || sequence != _receiveSequence) {
      throw const FormatException('Unexpected secure transfer record');
    }
    final nonce = ByteData(12)..setUint64(4, sequence, Endian.big);
    final clear = await _algorithm.decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, 9, bytes.length - 16),
        nonce: nonce.buffer.asUint8List(),
        mac: Mac(Uint8List.sublistView(bytes, bytes.length - 16)),
      ),
      secretKey: _receiveKey,
      aad: Uint8List.sublistView(bytes, 0, 9),
    );
    _receiveSequence++;
    return Uint8List.fromList(clear);
  }

  void dispose() {
    _sendKey.destroy();
    _receiveKey.destroy();
  }
}

class SecureTransferConnection {
  SecureTransferConnection(this.socket) : _reader = _SecureSocketReader(socket);

  static const protocolVersion = 5;
  static const _suite = 'X25519-SHA256-HKDF-AES256GCM';
  static const idleTimeout = Duration(seconds: 30);
  static const maximumPackageBytes = 8 * 1024 * 1024 * 1024;
  final Socket socket;
  final _SecureSocketReader _reader;
  TransferRecordCipher? _cipher;
  Future<void> _writes = Future.value();
  Future<void> _reads = Future.value();
  Future<void>? _closing;
  bool _authenticationStarted = false;
  bool _channelReady = false;
  String? _verificationPhrase;

  String get verificationPhrase {
    _checkReady();
    return _verificationPhrase!;
  }

  Future<void> get disconnected => _reader.disconnected;

  static List<int> _context(String purpose) =>
      utf8.encode('LoliSnatcher transfer $protocolVersion $_suite $purpose\u0000');

  static List<int> _nonce() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256));
  }

  static List<int> _decode(String field, Map<String, dynamic> frame) {
    final encoded = frame[field];
    if (encoded is! String) throw const FormatException('Invalid secure transfer handshake');
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) throw const FormatException('Invalid secure transfer handshake');
    return bytes;
  }

  static Future<List<int>> _commitment(String role, List<int> key, List<int> nonce) async =>
      (await Sha256().hash([..._context('commitment $role'), ...key, ...nonce])).bytes;

  Future<void> establishAsSender() => _establish(sender: true);
  Future<void> establishAsReceiver() => _establish(sender: false);

  Future<void> _establish({required bool sender}) => _guard(() async {
    if (_authenticationStarted) throw StateError('Secure transfer handshake already started');
    _authenticationStarted = true;
    final exchange = X25519();
    final keyPair = await exchange.newKeyPair();
    SecretKey? shared;
    SecretKey? verification;
    try {
      final role = sender ? 'server' : 'client';
      final remoteRole = sender ? 'client' : 'server';
      final publicKey = (await keyPair.extractPublicKey()).bytes;
      final nonce = _nonce();
      final commitment = await _commitment(role, publicKey, nonce);
      late final List<int> remoteCommitment;
      if (sender) {
        await _writeHandshake('secureCommit', role, {'commitment': base64Encode(commitment)});
        remoteCommitment = _decode('commitment', await _readHandshake('secureCommit', remoteRole));
      } else {
        remoteCommitment = _decode('commitment', await _readHandshake('secureCommit', remoteRole));
        await _writeHandshake('secureCommit', role, {'commitment': base64Encode(commitment)});
      }

      Future<void> reveal() => _writeHandshake('secureReveal', role, {
        'key': base64Encode(publicKey),
        'nonce': base64Encode(nonce),
      });
      if (sender) await reveal();
      final remote = await _readHandshake('secureReveal', remoteRole);
      final remoteKey = _decode('key', remote);
      final remoteNonce = _decode('nonce', remote);
      if (Mac(remoteCommitment) != Mac(await _commitment(remoteRole, remoteKey, remoteNonce))) {
        throw const FormatException('Transfer key commitment did not match');
      }
      if (!sender) await reveal();

      final serverFields = sender
          ? [...commitment, ...publicKey, ...nonce]
          : [...remoteCommitment, ...remoteKey, ...remoteNonce];
      final clientFields = sender
          ? [...remoteCommitment, ...remoteKey, ...remoteNonce]
          : [...commitment, ...publicKey, ...nonce];
      final transcript = (await Sha256().hash([
        ..._context('transcript'),
        ...utf8.encode('server\u0000'),
        ...serverFields,
        ...utf8.encode('client\u0000'),
        ...clientFields,
      ])).bytes;
      shared = await exchange.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: SimplePublicKey(remoteKey, type: KeyPairType.x25519),
      );
      final sharedBytes = await shared.extractBytes();
      if (sharedBytes.length != 32 || sharedBytes.fold<int>(0, (result, byte) => result | byte) == 0) {
        throw const FormatException('Invalid transfer shared secret');
      }
      final cipher = await TransferRecordCipher.derive(
        sharedSecret: shared,
        transcriptHash: transcript,
        sender: sender,
      );
      if (_closing != null) {
        cipher.dispose();
        throw const SocketException('Secure transfer closed');
      }
      _cipher = cipher;
      verification = await Hkdf(hmac: Hmac.sha256(), outputLength: 6).deriveKey(
        secretKey: shared,
        nonce: transcript,
        info: _context('verification emojis'),
      );
      final phrase = transferVerificationPhrase(await verification.extractBytes());
      final transcriptText = base64Encode(transcript);
      final confirmation = {'type': 'secureReady', 'role': role, 'transcript': transcriptText};
      Future<void> verifyConfirmation() async {
        final ready = await _readControl(idleTimeout);
        if (ready['type'] != 'secureReady' || ready['role'] != remoteRole || ready['transcript'] != transcriptText) {
          throw const FormatException('Invalid secure transfer confirmation');
        }
      }

      if (sender) {
        await _writeControl(confirmation);
        await verifyConfirmation();
      } else {
        await verifyConfirmation();
        await _writeControl(confirmation);
      }
      if (_closing != null) throw const SocketException('Secure transfer closed');
      // This establishes encryption. Human phrase comparison in the existing
      // sender approval is what authenticates the physical peer for this session.
      _verificationPhrase = phrase;
      _channelReady = true;
    } finally {
      verification?.destroy();
      shared?.destroy();
      keyPair.destroy();
    }
  });

  Future<void> _writeHandshake(String type, String role, Map<String, dynamic> fields) => _writePacket(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'type': type,
          'protocol': protocolVersion,
          'suite': _suite,
          'role': role,
          ...fields,
        }),
      ),
    ),
  );

  Future<Map<String, dynamic>> _readHandshake(String type, String role) async {
    final frame = jsonDecode(utf8.decode(await _readPacket(idleTimeout, maximum: 1024)));
    if (frame is! Map<String, dynamic> ||
        frame['type'] != type ||
        frame['role'] != role ||
        frame['protocol'] != protocolVersion ||
        frame['suite'] != _suite) {
      throw const FormatException('Unsupported secure transfer handshake; update both devices');
    }
    return frame;
  }

  void _checkReady() {
    if (!_channelReady || _cipher == null) throw StateError('Encrypted transfer channel is not ready');
    if (_closing != null) throw const SocketException('Secure transfer closed');
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      if (_closing != null) throw const SocketException('Secure transfer closed');
      return await action();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<T> _queue<T>(Future<T> Function() action, {required bool writing}) {
    final result = (writing ? _writes : _reads).then((_) => _guard(action));
    final tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    if (writing) {
      _writes = tail;
    } else {
      _reads = tail;
    }
    return result;
  }

  Future<void> writeFrame(Map<String, dynamic> frame) => _queue(() async {
    _checkReady();
    await _writeControl(frame);
  }, writing: true);

  Future<void> _writeControl(Map<String, dynamic> frame) async {
    final bytes = utf8.encode(jsonEncode(frame));
    await _writePacket(await _cipher!.seal(bytes, kind: 0));
  }

  Future<Map<String, dynamic>> readFrame({Duration timeout = idleTimeout}) => _queue(() async {
    _checkReady();
    return _readControl(timeout);
  }, writing: false);

  Future<Map<String, dynamic>> _readControl(Duration timeout) async {
    final bytes = await _cipher!.open(await _readPacket(timeout), kind: 0);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid secure transfer control frame');
    return decoded;
  }

  Future<void> _writePacket(Uint8List bytes) async {
    if (_closing != null) throw const SocketException('Secure transfer closed');
    if (bytes.isEmpty || bytes.length > TransferRecordCipher.maximumWireBytes) {
      throw const FormatException('Invalid secure transfer packet size');
    }
    final header = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    socket.add(header.buffer.asUint8List());
    socket.add(bytes);
    await socket.flush().timeout(idleTimeout);
  }

  Future<Uint8List> _readPacket(Duration timeout, {int maximum = TransferRecordCipher.maximumWireBytes}) async {
    final header = await _reader.readExactly(4, timeout: timeout);
    final size = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (size < 1 || size > maximum) throw const FormatException('Invalid secure transfer packet size');
    return _reader.readExactly(size);
  }

  Future<void> writeFile(File file, void Function(int)? onProgress, {bool Function()? isCancelled}) => _queue(() async {
    _checkReady();
    var sent = 0;
    final progress = _TransferProgress(onProgress);
    await for (final bytes in file.openRead()) {
      for (var offset = 0; offset < bytes.length; offset += TransferRecordCipher.maximumPlaintext) {
        if (isCancelled?.call() == true) throw const SocketException('Transfer cancelled');
        final end = min(bytes.length, offset + TransferRecordCipher.maximumPlaintext);
        final chunk = bytes is Uint8List ? Uint8List.sublistView(bytes, offset, end) : bytes.sublist(offset, end);
        await _writePacket(await _cipher!.seal(chunk, kind: 1));
        sent += end - offset;
        progress.update(sent);
      }
    }
    progress.update(sent, complete: true);
  }, writing: true);

  Future<void> readBytesToFile(int length, File file, void Function(int)? onProgress, {bool Function()? isCancelled}) =>
      _queue(() async {
        _checkReady();
        if (length < 1 || length > maximumPackageBytes) {
          throw const FormatException('Invalid secure transfer file size');
        }
        final output = await file.open(mode: FileMode.write);
        var read = 0;
        final progress = _TransferProgress(onProgress);
        try {
          while (read < length) {
            if (isCancelled?.call() == true) throw const SocketException('Transfer cancelled');
            final bytes = await _cipher!.open(await _readPacket(idleTimeout), kind: 1);
            if (bytes.length > length - read) throw const FormatException('Secure transfer file exceeds declared size');
            await output.writeFrom(bytes);
            read += bytes.length;
            progress.update(read);
          }
          await output.flush();
          progress.update(read, complete: true);
        } finally {
          await output.close();
        }
      }, writing: false);

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    socket.destroy();
    _channelReady = false;
    _verificationPhrase = null;
    _cipher?.dispose();
    await _reader.close();
  }
}

class _TransferProgress {
  _TransferProgress(this.callback);
  final void Function(int)? callback;
  final Stopwatch _elapsed = Stopwatch()..start();
  int _lastBytes = 0;

  void update(int bytes, {bool complete = false}) {
    if (complete || _elapsed.elapsedMilliseconds >= 250 || bytes - _lastBytes >= 1024 * 1024) {
      callback?.call(bytes);
      _lastBytes = bytes;
      _elapsed.reset();
    }
  }
}

class _SecureSocketReader {
  _SecureSocketReader(this.socket);
  final Socket socket;
  final _chunks = ListQueue<Uint8List>();
  // Owned by this connection; close cancels the subscription.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _available;
  int _buffered = 0;
  int _offset = 0;
  bool _done = false;
  bool _paused = false;
  Object? _error;
  final _disconnected = Completer<void>();
  Future<void> get disconnected => _disconnected.future;

  Future<Uint8List> readExactly(int length, {Duration timeout = SecureTransferConnection.idleTimeout}) async {
    if (length < 0 || length > TransferRecordCipher.maximumWireBytes) {
      throw const FormatException('Invalid packet length');
    }
    _subscription ??= socket.listen(
      (chunk) {
        _chunks.add(chunk);
        _buffered += chunk.length;
        if (!_paused && _buffered >= 4 * 1024 * 1024) {
          _subscription?.pause();
          _paused = true;
        }
        if (_available?.isCompleted == false) _available!.complete();
        _available = null;
      },
      onDone: () {
        _done = true;
        if (!_disconnected.isCompleted) _disconnected.complete();
        if (_available?.isCompleted == false) _available!.complete();
      },
      onError: (Object error) {
        _error = error;
        if (!_disconnected.isCompleted) _disconnected.complete();
        if (_available?.isCompleted == false) _available!.complete();
      },
      cancelOnError: true,
    );
    final deadline = DateTime.now().add(timeout);
    while (_buffered < length && !_done && _error == null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException('Secure transfer timed out');
      _available ??= Completer<void>();
      await _available!.future.timeout(remaining);
    }
    if (_error != null) throw SocketException('Secure transfer socket failed: ${_error.runtimeType}');
    if (_buffered < length) throw const SocketException('Secure transfer connection closed');
    final result = Uint8List(length);
    var written = 0;
    while (written < length) {
      final chunk = _chunks.first;
      final count = min(length - written, chunk.length - _offset);
      result.setRange(written, written + count, chunk, _offset);
      written += count;
      _offset += count;
      _buffered -= count;
      if (_offset == chunk.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    if (_paused && _buffered <= 1024 * 1024) {
      _paused = false;
      _subscription?.resume();
    }
    return result;
  }

  Future<void> close() async {
    _done = true;
    if (!_disconnected.isCompleted) _disconnected.complete();
    if (_available?.isCompleted == false) _available!.complete();
    await _subscription?.cancel();
    _chunks.clear();
    _buffered = 0;
  }
}
