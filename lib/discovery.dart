import 'catalog_cache.dart';
import 'library.dart';
import 'models.dart';
import 'xtream.dart';

/// Builds a taste-weighted pool of movies for the Discover globe.
///
/// Taste = the categories of movies the user has favourited / recently watched.
/// With no signal yet, falls back to a few random categories.
class Discovery {
  /// Build a large, taste-weighted movie pool. Fetches categories in small
  /// sequential batches with retry (providers reject big concurrent bursts),
  /// accumulating de-duplicated items until [target] is reached or categories
  /// run out.
  static Future<List<VodStream>> pool(XtreamClient c, {int target = 250, String? categoryId}) async {
    // A specific genre/category was chosen — just that one.
    if (categoryId != null) {
      final r = await _fetch(c, categoryId);
      final items = r.where((m) => m.icon.isNotEmpty).toList()..shuffle();
      return items.length > target ? items.sublist(0, target) : items;
    }

    final allCats = await CatalogCache.instance.vod(c);
    if (allCats.isEmpty) return [];

    // Preferred categories (from the user's movie taste) first, then the rest shuffled.
    final freq = <String, int>{};
    for (final m in [...Library.instance.favourites, ...Library.instance.recent]) {
      if (m.kind == 'movie' && m.cat.isNotEmpty) freq[m.cat] = (freq[m.cat] ?? 0) + 1;
    }
    final pref = freq.keys.where((id) => allCats.any((c) => c.id == id)).toList()
      ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
    final rest = allCats.map((e) => e.id).where((id) => !pref.contains(id)).toList()..shuffle();
    final ordered = [...pref, ...rest];

    final out = <VodStream>[];
    final seen = <int>{};
    const batch = 3;
    for (var i = 0; i < ordered.length && out.length < target; i += batch) {
      final ids = ordered.skip(i).take(batch);
      final lists = await Future.wait(ids.map((id) => _fetch(c, id)));
      for (final list in lists) {
        for (final m in list) {
          if (m.icon.isNotEmpty && seen.add(m.streamId)) out.add(m);
        }
      }
    }
    out.shuffle();
    return out.length > target ? out.sublist(0, target) : out;
  }

  static Future<List<VodStream>> _fetch(XtreamClient c, String id) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await c.vodStreams(id);
        if (r.isNotEmpty) return r;
      } catch (_) {}
      await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
    return const [];
  }
}
