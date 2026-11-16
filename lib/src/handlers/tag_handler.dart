import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:get_it/get_it.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/tag_type.dart';
import 'package:lolisnatcher/src/handlers/booru_handler.dart';
import 'package:lolisnatcher/src/handlers/booru_handler_factory.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/utils/logger.dart';

class UntypedCollection {
  UntypedCollection(this.tags, this.cooldown, this.booru);
  final List<String> tags;
  final int cooldown;
  final Booru booru;
}

class TagHandler {
  TagHandler() {
    untypedQueue.addListener(queueListener);
  }

  static TagHandler get instance => GetIt.instance<TagHandler>();

  static TagHandler register() {
    if (!GetIt.instance.isRegistered<TagHandler>()) {
      GetIt.instance.registerSingleton(
        TagHandler(),
        dispose: (tagHandler) => tagHandler.dispose(),
      );
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<TagHandler>();

  int prevLength = 0;
  final Map<String, Tag> _tagMap = {};
  Map<String, Tag> get tagMap => _tagMap; // TODO read only (or is it?)

  ValueNotifier<List<UntypedCollection>> untypedQueue = ValueNotifier([]);
  ValueNotifier<bool> tagFetchActive = ValueNotifier(false);
  bool tagSaveActive = false;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  Future<void> _tagSaveWrites = Future.value();

  Future<void> waitForTagSaves() => _tagSaveWrites;

  void queueListener() {
    tryGetTagTypes();
  }

  void dispose() {
    untypedQueue.removeListener(queueListener);
  }

  bool hasTag(String tagString) {
    return tagMap.containsKey(tagString.toLowerCase());
  }

  /// Check if tag is in the tag map and if it is - check if it is not outdated/stale
  bool hasTagAndNotStale(String tagString) {
    if (hasTag(tagString)) {
      return !getTag(tagString).isStale();
    } else {
      return false;
    }
  }

  Tag getTag(String tagString) {
    tagString = tagString.toLowerCase();
    Tag? tag;
    if (hasTag(tagString)) {
      tag = tagMap[tagString];
    }
    return tag ?? Tag(tagString, tagType: TagType.none);
  }

  Future<void> putTag(
    Tag tag, {
    required bool dbEnabled,
    required bool preferTypeIfNone,
    bool useDB = true,
  }) async {
    if (tag.fullString.trim().isEmpty) {
      return;
    }
    tag.fullString = tag.fullString.toLowerCase();
    if (preferTypeIfNone && hasTag(tag.fullString)) {
      if (getTag(tag.fullString).tagType != TagType.none && tag.tagType == TagType.none) {
        return;
      }
    }
    _tagMap[tag.fullString] = tag;

    if (dbEnabled && useDB && SearchHandler.instance.canBackup.value) {
      final write = _tagSaveWrites.then((_) async {
        if (SearchHandler.instance.canBackup.value) {
          await SettingsHandler.instance.dbHandler.updateTagsFromObjects([tag]);
        }
      });
      _tagSaveWrites = write.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          Logger.Inst().log(error, 'TagHandler', 'putTag', LogTypes.exception, s: stack);
        },
      );
      await write;
    }
    return;
  }

  void tryGetTagTypes() {
    if (!tagFetchActive.value) {
      if (untypedQueue.value.isNotEmpty) {
        getTagTypes(untypedQueue.value.removeLast());
      }
    }
  }

  Future getTagTypes(UntypedCollection untyped) async {
    if (SX.tagTypeFetchEnabled.value) {
      final bool dbEnabled = SX.dbEnabled.value;

      Logger.Inst().log('Snatching tags: ${untyped.tags}', 'TagHandler', 'getTagTypes', LogTypes.tagHandlerInfo);
      tagFetchActive.value = true;
      final temp = BooruHandlerFactory().getBooruHandler([untyped.booru], null);

      BooruHandler booruHandler = temp.booruHandler;
      if (booruHandler.shouldPopulateTags == false) {
        // if current booru doesn't support tag data, use other booru (if available) that supports it
        final boorusWithTagPopulation = SettingsHandler.instance.booruList.where(
          (b) => BooruHandlerFactory().getBooruHandler([b], null).booruHandler.shouldPopulateTags == true,
        );
        booruHandler = boorusWithTagPopulation.isEmpty
            ? booruHandler
            : BooruHandlerFactory().getBooruHandler([boorusWithTagPopulation.first], null).booruHandler;
      }

      int tagCounter = 0;
      while (untyped.tags.isNotEmpty) {
        final List<String> workingTags = [];
        const int tagMaxLimit = 100;
        final int tagMax = (untyped.tags.length > tagMaxLimit) ? tagMaxLimit : untyped.tags.length;

        for (int i = 0; i < tagMax; i++) {
          if (untyped.tags.isNotEmpty) {
            final String tag = untyped.tags.removeLast();
            if (!hasTagAndNotStale(tag) && !workingTags.contains(tag)) {
              workingTags.add(tag);
            }
          }
        }

        if (workingTags.isNotEmpty) {
          final List<Tag> newTags = await booruHandler.genTagObjects(workingTags);
          for (final Tag tag in newTags) {
            await putTag(
              tag,
              dbEnabled: dbEnabled,
              preferTypeIfNone: false,
            );

            //TODO write tag to database
            tagCounter++;
          }
          await Future.delayed(Duration(milliseconds: untyped.cooldown), () async {});
        }
      }
      Logger.Inst().log(
        'Got $tagCounter tag types, untyped list length was: ${untyped.tags.length}',
        'TagHandler',
        'getTagTypes',
        LogTypes.tagHandlerInfo,
      );
      tagFetchActive.value = false;
    }
    tryGetTagTypes();
  }

