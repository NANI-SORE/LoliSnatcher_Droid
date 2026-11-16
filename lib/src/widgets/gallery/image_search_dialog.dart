import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

// TODO add more engines? ability to add custom ones?

class ImageSearchEngine {
  const ImageSearchEngine({
    required this.name,
    required this.favicon,
    required this.url,
  });

  final String name;
  final String favicon;
  final String url;
}

const List<ImageSearchEngine> imageSearchEngines = [
  ImageSearchEngine(
    name: 'Google Lens',
    favicon: 'https://www.google.com/s2/favicons?domain=lens.google.com',
    url: 'https://lens.google.com/uploadbyurl?url=<image_url>',
  ),
  ImageSearchEngine(
    name: 'Google',
    favicon: 'https://www.google.com/s2/favicons?domain=www.google.com',
    url: 'https://www.google.com/searchbyimage?client=app&image_url=<image_url>',
  ),
  ImageSearchEngine(
    name: 'Yandex',
    favicon: 'https://yandex.com/favicon.ico',
    url: 'https://yandex.com/images/search?rpt=imageview&url=<image_url>',
  ),
  ImageSearchEngine(
    name: 'SauceNAO',
    favicon: 'https://saucenao.com/favicon.ico',
    url: 'https://saucenao.com/search.php?db=999&url=<image_url>',
  ),
  ImageSearchEngine(
    name: 'ImgOps',
    favicon: 'https://imgops.com/favicon.ico',
    url: 'https://imgops.com/<image_url>',
  ),
];

Future<void> showImageSearchDialog(
  BuildContext context,
  String url, {
  BooruItem? item,
  Booru? booru,
}) async {
  final engine = await showModalBottomSheet<ImageSearchEngine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SettingsBottomSheet(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 72,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: item != null
                        ? Thumbnail(item: item, booru: booru, isStandalone: true, useHero: false)
                        : Image.network(
                            url,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) => progress == null
                                ? child
                                : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.loc.imageSearch.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          contentItems: [
            for (final engine in imageSearchEngines)
              ListTile(
                title: Text(engine.name),
                leading: SizedBox.square(
                  dimension: 24,
                  child: Image.network(
                    engine.favicon,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(Icons.image_search_outlined, size: 24),
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () => Navigator.of(context).pop(engine),
              ),
          ],
        ),
      );
    },
  );
  if (engine != null) {
    await launchUrlString(
      engine.url.replaceAll('<image_url>', url),
      mode: LaunchMode.externalApplication,
    );
  }
}
