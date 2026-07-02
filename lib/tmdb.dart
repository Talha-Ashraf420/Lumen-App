import 'dart:convert';
import 'package:http/http.dart' as http;

/// TMDB metadata enrichment — better backdrops, overviews, ratings, cast and
/// YouTube trailers matched to provider titles. Results are memoised per query.
class Tmdb {
  static const _key = 'a1da981e444dd4584c26de3e4380c089';
  static const _base = 'https://api.themoviedb.org/3';
  static const img = 'https://image.tmdb.org/t/p'; // append /w780, /w500 + path

  static final Map<String, Future<TmdbInfo?>> _cache = {};

  static Future<TmdbInfo?> movie(String rawName) => _lookup('movie', rawName);
  static Future<TmdbInfo?> tv(String rawName) => _lookup('tv', rawName);

  static Future<TmdbInfo?> _lookup(String kind, String rawName) {
    final title = _clean(rawName);
    if (title.isEmpty) return Future.value(null);
    final year = _year(rawName);
    return _cache.putIfAbsent('$kind:$title:$year', () => _fetch(kind, title, year));
  }

  static Future<TmdbInfo?> _fetch(String kind, String title, int? year) async {
    try {
      final yearParam = year == null ? '' : (kind == 'movie' ? '&year=$year' : '&first_air_date_year=$year');
      final search = Uri.parse('$_base/search/$kind?api_key=$_key&query=${Uri.encodeQueryComponent(title)}$yearParam');
      final sr = await http.get(search).timeout(const Duration(seconds: 12));
      if (sr.statusCode != 200) return null;
      final results = (jsonDecode(sr.body)['results'] as List?) ?? [];
      if (results.isEmpty) return null;
      final id = results.first['id'];

      final detail = Uri.parse('$_base/$kind/$id?api_key=$_key&append_to_response=credits,videos');
      final dr = await http.get(detail).timeout(const Duration(seconds: 12));
      if (dr.statusCode != 200) return null;
      final j = jsonDecode(dr.body) as Map<String, dynamic>;

      final genres = ((j['genres'] as List?) ?? []).map((g) => g['name']).whereType<String>().take(3).join(', ');
      final cast = (((j['credits'] ?? {})['cast'] as List?) ?? [])
          .map((c) => c['name'])
          .whereType<String>()
          .take(5)
          .join(', ');
      String? trailer;
      final vids = (((j['videos'] ?? {})['results'] as List?) ?? []);
      for (final v in vids) {
        if (v['site'] == 'YouTube' && (v['type'] == 'Trailer' || v['type'] == 'Teaser')) {
          trailer = v['key'];
          if (v['type'] == 'Trailer') break;
        }
      }

      return TmdbInfo(
        overview: (j['overview'] ?? '') as String,
        backdrop: _path(j['backdrop_path'], 'w1280'),
        poster: _path(j['poster_path'], 'w500'),
        rating: (j['vote_average'] is num) ? (j['vote_average'] as num).toDouble() : 0,
        releaseDate: (j['release_date'] ?? j['first_air_date'] ?? '') as String,
        genres: genres,
        cast: cast,
        trailerKey: trailer,
      );
    } catch (_) {
      return null;
    }
  }

  static String _path(dynamic p, String size) => (p is String && p.isNotEmpty) ? '$img/$size$p' : '';

  static String _clean(String raw) {
    var s = raw;
    s = s.replaceFirst(RegExp(r'^\s*[A-Z]{2,3}\s*[|:\-]\s*'), ''); // "EN | ", "US - "
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    s = s.replaceAll(
        RegExp(r'\b(4K|UHD|FHD|HD|SD|HEVC|H ?265|H ?264|x265|x264|MULTI|DUAL|SUB|DUB|VOSTFR)\b', caseSensitive: false),
        ' ');
    s = s.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    s = s.replaceAll(RegExp(r'[_\.]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static int? _year(String raw) {
    final m = RegExp(r'(19|20)\d{2}').firstMatch(raw);
    return m == null ? null : int.tryParse(m.group(0)!);
  }
}

class TmdbInfo {
  final String overview, backdrop, poster, releaseDate, genres, cast;
  final double rating;
  final String? trailerKey;
  TmdbInfo({
    required this.overview,
    required this.backdrop,
    required this.poster,
    required this.releaseDate,
    required this.genres,
    required this.cast,
    required this.rating,
    this.trailerKey,
  });
  String? get trailerUrl => trailerKey == null ? null : 'https://www.youtube.com/watch?v=$trailerKey';
}
