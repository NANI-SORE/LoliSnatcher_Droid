import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:alice_lightweight/alice.dart';
import 'package:alice_lightweight/helper/alice_save_helper.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:lolisnatcher/gen/strings.g.dart';
import 'package:lolisnatcher/src/boorus/booru_type.dart';
import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/data/settings/app_mode.dart';
import 'package:lolisnatcher/src/data/settings/video_backend_mode.dart';
import 'package:lolisnatcher/src/data/tag.dart';
import 'package:lolisnatcher/src/data/update_info.dart';
import 'package:lolisnatcher/src/handlers/database_handler.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/secure_storage_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/get_perms.dart';
import 'package:lolisnatcher/src/services/saf_file_cache.dart';
import 'package:lolisnatcher/src/utils/clipboard.dart';
import 'package:lolisnatcher/src/utils/dio_network.dart';
import 'package:lolisnatcher/src/utils/http_overrides.dart';
import 'package:lolisnatcher/src/utils/logger.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/data/settings/all_settings.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/data/settings/settings_registry.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';
import 'package:lolisnatcher/src/widgets/video/media_kit_video_player.dart';

// exporting localization here to avoid import repetition, since we use settingsHandler in a lot of places anyway
export 'package:lolisnatcher/gen/strings.g.dart';

/// This class is used loading from and writing settings to files
class SettingsHandler {
  static SettingsHandler get instance => GetIt.instance<SettingsHandler>();

  static SettingsHandler register() {
    if (!GetIt.instance.isRegistered<SettingsHandler>()) {
      GetIt.instance.registerSingleton(SettingsHandler());
    }
    return instance;
  }

  static void unregister() => GetIt.instance.unregister<SettingsHandler>();

  DBHandler dbHandler = DBHandler();

  late Alice alice;

  // service vars
  final RxBool isInit = false.obs, isPostInit = false.obs;
  final RxString postInitMessage = ''.obs;
  String cachePath = '';
  String path = '';
  String boorusPath = '';

  final Rx<UpdateInfo?> updateInfo = Rxn(null);

  ////////////////////////////////////////////////////

  // runtime settings vars
  bool hasHydrus = false;
  final RxString discordURL = RxString(Constants.discordURL);

  // debug toggles
  bool useImageLogging = false;
  bool blurImages = kDebugMode ? Constants.blurImagesDefaultDev : false;

  ////////////////////////////////////////////////////

  final RxList<Booru> booruList = RxList<Booru>([]);

  int tagsFiltersMetadataVersion = 0;
  int booruListVersion = 0;

  int currentColumnCount(BuildContext context) {
    return context.isPortrait ? SX.portraitColumns.value : SX.landscapeColumns.value;
  }

  Future<bool> loadFromJSON(String jsonString, bool setMissingKeys) async {
    Map<String, dynamic> json = {};
    try {
      json = jsonDecode(jsonString);
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to parse settings config $e',
        'SettingsHandler',
        'loadFromJSON',
        LogTypes.exception,
        s: s,
      );
    }

    // Handle legacy key renames before passing to registry
    if (json.containsKey('hatedTags') && !json.containsKey('hiddenTags')) {
      json['hiddenTags'] = json.remove('hatedTags');
    }
    if (json.containsKey('lovedTags') && !json.containsKey('markedTags')) {
      json['markedTags'] = json.remove('lovedTags');
    }

    SettingsRegistry.instance.loadFromJson(json);

    // Force mobile app mode until desktop UI is redone
    SX.appMode.state.value = AppMode.Mobile;

