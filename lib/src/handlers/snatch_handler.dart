import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/image_writer.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

class SnatchHandler {
  SnatchHandler() {
    queuedList.addListener(queuedListListener);
  }

  static SnatchHandler get instance => GetIt.instance<SnatchHandler>();

  static SnatchHandler register() {
    if (!GetIt.instance.isRegistered<SnatchHandler>()) {
      GetIt.instance.registerSingleton(
        SnatchHandler(),
        dispose: (snatchHandler) => snatchHandler.dispose(),
      );
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SnatchHandler>();

  final RxBool active = false.obs;
  final RxString status = ''.obs;
  final RxInt queueProgress = 0.obs;
  final Rx<SnatchItem?> current = Rx<SnatchItem?>(null);
  final RxSet<Key> currentItemKeys = <Key>{}.obs;
  final Rxn<BooruItem> activeItem = Rxn<BooruItem>();
  final RxInt received = 0.obs;
  final RxInt total = 0.obs;

  final Rx<ShareItem?> currentShare = Rx<ShareItem?>(null);
  final RxInt shareProgress = 0.obs;
  final Rxn<BooruItem> shareActiveItem = Rxn<BooruItem>();
  final RxInt shareReceived = 0.obs;
  final RxInt shareTotal = 0.obs;

  final RxList<({BooruItem item, Booru booru})> existsItems = RxList([]);
  final RxList<({BooruItem item, Booru booru})> failedItems = RxList([]);
  final RxList<({BooruItem item, Booru booru})> cancelledItems = RxList([]);

  CancelToken? cancelToken;
  CancelToken? shareCancelToken;
  Timer? _progressStuckTimer;
  Timer? _shareProgressStuckTimer;
  bool _retryCurrentRequested = false;
  bool _retryCurrentShareRequested = false;
  int _shareOperationId = 0;

  double get currentProgress {
    if (total.value == 0) return 0;
    return received.value / total.value;
  }

  double get currentShareProgress {
    if (shareTotal.value == 0) return 0;
    return shareReceived.value / shareTotal.value;
  }

  final RxList<SnatchItem> queuedList = RxList<SnatchItem>([]);

  Stream<Map<String, int>> writeMultipleFake(List<BooruItem> items, Booru booru, int cooldown) async* {
    int snatchedCounter = 0;
    for (int i = 0; i < items.length; i++) {
      await Future.delayed(const Duration(milliseconds: 2000), () async {});
      snatchedCounter++;
      yield {
        'snatched': snatchedCounter,
      };
    }

    yield {
      'snatched': snatchedCounter,
      'exists': 0,
      'failed': 0,
      'cancelled': 0,
    };
  }

  void onProgress(int newReceived, int newTotal) {
    final progressChanged = received.value != newReceived || total.value != newTotal;
    received.value = newReceived;
    total.value = newTotal;
    final currentValue = current.value;
    final progress = queueProgress.value;
    activeItem.value = newTotal > 0 && currentValue != null && progress < currentValue.booruItems.length
        ? currentValue.booruItems[progress]
        : null;
    if (progressChanged && cancelToken != null && !cancelToken!.isCancelled) {
      _restartProgressStuckTimer();
    }
  }

  void onRemoveRetryItem(
    ({BooruItem item, Booru booru}) record,
  ) {
    existsItems.remove(record);
    failedItems.remove(record);
    cancelledItems.remove(record);
  }

  void onClearRetryableItems() {
    existsItems.clear();
    failedItems.clear();
    cancelledItems.clear();
  }

  void onAddRetryableItems({
    required Booru booru,
    List<BooruItem> exists = const [],
    List<BooruItem> failed = const [],
    List<BooruItem> cancelled = const [],
  }) {
    existsItems.addAll(exists.map((e) => (booru: booru, item: e)));
    failedItems.addAll(failed.map((e) => (booru: booru, item: e)));
    cancelledItems.addAll(cancelled.map((e) => (booru: booru, item: e)));
  }

  Future<void> onRetryAll({
    required int cooldown,
    bool ignoreExists = false,
  }) async {
    final itemsToRetry = [...existsItems, ...failedItems, ...cancelledItems];
    final Set<Booru> uniqueBoorus = itemsToRetry.map((i) => i.booru).toSet();
    final Map<Booru, List<BooruItem>> booruItemsMap = {};
    booruItemsMap.addEntries(uniqueBoorus.map((b) => MapEntry(b, [])));
    for (int i = 0; i < itemsToRetry.length; i++) {
      final BooruItem item = itemsToRetry[i].item;
      final Booru booru = itemsToRetry[i].booru;
      final List<BooruItem> items = booruItemsMap[booru]!;
      items.add(item);
      booruItemsMap[booru] = items;
    }

    final List<SnatchItem> snatchItems = [];
    await Future.wait(
      booruItemsMap.entries.map((entry) async {
        final booru = entry.key;
        final items = entry.value;
        final booruHandler = BooruHandlerFactory().getBooruHandler([booru], 10).booruHandler;
        if (booruHandler.hasLoadItemSupport) {
          try {
            // refetch data only on smaller-ish batches, otherwise they will most likely rate limit the user
            if (items.length <= 20) {
              for (final item in items) {
                await booruHandler.loadItem(
                  item: item,
                  withCapcthaCheck: true,
                );
                await Future.delayed(const Duration(milliseconds: 100));
              }
            }
          } catch (_) {}
        }

        snatchItems.add(
          SnatchItem(
            items,
            cooldown,
            booru,
            ignoreExists || items.any((i) => existsItems.any((e) => e.item == i)),
          ),
        );
      }),
    );

    queuedList.addAll(snatchItems);

    onClearRetryableItems();
  }

  void onRetryItem(
    ({BooruItem item, Booru booru}) record, {
    required int cooldown,
    bool ignoreExists = false,
  }) {
    queuedList.add(
      SnatchItem(
        [record.item],
        cooldown,
        record.booru,
        ignoreExists,
      ),
    );

    onRemoveRetryItem(record);
  }

  void onCancel() {
    _stopProgressStuckTimer();
    _retryCurrentRequested = false;
    cancelToken?.cancel();
  }

  int onShareStart(
    List<BooruItem> booruItems,
    Booru booru,
  ) {
    _shareOperationId++;
    _retryCurrentShareRequested = false;
    currentShare.value = ShareItem(booruItems, booru);
    shareProgress.value = 0;
    shareActiveItem.value = booruItems.isEmpty ? null : booruItems.first;
    shareReceived.value = 0;
    shareTotal.value = 0;
    return _shareOperationId;
  }

  void onShareProgress({
    required int operationId,
    required BooruItem item,
    required int itemIndex,
    required int received,
    required int total,
  }) {
    if (operationId != _shareOperationId) return;

    shareProgress.value = itemIndex;
    shareActiveItem.value = item;
    shareReceived.value = received;
    shareTotal.value = total;
    if (shareCancelToken != null && !shareCancelToken!.isCancelled) {
      _restartShareProgressStuckTimer();
    }
  }

  void onShareCancel() {
    _stopShareProgressStuckTimer();
    _retryCurrentShareRequested = false;
    shareCancelToken?.cancel();
  }

  void onShareCancelTokenCreate(CancelToken token, int operationId) {
    if (operationId != _shareOperationId) return;

    shareCancelToken = token;
    _restartShareProgressStuckTimer();
  }

  void onShareDone(int operationId) {
    if (operationId != _shareOperationId) return;

    _stopShareProgressStuckTimer();
    _retryCurrentShareRequested = false;
    shareCancelToken = null;
    currentShare.value = null;
    shareProgress.value = 0;
    shareActiveItem.value = null;
    shareReceived.value = 0;
    shareTotal.value = 0;
  }

  void onShareRetryCurrent() {
    final token = shareCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }

    _stopShareProgressStuckTimer();
    _retryCurrentShareRequested = true;
    shareReceived.value = 0;
    shareTotal.value = 0;
    token.cancel();
  }

  bool consumeShareRetryCurrent() {
    final retryCurrent = _retryCurrentShareRequested;
    _retryCurrentShareRequested = false;
    return retryCurrent;
  }

  void onRetryCurrent() {
    final token = cancelToken;
    if (token == null || token.isCancelled) {
      return;
    }

    _stopProgressStuckTimer();
    _retryCurrentRequested = true;
    received.value = 0;
    total.value = 0;
    token.cancel();
  }

  bool _consumeRetryCurrent() {
    final retryCurrent = _retryCurrentRequested;
    _retryCurrentRequested = false;
    return retryCurrent;
  }

  void onCancelTokenCreate(CancelToken token) {
    cancelToken = token;
    _restartProgressStuckTimer();
  }

  void _restartProgressStuckTimer() {
    _progressStuckTimer?.cancel();
    _progressStuckTimer = Timer(
      const Duration(seconds: 10),
      () {
        _progressStuckTimer = null;
        onRetryCurrent();
      },
    );
  }

  void _stopProgressStuckTimer() {
    _progressStuckTimer?.cancel();
    _progressStuckTimer = null;
  }

  void _restartShareProgressStuckTimer() {
    _shareProgressStuckTimer?.cancel();
    _shareProgressStuckTimer = Timer(
      const Duration(seconds: 10),
      () {
        _shareProgressStuckTimer = null;
        onShareRetryCurrent();
      },
    );
  }

  void _stopShareProgressStuckTimer() {
    _shareProgressStuckTimer?.cancel();
    _shareProgressStuckTimer = null;
  }

  Future snatch(SnatchItem item) async {
    status.value = queuedList.isNotEmpty
        ? '0/${item.booruItems.length}/${queuedList.length}'
        : '0/${item.booruItems.length}';
    current.value = item;
    currentItemKeys.assignAll(item.booruItems.map((booruItem) => booruItem.key));

    // writeMultipleFake(item.booruItems, item.booru, item.cooldown).listen(
    ImageWriter()
        .writeMultiple(
          item.booruItems,
          item.booru,
          item.cooldown,
          onProgress,
          item.ignoreExists,
          onCancelTokenCreate,
          _consumeRetryCurrent,
        )
        .listen(
          (Map<String, dynamic> data) {
            final int snatched = data['snatched']! as int;
            final List<BooruItem> exists = data['exists'] ?? [];
            final List<BooruItem> failed = data['failed'] ?? [];
            final List<BooruItem> cancelled = data['cancelled'] ?? [];
            final bool isLastMessage = data['exists'] != null && data['failed'] != null && data['cancelled'] != null;

            // last yield in stream will send fetch results counters
            // but show this message only when queue is empty => snatching is complete
            if (SX.downloadNotifications.value && isLastMessage) {
              if (current.value!.booruItems.length == 1) {
                final context = NavigationHandler.instance.navContext;
                FlashElements.showSnackbar(
                  duration: const Duration(seconds: 2),
                  position: FlashPosition.top,
                  title: Text(
                    context.loc.snatcher.itemsSnatched,
                    style: const TextStyle(fontSize: 20),
                  ),
                  content: Row(
                    children: [
                      if (exists.isNotEmpty || failed.isNotEmpty || cancelled.isNotEmpty || queuedList.isNotEmpty)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (exists.isNotEmpty) Text(context.loc.snatcher.itemWasAlreadySnatched),
                              if (failed.isNotEmpty) Text(context.loc.snatcher.failedToSnatchItem),
                              if (cancelled.isNotEmpty) Text(context.loc.snatcher.itemWasCancelled),
                              if (queuedList.isNotEmpty) Text(context.loc.snatcher.startingNextQueueItem),
                            ],
                          ),
                        ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: ThumbnailBuild(
                          item: current.value!.booruItems.first,
                          handler: BooruHandlerFactory().getBooruHandler(
                            [current.value!.booru],
                            null,
                          ).booruHandler,
                          selectable: false,
                          simple: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  leadingIcon: Icons.done_all,
                  sideColor: failed.isNotEmpty
                      ? Colors.red
                      : ((exists.isNotEmpty || cancelled.isNotEmpty) ? Colors.yellow : Colors.green),
                );
              } else {
                final context = NavigationHandler.instance.navContext;
                FlashElements.showSnackbar(
                  duration: const Duration(seconds: 2),
                  position: FlashPosition.top,
                  title: Text(context.loc.snatcher.itemsSnatched, style: const TextStyle(fontSize: 20)),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.loc.snatcher.snatchedCount(count: queueProgress.value),
                      ),
                      if (exists.isNotEmpty)
                        Text(
                          context.loc.snatcher.filesAlreadySnatched(count: exists.length),
                        ),
                      if (failed.isNotEmpty)
                        Text(
                          context.loc.snatcher.failedToSnatchFiles(count: failed.length),
                        ),
                      if (cancelled.isNotEmpty)
                        Text(
                          context.loc.snatcher.cancelledFiles(count: cancelled.length),
                        ),
                      if (queuedList.isNotEmpty) Text(context.loc.snatcher.startingNextQueueItem),
                    ],
                  ),
                  leadingIcon: Icons.done_all,
                  sideColor: failed.isNotEmpty
                      ? Colors.red
                      : ((exists.isNotEmpty || cancelled.isNotEmpty) ? Colors.yellow : Colors.green),
                );
              }
            }

            if (isLastMessage) {
              onAddRetryableItems(
                booru: item.booru,
                exists: exists,
                failed: failed,
                cancelled: cancelled,
              );
            }

            _stopProgressStuckTimer();
            cancelToken = null;
            _retryCurrentRequested = false;
            status.value = queuedList.isNotEmpty
                ? '$snatched/${item.booruItems.length}/${queuedList.length}'
                : '$snatched/${item.booruItems.length}';
            queueProgress.value = queueProgress.value + 1;
            activeItem.value = null;
            received.value = 0;
            total.value = 0;
          },
          onDone: () {
            _stopProgressStuckTimer();
            cancelToken = null;
            _retryCurrentRequested = false;
            status.value = '';
            current.value = null;
            currentItemKeys.clear();
            activeItem.value = null;
            queueProgress.value = 0;
            received.value = 0;
            total.value = 0;

            if (active.value) {
              if (queuedList.isNotEmpty) {
                snatch(queuedList.removeAt(0));
              } else {
                active.value = false;
              }
            }
          },
        );
  }

  void queuedListListener() {
    trySnatch();
  }

  void trySnatch() {
    if (!active.value && current.value == null) {
      if (queuedList.isNotEmpty) {
        active.value = true;
        snatch(queuedList.removeAt(0));
      }
    }
  }

  void queue(
    List<BooruItem> booruItems,
    Booru booru,
    int cooldown,
    bool ignoreExists,
  ) {
    if (booruItems.isNotEmpty) {
      final SnatchItem item = SnatchItem(booruItems, cooldown, booru, ignoreExists);
      queuedList.add(item);

      if (booruItems.length > 1) {
        if (SX.downloadNotifications.value) {
          final context = NavigationHandler.instance.navContext;
          FlashElements.showSnackbar(
            title: Text(
              context.loc.snatcher.addedItemsToQueue(count: booruItems.length),
              style: const TextStyle(fontSize: 20),
            ),
            position: FlashPosition.top,
            duration: const Duration(seconds: 2),
            leadingIcon: Icons.info_outline,
            sideColor: Colors.green,
          );
        }
      } else {
        if (SX.downloadNotifications.value) {
          final context = NavigationHandler.instance.navContext;
          FlashElements.showSnackbar(
            title: Text(
              context.loc.snatcher.addedItemToQueue,
              style: const TextStyle(fontSize: 20),
            ),
            position: FlashPosition.top,
            duration: const Duration(seconds: 2),
            leadingIcon: Icons.info_outline,
            sideColor: Colors.green,
            content: Row(
              children: [
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: ThumbnailBuild(
                    item: booruItems.first,
                    handler: BooruHandlerFactory().getBooruHandler([booru], null).booruHandler,
                    selectable: false,
                    simple: true,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          );
        }
      }
    }
  }

  Future searchSnatch(String tags, String amount, int cooldown, Booru booru) async {
    int count = 0, limit;
    BooruHandler booruHandler;
    List<BooruItem> booruItems = [];

    if (int.parse(amount) <= 100) {
      limit = int.parse(amount);
    } else {
      limit = 100;
    }

    final temp = BooruHandlerFactory().getBooruHandler([booru], limit);
    booruHandler = temp.booruHandler;
    booruHandler.pageNum = temp.startingPage;
    booruHandler.pageNum++;

    final context = NavigationHandler.instance.navContext;
    FlashElements.showSnackbar(
      title: Text(context.loc.snatcher.snatchingImages, style: const TextStyle(fontSize: 20)),
      position: FlashPosition.top,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.loc.snatcher.doNotCloseApp),
        ],
      ),
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
    );

    while (count < int.parse(amount) && !booruHandler.locked) {
      booruItems = await booruHandler.search(tags, null) ?? [];
      booruItems = booruItems.where((e) => !e.isHidden).toList();
      booruHandler.pageNum++;
      count = booruItems.length;
      // TODO error handling?
    }
    queue(booruItems, booru, cooldown, false);
  }

  void dispose() {
    _stopProgressStuckTimer();
    _stopShareProgressStuckTimer();
    shareCancelToken?.cancel();
    queuedList.removeListener(queuedListListener);
  }
}

class SnatchItem {
  SnatchItem(
    this.booruItems,
    this.cooldown,
    this.booru,
    this.ignoreExists,
  );

  final List<BooruItem> booruItems;
  final int cooldown;
  final Booru booru;
  final bool ignoreExists;
}

class ShareItem {
  ShareItem(
    this.booruItems,
    this.booru,
  );

  final List<BooruItem> booruItems;
  final Booru booru;
}
