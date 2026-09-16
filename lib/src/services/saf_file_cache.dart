import 'package:lolisnatcher/src/handlers/service_handler.dart';

class SAFFileCache {
  SAFFileCache._();
  static final SAFFileCache instance = SAFFileCache._();

  String _cachedUri = '';
  final Set<String> _fileNames = {};
  Set<String> get fileNames => Set.unmodifiable(_fileNames);
  bool _isPopulated = false;
  int _generation = 0;
  Future<void>? _population;
  final Map<String, bool> _changesDuringPopulation = {};

  Future<bool> existsFile(String safUri, String fileName) async {
    if (safUri == _cachedUri && _isPopulated && _fileNames.contains(fileName)) return true;
    // A file may have appeared since the last directory listing.
    final result = await ServiceHandler.existsFileFromSAFDirectoryFast(safUri, fileName);
    if (result && safUri == _cachedUri && _isPopulated) _fileNames.add(fileName);
    return result;
  }

  Future<void> populate(String safUri) {
    if (safUri.isEmpty) {
      invalidate();
      return Future.value();
    }
    if (safUri == _cachedUri && _population != null) return _population!;
    final generation = ++_generation;
    _cachedUri = safUri;
    _isPopulated = false;
    _fileNames.clear();
    _changesDuringPopulation.clear();
    final population = _populate(safUri, generation);
    _population = population;
    return population;
  }

  Future<void> _populate(String safUri, int generation) async {
    try {
      if (safUri.isEmpty || !await ServiceHandler.testSAFPersistence(safUri)) return;
      final names = await ServiceHandler.listFileNamesFromSAFDirectory(safUri);
      if (generation != _generation) return;
      _fileNames
        ..clear()
        ..addAll(names);
      for (final entry in _changesDuringPopulation.entries) {
        if (entry.value) {
          _fileNames.add(entry.key);
        } else {
          _fileNames.remove(entry.key);
        }
      }
      _isPopulated = true;
    } catch (_) {
      if (generation == _generation) _isPopulated = false;
    } finally {
      if (generation == _generation) {
        _population = null;
        _changesDuringPopulation.clear();
      }
    }
  }

  void onFileCreated(String fileName, {String? safUri}) {
    if (safUri != null && safUri != _cachedUri) return;
    if (_population != null) _changesDuringPopulation[fileName] = true;
    if (_isPopulated) {
      _fileNames.add(fileName);
    }
  }

  void onFileDeleted(String fileName, {String? safUri}) {
    if (safUri != null && safUri != _cachedUri) return;
    if (_population != null) _changesDuringPopulation[fileName] = false;
    if (_isPopulated) {
      _fileNames.remove(fileName);
    }
  }

  void invalidate() {
    _generation++;
    _population = null;
    _changesDuringPopulation.clear();
    _fileNames.clear();
    _isPopulated = false;
    _cachedUri = '';
  }
}
