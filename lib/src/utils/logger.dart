import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lolisnatcher/src/widgets/common/compact_error_widget.dart';
import 'package:talker/talker.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
// ignore: implementation_imports
import 'package:talker_flutter/src/controller/talker_view_controller.dart';

class Logger {
  static Logger? _loggerInstance;

  // ignore: non_constant_identifier_names
  static Logger Inst() {
    final bool isInit = _loggerInstance == null;

    _loggerInstance ??= Logger();
    _talkerInstance ??= Talker(
      settings: TalkerSettings(
        enabled: true,
        maxHistoryItems: 100000,
        useConsoleLogs: kDebugMode,
        useHistory: true,
      ),
      logger: TalkerLogger(
        output: (String message) {
          final StringBuffer buffer = StringBuffer();
          final lines = message.split('\n');
          lines.forEach(buffer.writeln);
          Platform.isIOS ? lines.forEach(print) : dev.log(buffer.toString());
          _fileLogger.writeTalker(message);
        },
      ),
    );

    viewController ??= TalkerViewController(talker: talker)..toggleExpandedLogs();

    if (isInit) {
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exception is DioException && CancelToken.isCancel(details.exception as DioException)) {
          // ignore exceptions caused by cancelling dio requests (mostly for image loading)
          return;
        }
        FlutterError.presentError(details);

        Logger.Inst().log(
          '$details',
          'FlutterError',
          'onError',
          LogTypes.exception,
          s: details.stack,
        );
      };

      // Set custom compact ErrorWidget builder to prevent layout breakage
      ErrorWidget.builder = CompactErrorWidget.builder;

      PlatformDispatcher.instance.onError = (error, stack) {
        Logger.Inst().log(
          error,
          'PlatformDispatcherError',
          'onError',
          LogTypes.exception,
          s: stack,
        );
        return true;
      };
    }

    return _loggerInstance!;
  }

  static Talker? _talkerInstance;

  static Talker get talker => _talkerInstance!;

  static TalkerViewController? viewController;

  static final _fileLogger = _DailyFileLogger();

  static Future<List<File>> getLogFiles() => _fileLogger.getFiles();

  static Future<String> readLogFile(File file, {int maxBytes = 2 * 1024 * 1024}) =>
      _fileLogger.readFile(file, maxBytes: maxBytes);

  static Future<void> flushLogFile() => _fileLogger.flush();

  static Future<void> deleteLogFile(File file) => _fileLogger.deleteFile(file);

  static Future<void> setLogcatCaptureEnabled(bool enabled) => _fileLogger.setLogcatCaptureEnabled(enabled);

  void log(
    dynamic object,
    String callerClass,
    String callerFunction,
    LogTypes? logType, {
    StackTrace? s,
  }) {
    String logStr = '';
    try {
      logStr = object is String ? object : '$object';
    } catch (_) {
      logStr = object.runtimeType.toString();
    }

    if (logStr.length > 10000) {
      logStr = '${logStr.substring(0, 10000)}...';
    }

    final logLevel = logType?.logLevel ?? LogLevel.wtf;
    if (logLevel == LogLevel.info) {
      _talkerInstance?.info(logStr, null, s);
    } else if (logLevel == LogLevel.error) {
      _talkerInstance?.error(logStr, null, s);
    } else if (logLevel == LogLevel.warning) {
      _talkerInstance?.warning(logStr, null, s);
    } else if (logLevel == LogLevel.debug) {
      _talkerInstance?.debug(logStr, null, s);
    } else if (logLevel == LogLevel.verbose) {
      _talkerInstance?.verbose(logStr, null, s);
    } else if (logLevel == LogLevel.wtf) {
      _talkerInstance?.verbose(logStr, null, s);
    } else {
      _talkerInstance?.verbose(logStr, null, s);
    }
  }

  static TalkerDioLogger? get dioInterceptor => _talkerInstance != null
      ? TalkerDioLogger(
          talker: _talkerInstance,
          settings: const TalkerDioLoggerSettings(
            printResponseData: false,
            printRequestData: true,
            printErrorData: true,
            printResponseHeaders: true,
            printRequestHeaders: true,
            printErrorHeaders: true,
            printResponseMessage: true,
            printErrorMessage: true,
          ),
        )
      : null;
}

