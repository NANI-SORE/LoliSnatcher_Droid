import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/snatch_handler.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/animated_progress_indicator.dart';
import 'package:lolisnatcher/src/widgets/common/cancel_button.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail_build.dart';

class DDShareItem extends StatelessWidget {
  const DDShareItem({
    required this.item,
    required this.handler,
    required this.index,
    required this.isFirst,
    required this.shareProgress,
    required this.totalItems,
    super.key,
  });

  final BooruItem item;
  final BooruHandler handler;
  final int index;
  final bool isFirst;
  final int shareProgress;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final snatchHandler = SnatchHandler.instance;

    return Stack(
      children: [
        if (isFirst)
          Positioned.fill(
            bottom: 0,
            left: 0,
            child: Obx(() {
              if (snatchHandler.shareTotal.value == 0) {
                return const SizedBox.shrink();
              }

              return AnimatedProgressIndicator(
                value: snatchHandler.currentShareProgress,
                valueColor: Theme.of(context).progressIndicatorTheme.color?.withValues(alpha: 0.5),
                indicatorStyle: IndicatorStyle.linear,
                borderRadius: 0,
                animationDuration: const Duration(milliseconds: 100),
              );
            }),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 100,
                    height: 150,
                    child: ThumbnailBuild(
                      item: item,
                      handler: handler,
                      selectable: false,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 8,
                    children: [
                      const Icon(Icons.share),
                      if (totalItems != 1)
                        Text(
                          '${shareProgress + index + 1}/$totalItems',
                          style: const TextStyle(fontSize: 16),
                        ),
                      if (isFirst)
                        CancelButton(
                          withIcon: true,
                          action: snatchHandler.onShareCancel,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (isFirst)
              Obx(
                () => Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8),
                  child: Row(
                    children: [
                      if (snatchHandler.shareTotal.value != 0)
                        Text(
                          '${Tools.formatBytes(
                            snatchHandler.shareReceived.value,
                            2,
                            withSpace: false,
                          )}/${Tools.formatBytes(
                            snatchHandler.shareTotal.value,
                            2,
                            withSpace: false,
                          )}',
                          style: const TextStyle(fontSize: 16),
                        )
                      else
                        const SizedBox.shrink(),
                      const Spacer(),
                      if (snatchHandler.shareTotal.value != 0)
                        Text(
                          '${(snatchHandler.currentShareProgress * 100.0).toStringAsFixed(2)}%',
                          style: const TextStyle(fontSize: 16),
                        )
                      else
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
