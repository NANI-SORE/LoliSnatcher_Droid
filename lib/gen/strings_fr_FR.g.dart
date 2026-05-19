///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'package:slang/overrides.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsFrFr extends Translations with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  /// [AppLocaleUtils.buildWithOverrides] is recommended for overriding.
  TranslationsFrFr({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : $meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.frFr,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
    super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
    $meta.setFlatMapFunction(_flatMapFunction);
  }

  /// Metadata for the translations of <fr-FR>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  /// Access flat map
  @override
  dynamic operator [](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

  late final TranslationsFrFr _root = this; // ignore: unused_field

  @override
  TranslationsFrFr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsFrFr(meta: meta ?? this.$meta);

  // Translations
  @override
  String get locale => TranslationOverrides.string(_root.$meta, 'locale', {}) ?? 'fr-FR';
  @override
  String get localeName => TranslationOverrides.string(_root.$meta, 'localeName', {}) ?? 'Français';
  @override
  String get appName => TranslationOverrides.string(_root.$meta, 'appName', {}) ?? 'LoliSnatcher';
  @override
  String get error => TranslationOverrides.string(_root.$meta, 'error', {}) ?? 'Erreur';
  @override
  String get errorExclamation => TranslationOverrides.string(_root.$meta, 'errorExclamation', {}) ?? 'Erreur !';
  @override
  String get success => TranslationOverrides.string(_root.$meta, 'success', {}) ?? 'Succès';
  @override
  String get successExclamation => TranslationOverrides.string(_root.$meta, 'successExclamation', {}) ?? 'Succès !';
  @override
  String get cancel => TranslationOverrides.string(_root.$meta, 'cancel', {}) ?? 'Annuler';
  @override
  String get kReturn => TranslationOverrides.string(_root.$meta, 'kReturn', {}) ?? 'Retour';
  @override
  String get later => TranslationOverrides.string(_root.$meta, 'later', {}) ?? 'Plus tard';
  @override
  String get close => TranslationOverrides.string(_root.$meta, 'close', {}) ?? 'Fermer';
  @override
  String get ok => TranslationOverrides.string(_root.$meta, 'ok', {}) ?? 'OK';
  @override
  String get yes => TranslationOverrides.string(_root.$meta, 'yes', {}) ?? 'Oui';
  @override
  String get no => TranslationOverrides.string(_root.$meta, 'no', {}) ?? 'Non';
  @override
  String get pleaseWait => TranslationOverrides.string(_root.$meta, 'pleaseWait', {}) ?? 'Veuillez patienter...';
  @override
  String get show => TranslationOverrides.string(_root.$meta, 'show', {}) ?? 'Montrer';
  @override
  String get hide => TranslationOverrides.string(_root.$meta, 'hide', {}) ?? 'Cacher';
  @override
  String get enable => TranslationOverrides.string(_root.$meta, 'enable', {}) ?? 'Activer';
  @override
  String get disable => TranslationOverrides.string(_root.$meta, 'disable', {}) ?? 'Désactiver';
  @override
  String get add => TranslationOverrides.string(_root.$meta, 'add', {}) ?? 'Ajouter';
  @override
  String get edit => TranslationOverrides.string(_root.$meta, 'edit', {}) ?? 'Modifier';
  @override
  String get delete => TranslationOverrides.string(_root.$meta, 'delete', {}) ?? 'Supprimer';
  @override
  String get confirm => TranslationOverrides.string(_root.$meta, 'confirm', {}) ?? 'Confirmer';
  @override
  String get copied => TranslationOverrides.string(_root.$meta, 'copied', {}) ?? 'Copié';
  @override
  String get copiedToClipboard => TranslationOverrides.string(_root.$meta, 'copiedToClipboard', {}) ?? 'Copié dans le presse-papiers';
  @override
  String get booru => TranslationOverrides.string(_root.$meta, 'booru', {}) ?? 'Booru';
  @override
  String get goToSettings => TranslationOverrides.string(_root.$meta, 'goToSettings', {}) ?? 'Allez dans les paramètres';
  @override
  String get exitTheAppQuestion => TranslationOverrides.string(_root.$meta, 'exitTheAppQuestion', {}) ?? 'Quitter l\'application ?';
  @override
  String get invalidUrl => TranslationOverrides.string(_root.$meta, 'invalidUrl', {}) ?? 'URL invalide !';
  @override
  String get clipboardIsEmpty => TranslationOverrides.string(_root.$meta, 'clipboardIsEmpty', {}) ?? 'Le presse-papiers est vide !';
  @override
  String get apiKey => TranslationOverrides.string(_root.$meta, 'apiKey', {}) ?? 'Clé API';
  @override
  String get password => TranslationOverrides.string(_root.$meta, 'password', {}) ?? 'Mot de passe';
  @override
  String get pause => TranslationOverrides.string(_root.$meta, 'pause', {}) ?? 'Pause';
  @override
  String get resume => TranslationOverrides.string(_root.$meta, 'resume', {}) ?? 'Reprendre';
  @override
  String get discord => TranslationOverrides.string(_root.$meta, 'discord', {}) ?? 'Discord';
  @override
  String get visitOurDiscord => TranslationOverrides.string(_root.$meta, 'visitOurDiscord', {}) ?? 'Visitez notre serveur Discord';
  @override
  String get item => TranslationOverrides.string(_root.$meta, 'item', {}) ?? 'Objet';
  @override
  String get select => TranslationOverrides.string(_root.$meta, 'select', {}) ?? 'Sélectionner';
  @override
  String get selectAll => TranslationOverrides.string(_root.$meta, 'selectAll', {}) ?? 'Tout sélectionner';
  @override
  String get reset => TranslationOverrides.string(_root.$meta, 'reset', {}) ?? 'Réinitialiser';
  @override
  String get open => TranslationOverrides.string(_root.$meta, 'open', {}) ?? 'Ouvrir';
  @override
  String get openInNewTab => TranslationOverrides.string(_root.$meta, 'openInNewTab', {}) ?? 'Ouvrir dans un nouvel onglet';
  @override
  String get move => TranslationOverrides.string(_root.$meta, 'move', {}) ?? 'Déplacer';
  @override
  String get shuffle => TranslationOverrides.string(_root.$meta, 'shuffle', {}) ?? 'Mélanger';
  @override
  String get sort => TranslationOverrides.string(_root.$meta, 'sort', {}) ?? 'Trier';
  @override
  String get search => TranslationOverrides.string(_root.$meta, 'search', {}) ?? 'Rechercher';
  @override
  String get filter => TranslationOverrides.string(_root.$meta, 'filter', {}) ?? 'Filtre';
  @override
  String get page => TranslationOverrides.string(_root.$meta, 'page', {}) ?? 'Page';
  @override
  String get pageNumber => TranslationOverrides.string(_root.$meta, 'pageNumber', {}) ?? 'Page n°';
  @override
  String get tags => TranslationOverrides.string(_root.$meta, 'tags', {}) ?? 'Tags';
  @override
  String get type => TranslationOverrides.string(_root.$meta, 'type', {}) ?? 'Type';
  @override
  String get name => TranslationOverrides.string(_root.$meta, 'name', {}) ?? 'Nom';
  @override
  String get address => TranslationOverrides.string(_root.$meta, 'address', {}) ?? 'Adresse';
  @override
  String get username => TranslationOverrides.string(_root.$meta, 'username', {}) ?? 'Nom d\'utilisateur';
  @override
  String get favourites => TranslationOverrides.string(_root.$meta, 'favourites', {}) ?? 'Favoris';
  @override
  String get downloads => TranslationOverrides.string(_root.$meta, 'downloads', {}) ?? 'Téléchargements';
  @override
  late final _TranslationsValidationErrorsFrFr validationErrors = _TranslationsValidationErrorsFrFr._(_root);
  @override
  late final _TranslationsInitFrFr init = _TranslationsInitFrFr._(_root);
  @override
  late final _TranslationsPermissionsFrFr permissions = _TranslationsPermissionsFrFr._(_root);
  @override
  late final _TranslationsAuthenticationFrFr authentication = _TranslationsAuthenticationFrFr._(_root);
  @override
  late final _TranslationsSearchHandlerFrFr searchHandler = _TranslationsSearchHandlerFrFr._(_root);
  @override
  late final _TranslationsSnatcherFrFr snatcher = _TranslationsSnatcherFrFr._(_root);
  @override
  late final _TranslationsMultibooruFrFr multibooru = _TranslationsMultibooruFrFr._(_root);
  @override
  late final _TranslationsHydrusFrFr hydrus = _TranslationsHydrusFrFr._(_root);
  @override
  late final _TranslationsTabsFrFr tabs = _TranslationsTabsFrFr._(_root);
  @override
  late final _TranslationsHistoryFrFr history = _TranslationsHistoryFrFr._(_root);
  @override
  late final _TranslationsSettingsFrFr settings = _TranslationsSettingsFrFr._(_root);
  @override
  late final _TranslationsLockscreenFrFr lockscreen = _TranslationsLockscreenFrFr._(_root);
  @override
  late final _TranslationsLoliSyncFrFr loliSync = _TranslationsLoliSyncFrFr._(_root);
  @override
  late final _TranslationsTagViewFrFr tagView = _TranslationsTagViewFrFr._(_root);
  @override
  late final _TranslationsMediaFrFr media = _TranslationsMediaFrFr._(_root);
  @override
  late final _TranslationsPreviewFrFr preview = _TranslationsPreviewFrFr._(_root);
}

// Path: validationErrors
class _TranslationsValidationErrorsFrFr extends TranslationsValidationErrorsEn {
  _TranslationsValidationErrorsFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get required => TranslationOverrides.string(_root.$meta, 'validationErrors.required', {}) ?? 'Veuillez saisir une valeur';
  @override
  String get invalid => TranslationOverrides.string(_root.$meta, 'validationErrors.invalid', {}) ?? 'Veuillez saisir une valeur valide';
  @override
  String get invalidNumber => TranslationOverrides.string(_root.$meta, 'validationErrors.invalidNumber', {}) ?? 'Veuillez saisir un nombre';
  @override
  String get invalidNumericValue =>
      TranslationOverrides.string(_root.$meta, 'validationErrors.invalidNumericValue', {}) ?? 'Veuillez saisir une valeur numérique valide';
  @override
  String get greaterThanOrEqualZero =>
      TranslationOverrides.string(_root.$meta, 'validationErrors.greaterThanOrEqualZero', {}) ?? 'Veuillez saisir une valeur égale ou supérieure à 0';
  @override
  String get lessThan4 => TranslationOverrides.string(_root.$meta, 'validationErrors.lessThan4', {}) ?? 'Veuillez saisir une valeur inférieure à 4';
  @override
  String get biggerThan100 =>
      TranslationOverrides.string(_root.$meta, 'validationErrors.biggerThan100', {}) ?? 'Veuillez saisir une valeur supérieure à 100';
  @override
  String get moreThan4ColumnsWarning =>
      TranslationOverrides.string(_root.$meta, 'validationErrors.moreThan4ColumnsWarning', {}) ??
      'Utiliser plus de 4 colonnes peut affecter les performances';
  @override
  String get moreThan8ColumnsWarning =>
      TranslationOverrides.string(_root.$meta, 'validationErrors.moreThan8ColumnsWarning', {}) ??
      'Utiliser plus de 8 colonnes peut affecter les performances';
}

// Path: init
class _TranslationsInitFrFr extends TranslationsInitEn {
  _TranslationsInitFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get initError => TranslationOverrides.string(_root.$meta, 'init.initError', {}) ?? 'Erreur d\'initialisation !';
  @override
  String get settingUpProxy => TranslationOverrides.string(_root.$meta, 'init.settingUpProxy', {}) ?? 'Configuration du proxy…';
  @override
  String get loadingDatabase => TranslationOverrides.string(_root.$meta, 'init.loadingDatabase', {}) ?? 'Chargement de la base de données…';
  @override
  String get restoringTabs => TranslationOverrides.string(_root.$meta, 'init.restoringTabs', {}) ?? 'Restauration des onglets…';
}

// Path: permissions
class _TranslationsPermissionsFrFr extends TranslationsPermissionsEn {
  _TranslationsPermissionsFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get noAccessToCustomStorageDirectory =>
      TranslationOverrides.string(_root.$meta, 'permissions.noAccessToCustomStorageDirectory', {}) ??
      'Aucun accès au répertoire de stockage personnalisé';
  @override
  String get pleaseSetStorageDirectoryAgain =>
      TranslationOverrides.string(_root.$meta, 'permissions.pleaseSetStorageDirectoryAgain', {}) ??
      'Veuillez redéfinir le répertoire de stockage pour autoriser l\'application à y accéder';
  @override
  String get setDirectory => TranslationOverrides.string(_root.$meta, 'permissions.setDirectory', {}) ?? 'Définir le répertoire';
  @override
  String get currentlyNotAvailableForThisPlatform =>
      TranslationOverrides.string(_root.$meta, 'permissions.currentlyNotAvailableForThisPlatform', {}) ?? 'Non disponible sur cette plateforme';
  @override
  String get resetDirectory => TranslationOverrides.string(_root.$meta, 'permissions.resetDirectory', {}) ?? 'Réinitialiser le répertoire';
  @override
  String get afterResetFilesWillBeSavedToDefaultDirectory =>
      TranslationOverrides.string(_root.$meta, 'permissions.afterResetFilesWillBeSavedToDefaultDirectory', {}) ??
      'Les fichiers seront enregistrés dans le répertoire par défaut après la réinitialisation';
}

// Path: authentication
class _TranslationsAuthenticationFrFr extends TranslationsAuthenticationEn {
  _TranslationsAuthenticationFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get pleaseAuthenticateToUseTheApp =>
      TranslationOverrides.string(_root.$meta, 'authentication.pleaseAuthenticateToUseTheApp', {}) ??
      'Veuillez vous authentifier pour utiliser l\'application';
  @override
  String get noBiometricHardwareAvailable =>
      TranslationOverrides.string(_root.$meta, 'authentication.noBiometricHardwareAvailable', {}) ?? 'Aucun matériel biométrique disponible';
  @override
  String get temporaryLockout => TranslationOverrides.string(_root.$meta, 'authentication.temporaryLockout', {}) ?? 'Verrouillage temporaire';
}

// Path: searchHandler
class _TranslationsSearchHandlerFrFr extends TranslationsSearchHandlerEn {
  _TranslationsSearchHandlerFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get removedLastTab => TranslationOverrides.string(_root.$meta, 'searchHandler.removedLastTab', {}) ?? 'Onglet précédent supprimé';
  @override
  String get uoh => TranslationOverrides.string(_root.$meta, 'searchHandler.uoh', {}) ?? 'UOOOOOOOHHH';
  @override
  String get tabsRestored => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsRestored', {}) ?? 'Onglets restaurés';
  @override
  String get someRestoredTabsHadIssues =>
      TranslationOverrides.string(_root.$meta, 'searchHandler.someRestoredTabsHadIssues', {}) ??
      'Certains onglets restaurés contenaient des boorus inconnus ou des caractères cassés.';
  @override
  String get tabsMerged => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsMerged', {}) ?? 'Onglets fusionnés';
  @override
  String get tabsReplaced => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsReplaced', {}) ?? 'Onglets remplacés';
}

// Path: snatcher
class _TranslationsSnatcherFrFr extends TranslationsSnatcherEn {
  _TranslationsSnatcherFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get delayInMs => TranslationOverrides.string(_root.$meta, 'snatcher.delayInMs', {}) ?? 'Délai (en ms)';
  @override
  String get delayBetweenEachDownload =>
      TranslationOverrides.string(_root.$meta, 'snatcher.delayBetweenEachDownload', {}) ?? 'Délai entre chaque téléchargement';
  @override
  String get doNotCloseApp => TranslationOverrides.string(_root.$meta, 'snatcher.doNotCloseApp', {}) ?? 'Ne fermez pas l\'application !';
}

// Path: multibooru
class _TranslationsMultibooruFrFr extends TranslationsMultibooruEn {
  _TranslationsMultibooruFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'multibooru.title', {}) ?? 'Multibooru';
  @override
  String get multibooruMode => TranslationOverrides.string(_root.$meta, 'multibooru.multibooruMode', {}) ?? 'Mode multibooru';
  @override
  String get multibooruRequiresAtLeastTwoBoorus =>
      TranslationOverrides.string(_root.$meta, 'multibooru.multibooruRequiresAtLeastTwoBoorus', {}) ?? 'Nécessite au moins 2 boorus configurés';
}

