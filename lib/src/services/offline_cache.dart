// Invalidates work started before a manual cache clear. Storage paths and cache
// keys remain stable; only in-flight work uses this generation.
class OfflineCache {
  static int _generation = 0;
  static int _clearsInProgress = 0;

  static int get generation => _generation;
  static bool isCurrent(int generation) => generation == _generation && _clearsInProgress == 0;

  static void beginClear() {
    _generation++;
    _clearsInProgress++;
  }

  static void endClear() {
    _clearsInProgress--;
    _generation++;
  }
}