    return true;
  }

  Future<bool> loadSettings() async {
    if (path == '') {
      await setConfigDir();
    }
    if (cachePath == '') {
      cachePath = await ServiceHandler.getCacheDir();
    }

    // Register all setting definitions in the new registry (idempotent if already registered)
    if (SettingsRegistry.instance.isEmpty) {
      registerAllSettings();
    }

    if (await checkForSettings()) {
      await loadSettingsJson();
    } else {
      await saveSettings(restate: true);
    }
    return true;
  }

  Future<bool> loadDatabase(ValueChanged<String> onStatusUpdate) async {
    try {
      if (!Tools.isTestMode) {
        if (SX.dbEnabled.value) {
          await dbHandler.dbConnect(
            path,
            onStatusUpdate: onStatusUpdate,
          );
        } else {
          dbHandler = DBHandler();
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'loadDatabase error: $e',
        'SettingsHandler',
        'loadDatabase',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  Future<bool> indexDatabase() async {
    try {
      if (!Tools.isTestMode) {
        if (SX.dbEnabled.value) {
          if (SX.indexesEnabled.value) {
            postInitMessage.value = '${loc.settings.database.indexingDatabase}...\n${loc.thisMayTakeSomeTime}';
            await dbHandler.createIndexes();
          } else {
            postInitMessage.value = '${loc.settings.database.droppingIndexes}...\n${loc.thisMayTakeSomeTime}';
            await dbHandler.dropIndexes();
          }
        }
      }
      return true;
    } catch (e, s) {
      Logger.Inst().log(
        'indexDatabase error: $e',
        'SettingsHandler',
        'indexDatabase',
        LogTypes.exception,
        s: s,
      );
      return false;
    }
  }

  Future<bool> checkForSettings() {
    final File settingsFile = File('${path}settings.json');
    return settingsFile.exists();
  }

  Future<void> loadSettingsJson() async {
    final File settingsFile = File('${path}settings.json');
    final String settings = await settingsFile.readAsString();
    await loadFromJSON(settings, true);
  }

  Future<bool> saveSettings({required bool restate}) async {
    await getStoragePermission();
    if (path == '') {
      await setConfigDir();
    }
    await Directory(path).create(recursive: true);

    final json = SettingsRegistry.instance.toJson();
    json['version'] = Constants.updateInfo.versionName;
    json['build'] = Constants.updateInfo.buildNumber;

    final File settingsFile = File('${path}settings.json');
    final writer = settingsFile.openWrite();
    writer.write(jsonEncode(json));
    await writer.close();

    if (restate) {
      final searchHandler = SearchHandler.instance;
      searchHandler.filterCurrentFetched();
      unawaited(
        Future.delayed(const Duration(seconds: 1)).then((_) {
          searchHandler.rootRestate?.call();
        }),
      );
    }
    return true;
  }

  Future<bool> loadBoorus() async {
    final List<Booru> tempList = [];
    try {
      if (path == '') {
        await setConfigDir();
      }

      final Directory directory = Directory(boorusPath);
      List<FileSystemEntity> files = [];
      if (await directory.exists()) {
        files = await directory.list().toList();
      }

      if (files.isNotEmpty) {
        for (int i = 0; i < files.length; i++) {
          if (files[i].path.contains('.json')) {
            // && files[i].path != 'settings.json'
            // print(files[i].toString());
            final File booruFile = files[i] as File;
            final Booru booruFromFile = Booru.fromJSON(await booruFile.readAsString());
            final bool isAllowed = BooruType.saveable.contains(booruFromFile.type);
            if (isAllowed) {
              tempList.add(booruFromFile);
            } else {
              await booruFile.delete();
            }

            if (booruFromFile.type?.isHydrus == true) {
              hasHydrus = true;
            }
          }
        }
      }

      // Load per-booru setting overrides into the registry
      final registry = SettingsRegistry.instance;
      for (final booru in tempList) {
        if (booru.name != null && booru.settingOverrides != null) {
          registry.loadOverridesFromMap(booru.name!, booru.settingOverrides);
        }
      }

      if (SX.dbEnabled.value && tempList.isNotEmpty) {
        tempList.add(Booru(loc.favourites, BooruType.Favourites, '', '', ''));
        tempList.add(Booru(loc.downloads, BooruType.Downloads, '', '', ''));
      }
    } catch (e, s) {
      Logger.Inst().log(
        'Failed to load boorus $e',
        'SettingsHandler',
        'loadBoorus',
        LogTypes.exception,
        s: s,
      );
    }

    booruList.value = tempList
        .where((element) => !booruList.contains(element))
        .toList(); // filter due to possibility of duplicates
    booruListVersion++;

    if (tempList.isNotEmpty) {
      unawaited(sortBooruList());
    }
    return true;
  }

  Future<void> sortBooruList() async {
    final List<Booru> sorted = [
      ...booruList,
    ]; // spread the array just in case, to guarantee that we don't affect the original value
    sorted.sort((a, b) {
      // sort alphabetically
      return a.name!.toLowerCase().compareTo(b.name!.toLowerCase());
    });

    int prefIndex = 0;
    final pref = SX.prefBooru.value;
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i].name == pref && pref.isNotEmpty) {
        prefIndex = i;
        // print("prefIndex is" + prefIndex.toString());
      }
    }
    if (prefIndex != 0) {
      // move default booru to top
      // print("Booru pref found in booruList");
      final Booru tmp = sorted.elementAt(prefIndex);
      sorted.remove(tmp);
      sorted.insert(0, tmp);
      // print("booruList is");
      // print(sorted);
    }

    final int favsIndex = sorted.indexWhere((el) => el.type?.isFavourites == true);
    if (favsIndex != -1) {
      // move favourites to the end
      final Booru tmp = sorted.elementAt(favsIndex);
      sorted.remove(tmp);
      sorted.add(tmp);
    }

    final int dlsIndex = sorted.indexWhere((el) => el.type?.isDownloads == true);
    if (dlsIndex != -1) {
      // move downloads to the end
      final Booru tmp = sorted.elementAt(dlsIndex);
      sorted.remove(tmp);
      sorted.add(tmp);
    }

    booruList.value = sorted;
    booruListVersion++;
  }

  Future saveBooru(Booru booru, {bool onlySave = false}) async {
    if (path == '') {
      await setConfigDir();
    }

    // Sync per-booru setting overrides from registry back to the booru object
    if (booru.name != null) {
      booru.settingOverrides = SettingsRegistry.instance.saveOverridesToMap(booru.name!);
    }

    await Directory(boorusPath).create(recursive: true);
    final File booruFile = File('$boorusPath${booru.name}.json');
    final writer = booruFile.openWrite();
    writer.write(jsonEncode(booru.toJson()));
    await writer.close();

    if (!onlySave) {
      // used only to avoid duplication after migration to json format
      // TODO remove condition when migration logic is removed
      booruList.add(booru);
      booruListVersion++;
      unawaited(sortBooruList());
    }
    return true;
  }

  Future<bool> deleteBooru(Booru booru) async {
    final File booruFile = File('$boorusPath${booru.name}.json');
    await booruFile.delete();

    // Clean up in-memory per-booru setting overrides
    if (booru.name != null) {
      SettingsRegistry.instance.removeAllOverridesForBooru(booru.name!);
    }

    if (SX.prefBooru.value == booru.name) {
      SX.prefBooru.state.value = '';
      await saveSettings(restate: true);
    }
    booruList.remove(booru);
    booruListVersion++;
    unawaited(sortBooruList());
    return true;
  }

  // TODO add more tags?
  static const List<String> soundTags = [
    'sound',
    'sound_edit',
    'has_audio',
    'voice_acted',
  ];

  static const List<String> aiTags = [
    'ai_assisted',
    'ai-assisted',
    'ai_created',
    'ai-created',
    'ai_generated',
    'ai-generated',
    'novelai',
    'stable_diffusion',
    'stable-diffusion',
  ];

  TagsListData parseTagsList(List<Tag> itemTags, {bool isCapped = true}) {
    final List<String> cleanItemTags = cleanTagsList(itemTags);
    final hidden = SX.hiddenTags.value;
    final marked = SX.markedTags.value;
    List<String> hiddenInItem = cleanItemTags.where(hidden.contains).toList();
    List<String> markedInItem = cleanItemTags.where(marked.contains).toList();
    final List<String> soundInItem = soundTags.where(cleanItemTags.contains).toList();
    final List<String> aiInItem = aiTags.where(cleanItemTags.contains).toList();

    if (isCapped) {
      if (hiddenInItem.length > 5) {
        hiddenInItem = [...hiddenInItem.take(5), '...'];
      }
      if (markedInItem.length > 5) {
        markedInItem = [...markedInItem.take(5), '...'];
      }
    }

    return TagsListData(hiddenInItem, markedInItem, soundInItem, aiInItem);
  }

  bool containsHidden(List<String> itemTags) {
    return itemTags.any(SX.hiddenTags.value.contains);
  }

  bool containsMarked(List<String> itemTags) {
    return itemTags.any(SX.markedTags.value.contains);
  }

  bool containsSound(List<String> itemTags) {
    return itemTags.any(soundTags.contains);
  }

  bool containsAI(List<String> itemTags) {
    return itemTags.any(aiTags.contains);
  }

  void addTagToList(String type, String tag) {
    bool changed = false;
    switch (type) {
      case 'hated':
      case 'hidden':
        changed = true;
        SX.hiddenTags.state.value = [...SX.hiddenTags.value, tag];
        break;
      case 'loved':
      case 'marked':
        changed = true;
        SX.markedTags.state.value = [...SX.markedTags.value, tag];
        break;
      default:
        break;
    }
    if (changed) {
      tagsFiltersMetadataVersion++;
    }
    saveSettings(restate: false);
  }

  void removeTagFromList(String type, String tag) {
    bool changed = false;
    switch (type) {
      case 'hated':
      case 'hidden':
        changed = true;
        SX.hiddenTags.state.value = SX.hiddenTags.value.where((t) => t != tag).toList();
        break;
      case 'loved':
      case 'marked':
        changed = true;
        SX.markedTags.state.value = SX.markedTags.value.where((t) => t != tag).toList();
        break;
      default:
        break;
    }
    if (changed) {
      tagsFiltersMetadataVersion++;
    }
    saveSettings(restate: false);
  }

  List<String> cleanTagsList(List<Tag> tags) {
    List<String> cleanTags = [];
    cleanTags = tags
        .where((tag) => tag.fullString.isNotEmpty)
        .map((tag) => tag.fullString.trim().toLowerCase())
        .toList();
    cleanTags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cleanTags;
  }

  Future<void> checkUpdate({bool withMessage = false}) async {
    if (Tools.isTestMode) {
      return;
    }

    // const String fakeUpdate = '123'; // for tests // broken string
    // const Map<String, dynamic> = {}; // for tests // full json here

    try {
      const String updateFileName = EnvironmentConfig.isFromStore ? 'update_store.json' : 'update.json';
      final response = await DioNetwork.get(
        'https://raw.githubusercontent.com/NO-ob/LoliSnatcher_Droid/master/$updateFileName',
      );
      final json = response.data is String ? jsonDecode(response.data) : (response.data is Map ? response.data : {});
      if (json is Map && json.isEmpty) {
        throw Exception('Update file is empty');
      }

      try {
        Logger.Inst().log(
          jsonEncode(json),
          'SettingsHandler',
          'checkUpdate',
          LogTypes.settingsError,
        );
      } catch (_) {}

      updateInfo.value = UpdateInfo(
        versionName: json['version_name'] ?? '0.0.0',
        buildNumber: json['build_number'] ?? 0,
        title: json['title'] ?? '...',
        changelog: json['changelog'] ?? '...',
        isInStore: json['is_in_store'] ?? false,
        isImportant: json['is_important'] ?? false,
        storePackage: json['store_package'] ?? '',
        githubURL: json['github_url'] ?? 'https://github.com/NO-ob/LoliSnatcher_Droid/releases/latest',
      );

      final String? discordFromGithub = json['discord_url'];
      if (discordFromGithub != null && discordFromGithub.isNotEmpty) {
        // overwrite included discord url if it's not the same as the one in update info
        if (discordFromGithub != discordURL.value) {
          discordURL.value = discordFromGithub;
        }
      }

      if (Constants.updateInfo.buildNumber < (updateInfo.value!.buildNumber)) {
        // if current build number is less than update build number in json
        if (EnvironmentConfig.isFromStore) {
          // installed from store
          if (updateInfo.value!.isInStore) {
            // app is still in store
            showUpdate(withMessage || updateInfo.value!.isImportant);
          } else {
            // app was removed from store
            // then always notify user so they can move to github version and get news about removal
            showUpdate(true);
          }
        } else {
          // installed from github
          showUpdate(withMessage || updateInfo.value!.isImportant);
        }
      } else {
        final secureStorageHandler = SecureStorageHandler.instance;
        final viewedAtBuild = int.tryParse(
          await secureStorageHandler.read(SecureStorageKey.viewedUpdateChangelogForBuild) ?? '',
        );
        if (booruList.isEmpty) {
          // don't bother new (no boorus) users until next update
          await secureStorageHandler.write(
            SecureStorageKey.viewedUpdateChangelogForBuild,
            Constants.updateInfo.buildNumber.toString(),
          );
        } else if (viewedAtBuild == null || viewedAtBuild < Constants.updateInfo.buildNumber) {
          await secureStorageHandler.write(
            SecureStorageKey.viewedUpdateChangelogForBuild,
            Constants.updateInfo.buildNumber.toString(),
          );
          showUpdate(true, isAfterUpdate: true);
        } else {
          if (withMessage) {
            // otherwise show latest version message
            showLastVersionMessage();
          }
        }
      }
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'checkUpdate',
        LogTypes.settingsError,
        s: s,
      );
      if (withMessage) {
        FlashElements.showSnackbar(
          title: Text(
            loc.settings.checkForUpdates.updateCheckError,
            style: const TextStyle(fontSize: 20),
          ),
          content: Text(
            e.toString(),
          ),
          sideColor: Colors.red,
          leadingIcon: Icons.update,
          leadingIconColor: Colors.red,
        );
      }
    }
  }

  void showLastVersionMessage() {
    FlashElements.showSnackbar(
      title: Text(
        loc.settings.checkForUpdates.youHaveLatestVersion,
        style: const TextStyle(fontSize: 20),
      ),
      sideColor: Colors.green,
      leadingIcon: Icons.update,
      leadingIconColor: Colors.green,
      actionsBuilder: (context, controller) {
        return [
          ElevatedButton.icon(
            onPressed: () {
              controller.dismiss();
              showUpdate(
                true,
                isAfterUpdate: true,
              );
            },
            icon: const Icon(Icons.list_alt_rounded),
            label: Text(
              loc.settings.checkForUpdates.viewLatestChangelog,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ];
      },
    );
  }

  void showUpdate(
    bool showMessage, {
    bool isAfterUpdate = false,
  }) {
    // ignore: no_leading_underscores_for_local_identifiers
    final _updateInfo = isAfterUpdate ? Constants.updateInfo : updateInfo.value;
    if (showMessage && _updateInfo != null) {
      const bool isFromStore = EnvironmentConfig.isFromStore;

      final bool isDiffVersion = Constants.updateInfo.buildNumber < _updateInfo.buildNumber;

      final ctx = NavigationHandler.instance.navContext;

      SettingsPageOpen(
        context: ctx,
        page: (_) => Scaffold(
          appBar: SettingsAppBar(
            title:
                '${isDiffVersion ? loc.settings.checkForUpdates.updateAvailable : '${isAfterUpdate ? loc.settings.checkForUpdates.whatsNew : loc.settings.checkForUpdates.updateChangelog}:'} ${_updateInfo.versionName}+${_updateInfo.buildNumber}',
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isDiffVersion) ...[
                          Text(
                            '${loc.settings.checkForUpdates.currentVersion}: ${Constants.updateInfo.versionName}+${Constants.updateInfo.buildNumber}',
                          ),
                          const Text(''),
                        ],
                        Text(
                          _updateInfo.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(''),
                        Text(
                          loc.settings.checkForUpdates.changelog,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(''),
                        Text(_updateInfo.changelog),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.close),
                        label: Text(isDiffVersion ? loc.later : loc.close),
                      ),
                      const SizedBox(width: 16),
                      if (isFromStore && _updateInfo.isInStore)
                        ElevatedButton.icon(
                          onPressed: () {
                            // try {
                            //   launchUrlString("market://details?id=" + _updateInfo.storePackage);
                            // } on PlatformException catch(e) {
                            //   launchUrlString("https://play.google.com/store/apps/details?id=" + _updateInfo.storePackage);
                            // }
                            launchUrlString(
                              'https://play.google.com/store/apps/details?id=${_updateInfo.storePackage}',
                              mode: LaunchMode.externalApplication,
                            );
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(loc.settings.checkForUpdates.visitPlayStore),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () {
                            launchUrlString(
                              _updateInfo.githubURL,
                              mode: LaunchMode.externalApplication,
                            );
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.exit_to_app),
                          label: Text(loc.settings.checkForUpdates.visitReleases),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).open();
    }
  }

  Future<void> setConfigDir() async {
    // print('-=-=-=-=-=-=-=-');
    // print(Platform.environment);
    path = await ServiceHandler.getConfigDir();
    boorusPath = '${path}boorus/';
    return;
  }

  Future<void> setLocale(AppLocale? locale) async {
    if (locale == null) {
      await LocaleSettings.useDeviceLocale();
    } else {
      await LocaleSettings.setLocale(locale);
    }
  }

  Future<void> initialize() async {
    if (isInit.value == true) {
      return;
    }

    try {
      await getStoragePermission();
      await loadSettings();
      await Logger.setLogcatCaptureEnabled(SX.captureLogcat.value);
      await setLocale(SX.locale.value);
    } catch (e, s) {
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'initialize',
        LogTypes.settingsError,
        s: s,
      );
      FlashElements.showSnackbar(
        title: Text(
          loc.init.initError,
          style: const TextStyle(fontSize: 20),
        ),
        content: Text(
          e.toString(),
        ),
        sideColor: Colors.red,
        leadingIcon: Icons.error,
        leadingIconColor: Colors.red,
      );
    }
    print('isFromStore: ${EnvironmentConfig.isFromStore}');

    // print('=-=-=-=-=-=-=-=-=-=-=-=-=');
    // print(toJSON());
    // print(jsonEncode(toJSON()));

    alice = Alice(
      quickShareAction: Platform.isWindows
          ? (call) async {
              await ClipboardUtils.copyTextToClipboard(
                await AliceSaveHelper.buildCallLog(call),
              );
            }
          : null,
    );

    if (Platform.isAndroid && SX.extPathOverride.value.isNotEmpty) {
      unawaited(SAFFileCache.instance.populate(SX.extPathOverride.value));
    }

    isInit.value = true;
    return;
  }

  Future<void> postInit(AsyncCallback externalAction) async {
    if (isPostInit.value == true) {
      return;
    }

    try {
      postInitMessage.value = loc.init.settingUpProxy;
      await initProxy();

      switch (SX.videoBackendMode.value) {
        case VideoBackendMode.normal:
          MediaKitVideoPlayer.registerNative();
          break;
        case VideoBackendMode.mpv:
          MediaKitVideoPlayer.registerWith();
          break;
        case VideoBackendMode.mdk:
          fvp.registerWith();
          break;
      }

      postInitMessage.value = loc.init.loadingDatabase;
      await loadDatabase((newStatus) {
        postInitMessage.value = 'Fixing data in the database...\nThis may take some time\n$newStatus';
      });
      await indexDatabase();
      if (booruList.isEmpty) {
        postInitMessage.value = loc.init.loadingBoorus;
        await loadBoorus();
      }
      await externalAction();
    } catch (e, s) {
      postInitMessage.value = loc.errorExclamation;
      Logger.Inst().log(
        e.toString(),
        'SettingsHandler',
        'postInit',
        LogTypes.settingsError,
        s: s,
      );
      FlashElements.showSnackbar(
        title: Text(
          loc.init.initError,
          style: const TextStyle(fontSize: 20),
        ),
        content: Text(
          e.toString(),
        ),
        sideColor: Colors.red,
        leadingIcon: Icons.error,
        leadingIconColor: Colors.red,
      );
    }

    unawaited(checkUpdate(withMessage: false));

    isPostInit.value = true;
    postInitMessage.value = '';
    return;
  }
}

class EnvironmentConfig {
  static const bool isFromStore = bool.fromEnvironment(
    'LS_IS_STORE',
    defaultValue: false,
  );

  static const bool isTesting = bool.fromEnvironment(
    'LS_IS_TESTING',
    defaultValue: false,
  );
}

class TagsListData {
  const TagsListData([
    this.hiddenTags = const [],
    this.markedTags = const [],
    this.soundTags = const [],
    this.aiTags = const [],
  ]);

  final List<String> hiddenTags;
  final List<String> markedTags;
  final List<String> soundTags;
  final List<String> aiTags;
}