// Path: hydrus
class _TranslationsHydrusFrFr extends TranslationsHydrusEn {
  _TranslationsHydrusFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get addUrls => TranslationOverrides.string(_root.$meta, 'hydrus.addUrls', {}) ?? 'Ajouter des URL';
}

// Path: tabs
class _TranslationsTabsFrFr extends TranslationsTabsEn {
  _TranslationsTabsFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get tab => TranslationOverrides.string(_root.$meta, 'tabs.tab', {}) ?? 'Onglet';
  @override
  String get selectABooru => TranslationOverrides.string(_root.$meta, 'tabs.selectABooru', {}) ?? 'Sélectionnez un Booru';
  @override
  String get secondaryBoorus => TranslationOverrides.string(_root.$meta, 'tabs.secondaryBoorus', {}) ?? 'Booru secondaire';
  @override
  String get addNewTab => TranslationOverrides.string(_root.$meta, 'tabs.addNewTab', {}) ?? 'Ajouter un nouvel onglet';
  @override
  String get selectABooruOrLeaveEmpty =>
      TranslationOverrides.string(_root.$meta, 'tabs.selectABooruOrLeaveEmpty', {}) ?? 'Sélectionnez un booru ou laissez vide';
  @override
  String get addModePrevTab => TranslationOverrides.string(_root.$meta, 'tabs.addModePrevTab', {}) ?? 'Onglet précédent';
  @override
  String get addModeNextTab => TranslationOverrides.string(_root.$meta, 'tabs.addModeNextTab', {}) ?? 'Onglet suivant';
  @override
  String get queryModeDefault => TranslationOverrides.string(_root.$meta, 'tabs.queryModeDefault', {}) ?? 'Défaut';
  @override
  String get customQuery => TranslationOverrides.string(_root.$meta, 'tabs.customQuery', {}) ?? 'Requête personnalisée';
  @override
  String get empty => TranslationOverrides.string(_root.$meta, 'tabs.empty', {}) ?? '[vide]';
  @override
  String get switchToNewTab => TranslationOverrides.string(_root.$meta, 'tabs.switchToNewTab', {}) ?? 'Passer à un nouvel onglet';
  @override
  String get add => TranslationOverrides.string(_root.$meta, 'tabs.add', {}) ?? 'Ajouter';
  @override
  String get tabsManager => TranslationOverrides.string(_root.$meta, 'tabs.tabsManager', {}) ?? 'Gestionnaire d\'onglets';
  @override
  String get sortMode => TranslationOverrides.string(_root.$meta, 'tabs.sortMode', {}) ?? 'Trier les onglets';
  @override
  String get help => TranslationOverrides.string(_root.$meta, 'tabs.help', {}) ?? 'Aide';
  @override
  String get deleteTabs => TranslationOverrides.string(_root.$meta, 'tabs.deleteTabs', {}) ?? 'Supprimer les onglets';
  @override
  String get shuffleTabs => TranslationOverrides.string(_root.$meta, 'tabs.shuffleTabs', {}) ?? 'Mélanger les onglets';
  @override
  String get tabRandomlyShuffled => TranslationOverrides.string(_root.$meta, 'tabs.tabRandomlyShuffled', {}) ?? 'Onglet mélangé aléatoirement';
  @override
  String get scrollToCurrent => TranslationOverrides.string(_root.$meta, 'tabs.scrollToCurrent', {}) ?? 'Défilez jusqu\'à l\'onglet actuel';
  @override
  String get sortAlphabetically => TranslationOverrides.string(_root.$meta, 'tabs.sortAlphabetically', {}) ?? 'Trier par ordre alphabétique';
  @override
  String get sortAlphabeticallyReversed =>
      TranslationOverrides.string(_root.$meta, 'tabs.sortAlphabeticallyReversed', {}) ?? 'Trier par ordre alphabétique (inversé)';
  @override
  String get longPressSortToSave =>
      TranslationOverrides.string(_root.$meta, 'tabs.longPressSortToSave', {}) ??
      'Appuyez longuement sur le bouton de tri pour enregistrer l\'ordre actuel';
  @override
  String get deleteSelectedTabs => TranslationOverrides.string(_root.$meta, 'tabs.deleteSelectedTabs', {}) ?? 'Supprimer les onglets sélectionnés';
  @override
  String get longPressToMove =>
      TranslationOverrides.string(_root.$meta, 'tabs.longPressToMove', {}) ?? 'Appuyez longuement sur un onglet pour le déplacer';
  @override
  String get noTabsFound => TranslationOverrides.string(_root.$meta, 'tabs.noTabsFound', {}) ?? 'Aucun onglet trouvé';
  @override
  late final _TranslationsTabsFiltersFrFr filters = _TranslationsTabsFiltersFrFr._(_root);
}

