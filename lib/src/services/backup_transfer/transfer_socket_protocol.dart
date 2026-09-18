import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_transfer_logger.dart';

abstract final class TransferProtocol {
  static const version = 1;
  static const capabilities = ['sha256', 'requestId', 'importAck'];
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

class TransferSocketConnection {
  TransferSocketConnection(this.socket) : _reader = _SocketChunkReader(socket);

  final Socket socket;
  final _SocketChunkReader _reader;

  Future<void> writeFrame(Map<String, dynamic> frame) async {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(frame)));
    if (payload.isEmpty || payload.length > TransferProtocol.maxFrameBytes) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
    final header = ByteData(4)..setUint32(0, payload.length, Endian.big);
    BackupTransferLogger.info(
      'Writing frame type=${frame['type']} bytes=${payload.length}',
      'TransferSocketConnection',
      'writeFrame',
    );
    socket.add(header.buffer.asUint8List());
    socket.add(payload);
    await socket.flush().timeout(TransferProtocol.idleTimeout);
  }

  Future<Map<String, dynamic>> readFrame({Duration timeout = TransferProtocol.idleTimeout}) async {
    final header = await _reader.readExactly(4, timeout: timeout);
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (length == 0 || length > TransferProtocol.maxFrameBytes) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
    final payload = await _reader.readExactly(length);
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
    final frame = decoded;
    BackupTransferLogger.info(
      'Read frame type=${frame['type']} bytes=$length',
      'TransferSocketConnection',
      'readFrame',
    );
    return frame;
  }

  Future<Uint8List> readBytes(int length, void Function(int read)? onProgress) async {
    if (length < 0 || length > TransferProtocol.maxFrameBytes) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
    final builder = BytesBuilder(copy: false);
    var remaining = length;
    var read = 0;
    final progress = _ProgressThrottle(onProgress);
    while (remaining > 0) {
      final chunk = await _reader.readExactly(remaining > 64 * 1024 ? 64 * 1024 : remaining);
      builder.add(chunk);
      remaining -= chunk.length;
      read += chunk.length;
      progress.call(read);
    }
    progress.complete(read);
    return builder.takeBytes();
  }

  Future<void> readBytesToFile(
    int length,
    File file,
    void Function(int read)? onProgress, {
    bool Function()? isCancelled,
  }) async {
    TransferProtocol.validateSize(length);
    BackupTransferLogger.info(
      'Reading $length bytes to file ${file.path}',
      'TransferSocketConnection',
      'readBytesToFile',
    );
    final sink = file.openWrite();
    var remaining = length;
    var read = 0;
    final progress = _ProgressThrottle(onProgress);
    try {
      while (remaining > 0) {
        if (isCancelled?.call() == true) {
          throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
        }
        final chunk = await _reader.readExactly(remaining > 64 * 1024 ? 64 * 1024 : remaining);
        if (isCancelled?.call() == true) {
          throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
        }
        sink.add(chunk);
        // Bound the disk writer's queue as well as the socket reader's queue.
        await sink.flush().timeout(TransferProtocol.idleTimeout);
        remaining -= chunk.length;
        read += chunk.length;
        progress.call(read);
      }
      progress.complete(read);
      BackupTransferLogger.info(
        'Finished reading $read bytes to file ${file.path}',
        'TransferSocketConnection',
        'readBytesToFile',
      );
    } finally {
      await sink.close();
    }
  }

  Future<void> writeBytes(Uint8List bytes, void Function(int sent)? onProgress) async {
    var sent = 0;
    const chunkSize = 64 * 1024;
    final progress = _ProgressThrottle(onProgress);
    while (sent < bytes.length) {
      final end = sent + chunkSize > bytes.length ? bytes.length : sent + chunkSize;
      socket.add(bytes.sublist(sent, end));
      sent = end;
      progress.call(sent);
      await socket.flush().timeout(TransferProtocol.idleTimeout);
    }
    progress.complete(sent);
  }

  Future<void> writeFile(
    File file,
    void Function(int sent)? onProgress, {
    bool Function()? isCancelled,
  }) async {
    BackupTransferLogger.info(
      'Writing file ${file.path}',
      'TransferSocketConnection',
      'writeFile',
    );
    final progress = _ProgressThrottle(onProgress);
    var sent = 0;
    final stream = file.openRead();
    await for (final chunk in stream) {
      if (isCancelled?.call() == true) {
        throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
      }
      socket.add(chunk);
      sent += chunk.length;
      progress.call(sent);
      await socket.flush().timeout(TransferProtocol.idleTimeout);
      if (isCancelled?.call() == true) {
        throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
      }
    }
    progress.complete(sent);
    BackupTransferLogger.info(
      'Finished writing file ${file.path} bytes=$sent',
      'TransferSocketConnection',
      'writeFile',
    );
  }

  Future<void> close() async {
    socket.destroy();
    await _reader.close();
  }
}

