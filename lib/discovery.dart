import 'catalog_cache.dart';
import 'library.dart';
import 'models.dart';
import 'xtream.dart';

/// Builds a taste-weighted pool of movies for the Discover globe.
///
/// Taste = the categories of movies the user has favourited / recently watched.
/// With no signal yet, falls back to a few random categories.
class Discovery {
  static Future<List<VodStream>> pool(XtreamClient c, {int size = 240}) async {
    final allCats = await CatalogCache.instance.vod(c);
    if (allCats.isEmpty) return [];

    // Count category frequency across the user's movie favourites + recents.
    final freq = <String, int>{};
    for (final m in [...Library.instance.favourites, ...Library.instance.recent]) {
      if (m.kind == 'movie' && m.cat.isNotEmpty) {
        freq[m.cat] = (freq[m.cat] ?? 0) + 1;
      }
    }

    // Preferred categories first, then fill with random ones for a dense, varied globe.
    final chosen = <String>[];
    if (freq.isNotEmpty) {
      final pref = freq.keys.toList()..sort((a, b) => freq[b]!.compareTo(freq[a]!));
      chosen.addAll(pref.take(6));
    }
    final rest = allCats.where((cat) => !chosen.contains(cat.id)).toList()..shuffle();
    for (final cat in rest) {
      if (chosen.length >= 12) break;
      chosen.add(cat.id);
    }

    final lists = await Future.wait(
      chosen.map((id) => c.vodStreams(id).catchError((_) => <VodStream>[])),
    );
    final items = lists.expand((e) => e).where((m) => m.icon.isNotEmpty).toList()..shuffle();
    return items.take(size).toList();
  }
}