// Path: history
class _TranslationsHistoryFrFr extends TranslationsHistoryEn {
  _TranslationsHistoryFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get unknownBooruType => TranslationOverrides.string(_root.$meta, 'history.unknownBooruType', {}) ?? 'Type de Booru inconnu !';
}

// Path: settings
class _TranslationsSettingsFrFr extends TranslationsSettingsEn {
  _TranslationsSettingsFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.title', {}) ?? 'Paramètres';
  @override
  late final _TranslationsSettingsLanguageFrFr language = _TranslationsSettingsLanguageFrFr._(_root);
  @override
  late final _TranslationsSettingsBooruFrFr booru = _TranslationsSettingsBooruFrFr._(_root);
  @override
  late final _TranslationsSettingsInterfaceFrFr interface = _TranslationsSettingsInterfaceFrFr._(_root);
  @override
  late final _TranslationsSettingsThemeFrFr theme = _TranslationsSettingsThemeFrFr._(_root);
  @override
  late final _TranslationsSettingsViewerFrFr viewer = _TranslationsSettingsViewerFrFr._(_root);
  @override
  late final _TranslationsSettingsVideoFrFr video = _TranslationsSettingsVideoFrFr._(_root);
  @override
  late final _TranslationsSettingsBackupAndRestoreFrFr backupAndRestore = _TranslationsSettingsBackupAndRestoreFrFr._(_root);
  @override
  late final _TranslationsSettingsNetworkFrFr network = _TranslationsSettingsNetworkFrFr._(_root);
  @override
  late final _TranslationsSettingsPrivacyFrFr privacy = _TranslationsSettingsPrivacyFrFr._(_root);
  @override
  late final _TranslationsSettingsPerformanceFrFr performance = _TranslationsSettingsPerformanceFrFr._(_root);
  @override
  late final _TranslationsSettingsItemFiltersFrFr itemFilters = _TranslationsSettingsItemFiltersFrFr._(_root);
  @override
  late final _TranslationsSettingsSyncFrFr sync = _TranslationsSettingsSyncFrFr._(_root);
  @override
  late final _TranslationsSettingsCheckForUpdatesFrFr checkForUpdates = _TranslationsSettingsCheckForUpdatesFrFr._(_root);
  @override
  late final _TranslationsSettingsHelpFrFr help = _TranslationsSettingsHelpFrFr._(_root);
  @override
  late final _TranslationsSettingsDirPickerFrFr dirPicker = _TranslationsSettingsDirPickerFrFr._(_root);
  @override
  String get version => TranslationOverrides.string(_root.$meta, 'settings.version', {}) ?? 'Version';
}