class _ProgressThrottle {
  _ProgressThrottle(this.onProgress);

  final void Function(int value)? onProgress;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastValue = 0;

  void call(int value) {
    if (onProgress == null) return;
    final now = DateTime.now();
    final enoughBytes = value - _lastValue >= 1024 * 1024;
    final enoughTime = now.difference(_lastEmit).inMilliseconds >= 250;
    if (!enoughBytes && !enoughTime) return;
    _lastEmit = now;
    _lastValue = value;
    onProgress!(value);
  }

  void complete(int value) {
    if (onProgress == null || value == _lastValue) return;
    _lastValue = value;
    _lastEmit = DateTime.now();
    onProgress!(value);
  }
}

class _SocketChunkReader {
  _SocketChunkReader(this.socket);

  static const _pauseAtBytes = 4 * 1024 * 1024;
  static const _resumeAtBytes = 1024 * 1024;

  final Socket socket;
  final _chunks = ListQueue<Uint8List>();
  // The subscription is intentionally kept for the lifetime of this socket reader.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _available;
  int _bufferedBytes = 0;
  int _chunkOffset = 0;
  bool _done = false;
  bool _paused = false;
  Object? _error;

  Future<Uint8List> readExactly(int length, {Duration timeout = TransferProtocol.idleTimeout}) async {
    if (length < 0 || length > TransferProtocol.maxFrameBytes) {
      throw FormatException(loc.settings.backupAndTransfer.invalidTransferData);
    }
    _subscription ??= socket.listen(
      (chunk) {
        _chunks.add(chunk);
        _bufferedBytes += chunk.length;
        if (!_paused && _bufferedBytes >= _pauseAtBytes) {
          _subscription?.pause();
          _paused = true;
        }
        if (_available?.isCompleted == false) _available!.complete();
        _available = null;
      },
      onDone: () {
        _done = true;
        if (_available?.isCompleted == false) _available!.complete();
      },
      onError: (Object error) {
        _error = error;
        if (_available?.isCompleted == false) _available!.complete();
      },
      cancelOnError: true,
    );

    while (_bufferedBytes < length && !_done && _error == null) {
      _available ??= Completer<void>();
      await _available!.future.timeout(timeout);
    }
    if (_error != null) throw Exception(_error);
    if (_bufferedBytes < length) {
      throw SocketException(loc.settings.backupAndTransfer.transferCancelled);
    }

    final result = Uint8List(length);
    var written = 0;
    while (written < length) {
      final chunk = _chunks.first;
      final available = chunk.length - _chunkOffset;
      final toCopy = length - written < available ? length - written : available;
      result.setRange(written, written + toCopy, chunk, _chunkOffset);
      written += toCopy;
      _chunkOffset += toCopy;
      _bufferedBytes -= toCopy;
      if (_chunkOffset >= chunk.length) {
        _chunks.removeFirst();
        _chunkOffset = 0;
      }
    }
    _resumeIfNeeded();
    return result;
  }

  Future<void> close() async {
    _done = true;
    if (_available?.isCompleted == false) _available!.complete();
    await _subscription?.cancel();
    _chunks.clear();
    _bufferedBytes = 0;
  }

  void _resumeIfNeeded() {
    if (!_paused || _bufferedBytes > _resumeAtBytes) return;
    _paused = false;
    _subscription?.resume();
  }
}