  /// Stores given tags list with given type, if tag is already in the tag map - update it's type, but only if the type was "none"
  Future<void> addTagsWithType(List<String> tags, TagType type) async {
    final dbEnabled = SX.dbEnabled.value;

    for (final String tag in tags) {
      if (!hasTagAndNotStale(tag)) {
        await putTag(
          Tag(tag, tagType: type),
          dbEnabled: dbEnabled,
          preferTypeIfNone: false,
        );
      } else if (type != TagType.none) {
        if (getTag(tag).tagType == TagType.none) {
          await putTag(
            Tag(tag, tagType: type),
            dbEnabled: dbEnabled,
            preferTypeIfNone: true,
          );
        }
      }
    }
  }

  void queue(List<String> untypedTags, Booru booru, int cooldown) {
    Logger.Inst().log(
      'Added ${untypedTags.length} tags to queue from ${booru.name}',
      'TagHandler',
      'queue',
      LogTypes.tagHandlerInfo,
    );
    if (untypedTags.isNotEmpty) {
      untypedQueue.value.add(UntypedCollection(untypedTags, cooldown, booru));
    }
  }

  Future<void> initialize() async {
    if (SettingsHandler.instance.path.isNotEmpty) {
      await loadTags();
    }
  }

  Future<bool> loadTags() async {
    try {
      final bool dbEnabled = SX.dbEnabled.value;
      if (dbEnabled) {
        final List<Tag> tags = await SettingsHandler.instance.dbHandler.getAllTags();
        for (final Tag tag in tags) {
          await putTag(
            tag,
            useDB: false,
            dbEnabled: dbEnabled,
            preferTypeIfNone: true,
          );
        }
      } else {
        if (await checkForTagsFile()) {
          await loadTagsFile();
        }
      }
      _isInitialized = true;
    } catch (e, s) {
      Logger.Inst().log(
        'Error loading tags: $e',
        'TagHandler',
        'loadTags',
        LogTypes.exception,
        s: s,
      );
      return false;
    }

    return true;
  }

  Future<bool> checkForTagsFile() {
    final File tagFile = File('${SettingsHandler.instance.path}tags.json');
    return tagFile.exists();
  }

  Future<void> loadTagsFile() async {
    final File tagFile = File('${SettingsHandler.instance.path}tags.json');
    final String jsonString = await tagFile.readAsString();
    if (!await loadFromJSON(jsonString)) throw const FormatException('Could not load saved tags');
    return;
  }

  Future<bool> loadFromJSON(
    String jsonString, {
    bool preferTagTypeIfNone = false,
    void Function(int progress, int total)? onProgress,
  }) async {
    try {
      final bool dbEnabled = SX.dbEnabled.value;

      final List jsonList = jsonDecode(jsonString);
      for (final Map<String, dynamic> rawTag in jsonList) {
        try {
          final Tag tagObject = Tag.fromJson(rawTag);
          await putTag(
            tagObject,
            preferTypeIfNone: preferTagTypeIfNone,
            dbEnabled: dbEnabled,
          );
          if (onProgress != null) {
            onProgress(jsonList.indexOf(rawTag), jsonList.length);
          }
          Logger.Inst().log(
            'Parsed tag: $rawTag',
            'TagHandler',
            'loadFromJSON',
            LogTypes.tagHandlerInfo,
          );
        } catch (e, s) {
          Logger.Inst().log(
            'Error parsing tag: $rawTag',
            'TagHandler',
            'loadFromJSON',
            LogTypes.exception,
            s: s,
          );
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'Error loading tags from JSON: $e',
        'TagHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  List<Tag> toList() {
    final List<Tag> tagList = [];
    tagMap.forEach((key, value) => tagList.add(value));
    return tagList;
  }

  void removeTag(Tag tag) {
    _tagMap.remove(tag.fullString);
  }

  Future<void> saveTags({bool duringRestore = false}) {
    final write = _tagSaveWrites.then((_) => _saveTags(duringRestore: duringRestore));
    _tagSaveWrites = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        Logger.Inst().log(error, 'TagHandler', 'saveTags', LogTypes.exception, s: stack);
      },
    );
    return write;
  }

  Future<void> _saveTags({required bool duringRestore}) async {
    if (!SearchHandler.instance.canBackup.value && !duringRestore) return;
    tagSaveActive = true;
    final SettingsHandler settings = SettingsHandler.instance;
    try {
      await getStoragePermission();
      if (!SearchHandler.instance.canBackup.value && !duringRestore) return;
      prevLength = tagMap.entries.length;
      if (!SX.dbEnabled.value) {
        if (settings.path == '') {
          await settings.setConfigDir();
        }
        await Directory(settings.path).create(recursive: true);
        final File tagFile = File('${settings.path}tags.json');
        final temporary = File('${tagFile.path}.tmp');
        await temporary.writeAsString(jsonEncode(toList()), flush: true);
        await temporary.rename(tagFile.path);
      }
    } catch (e, s) {
      Logger.Inst().log(
        'FAILED TO WRITE TAG FILE: $e',
        'TagHandler',
        'saveTags',
        LogTypes.exception,
        s: s,
      );
      if (duringRestore) rethrow;
    } finally {
      tagSaveActive = false;
    }
  }
}