// Path: lockscreen
class _TranslationsLockscreenFrFr extends TranslationsLockscreenEn {
  _TranslationsLockscreenFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get tapToAuthenticate => TranslationOverrides.string(_root.$meta, 'lockscreen.tapToAuthenticate', {}) ?? 'Appuyez pour vous authentifier';
}

// Path: loliSync
class _TranslationsLoliSyncFrFr extends TranslationsLoliSyncEn {
  _TranslationsLoliSyncFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get waitingForConnection => TranslationOverrides.string(_root.$meta, 'loliSync.waitingForConnection', {}) ?? 'En attente de connexion…';
}

// Path: tagView
class _TranslationsTagViewFrFr extends TranslationsTagViewEn {
  _TranslationsTagViewFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get tapToTryAgain => TranslationOverrides.string(_root.$meta, 'tagView.tapToTryAgain', {}) ?? 'Appuyez pour réessayer';
}

// Path: media
class _TranslationsMediaFrFr extends TranslationsMediaEn {
  _TranslationsMediaFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  late final _TranslationsMediaLoadingFrFr loading = _TranslationsMediaLoadingFrFr._(_root);
  @override
  late final _TranslationsMediaVideoFrFr video = _TranslationsMediaVideoFrFr._(_root);
}

// Path: preview
class _TranslationsPreviewFrFr extends TranslationsPreviewEn {
  _TranslationsPreviewFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  late final _TranslationsPreviewErrorFrFr error = _TranslationsPreviewErrorFrFr._(_root);
}

// Path: tabs.filters
class _TranslationsTabsFiltersFrFr extends TranslationsTabsFiltersEn {
  _TranslationsTabsFiltersFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'tabs.filters.title', {}) ?? 'Filtres d\'onglets';
}

// Path: settings.language
class _TranslationsSettingsLanguageFrFr extends TranslationsSettingsLanguageEn {
  _TranslationsSettingsLanguageFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.language.title', {}) ?? 'Langue';
  @override
  String get helpUsTranslate => TranslationOverrides.string(_root.$meta, 'settings.language.helpUsTranslate', {}) ?? 'Aidez-nous à traduire';
  @override
  String get visitForDetails =>
      TranslationOverrides.string(_root.$meta, 'settings.language.visitForDetails', {}) ??
      'Visitez <a href=\'https://github.com/NO-ob/LoliSnatcher_Droid/blob/master/CONTRIBUTING.md#localization--translations\'>github</a> pour plus de détails ou appuyez sur l\'image ci-dessous pour accéder à POEditor';
}

// Path: settings.booru
class _TranslationsSettingsBooruFrFr extends TranslationsSettingsBooruEn {
  _TranslationsSettingsBooruFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.booru.title', {}) ?? 'Boorus et Recherche';
}

// Path: settings.interface
class _TranslationsSettingsInterfaceFrFr extends TranslationsSettingsInterfaceEn {
  _TranslationsSettingsInterfaceFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.interface.title', {}) ?? 'Interface';
}

// Path: settings.theme
class _TranslationsSettingsThemeFrFr extends TranslationsSettingsThemeEn {
  _TranslationsSettingsThemeFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.theme.title', {}) ?? 'Thèmes';
  @override
  String get themeMode => TranslationOverrides.string(_root.$meta, 'settings.theme.themeMode', {}) ?? 'Mode du thème';
  @override
  String get theme => TranslationOverrides.string(_root.$meta, 'settings.theme.theme', {}) ?? 'Thème';
  @override
  String get viewMoreFonts => TranslationOverrides.string(_root.$meta, 'settings.theme.viewMoreFonts', {}) ?? 'Afficher plus de polices';
}

// Path: settings.viewer
class _TranslationsSettingsViewerFrFr extends TranslationsSettingsViewerEn {
  _TranslationsSettingsViewerFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get zoomButtonPosition => TranslationOverrides.string(_root.$meta, 'settings.viewer.zoomButtonPosition', {}) ?? 'Position du bouton de zoom';
  @override
  String get toolbarButtonsOrder =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.toolbarButtonsOrder', {}) ?? 'Ordre des boutons de la barre d\'outils';
  @override
  String get thisButtonCannotBeDisabled =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.thisButtonCannotBeDisabled', {}) ?? 'Ce bouton ne peut pas être désactivé';
  @override
  String get useVolumeButtonsForScrolling =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.useVolumeButtonsForScrolling', {}) ??
      'Utilisez les boutons de volume pour faire défiler';
  @override
  String get volumeButtonsScrollSpeed =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.volumeButtonsScrollSpeed', {}) ?? 'Vitesse de défilement des boutons de volume';
  @override
  String get usingDefaultAnimation =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.usingDefaultAnimation', {}) ?? 'Utilisation de l\'animation par défaut';
  @override
  String get usingCustomAnimation =>
      TranslationOverrides.string(_root.$meta, 'settings.viewer.usingCustomAnimation', {}) ?? 'Utilisation de l\'animation personnalisée';
  @override
  late final _TranslationsSettingsViewerScrollDirectionValuesFrFr scrollDirectionValues = _TranslationsSettingsViewerScrollDirectionValuesFrFr._(
    _root,
  );
}