// TODO more types
enum LogTypes {
  booruHandlerFetchFailed,
  booruHandlerInfo,
  booruHandlerParseFailed,
  booruHandlerRawFetched,
  booruHandlerSearchURL,
  booruHandlerTagInfo,
  booruItemLoad,
  exception,
  imageInfo,
  imageLoadingError,
  loliSyncInfo,
  networkError,
  settingsError,
  settingsLoad,
  tagHandlerInfo,
  ;

  @override
  String toString() {
    return name;
  }

  static LogTypes fromString(String str) {
    return LogTypes.values.firstWhere((element) => element.name == str, orElse: () => LogTypes.exception);
  }

  LogLevel get logLevel {
    switch (this) {
      case LogTypes.booruHandlerFetchFailed:
      case LogTypes.booruHandlerParseFailed:
      case LogTypes.exception:
      case LogTypes.imageLoadingError:
      case LogTypes.networkError:
      case LogTypes.settingsError:
        return LogLevel.error;
      //
      case LogTypes.booruHandlerInfo:
      case LogTypes.booruHandlerRawFetched:
      case LogTypes.booruHandlerSearchURL:
      case LogTypes.booruHandlerTagInfo:
      case LogTypes.booruItemLoad:
      case LogTypes.imageInfo:
      case LogTypes.loliSyncInfo:
      case LogTypes.settingsLoad:
      case LogTypes.tagHandlerInfo:
        return LogLevel.info;
      // ignore: unreachable_switch_default
      default:
        return LogLevel.wtf;
    }
  }
}

enum LogLevel {
  info,
  warning,
  error,
  debug,
  verbose,
  wtf,
}

