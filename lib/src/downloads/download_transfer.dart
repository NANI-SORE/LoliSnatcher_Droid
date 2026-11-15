import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:lolisnatcher/src/downloads/contracts.dart';
import 'package:lolisnatcher/src/downloads/download_configuration.dart';
import 'package:lolisnatcher/src/downloads/download_network.dart';
import 'package:lolisnatcher/src/downloads/download_store.dart';

class DownloadTransfer {
  DownloadTransfer(this.store, this.paths, this.network);
  final DownloadStore store;
  final DownloadPaths paths;
  final DownloadNetwork network;

  Future<void> run(DownloadTask task, CancelToken token) async {
    try {
      final descriptor = task.transfer;
      final journalFile = File(paths.journal(task.id));
      if (task.stage.isEmpty && await journalFile.exists()) await journalFile.delete();
      var journal = await journalFile.exists() ? downloadMap(await journalFile.readAsString()) : <String, dynamic>{};
      final partial = File(paths.partial(task.id));
      if (journal.isEmpty && !descriptor.overwrite && await _exists(descriptor)) {
        await store.applyReceipt(_receipt(task, DownloadState.skipped, destination: _destination(descriptor)));
        return;
      }
      if (journal.isEmpty) {
        if (task.stage != 'downloaded' || !await partial.exists()) {
          var complete = false;
          while (!complete) {
            complete = await _download((await store.task(task.id))!, partial, token);
          }
        }
        await validate(partial, descriptor);
        await store.updateAttempt(task, {'stage': 'downloaded'});
        if (!await store.authorizePublication(task)) return;
        journal = {
          'sha256': (await sha256.bind(partial.openRead()).first).toString(),
          'publicationId': const Uuid().v4(),
          'file': false,
          'sidecar': false,
        };
        await _saveJournal(journalFile, journal);
      } else {
        // A publication authorized before pause/cancel still has a physical
        // outcome. Reconcile that outcome instead of starting a second copy.
        if (!await store.authorizePublication(task)) return;
      }
      final destination = await _publish(descriptor, partial, journalFile, journal);
      await store.applyReceipt(
        _receipt(
          task,
          DownloadState.completed,
          destination: destination,
          warning: journal['warning'] as String?,
          filename: journal['filename'] as String?,
        ),
      );
      if (await partial.exists()) await partial.delete();
    } catch (error) {
      await fail(task, error);
    }
  }

  Future<void> fail(DownloadTask task, Object error) async {
    final code = DownloadNetwork.errorCode(error);
    if (code == 'interrupted') {
      await store.applyReceipt(_receipt(task, DownloadState.queued));
      await store.updateAttempt(task, {'attempts': max(0, task.attempts - 1)});
      return;
    }
    final now = DateTime.now();
    if (code == 'network') {
      await store.applyReceipt(
        _receipt(
          task,
          DownloadState.waitingNetwork,
          error: code,
          retryAt: now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
        ),
      );
      await store.updateAttempt(task, {'attempts': max(0, task.attempts - 1)});
      return;
    }
    final retryable =
        code == 'timeout' ||
        code == 'http429' ||
        code == 'http503' ||
        code == 'http500' ||
        code == 'http502' ||
        code == 'http504' ||
        const ['rangeRestart', 'invalidRange', 'invalidSize', 'checksum', 'incompleteFile'].contains(code);
    if (const ['invalidRange', 'invalidSize', 'checksum', 'incompleteFile'].contains(code)) {
      final partial = File(paths.partial(task.id));
      if (await partial.exists()) await partial.delete();
      await store.updateAttempt(task, {'stage': '', 'validator': null, 'received': 0});
    }
    if (retryable && task.attempts < 5) {
      final retryAfter = error is DioException
          ? RateLimitPolicy.retryAfter(error.response?.headers.value('retry-after'), now)
          : null;
      final backoff = now.add(RateLimitPolicy.backoff(task.attempts, jitter: Random().nextDouble() * .2));
      await store.applyReceipt(
        _receipt(
          task,
          code == 'http429' || code == 'http503' ? DownloadState.waitingRate : DownloadState.queued,
          error: code,
          retryAt: retryAfter != null && retryAfter.isAfter(backoff)
              ? retryAfter.millisecondsSinceEpoch
              : backoff.millisecondsSinceEpoch,
        ),
      );
    } else {
      await store.applyReceipt(
        _receipt(task, retryable ? DownloadState.failed : DownloadState.needsAction, error: code),
      );
    }
  }