// Path: settings.video
class _TranslationsSettingsVideoFrFr extends TranslationsSettingsVideoEn {
  _TranslationsSettingsVideoFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.video.title', {}) ?? 'Vidéo';
}

// Path: settings.backupAndRestore
class _TranslationsSettingsBackupAndRestoreFrFr extends TranslationsSettingsBackupAndRestoreEn {
  _TranslationsSettingsBackupAndRestoreFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.backupAndRestore.title', {}) ?? 'Sauvegarde et Restauration';
}

// Path: settings.network
class _TranslationsSettingsNetworkFrFr extends TranslationsSettingsNetworkEn {
  _TranslationsSettingsNetworkFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.network.title', {}) ?? 'Réseau';
}

// Path: settings.privacy
class _TranslationsSettingsPrivacyFrFr extends TranslationsSettingsPrivacyEn {
  _TranslationsSettingsPrivacyFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.privacy.title', {}) ?? 'Confidentialité';
}

// Path: settings.performance
class _TranslationsSettingsPerformanceFrFr extends TranslationsSettingsPerformanceEn {
  _TranslationsSettingsPerformanceFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.performance.title', {}) ?? 'Performance';
}

// Path: settings.itemFilters
class _TranslationsSettingsItemFiltersFrFr extends TranslationsSettingsItemFiltersEn {
  _TranslationsSettingsItemFiltersFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.itemFilters.title', {}) ?? 'Filtres';
}

// Path: settings.sync
class _TranslationsSettingsSyncFrFr extends TranslationsSettingsSyncEn {
  _TranslationsSettingsSyncFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get testConnection => TranslationOverrides.string(_root.$meta, 'settings.sync.testConnection', {}) ?? 'Test de connexion';
}

// Path: settings.checkForUpdates
class _TranslationsSettingsCheckForUpdatesFrFr extends TranslationsSettingsCheckForUpdatesEn {
  _TranslationsSettingsCheckForUpdatesFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get updateAvailable =>
      TranslationOverrides.string(_root.$meta, 'settings.checkForUpdates.updateAvailable', {}) ?? 'Mise à jour disponible !';
  @override
  String get youHaveLatestVersion =>
      TranslationOverrides.string(_root.$meta, 'settings.checkForUpdates.youHaveLatestVersion', {}) ?? 'Vous disposez de la dernière version';
}

// Path: settings.help
class _TranslationsSettingsHelpFrFr extends TranslationsSettingsHelpEn {
  _TranslationsSettingsHelpFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get title => TranslationOverrides.string(_root.$meta, 'settings.help.title', {}) ?? 'Aide';
}

// Path: settings.dirPicker
class _TranslationsSettingsDirPickerFrFr extends TranslationsSettingsDirPickerEn {
  _TranslationsSettingsDirPickerFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get yes => TranslationOverrides.string(_root.$meta, 'settings.dirPicker.yes', {}) ?? 'Oui';
}

// Path: media.loading
class _TranslationsMediaLoadingFrFr extends TranslationsMediaLoadingEn {
  _TranslationsMediaLoadingFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  late final _TranslationsMediaLoadingStopReasonsFrFr stopReasons = _TranslationsMediaLoadingStopReasonsFrFr._(_root);
}

// Path: media.video
class _TranslationsMediaVideoFrFr extends TranslationsMediaVideoEn {
  _TranslationsMediaVideoFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get videosDisabledOrNotSupported =>
      TranslationOverrides.string(_root.$meta, 'media.video.videosDisabledOrNotSupported', {}) ?? 'Vidéos désactivées ou non prises en charge';
}

// Path: preview.error
class _TranslationsPreviewErrorFrFr extends TranslationsPreviewErrorEn {
  _TranslationsPreviewErrorFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get tapToRetryIfStuck =>
      TranslationOverrides.string(_root.$meta, 'preview.error.tapToRetryIfStuck', {}) ??
      'Appuyez pour réessayer si la requête semble bloquée ou prend trop de temps';
  @override
  String get errorWithMessage => TranslationOverrides.string(_root.$meta, 'preview.error.errorWithMessage', {}) ?? 'Appuyez ici pour réessayer';
  @override
  String get tapToRetry => TranslationOverrides.string(_root.$meta, 'preview.error.tapToRetry', {}) ?? 'Appuyez ici pour réessayer';
}

// Path: settings.viewer.scrollDirectionValues
class _TranslationsSettingsViewerScrollDirectionValuesFrFr extends TranslationsSettingsViewerScrollDirectionValuesEn {
  _TranslationsSettingsViewerScrollDirectionValuesFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get vertical => TranslationOverrides.string(_root.$meta, 'settings.viewer.scrollDirectionValues.vertical', {}) ?? 'Vertical';
}

// Path: media.loading.stopReasons
class _TranslationsMediaLoadingStopReasonsFrFr extends TranslationsMediaLoadingStopReasonsEn {
  _TranslationsMediaLoadingStopReasonsFrFr._(TranslationsFrFr root) : this._root = root, super.internal(root);

  final TranslationsFrFr _root; // ignore: unused_field

  // Translations
  @override
  String get videoError => TranslationOverrides.string(_root.$meta, 'media.loading.stopReasons.videoError', {}) ?? 'Erreur vidéo';
}

