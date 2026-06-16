import 'catalog_cache.dart';
import 'library.dart';
import 'models.dart';
import 'xtream.dart';

/// Builds a taste-weighted pool of movies for the Discover globe.
///
/// Taste = the categories of movies the user has favourited / recently watched.
/// With no signal yet, falls back to a few random categories.
class Discovery {
  static Future<List<VodStream>> pool(XtreamClient c, {int size = 48}) async {
    final allCats = await CatalogCache.instance.vod(c);
    if (allCats.isEmpty) return [];

    // Count category frequency across the user's movie favourites + recents.
    final freq = <String, int>{};
    for (final m in [...Library.instance.favourites, ...Library.instance.recent]) {
      if (m.kind == 'movie' && m.cat.isNotEmpty) {
        freq[m.cat] = (freq[m.cat] ?? 0) + 1;
      }
    }

    List<String> chosen;
    if (freq.isNotEmpty) {
      chosen = freq.keys.toList()..sort((a, b) => freq[b]!.compareTo(freq[a]!));
      chosen = chosen.take(4).toList();
      // mix in one random category for variety
      final rest = allCats.where((cat) => !chosen.contains(cat.id)).toList()..shuffle();
      if (rest.isNotEmpty) chosen.add(rest.first.id);
    } else {
      final shuffled = [...allCats]..shuffle();
      chosen = shuffled.take(4).map((e) => e.id).toList();
    }

    final lists = await Future.wait(
      chosen.map((id) => c.vodStreams(id).catchError((_) => <VodStream>[])),
    );
    final items = lists.expand((e) => e).where((m) => m.icon.isNotEmpty).toList()..shuffle();
    return items.take(size).toList();
  }
}
