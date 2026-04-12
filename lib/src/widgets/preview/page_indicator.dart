import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/dialogs/page_number_dialog.dart';

class GridPageIndicator extends StatelessWidget {
  const GridPageIndicator(
    this.page, {
    super.key,
  });

  final int page;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 1,
        children: [
          Text(
            page.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Icon(
            Icons.insert_drive_file,
            size: 12,
          ),
        ],
      ),
    );
  }
}

class GridPageNumberOverlay extends StatefulWidget {
  const GridPageNumberOverlay({
    super.key,
  });

  @override
  State<GridPageNumberOverlay> createState() => _GridPageNumberOverlayState();
}

class _GridPageNumberOverlayState extends State<GridPageNumberOverlay> {
  final searchHandler = SearchHandler.instance;
  final settingsHandler = SettingsHandler.instance;

  Timer? overlayTimer;
  final RxBool showOverlay = false.obs;

  @override
  void initState() {
    super.initState();

    searchHandler.gridScrollController.addListener(_onPageChanged);

    ever(searchHandler.currentScrollPage, (_) => _onPageChanged());
  }

  void _onPageChanged() {
    showOverlay.value = true;
    overlayTimer?.cancel();
    overlayTimer = Timer(const Duration(milliseconds: 2500), () {
      showOverlay.value = false;
    });
  }

  @override
  void dispose() {
    overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final int page = searchHandler.currentScrollPage.value;
      final bool show = showOverlay.value && page > -1;

      return Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              enabled: !settingsHandler.shitDevice,
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: context.theme.colorScheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: show
                      ? () => SettingsPageOpen(
                          context: context,
                          asBottomSheet: true,
                          page: (_) => const PageNumberDialog(),
                        ).open()
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      spacing: 2,
                      children: [
                        Text(
                          page.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const Icon(
                          Icons.insert_drive_file,
                          size: 14,
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
