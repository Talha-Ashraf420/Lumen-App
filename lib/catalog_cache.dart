import 'models.dart';
import 'xtream.dart';

/// Shared category cache so every screen (Home / Search / Live) reuses the same
/// successfully-loaded categories. Retries transient failures and never caches
/// an empty/failed result as final, so a later call can still succeed.
class CatalogCache {
  CatalogCache._();
  static final CatalogCache instance = CatalogCache._();

  List<Category>? _vod, _series, _live;

  Future<List<Category>> vod(XtreamClient c) async =>
      (_vod ??= await _retry(() => c.vodCategories())) ?? const [];

  Future<List<Category>> series(XtreamClient c) async =>
      (_series ??= await _retry(() => c.seriesCategories())) ?? const [];

  Future<List<Category>> live(XtreamClient c) async =>
      (_live ??= await _retry(() => c.liveCategories())) ?? const [];

  void clear() {
    _vod = _series = _live = null;
  }

  /// Returns the first non-empty result across a few attempts, or null on
  /// persistent failure (so the caller's `??=` leaves the slot open to retry).
  static Future<List<Category>?> _retry(Future<List<Category>> Function() f) async {
    for (var i = 0; i < 3; i++) {
      try {
        final r = await f();
        if (r.isNotEmpty) return r;
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
    }
    return null;
  }
}
