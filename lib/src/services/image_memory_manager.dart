import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'package:dio/dio.dart';

/// A policy refusal, distinct from a corrupt file or a transport failure.
class ImageMemoryException implements Exception {
  const ImageMemoryException(this.reason, {this.isTransient = false});

  final String reason;
  final bool isTransient;

  @override
  String toString() => 'ImageMemoryException: $reason';
}

/// A reservation follows its owner, including while Flutter keeps it cached.
class ImageMemoryLease {
  ImageMemoryLease._(this._manager, this.bytes);

  final ImageMemoryManager _manager;
  final int bytes;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _manager._retainedBytes -= bytes;
  }
}

extension ImageMemoryCancellation on CancelToken {
  void throwIfCancellationRequested() {
    if (isCancelled) throw cancelError!;
  }
}

class ImageMemoryManager with WidgetsBindingObserver {
  ImageMemoryManager._();

  static final ImageMemoryManager instance = ImageMemoryManager._();

  static const int maxEncodedBytes = 64 * 1024 * 1024;
  static const int maxSourcePixels = 32 * 1000 * 1000;
  static const int maxAnimatedSourcePixels = 8 * 1000 * 1000;
  static const int maxAvifSourcePixels = 4 * 1000 * 1000;
  static const int maxSourceDimension = 32768;
  static const int maxOutputPixels = 16 * 1000 * 1000;
  static const int maxTextureDimension = 8192;
  static const int maxRetainedBytes = 128 * 1024 * 1024;
  static const int maxCacheBytes = 64 * 1024 * 1024;
  static const int maxTransientBytes = 256 * 1024 * 1024;
  static const Duration pressureCooldown = Duration(seconds: 30);

  final ValueNotifier<bool> underPressure = ValueNotifier(false);
  final ValueNotifier<bool> animationViewerActive = ValueNotifier(false);
  final Set<Object> _animationViewers = {};
  bool _animationNotificationScheduled = false;

  bool get hasAnimationViewer => _animationViewers.isNotEmpty;

  /// Thumbnail codecs yield their memory while foreground animations play.
  /// Coalesce build-time focus changes, including swipes between two viewers.
  void setAnimationViewerActive(Object owner, bool active) {
    if (active) {
      _animationViewers.add(owner);
    } else {
      _animationViewers.remove(owner);
    }
    if (_animationNotificationScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _animationNotificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _animationNotificationScheduled = false;
        animationViewerActive.value = hasAnimationViewer;
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      animationViewerActive.value = hasAnimationViewer;
    }
  }

  final Queue<_DecodeJob> _queue = Queue<_DecodeJob>();
  final Queue<_DecodeJob> _downloads = Queue<_DecodeJob>();
  final Expando<_DecodeCancellation> _cancellations = Expando<_DecodeCancellation>();
  Timer? _pressureTimer;
  bool _initialized = false;
  bool _decoding = false;
  int _retainedBytes = 0;
  int _activeDownloads = 0;
  int _rejectedCount = 0;
  int _foregroundDecodes = 0;