  TransferReceipt _receipt(
    DownloadTask task,
    DownloadState state, {
    String? destination,
    String? error,
    String? warning,
    String? filename,
    int retryAt = 0,
  }) => TransferReceipt(
    id: const Uuid().v4(),
    taskId: task.id,
    attemptId: task.attemptId!,
    state: state,
    destination: destination,
    error: error,
    retryAt: retryAt,
    warning: warning,
    filename: filename,
  );

  String _destination(PreparedTransfer descriptor) => descriptor.destination.isSaf
      ? descriptor.destination.path
      : p.join(descriptor.destination.path, descriptor.filename);

  Future<bool> _exists(PreparedTransfer descriptor) async {
    if (descriptor.destination.isSaf) {
      return await downloadPlatform.invokeMethod<bool>('exists', descriptor.toJson()) ?? false;
    }
    final file = File(_destination(descriptor));
    return await file.exists() && await file.length() > 0;
  }

  Future<bool> _download(DownloadTask task, File partial, CancelToken token) async {
    final descriptor = task.transfer;
    var offset = await partial.exists() ? await partial.length() : 0;
    var validator = task.validator;
    if (validator == null) offset = 0;
    final headers = <String, dynamic>{...descriptor.headers, 'Accept-Encoding': 'identity'};
    final cookies = await network.configuration.cookies(descriptor.url);
    headers.removeWhere((key, _) => key.toLowerCase() == 'cookie');
    if (cookies.isNotEmpty) headers['Cookie'] = cookies;
    if (offset > 0) {
      headers['Range'] = 'bytes=$offset-';
      headers['If-Range'] = validator;
    }
    final dio = network.client();
    Response<ResponseBody>? response;
    try {
      response = await dio.get<ResponseBody>(
        descriptor.url,
        options: Options(headers: headers, responseType: ResponseType.stream),
        cancelToken: token,
      );
      final body = response.data!;
      int? rangeTotal;
      int? rangeLength;
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(response.headers.value('content-range') ?? '');
        if (match == null || int.parse(match.group(1)!) != offset) throw const DownloadBlocked('invalidRange');
        final end = int.parse(match.group(2)!);
        rangeTotal = int.parse(match.group(3)!);
        if (end < offset || end >= rangeTotal) throw const DownloadBlocked('invalidRange');
        rangeLength = end - offset + 1;
      } else if (response.statusCode == 200) {
        offset = 0;
      } else {
        throw const DownloadBlocked('invalidResponse');
      }
      final mime = response.headers.value('content-type')?.toLowerCase() ?? '';
      if (mime.contains('text/html') || mime.contains('application/json') || mime.contains('text/xml')) {
        await body.stream.drain<void>();
        throw const DownloadBlocked('authentication');
      }
      final length = int.tryParse(response.headers.value('content-length') ?? '');
      if (rangeLength != null && length != null && rangeLength != length) throw const DownloadBlocked('invalidRange');
      final total = rangeTotal ?? (length == null ? 0 : offset + length);
      validator = response.headers.value('etag');
      if (validator?.startsWith('W/') == true) validator = null;
      validator ??= response.headers.value('last-modified');
      await store.updateAttempt(task, {'validator': validator, 'total': total, 'received': offset});
      final handle = await partial.open(mode: offset > 0 ? FileMode.append : FileMode.write);
      var received = offset;
      var last = DateTime.now();
      try {
        await for (final chunk in body.stream.timeout(const Duration(seconds: 60))) {
          if (token.isCancelled) throw token.cancelError!;
          await handle.writeFrom(chunk);
          received += chunk.length;
          if (DateTime.now().difference(last).inMilliseconds >= 500) {
            last = DateTime.now();
            await store.updateAttempt(task, {'received': received});
          }
        }
        await handle.flush();
      } finally {
        await handle.close();
      }
      if (length != null && received != offset + length || rangeLength != null && received != offset + rangeLength) {
        throw const DownloadBlocked('incompleteFile');
      }
      if (rangeTotal != null && received < rangeTotal && validator == null) throw const DownloadBlocked('invalidRange');
      await store.updateAttempt(task, {'received': received, 'total': total == 0 ? received : total});
      return rangeTotal == null || received == rangeTotal;
    } on DioException catch (error) {
      if (error.response?.statusCode == 416) {
        final complete = RegExp(r'^bytes \*/(\d+)$').firstMatch(error.response?.headers.value('content-range') ?? '');
        final currentValidator =
            error.response?.headers.value('etag') ?? error.response?.headers.value('last-modified');
        if (complete != null &&
            validator != null &&
            currentValidator == validator &&
            await partial.exists() &&
            await partial.length() == int.parse(complete.group(1)!)) {
          await validate(partial, descriptor);
          return true;
        }
        if (await partial.exists()) await partial.delete();
        await store.updateAttempt(task, {'validator': null, 'received': 0});
        throw const DownloadBlocked('rangeRestart');
      }
      rethrow;
    } on TimeoutException {
      throw DioException(
        requestOptions: RequestOptions(path: descriptor.url),
        type: DioExceptionType.receiveTimeout,
      );
    } finally {
      if (response != null) DownloadNetwork.release(response.requestOptions);
      dio.close(force: true);
    }
  }

  static Future<void> validate(File file, PreparedTransfer descriptor) async {
    final length = await file.length();
    if (length == 0 ||
        descriptor.expectedSize != null && descriptor.expectedSize! > 0 && length != descriptor.expectedSize) {
      throw const DownloadBlocked('invalidSize');
    }
    final reader = await file.open();
    final prefix = await reader.read(512);
    await reader.close();
    final text = utf8.decode(prefix, allowMalformed: true).trimLeft().toLowerCase();
    if (text.startsWith('<!doctype html') ||
        text.startsWith('<html') ||
        text.startsWith('{"error') ||
        text.startsWith('{"message')) {
      throw const DownloadBlocked('authentication');
    }
    if (descriptor.checksum != null &&
        (await md5.bind(file.openRead()).first).toString() != descriptor.checksum!.toLowerCase()) {
      throw const DownloadBlocked('checksum');
    }
  }

  Future<void> _saveJournal(File file, Map<String, dynamic> journal) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(journal), flush: true);
    await temporary.rename(file.path);
  }

  Future<String> _publish(
    PreparedTransfer descriptor,
    File partial,
    File journalFile,
    Map<String, dynamic> journal,
  ) async {
    if (descriptor.destination.isSaf) {
      // The application-context publisher owns its own crash journal; it can
      // reconcile document-provider copies even after this Dart engine dies.
      final result = await downloadPlatform.invokeMapMethod<String, dynamic>('publish', {
        ...descriptor.toJson(),
        'partial': partial.path,
        'digest': journal['sha256'],
        'publicationId': journal['publicationId'],
      });
      journal['filename'] = result!['filename'];
      journal['warning'] = result['warning'];
      await _saveJournal(journalFile, journal);
      return result['destination'] as String;
    }
    final target = File(_destination(descriptor));
    await target.parent.create(recursive: true);
    // Android's shared Pictures directory admits media by its extension.
    // Appending .part/.previous after .jpg makes the copy or rename fail under
    // scoped storage, even though the final media filename is writable.
    String siblingPath(String suffix) => Platform.isAndroid
        ? '${p.withoutExtension(target.path)}.${descriptor.id}.$suffix${p.extension(target.path)}'
        : '${target.path}.${descriptor.id}.$suffix';
    final temporary = File(siblingPath('part'));
    final legacyPrevious = File('${target.path}.${descriptor.id}.previous');
    final previous = await legacyPrevious.exists() ? legacyPrevious : File(siblingPath('previous'));
    if (journal['file'] != true) {
      final matches =
          await target.exists() && (await sha256.bind(target.openRead()).first).toString() == journal['sha256'];
      if (!matches) {
        if (await target.exists() && !descriptor.overwrite) throw const DownloadBlocked('publicationAmbiguous');
        if (!await partial.exists()) throw const DownloadBlocked('publicationAmbiguous');
        await partial.copy(temporary.path);
        final handle = await temporary.open(mode: FileMode.append);
        await handle.flush();
        await handle.close();
        if (await target.exists() && !await previous.exists()) await target.rename(previous.path);
        await temporary.rename(target.path);
      }
      journal['file'] = true;
      await _saveJournal(journalFile, journal);
    }
    if (descriptor.writeJson && journal['sidecar'] != true) {
      final sidecar = File(p.setExtension(target.path, '.json'));
      final tmp = File('${sidecar.path}.${descriptor.id}.tmp');
      await tmp.writeAsString(jsonEncode(descriptor.item), flush: true);
      await tmp.rename(sidecar.path);
      journal['sidecar'] = true;
      await _saveJournal(journalFile, journal);
    }
    if (Platform.isIOS && descriptor.destination.photos) {
      await downloadPlatform.invokeMethod<void>('publishForeground', {
        ...descriptor.toJson(),
        'path': target.path,
        'digest': journal['sha256'],
      });
    }
    if (Platform.isAndroid) await downloadPlatform.invokeMethod<void>('scan', {'path': target.path});
    if (await previous.exists()) await previous.delete();
    return target.path;
  }
}
