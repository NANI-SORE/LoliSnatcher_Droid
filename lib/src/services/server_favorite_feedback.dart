import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';

enum ServerFavoriteRequestAction {
  add,
  remove,
}

enum ServerFavoriteRequestStatus {
  success,
  failed,
}

class ServerFavoriteRequestLogEntry {
  const ServerFavoriteRequestLogEntry({
    required this.timestamp,
    required this.action,
    required this.status,
    required this.booruName,
    required this.serverId,
    required this.item,
    this.message,
  });

  final DateTime timestamp;
  final ServerFavoriteRequestAction action;
  final ServerFavoriteRequestStatus status;
  final String booruName;
  final String serverId;
  final BooruItem item;
  final String? message;
}

class ServerFavoriteFeedback {
  ServerFavoriteFeedback._();

  static final ValueNotifier<List<ServerFavoriteRequestLogEntry>> requests = ValueNotifier([]);
  static final Random _random = Random();

  static void record({
    required ServerFavoriteRequestAction action,
    required ServerFavoriteRequestStatus status,
    required String booruName,
    required String serverId,
    required BooruItem item,
    String? message,
    bool animate = false,
  }) {
    requests.value = [
      ServerFavoriteRequestLogEntry(
        timestamp: DateTime.now(),
        action: action,
        status: status,
        booruName: booruName,
        serverId: serverId,
        item: item,
        message: message,
      ),
      ...requests.value,
    ].take(200).toList(growable: false);

    if (animate && status == ServerFavoriteRequestStatus.success && SX.serverFavoriteSuccessAnimation.value) {
      switch (action) {
        case ServerFavoriteRequestAction.add:
          showSuccessAnimation(item);
          break;
        case ServerFavoriteRequestAction.remove:
          showRemoveAnimation(item);
          break;
      }
    }
  }

  static void clear() {
    requests.value = const [];
  }

  static void showSuccessAnimation(BooruItem item) {
    final context = NavigationHandler.instance.navigatorKey.currentContext;
    if (context == null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ServerFavoriteHeartStream(
        item: item,
        seed: _random.nextInt(1000000),
        isBroken: false,
        onFinished: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  static void showRemoveAnimation(BooruItem item) {
    final context = NavigationHandler.instance.navigatorKey.currentContext;
    if (context == null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ServerFavoriteHeartStream(
        item: item,
        seed: _random.nextInt(1000000),
        isBroken: true,
        onFinished: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _ServerFavoriteHeartStream extends StatefulWidget {
  const _ServerFavoriteHeartStream({
    required this.item,
    required this.seed,
    required this.isBroken,
    required this.onFinished,
  });

  final BooruItem item;
  final int seed;
  final bool isBroken;
  final VoidCallback onFinished;

  @override
  State<_ServerFavoriteHeartStream> createState() => _ServerFavoriteHeartStreamState();
}

class _ServerFavoriteHeartStreamState extends State<_ServerFavoriteHeartStream> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final double startX;
  late final double endX;
  late final double scale;

  @override
  void initState() {
    super.initState();
    final random = Random(widget.seed);
    startX = random.nextDouble() * 34 - 17;
    endX = random.nextDouble() * 80 - 40;
    scale = 0.94 + random.nextDouble() * 0.18;
    controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2600),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.onFinished();
          }
        });
    unawaited(controller.forward());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final baseLeft = screen.width - 88;
    final baseBottom = max<double>(96, screen.height * 0.18);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(children: [_buildHeart(baseLeft, baseBottom)]);
        },
      ),
    );
  }

  Widget _buildHeart(double baseLeft, double baseBottom) {
    final raw = controller.value.clamp(0.0, 1.0);
    final curve = Curves.easeOutCubic.transform(raw);
    final opacity = raw < 0.14
        ? raw / 0.14
        : raw < 0.74
        ? 1.0
        : ((1 - raw) / 0.26).clamp(0.0, 1.0);
    final y = baseBottom + curve * 170;
    final x = baseLeft + startX + (endX - startX) * curve;

    return Positioned(
      left: x,
      bottom: y,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale * (0.9 + 0.1 * curve),
          child: _HeartThumbnail(
            item: widget.item,
            isBroken: widget.isBroken,
          ),
        ),
      ),
    );
  }
}

class _HeartThumbnail extends StatelessWidget {
  const _HeartThumbnail({
    required this.item,
    required this.isBroken,
  });

  final BooruItem item;
  final bool isBroken;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        ClipOval(
          child: SizedBox(
            width: 32,
            height: 32,
            child: item.thumbnailURL.isEmpty
                ? const ColoredBox(color: Colors.black26)
                : Image.network(
                    item.thumbnailURL,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                  ),
          ),
        ),
        Positioned(
          right: 1,
          bottom: 1,
          child: Icon(
            isBroken ? Icons.heart_broken : Icons.favorite,
            color: isBroken ? Colors.redAccent : Colors.pinkAccent,
            size: 20,
          ),
        ),
      ],
    );
  }
}