  int get retainedBytes => _retainedBytes;
  int get activeDecodeCount => _decoding ? 1 : 0;
  int get queuedDecodeCount => _queue.length;
  int get rejectedCount => _rejectedCount;
  int get activeDownloadCount => _activeDownloads;
  int get queuedDownloadCount => _downloads.length;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    final cache = PaintingBinding.instance.imageCache;
    if (cache.maximumSizeBytes > maxCacheBytes) cache.maximumSizeBytes = maxCacheBytes;
  }

  @override
  void didHaveMemoryPressure() => handleMemoryPressure();

  void handleMemoryPressure() {
    initialize();
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => underPressure.value = true);
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      underPressure.value = true;
    }
    _pressureTimer?.cancel();
    _pressureTimer = Timer(pressureCooldown, () => underPressure.value = false);
    // Do not clear live-image tracking: attached widgets still own those images.
    PaintingBinding.instance.imageCache.clear();
  }

  ImageMemoryLease reserveImage(int bytes) {
    initialize();
    if (bytes < 0 || bytes > maxRetainedBytes) {
      _rejectedCount++;
      throw const ImageMemoryException('Image exceeds the retained memory budget');
    }
    if (_retainedBytes + bytes > maxRetainedBytes) {
      handleMemoryPressure();
      // Cache handles can be released at the end of the frame. Never wait on
      // them here: a visible caller can otherwise deadlock behind keep-alives.
      if (_retainedBytes + bytes > maxRetainedBytes) {
        _rejectedCount++;
        throw const ImageMemoryException('Image memory is currently in use', isTransient: true);
      }
    }
    _retainedBytes += bytes;
    return ImageMemoryLease._(this, bytes);
  }

  /// Serializes transient native work. The operation must dispose any native
  /// result itself if cancellation arrives while the operation is running.
  Future<T> runDecode<T>(
    int estimatedBytes,
    Future<T> Function() operation, {
    CancelToken? cancelToken,
    bool Function()? isForeground,
  }) {
    initialize();
    if (estimatedBytes < 0 || estimatedBytes > maxTransientBytes) {
      _rejectedCount++;
      return Future<T>.error(const ImageMemoryException('Decode exceeds the transient memory budget'));
    }
    return _enqueue(operation, cancelToken, isForeground: isForeground);
  }

  Future<T> runDownload<T>(Future<T> Function() operation, {CancelToken? cancelToken}) {
    initialize();
    return _enqueue(operation, cancelToken, download: true);
  }

  Future<T> _enqueue<T>(
    Future<T> Function() operation,
    CancelToken? cancelToken, {
    bool download = false,
    bool Function()? isForeground,
  }) {
    if (cancelToken?.isCancelled == true) return Future<T>.error(cancelToken!.cancelError!);
    final result = Completer<T>();
    final execute = Zone.current.bindCallback(operation);
    late final _DecodeJob job;
    job = _DecodeJob(
      () async {
        try {
          cancelToken?.throwIfCancellationRequested();
          result.complete(await execute());
        } catch (error, stack) {
          result.completeError(error, stack);
        }
      },
      result.completeError,
      isForeground,
    );
    (download ? _downloads : _queue).add(job);
    if (cancelToken != null) {
      var cancellation = _cancellations[cancelToken];
      if (cancellation == null) {
        cancellation = _DecodeCancellation();
        _cancellations[cancelToken] = cancellation;
        final registration = cancellation;
        // One handler per token, rather than one permanent Future callback
        // for every animation frame decoded during that token's lifetime.
        unawaited(
          cancelToken.whenCancel.then((error) {
            for (final pending in registration.jobs) {
              if (_queue.remove(pending) || _downloads.remove(pending)) pending.reject(error);
            }
            registration.jobs.clear();
          }),
        );
      }
      cancellation.jobs.add(job);
      job.cancellation = cancellation;
    }
    if (download) {
      _pumpDownloads();
    } else {
      _pump();
    }
    return result.future;
  }

  void _pump() {
    if (_decoding) return;
    if (_queue.isEmpty) {
      _foregroundDecodes = 0;
      return;
    }
    _decoding = true;
    // Evaluate visibility now so a queued neighboring viewer can be promoted
    // after a swipe. Give the oldest job a turn after three foreground jobs.
    final foreground = _foregroundDecodes < 3
        ? _queue.where((job) => job.isForeground?.call() ?? false).firstOrNull
        : null;
    final job = foreground ?? _queue.first;
    _queue.remove(job);
    _foregroundDecodes = foreground == null ? 0 : _foregroundDecodes + 1;
    job.cancellation?.jobs.remove(job);
    unawaited(
      job.run().whenComplete(() {
        _decoding = false;
        _pump();
      }),
    );
  }

  void _pumpDownloads() {
    while (_activeDownloads < 4 && _downloads.isNotEmpty) {
      _activeDownloads++;
      final job = _downloads.removeFirst();
      job.cancellation?.jobs.remove(job);
      unawaited(
        job.run().whenComplete(() {
          _activeDownloads--;
          _pumpDownloads();
        }),
      );
    }
  }
}

class _DecodeJob {
  _DecodeJob(this.run, this.reject, this.isForeground);

  final Future<void> Function() run;
  final void Function(Object, [StackTrace?]) reject;
  final bool Function()? isForeground;
  _DecodeCancellation? cancellation;
}

class _DecodeCancellation {
  final Set<_DecodeJob> jobs = <_DecodeJob>{};
}