class _DailyFileLogger {
  static const _retention = Duration(days: 14);
  static const _maxFileBytes = 25 * 1024 * 1024;
  static const _writeDelay = Duration(seconds: 1000);
  static final _ansiEscape = RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])');
  static final _talkerHeader = RegExp(r'^\[([^\]]+)\]\s*\|\s*[^|]+\|\s*');

  late final Future<void> _ready = _initialize();
  Future<void> _pendingWrite = Future<void>.value();
  final List<_PendingLogLine> _buffer = [];
  final List<String> _recentAppMessages = [];
  late Directory _logDirectory;
  IOSink? _sink;
  String? _sinkDate;
  int _sinkBytes = 0;
  bool _sizeLimitReached = false;
  bool _available = false;
  bool _logcatEnabled = false;
  Timer? _flushTimer;
  Process? _logcatProcess;
  StreamSubscription<String>? _logcatOutputSubscription;
  StreamSubscription<String>? _logcatErrorSubscription;

  Future<void> _initialize() async {
    try {
      _logDirectory = await _resolveLogDirectory();
      await _logDirectory.create(recursive: true);
      _available = true;
      await _deleteExpiredFiles();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('File logging is unavailable: $error');
      }
    }
  }

  Future<Directory> _resolveLogDirectory() async {
    String? rootPath;
    String appDirectory = 'LoliSnatcher';

    if (Platform.isWindows) {
      rootPath = Platform.environment['LOCALAPPDATA'];
      appDirectory = 'LoliSnatcher';
    } else if (Platform.isLinux) {
      rootPath = Platform.environment['HOME'];
      appDirectory = '.loliSnatcher';
    }

    if (rootPath == null || rootPath.isEmpty) {
      rootPath = (await getApplicationSupportDirectory()).path;
      appDirectory = '';
    }

    return Directory(
      [
        rootPath,
        if (appDirectory.isNotEmpty) appDirectory,
        'logs',
      ].join(Platform.pathSeparator),
    );
  }

  void writeTalker(String message) {
    final lines = message.replaceAll(_ansiEscape, '').replaceAll('\r\n', '\n').split('\n');

    if (lines.isNotEmpty && _isTalkerBorder(lines.first)) {
      lines.removeAt(0);
    }
    if (lines.isNotEmpty && _isTalkerBorder(lines.last)) {
      lines.removeLast();
    }

    final cleanedLines = lines.map((line) {
      final unwrapped = line.startsWith('│ ') ? line.substring(2) : line;
      return unwrapped.trimRight();
    }).toList();

    if (cleanedLines.isNotEmpty) {
      cleanedLines[0] = cleanedLines.first.replaceFirstMapped(
        _talkerHeader,
        (match) => '[${match.group(1)}] ',
      );
    }

    while (cleanedLines.isNotEmpty && cleanedLines.first.isEmpty) {
      cleanedLines.removeAt(0);
    }
    while (cleanedLines.isNotEmpty && cleanedLines.last.isEmpty) {
      cleanedLines.removeLast();
    }

    write(cleanedLines.join('\n'));
  }

  bool _isTalkerBorder(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 2 || !'┌└'.contains(trimmed[0])) {
      return false;
    }
    return trimmed.substring(1).split('').every((character) => character == '─');
  }

  void write(String message, {String source = 'app'}) {
    final cleanMessage = message.replaceAll(_ansiEscape, '').trimRight();
    if (cleanMessage.isEmpty || (source == 'logcat' && _isDuplicateLogcat(cleanMessage))) {
      return;
    }

    final now = DateTime.now();
    final date = _dateString(now);
    if (_sizeLimitReached && _sinkDate == date) {
      return;
    }

    if (source == 'app') {
      _rememberAppMessage(cleanMessage);
    }

    _buffer.add(
      _PendingLogLine(
        date: date,
        text: '[${now.toIso8601String()}][$source] $cleanMessage\n',
      ),
    );
    _flushTimer ??= Timer(_writeDelay, () {
      _flushTimer = null;
      unawaited(_queueBufferedWrite());
    });
  }

  void _rememberAppMessage(String message) {
    for (final line in message.split('\n')) {
      final normalized = line.trim();
      if (normalized.length >= 16) {
        _recentAppMessages.add(normalized);
      }
    }
    if (_recentAppMessages.length > 100) {
      _recentAppMessages.removeRange(0, _recentAppMessages.length - 100);
    }
  }

  bool _isDuplicateLogcat(String line) {
    return _recentAppMessages.any(line.contains);
  }

  Future<void> _queueBufferedWrite() async {
    if (_buffer.isEmpty) {
      return;
    }
    final batch = List<_PendingLogLine>.of(_buffer);
    _buffer.clear();
    _pendingWrite = _pendingWrite
        .then((_) async {
          await _ready;
          if (_available) {
            await _writeBatch(batch);
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (kDebugMode) {
            debugPrint('Failed to write log file: $error\n$stack');
          }
        });
    await _pendingWrite;
  }

  Future<void> _writeBatch(List<_PendingLogLine> batch) async {
    for (final line in batch) {
      await _openSinkForDate(line.date);
      if (_sizeLimitReached) {
        continue;
      }

      final bytes = utf8.encode(line.text);
      if (_sinkBytes + bytes.length > _maxFileBytes) {
        // TODO change to log rotation if 25mb is not big enough for power users
        const limitMessage = '[logger] Daily log size limit reached; further logs are omitted.\n';
        final limitBytes = utf8.encode(limitMessage);
        if (_sinkBytes + limitBytes.length <= _maxFileBytes) {
          _sink!.add(limitBytes);
          _sinkBytes += limitBytes.length;
        }
        _sizeLimitReached = true;
        continue;
      }

      _sink!.add(bytes);
      _sinkBytes += bytes.length;
    }
    await _sink?.flush();
  }

  Future<void> _openSinkForDate(String date) async {
    if (_sinkDate != date) {
      await _sink?.flush();
      await _sink?.close();
      final file = File('${_logDirectory.path}${Platform.pathSeparator}lolisnatcher-$date.log');
      _sinkBytes = await file.exists() ? await file.length() : 0;
      _sizeLimitReached = _sinkBytes >= _maxFileBytes;
      _sink = file.openWrite(mode: FileMode.append);
      _sinkDate = date;
    }
  }

  Future<void> _deleteExpiredFiles() async {
    final cutoff = DateTime.now().subtract(_retention);
    await for (final entity in _logDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.log')) {
        continue;
      }
      try {
        final modified = await entity.lastModified();
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // A log may be unavailable briefly while another process is using it.
      }
    }
  }

  Future<void> setLogcatCaptureEnabled(bool enabled) async {
    _logcatEnabled = enabled;
    await _ready;
    if (!Platform.isAndroid || !_available) {
      return;
    }
    if (enabled) {
      await _startLogcat();
    } else {
      await _stopLogcat();
    }
  }

  Future<void> _startLogcat() async {
    if (!_logcatEnabled || _logcatProcess != null) {
      return;
    }
    try {
      final logcatProcess = await Process.start(
        'logcat',
        ['--pid=$pid', '-v', 'threadtime', '*:W'],
        runInShell: false,
      );
      _logcatProcess = logcatProcess;
      _logcatOutputSubscription = logcatProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => write(line, source: 'logcat'));
      _logcatErrorSubscription = logcatProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => write(line, source: 'logcat-error'));
      unawaited(
        logcatProcess.exitCode.then((_) {
          if (identical(_logcatProcess, logcatProcess)) {
            _logcatProcess = null;
            _logcatOutputSubscription = null;
            _logcatErrorSubscription = null;
          }
        }),
      );
    } catch (error) {
      write('Logcat capture is unavailable: $error', source: 'logger');
    }
  }

  Future<void> _stopLogcat() async {
    final process = _logcatProcess;
    _logcatProcess = null;
    await _logcatOutputSubscription?.cancel();
    await _logcatErrorSubscription?.cancel();
    _logcatOutputSubscription = null;
    _logcatErrorSubscription = null;
    process?.kill();
  }

  Future<List<File>> getFiles() async {
    await _ready;
    if (!_available) {
      return [];
    }
    await flush();
    final files = await _logDirectory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.log'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<String> readFile(File file, {required int maxBytes}) async {
    await _ready;
    if (!_available) {
      return '';
    }
    await flush();
    final length = await file.length();
    final start = length > maxBytes ? length - maxBytes : 0;
    final reader = await file.open();
    try {
      await reader.setPosition(start);
      final contents = utf8.decode(await reader.read(maxBytes), allowMalformed: true);
      return start == 0 ? contents : '... earlier log content omitted ...\n$contents';
    } finally {
      await reader.close();
    }
  }

  Future<void> deleteFile(File file) async {
    await flush();
    _pendingWrite = _pendingWrite.then((_) async {
      if (_sink != null && _sinkDate != null) {
        final activePath = '${_logDirectory.path}${Platform.pathSeparator}lolisnatcher-$_sinkDate.log';
        if (File(activePath).absolute.path == file.absolute.path) {
          await _sink!.flush();
          await _sink!.close();
          _sink = null;
          _sinkDate = null;
          _sinkBytes = 0;
          _sizeLimitReached = false;
        }
      }
      if (await file.exists()) {
        await file.delete();
      }
    });
    await _pendingWrite;
  }

  Future<void> flush() async {
    await _ready;
    if (!_available) {
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    await _queueBufferedWrite();
    await _pendingWrite;
    await _sink?.flush();
  }

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _PendingLogLine {
  const _PendingLogLine({
    required this.date,
    required this.text,
  });

  final String date;
  final String text;
}
