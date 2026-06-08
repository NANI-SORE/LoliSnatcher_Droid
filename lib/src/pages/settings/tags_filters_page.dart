import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lolisnatcher/src/data/tag.dart';

import 'package:lolisnatcher/src/data/settings/setting_def.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_add_dialog.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_edit_dialog.dart';
import 'package:lolisnatcher/src/widgets/tags_filters/tf_list.dart';

class TagsFiltersPage extends StatefulWidget {
  const TagsFiltersPage({super.key});

  @override
  State<TagsFiltersPage> createState() => _TagsFiltersPageState();
}

class _TagsFiltersPageState extends State<TagsFiltersPage> with SingleTickerProviderStateMixin {
  final SettingsHandler settingsHandler = SettingsHandler.instance;

  late TabController tabController;
  final ScrollController scrollController = ScrollController();
  final TextEditingController tagSearchController = TextEditingController();

  List<String> hiddenList = [];
  List<String> markedList = [];

  @override
  void initState() {
    super.initState();

    hiddenList = [...SX.hiddenTags.value];
    hiddenList.sort(sortTags);

    markedList = [...SX.markedTags.value];
    markedList.sort(sortTags);

    tabController = TabController(vsync: this, length: 3)..addListener(updateState);
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    tagSearchController.dispose();
    tabController.removeListener(updateState);
    tabController.dispose();
    super.dispose();
  }

  Future<void> _onPopInvoked(_, _) async {
    final cleanedHidden = settingsHandler.cleanTagsList(hiddenList.map(Tag.new).toList());
    final cleanedMarked = settingsHandler.cleanTagsList(markedList.map(Tag.new).toList());
    SX.hiddenTags.state.value = cleanedHidden;
    SX.markedTags.state.value = cleanedMarked;
    await settingsHandler.saveSettings(restate: false);
  }

  List<String> getTagsList(String type) {
    List<String> tagsList = [];
    if (type == 'Hidden') {
      tagsList = hiddenList;
    } else if (type == 'Marked') {
      tagsList = markedList;
    }
    return tagsList;
  }

  int sortTags(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  void addTag(String newTag, String type) {
    if (newTag.isEmpty) {
      return;
    }

    final List<String> changedList = getTagsList(type);
    if (changedList.contains(newTag)) {
      duplicateMessage(newTag, type);
    } else {
      changedList.add(newTag);
      changedList.sort(sortTags);
      updateState();
    }
  }

  void editTag(String oldTag, String newTag, String type) {
    if (newTag.isEmpty) {
      return;
    }

    final List<String> changedList = getTagsList(type);
    if (changedList.contains(newTag)) {
      duplicateMessage(newTag, type);
    } else {
      final int index = changedList.indexOf(oldTag);
      changedList[index] = newTag;
      changedList.sort(sortTags);
      updateState();
    }
  }

  void deleteTag(String tag, String type) {
    final List<String> changedList = getTagsList(type);
    changedList.remove(tag);
    changedList.sort(sortTags);
    updateState();
  }

  void duplicateMessage(String tag, String type) {
    FlashElements.showSnackbar(
      context: context,
      title: Text(context.loc.settings.itemFilters.duplicateFilter, style: const TextStyle(fontSize: 20)),
      content: Text(
        context.loc.settings.itemFilters.alreadyInList(tag: tag, type: type),
        style: const TextStyle(fontSize: 16),
      ),
      leadingIcon: Icons.warning_amber,
      leadingIconColor: Colors.yellow,
      sideColor: Colors.yellow,
    );
  }

  void openAddDialog(String type) {
    SettingsPageOpen(
      context: context,
      asDialog: true,
      page: (_) => TagsFiltersAddDialog(
        tagFilterType: type,
        onAdd: (String newTag) => addTag(newTag, type),
      ),
    ).open();
  }

  void openEditDialog(String tag, String type) {
    SettingsPageOpen(
      context: context,
      asDialog: true,
      page: (_) => TagsFiltersEditDialog(
        tag: tag,
        onEdit: (String newTag) => editTag(tag, newTag, type),
        onDelete: (String tag) => deleteTag(tag, type),
      ),
    ).open();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(context.loc.settings.itemFilters.title),
          bottom: TabBar(
            controller: tabController,
            indicatorColor: Theme.of(context).colorScheme.secondary,
            onTap: (_) => tagSearchController.clear(),
            labelColor: Theme.of(context).appBarTheme.foregroundColor,
            unselectedLabelColor: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.5),
            labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 16),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                icon: const Icon(
                  CupertinoIcons.eye_slash,
                  size: 24,
                  color: Colors.red,
                ),
                height: 60,
                child: Center(
                  child: Text(context.loc.settings.itemFilters.hidden),
                ),
              ),
              Tab(
                icon: const Icon(
                  Icons.star,
                  size: 24,
                  color: Colors.yellow,
                ),
                height: 60,
                child: Text(context.loc.settings.itemFilters.marked),
              ),
              Tab(
                icon: Icon(
                  Icons.settings,
                  size: 24,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                height: 60,
                child: Text(context.loc.settings.title),
              ),
            ],
          ),
        ),
        floatingActionButton: tabController.index < 2
            ? FloatingActionButton(
                onPressed: () {
                  openAddDialog(tabController.index == 0 ? 'Hidden' : 'Marked');
                },
                child: const Icon(Icons.add),
              )
            : null,
        body: TabBarView(
          controller: tabController,
          children: [
            TagsFiltersList(
              tagsList: hiddenList,
              filterTagsType: 'Hidden',
              onTagSelected: (String tag) {
                openEditDialog(tag, 'Hidden');
              },
              onSearchTextChanged: (String newText) {
                updateState();
              },
              scrollController: scrollController,
              tagSearchController: tagSearchController,
              openAddDialog: () => openAddDialog('Hidden'),
            ),
            TagsFiltersList(
              tagsList: markedList,
              filterTagsType: 'Marked',
              onTagSelected: (String tag) {
                openEditDialog(tag, 'Marked');
              },
              onSearchTextChanged: (String newText) {
                updateState();
              },
              scrollController: scrollController,
              tagSearchController: tagSearchController,
              openAddDialog: () => openAddDialog('Marked'),
            ),
            ListView(
              controller: scrollController,
              children: [
                const SettingsButton(name: '', enabled: false),
                for (final state in SettingsRegistry.instance.byCategory(SettingCategory.tagsFilters))
                  if (state.def.widgetBuilder != null) state.buildWidget(context),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