/// The flat map containing all translations for locale <fr-FR>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsFrFr {
  dynamic _flatMapFunction(String path) {
    return switch (path) {
      'locale' => TranslationOverrides.string(_root.$meta, 'locale', {}) ?? 'fr-FR',
      'localeName' => TranslationOverrides.string(_root.$meta, 'localeName', {}) ?? 'Français',
      'appName' => TranslationOverrides.string(_root.$meta, 'appName', {}) ?? 'LoliSnatcher',
      'error' => TranslationOverrides.string(_root.$meta, 'error', {}) ?? 'Erreur',
      'errorExclamation' => TranslationOverrides.string(_root.$meta, 'errorExclamation', {}) ?? 'Erreur !',
      'success' => TranslationOverrides.string(_root.$meta, 'success', {}) ?? 'Succès',
      'successExclamation' => TranslationOverrides.string(_root.$meta, 'successExclamation', {}) ?? 'Succès !',
      'cancel' => TranslationOverrides.string(_root.$meta, 'cancel', {}) ?? 'Annuler',
      'kReturn' => TranslationOverrides.string(_root.$meta, 'kReturn', {}) ?? 'Retour',
      'later' => TranslationOverrides.string(_root.$meta, 'later', {}) ?? 'Plus tard',
      'close' => TranslationOverrides.string(_root.$meta, 'close', {}) ?? 'Fermer',
      'ok' => TranslationOverrides.string(_root.$meta, 'ok', {}) ?? 'OK',
      'yes' => TranslationOverrides.string(_root.$meta, 'yes', {}) ?? 'Oui',
      'no' => TranslationOverrides.string(_root.$meta, 'no', {}) ?? 'Non',
      'pleaseWait' => TranslationOverrides.string(_root.$meta, 'pleaseWait', {}) ?? 'Veuillez patienter...',
      'show' => TranslationOverrides.string(_root.$meta, 'show', {}) ?? 'Montrer',
      'hide' => TranslationOverrides.string(_root.$meta, 'hide', {}) ?? 'Cacher',
      'enable' => TranslationOverrides.string(_root.$meta, 'enable', {}) ?? 'Activer',
      'disable' => TranslationOverrides.string(_root.$meta, 'disable', {}) ?? 'Désactiver',
      'add' => TranslationOverrides.string(_root.$meta, 'add', {}) ?? 'Ajouter',
      'edit' => TranslationOverrides.string(_root.$meta, 'edit', {}) ?? 'Modifier',
      'delete' => TranslationOverrides.string(_root.$meta, 'delete', {}) ?? 'Supprimer',
      'confirm' => TranslationOverrides.string(_root.$meta, 'confirm', {}) ?? 'Confirmer',
      'copied' => TranslationOverrides.string(_root.$meta, 'copied', {}) ?? 'Copié',
      'copiedToClipboard' => TranslationOverrides.string(_root.$meta, 'copiedToClipboard', {}) ?? 'Copié dans le presse-papiers',
      'booru' => TranslationOverrides.string(_root.$meta, 'booru', {}) ?? 'Booru',
      'goToSettings' => TranslationOverrides.string(_root.$meta, 'goToSettings', {}) ?? 'Allez dans les paramètres',
      'exitTheAppQuestion' => TranslationOverrides.string(_root.$meta, 'exitTheAppQuestion', {}) ?? 'Quitter l\'application ?',
      'invalidUrl' => TranslationOverrides.string(_root.$meta, 'invalidUrl', {}) ?? 'URL invalide !',
      'clipboardIsEmpty' => TranslationOverrides.string(_root.$meta, 'clipboardIsEmpty', {}) ?? 'Le presse-papiers est vide !',
      'apiKey' => TranslationOverrides.string(_root.$meta, 'apiKey', {}) ?? 'Clé API',
      'password' => TranslationOverrides.string(_root.$meta, 'password', {}) ?? 'Mot de passe',
      'pause' => TranslationOverrides.string(_root.$meta, 'pause', {}) ?? 'Pause',
      'resume' => TranslationOverrides.string(_root.$meta, 'resume', {}) ?? 'Reprendre',
      'discord' => TranslationOverrides.string(_root.$meta, 'discord', {}) ?? 'Discord',
      'visitOurDiscord' => TranslationOverrides.string(_root.$meta, 'visitOurDiscord', {}) ?? 'Visitez notre serveur Discord',
      'item' => TranslationOverrides.string(_root.$meta, 'item', {}) ?? 'Objet',
      'select' => TranslationOverrides.string(_root.$meta, 'select', {}) ?? 'Sélectionner',
      'selectAll' => TranslationOverrides.string(_root.$meta, 'selectAll', {}) ?? 'Tout sélectionner',
      'reset' => TranslationOverrides.string(_root.$meta, 'reset', {}) ?? 'Réinitialiser',
      'open' => TranslationOverrides.string(_root.$meta, 'open', {}) ?? 'Ouvrir',
      'openInNewTab' => TranslationOverrides.string(_root.$meta, 'openInNewTab', {}) ?? 'Ouvrir dans un nouvel onglet',
      'move' => TranslationOverrides.string(_root.$meta, 'move', {}) ?? 'Déplacer',
      'shuffle' => TranslationOverrides.string(_root.$meta, 'shuffle', {}) ?? 'Mélanger',
      'sort' => TranslationOverrides.string(_root.$meta, 'sort', {}) ?? 'Trier',
      'search' => TranslationOverrides.string(_root.$meta, 'search', {}) ?? 'Rechercher',
      'filter' => TranslationOverrides.string(_root.$meta, 'filter', {}) ?? 'Filtre',
      'page' => TranslationOverrides.string(_root.$meta, 'page', {}) ?? 'Page',
      'pageNumber' => TranslationOverrides.string(_root.$meta, 'pageNumber', {}) ?? 'Page n°',
      'tags' => TranslationOverrides.string(_root.$meta, 'tags', {}) ?? 'Tags',
      'type' => TranslationOverrides.string(_root.$meta, 'type', {}) ?? 'Type',
      'name' => TranslationOverrides.string(_root.$meta, 'name', {}) ?? 'Nom',
      'address' => TranslationOverrides.string(_root.$meta, 'address', {}) ?? 'Adresse',
      'username' => TranslationOverrides.string(_root.$meta, 'username', {}) ?? 'Nom d\'utilisateur',
      'favourites' => TranslationOverrides.string(_root.$meta, 'favourites', {}) ?? 'Favoris',
      'downloads' => TranslationOverrides.string(_root.$meta, 'downloads', {}) ?? 'Téléchargements',
      'validationErrors.required' => TranslationOverrides.string(_root.$meta, 'validationErrors.required', {}) ?? 'Veuillez saisir une valeur',
      'validationErrors.invalid' => TranslationOverrides.string(_root.$meta, 'validationErrors.invalid', {}) ?? 'Veuillez saisir une valeur valide',
      'validationErrors.invalidNumber' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.invalidNumber', {}) ?? 'Veuillez saisir un nombre',
      'validationErrors.invalidNumericValue' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.invalidNumericValue', {}) ?? 'Veuillez saisir une valeur numérique valide',
      'validationErrors.greaterThanOrEqualZero' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.greaterThanOrEqualZero', {}) ??
            'Veuillez saisir une valeur égale ou supérieure à 0',
      'validationErrors.lessThan4' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.lessThan4', {}) ?? 'Veuillez saisir une valeur inférieure à 4',
      'validationErrors.biggerThan100' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.biggerThan100', {}) ?? 'Veuillez saisir une valeur supérieure à 100',
      'validationErrors.moreThan4ColumnsWarning' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.moreThan4ColumnsWarning', {}) ??
            'Utiliser plus de 4 colonnes peut affecter les performances',
      'validationErrors.moreThan8ColumnsWarning' =>
        TranslationOverrides.string(_root.$meta, 'validationErrors.moreThan8ColumnsWarning', {}) ??
            'Utiliser plus de 8 colonnes peut affecter les performances',
      'init.initError' => TranslationOverrides.string(_root.$meta, 'init.initError', {}) ?? 'Erreur d\'initialisation !',
      'init.settingUpProxy' => TranslationOverrides.string(_root.$meta, 'init.settingUpProxy', {}) ?? 'Configuration du proxy…',
      'init.loadingDatabase' => TranslationOverrides.string(_root.$meta, 'init.loadingDatabase', {}) ?? 'Chargement de la base de données…',
      'init.restoringTabs' => TranslationOverrides.string(_root.$meta, 'init.restoringTabs', {}) ?? 'Restauration des onglets…',
      'permissions.noAccessToCustomStorageDirectory' =>
        TranslationOverrides.string(_root.$meta, 'permissions.noAccessToCustomStorageDirectory', {}) ??
            'Aucun accès au répertoire de stockage personnalisé',
      'permissions.pleaseSetStorageDirectoryAgain' =>
        TranslationOverrides.string(_root.$meta, 'permissions.pleaseSetStorageDirectoryAgain', {}) ??
            'Veuillez redéfinir le répertoire de stockage pour autoriser l\'application à y accéder',
      'permissions.setDirectory' => TranslationOverrides.string(_root.$meta, 'permissions.setDirectory', {}) ?? 'Définir le répertoire',
      'permissions.currentlyNotAvailableForThisPlatform' =>
        TranslationOverrides.string(_root.$meta, 'permissions.currentlyNotAvailableForThisPlatform', {}) ?? 'Non disponible sur cette plateforme',
      'permissions.resetDirectory' => TranslationOverrides.string(_root.$meta, 'permissions.resetDirectory', {}) ?? 'Réinitialiser le répertoire',
      'permissions.afterResetFilesWillBeSavedToDefaultDirectory' =>
        TranslationOverrides.string(_root.$meta, 'permissions.afterResetFilesWillBeSavedToDefaultDirectory', {}) ??
            'Les fichiers seront enregistrés dans le répertoire par défaut après la réinitialisation',
      'authentication.pleaseAuthenticateToUseTheApp' =>
        TranslationOverrides.string(_root.$meta, 'authentication.pleaseAuthenticateToUseTheApp', {}) ??
            'Veuillez vous authentifier pour utiliser l\'application',
      'authentication.noBiometricHardwareAvailable' =>
        TranslationOverrides.string(_root.$meta, 'authentication.noBiometricHardwareAvailable', {}) ?? 'Aucun matériel biométrique disponible',
      'authentication.temporaryLockout' =>
        TranslationOverrides.string(_root.$meta, 'authentication.temporaryLockout', {}) ?? 'Verrouillage temporaire',
      'searchHandler.removedLastTab' => TranslationOverrides.string(_root.$meta, 'searchHandler.removedLastTab', {}) ?? 'Onglet précédent supprimé',
      'searchHandler.uoh' => TranslationOverrides.string(_root.$meta, 'searchHandler.uoh', {}) ?? 'UOOOOOOOHHH',
      'searchHandler.tabsRestored' => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsRestored', {}) ?? 'Onglets restaurés',
      'searchHandler.someRestoredTabsHadIssues' =>
        TranslationOverrides.string(_root.$meta, 'searchHandler.someRestoredTabsHadIssues', {}) ??
            'Certains onglets restaurés contenaient des boorus inconnus ou des caractères cassés.',
      'searchHandler.tabsMerged' => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsMerged', {}) ?? 'Onglets fusionnés',
      'searchHandler.tabsReplaced' => TranslationOverrides.string(_root.$meta, 'searchHandler.tabsReplaced', {}) ?? 'Onglets remplacés',
      'snatcher.delayInMs' => TranslationOverrides.string(_root.$meta, 'snatcher.delayInMs', {}) ?? 'Délai (en ms)',
      'snatcher.delayBetweenEachDownload' =>
        TranslationOverrides.string(_root.$meta, 'snatcher.delayBetweenEachDownload', {}) ?? 'Délai entre chaque téléchargement',
      'snatcher.doNotCloseApp' => TranslationOverrides.string(_root.$meta, 'snatcher.doNotCloseApp', {}) ?? 'Ne fermez pas l\'application !',
      'multibooru.title' => TranslationOverrides.string(_root.$meta, 'multibooru.title', {}) ?? 'Multibooru',
      'multibooru.multibooruMode' => TranslationOverrides.string(_root.$meta, 'multibooru.multibooruMode', {}) ?? 'Mode multibooru',
      'multibooru.multibooruRequiresAtLeastTwoBoorus' =>
        TranslationOverrides.string(_root.$meta, 'multibooru.multibooruRequiresAtLeastTwoBoorus', {}) ?? 'Nécessite au moins 2 boorus configurés',
      'hydrus.addUrls' => TranslationOverrides.string(_root.$meta, 'hydrus.addUrls', {}) ?? 'Ajouter des URL',
      'tabs.tab' => TranslationOverrides.string(_root.$meta, 'tabs.tab', {}) ?? 'Onglet',
      'tabs.selectABooru' => TranslationOverrides.string(_root.$meta, 'tabs.selectABooru', {}) ?? 'Sélectionnez un Booru',
      'tabs.secondaryBoorus' => TranslationOverrides.string(_root.$meta, 'tabs.secondaryBoorus', {}) ?? 'Booru secondaire',
      'tabs.addNewTab' => TranslationOverrides.string(_root.$meta, 'tabs.addNewTab', {}) ?? 'Ajouter un nouvel onglet',
      'tabs.selectABooruOrLeaveEmpty' =>
        TranslationOverrides.string(_root.$meta, 'tabs.selectABooruOrLeaveEmpty', {}) ?? 'Sélectionnez un booru ou laissez vide',
      'tabs.addModePrevTab' => TranslationOverrides.string(_root.$meta, 'tabs.addModePrevTab', {}) ?? 'Onglet précédent',
      'tabs.addModeNextTab' => TranslationOverrides.string(_root.$meta, 'tabs.addModeNextTab', {}) ?? 'Onglet suivant',
      'tabs.queryModeDefault' => TranslationOverrides.string(_root.$meta, 'tabs.queryModeDefault', {}) ?? 'Défaut',
      'tabs.customQuery' => TranslationOverrides.string(_root.$meta, 'tabs.customQuery', {}) ?? 'Requête personnalisée',
      'tabs.empty' => TranslationOverrides.string(_root.$meta, 'tabs.empty', {}) ?? '[vide]',
      'tabs.switchToNewTab' => TranslationOverrides.string(_root.$meta, 'tabs.switchToNewTab', {}) ?? 'Passer à un nouvel onglet',
      'tabs.add' => TranslationOverrides.string(_root.$meta, 'tabs.add', {}) ?? 'Ajouter',
      'tabs.tabsManager' => TranslationOverrides.string(_root.$meta, 'tabs.tabsManager', {}) ?? 'Gestionnaire d\'onglets',
      'tabs.sortMode' => TranslationOverrides.string(_root.$meta, 'tabs.sortMode', {}) ?? 'Trier les onglets',
      'tabs.help' => TranslationOverrides.string(_root.$meta, 'tabs.help', {}) ?? 'Aide',
      'tabs.deleteTabs' => TranslationOverrides.string(_root.$meta, 'tabs.deleteTabs', {}) ?? 'Supprimer les onglets',
      'tabs.shuffleTabs' => TranslationOverrides.string(_root.$meta, 'tabs.shuffleTabs', {}) ?? 'Mélanger les onglets',
      'tabs.tabRandomlyShuffled' => TranslationOverrides.string(_root.$meta, 'tabs.tabRandomlyShuffled', {}) ?? 'Onglet mélangé aléatoirement',
      'tabs.scrollToCurrent' => TranslationOverrides.string(_root.$meta, 'tabs.scrollToCurrent', {}) ?? 'Défilez jusqu\'à l\'onglet actuel',
      'tabs.sortAlphabetically' => TranslationOverrides.string(_root.$meta, 'tabs.sortAlphabetically', {}) ?? 'Trier par ordre alphabétique',
      'tabs.sortAlphabeticallyReversed' =>
        TranslationOverrides.string(_root.$meta, 'tabs.sortAlphabeticallyReversed', {}) ?? 'Trier par ordre alphabétique (inversé)',
      'tabs.longPressSortToSave' =>
        TranslationOverrides.string(_root.$meta, 'tabs.longPressSortToSave', {}) ??
            'Appuyez longuement sur le bouton de tri pour enregistrer l\'ordre actuel',
      'tabs.deleteSelectedTabs' => TranslationOverrides.string(_root.$meta, 'tabs.deleteSelectedTabs', {}) ?? 'Supprimer les onglets sélectionnés',
      'tabs.longPressToMove' =>
        TranslationOverrides.string(_root.$meta, 'tabs.longPressToMove', {}) ?? 'Appuyez longuement sur un onglet pour le déplacer',
      'tabs.noTabsFound' => TranslationOverrides.string(_root.$meta, 'tabs.noTabsFound', {}) ?? 'Aucun onglet trouvé',
      'tabs.filters.title' => TranslationOverrides.string(_root.$meta, 'tabs.filters.title', {}) ?? 'Filtres d\'onglets',
      'history.unknownBooruType' => TranslationOverrides.string(_root.$meta, 'history.unknownBooruType', {}) ?? 'Type de Booru inconnu !',
      'settings.title' => TranslationOverrides.string(_root.$meta, 'settings.title', {}) ?? 'Paramètres',
      'settings.language.title' => TranslationOverrides.string(_root.$meta, 'settings.language.title', {}) ?? 'Langue',
      'settings.language.helpUsTranslate' =>
        TranslationOverrides.string(_root.$meta, 'settings.language.helpUsTranslate', {}) ?? 'Aidez-nous à traduire',
      'settings.language.visitForDetails' =>
        TranslationOverrides.string(_root.$meta, 'settings.language.visitForDetails', {}) ??
            'Visitez <a href=\'https://github.com/NO-ob/LoliSnatcher_Droid/blob/master/CONTRIBUTING.md#localization--translations\'>github</a> pour plus de détails ou appuyez sur l\'image ci-dessous pour accéder à POEditor',
      'settings.booru.title' => TranslationOverrides.string(_root.$meta, 'settings.booru.title', {}) ?? 'Boorus et Recherche',
      'settings.interface.title' => TranslationOverrides.string(_root.$meta, 'settings.interface.title', {}) ?? 'Interface',
      'settings.theme.title' => TranslationOverrides.string(_root.$meta, 'settings.theme.title', {}) ?? 'Thèmes',
      'settings.theme.themeMode' => TranslationOverrides.string(_root.$meta, 'settings.theme.themeMode', {}) ?? 'Mode du thème',
      'settings.theme.theme' => TranslationOverrides.string(_root.$meta, 'settings.theme.theme', {}) ?? 'Thème',
      'settings.theme.viewMoreFonts' => TranslationOverrides.string(_root.$meta, 'settings.theme.viewMoreFonts', {}) ?? 'Afficher plus de polices',
      'settings.viewer.zoomButtonPosition' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.zoomButtonPosition', {}) ?? 'Position du bouton de zoom',
      'settings.viewer.toolbarButtonsOrder' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.toolbarButtonsOrder', {}) ?? 'Ordre des boutons de la barre d\'outils',
      'settings.viewer.thisButtonCannotBeDisabled' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.thisButtonCannotBeDisabled', {}) ?? 'Ce bouton ne peut pas être désactivé',
      'settings.viewer.useVolumeButtonsForScrolling' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.useVolumeButtonsForScrolling', {}) ??
            'Utilisez les boutons de volume pour faire défiler',
      'settings.viewer.volumeButtonsScrollSpeed' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.volumeButtonsScrollSpeed', {}) ?? 'Vitesse de défilement des boutons de volume',
      'settings.viewer.usingDefaultAnimation' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.usingDefaultAnimation', {}) ?? 'Utilisation de l\'animation par défaut',
      'settings.viewer.usingCustomAnimation' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.usingCustomAnimation', {}) ?? 'Utilisation de l\'animation personnalisée',
      'settings.viewer.scrollDirectionValues.vertical' =>
        TranslationOverrides.string(_root.$meta, 'settings.viewer.scrollDirectionValues.vertical', {}) ?? 'Vertical',
      'settings.video.title' => TranslationOverrides.string(_root.$meta, 'settings.video.title', {}) ?? 'Vidéo',
      'settings.backupAndRestore.title' =>
        TranslationOverrides.string(_root.$meta, 'settings.backupAndRestore.title', {}) ?? 'Sauvegarde et Restauration',
      'settings.network.title' => TranslationOverrides.string(_root.$meta, 'settings.network.title', {}) ?? 'Réseau',
      'settings.privacy.title' => TranslationOverrides.string(_root.$meta, 'settings.privacy.title', {}) ?? 'Confidentialité',
      'settings.performance.title' => TranslationOverrides.string(_root.$meta, 'settings.performance.title', {}) ?? 'Performance',
      'settings.itemFilters.title' => TranslationOverrides.string(_root.$meta, 'settings.itemFilters.title', {}) ?? 'Filtres',
      'settings.sync.testConnection' => TranslationOverrides.string(_root.$meta, 'settings.sync.testConnection', {}) ?? 'Test de connexion',
      'settings.checkForUpdates.updateAvailable' =>
        TranslationOverrides.string(_root.$meta, 'settings.checkForUpdates.updateAvailable', {}) ?? 'Mise à jour disponible !',
      'settings.checkForUpdates.youHaveLatestVersion' =>
        TranslationOverrides.string(_root.$meta, 'settings.checkForUpdates.youHaveLatestVersion', {}) ?? 'Vous disposez de la dernière version',
      'settings.help.title' => TranslationOverrides.string(_root.$meta, 'settings.help.title', {}) ?? 'Aide',
      'settings.dirPicker.yes' => TranslationOverrides.string(_root.$meta, 'settings.dirPicker.yes', {}) ?? 'Oui',
      'settings.version' => TranslationOverrides.string(_root.$meta, 'settings.version', {}) ?? 'Version',
      'lockscreen.tapToAuthenticate' =>
        TranslationOverrides.string(_root.$meta, 'lockscreen.tapToAuthenticate', {}) ?? 'Appuyez pour vous authentifier',
      'loliSync.waitingForConnection' => TranslationOverrides.string(_root.$meta, 'loliSync.waitingForConnection', {}) ?? 'En attente de connexion…',
      'tagView.tapToTryAgain' => TranslationOverrides.string(_root.$meta, 'tagView.tapToTryAgain', {}) ?? 'Appuyez pour réessayer',
      'media.loading.stopReasons.videoError' =>
        TranslationOverrides.string(_root.$meta, 'media.loading.stopReasons.videoError', {}) ?? 'Erreur vidéo',
      'media.video.videosDisabledOrNotSupported' =>
        TranslationOverrides.string(_root.$meta, 'media.video.videosDisabledOrNotSupported', {}) ?? 'Vidéos désactivées ou non prises en charge',
      'preview.error.tapToRetryIfStuck' =>
        TranslationOverrides.string(_root.$meta, 'preview.error.tapToRetryIfStuck', {}) ??
            'Appuyez pour réessayer si la requête semble bloquée ou prend trop de temps',
      'preview.error.errorWithMessage' =>
        TranslationOverrides.string(_root.$meta, 'preview.error.errorWithMessage', {}) ?? 'Appuyez ici pour réessayer',
      'preview.error.tapToRetry' => TranslationOverrides.string(_root.$meta, 'preview.error.tapToRetry', {}) ?? 'Appuyez ici pour réessayer',
      _ => null,
    };
  }
}
