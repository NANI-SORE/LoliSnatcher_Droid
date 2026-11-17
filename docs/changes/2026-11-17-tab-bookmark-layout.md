# Saved-page bookmark layout

The tab selector keeps its saved-page bookmark beside the search query in one horizontal row, matching tab-manager items. The query receives the remaining width, retaining its existing downscaling/marquee behavior; the bookmark reserves its own 16-pixel width plus 3 pixels of spacing. Source names remain on the subtitle line.

The marker follows the existing reactive save-page setting and disappears without reserving space when saving is disabled. Fetching, page restoration, saved tab data, query coloring and tab-manager actions are unchanged. No settings or storage migration is required.

Validation: targeted analysis of `tab_selector.dart` passed with the pinned SDK on this branch and on the combined branch. Layout review confirmed finite horizontal constraints and the existing reactive update path. No new tests or APK were produced for this layout-only change.
