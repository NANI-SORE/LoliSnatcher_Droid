import 'dart:math';

import 'package:flutter/material.dart';

import 'package:get/get.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';

/// Compact progress and cancellation shared by the gallery and page dialog.
class PageLoadingStatus extends StatelessWidget {
  const PageLoadingStatus({required this.tab, super.key});

  final SearchTab tab;

  @override
  Widget build(BuildContext context) {
    final search = SearchHandler.instance;
    return Obx(() {
      final target = search.autoSearchTargetPage.value;
      if (!search.isAutoSearchingTab(tab) || target == null) return const SizedBox.shrink();
      final page = max(tab.firstPage, min(target, search.pageNum.value));
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          Flexible(
            child: Text(
              context.loc.pageNavigation.loadingThrough(page: tab.displayPage(page), target: tab.displayPage(target)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: context.loc.pageNavigation.stopLoading,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            onPressed: () {
              if (search.isAutoSearchingTab(tab)) search.stopAutoSearch();
            },
          ),
        ],
      );
    });
  }
}
