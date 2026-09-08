// Xtream Codes data models.

class XtreamCredentials {
  final String baseUrl; // scheme + host[:port], no trailing slash
  final String username;
  final String password;

  /// Lumen's bundled, network-free sample library. Demo profiles deliberately
  /// carry no provider URL, token, username, or password.
  final bool demo;
  // Plain (non-Xtream) playlist support: when [m3uUrl] is set the client runs
  // in M3U mode and serves channels parsed from the playlist.
  final String? m3uUrl;
  const XtreamCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.m3uUrl,
    this.demo = false,
  });

  static const demoProfile = XtreamCredentials(
    baseUrl: 'demo://lumen',
    username: 'Demo profile',
    password: '',
    demo: true,
  );

  bool get isDemo => demo;
  bool get isM3u => (m3uUrl ?? '').isNotEmpty;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    if (demo) 'demo': true,
    if (m3uUrl != null) 'm3uUrl': m3uUrl,
  };
  factory XtreamCredentials.fromJson(Map<String, dynamic> j) =>
      XtreamCredentials(
        baseUrl: _toStr(j['baseUrl']),
        username: _toStr(j['username']),
        password: _toStr(j['password']),
        m3uUrl: j['m3uUrl'],
        demo: j['demo'] == true,
      );
}

int _toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
double _toDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _toStr(dynamic v) => v == null ? '' : '$v';

/// Normalises the provider's loosely-typed `added` field for reliable sorting.
/// Xtream panels commonly return Unix seconds, but a few return milliseconds
/// or an ISO/date string. Keeping one comparison format prevents a mixed
/// catalog from quietly falling back to provider order.
int mediaAddedValue(String value) {
  final text = value.trim();
  if (text.isEmpty) return 0;
  final numeric = int.tryParse(text);
  if (numeric != null) {
    if (numeric <= 0) return 0;
    // Unix seconds are currently 10 digits; values beyond year 2286 are much
    // more likely to already be milliseconds.
    return numeric < 10000000000 ? numeric * 1000 : numeric;
  }
  return DateTime.tryParse(text)?.millisecondsSinceEpoch ?? 0;
}

/// Returns a stable newest-first movie list. Items without usable provider
/// timestamps remain visible after dated items in their original order.
List<VodStream> moviesRecentlyAdded(Iterable<VodStream> values) {
  final indexed = values.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final byDate = mediaAddedValue(
      b.$2.added,
    ).compareTo(mediaAddedValue(a.$2.added));
    return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

int _catalogDateValue(String value) {
  final text = value.trim();
  final year = RegExp(r'(19|20)\d{2}').firstMatch(text)?.group(0);
  if (year != null && (text.length == 4 || !RegExp(r'^\d+$').hasMatch(text))) {
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
    return DateTime.utc(int.parse(year)).millisecondsSinceEpoch;
  }
  return mediaAddedValue(text);
}

/// Series providers rarely expose the movie-style `added` epoch. Use the
/// release date (or a year embedded in the title) as the best available,
/// deterministic newest-first signal for series shelves.
List<Series> seriesRecentlyAdded(Iterable<Series> values) {
  final indexed = values.indexed.toList(growable: false);
  indexed.sort((a, b) {
    final aValue = _catalogDateValue(
      a.$2.releaseDate.isEmpty ? a.$2.name : a.$2.releaseDate,
    );
    final bValue = _catalogDateValue(
      b.$2.releaseDate.isEmpty ? b.$2.name : b.$2.releaseDate,
    );
    final byDate = bValue.compareTo(aValue);
    return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

class Category {
  final String id;
  final String name;
  Category(this.id, this.name);
  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(_toStr(j['category_id']), _toStr(j['category_name']));
}

class LiveStream {
  final int streamId;
  final String name;
  final String icon;
  final String categoryId;
  final String epgId;
  final String epgName;
  final String countryCode;
  final String fallbackIcon;
  final String logoSource;

  LiveStream(
    this.streamId,
    this.name,
    this.icon,
    this.categoryId, {
    this.epgId = '',
    this.epgName = '',
    this.countryCode = '',
    this.fallbackIcon = '',
    this.logoSource = '',
  });

  /// Artwork shown by catalog surfaces. A provider/playlist logo always wins;
  /// guide and public-catalog matches only fill an empty value.
  String get effectiveIcon => icon.isNotEmpty ? icon : fallbackIcon;

  LiveStream copyWith({
    String? icon,
    String? fallbackIcon,
    String? logoSource,
  }) => LiveStream(
    streamId,
    name,
    icon ?? this.icon,
    categoryId,
    epgId: epgId,
    epgName: epgName,
    countryCode: countryCode,
    fallbackIcon: fallbackIcon ?? this.fallbackIcon,
    logoSource: logoSource ?? this.logoSource,
  );

  factory LiveStream.fromJson(Map<String, dynamic> j) => LiveStream(
    _toInt(j['stream_id']),
    _toStr(j['name']),
    _toStr(j['stream_icon']),
    _toStr(j['category_id']),
    epgId: _toStr(j['epg_channel_id'] ?? j['tvg_id'] ?? j['tvg-id']),
    epgName: _toStr(j['tvg_name'] ?? j['tvg-name']),
    countryCode: _toStr(j['country'] ?? j['country_code']),
    fallbackIcon: _toStr(j['_lumen_fallback_icon']),
    logoSource: _toStr(j['_lumen_logo_source']),
  );
}

class VodStream {
  final int streamId;
  final String name;
  final String icon;
  final String categoryId;
  final String containerExtension;
  final double rating;
  final String added;
  VodStream(
    this.streamId,
    this.name,
    this.icon,
    this.categoryId,
    this.containerExtension,
    this.rating,
    this.added,
  );
  factory VodStream.fromJson(Map<String, dynamic> j) => VodStream(
    _toInt(j['stream_id']),
    _toStr(j['name']),
    _toStr(j['stream_icon']),
    _toStr(j['category_id']),
    _toStr(j['container_extension']).isEmpty
        ? 'mp4'
        : _toStr(j['container_extension']),
    _toDouble(j['rating']),
    _toStr(j['added']),
  );
}

class VodInfo {
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final double rating;
  final String duration;
  final String image;
  final String backdrop;
  final String containerExtension;
  VodInfo({
    required this.plot,
    required this.cast,
    required this.director,
    required this.genre,
    required this.releaseDate,
    required this.rating,
    required this.duration,
    required this.image,
    required this.backdrop,
    required this.containerExtension,
  });
  factory VodInfo.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] ?? {}) as Map<String, dynamic>;
    final data = (j['movie_data'] ?? {}) as Map<String, dynamic>;
    final backdrops = info['backdrop_path'];
    return VodInfo(
      plot: _toStr(info['plot']),
      cast: _toStr(info['cast']),
      director: _toStr(info['director']),
      genre: _toStr(info['genre']),
      releaseDate: _toStr(info['releasedate']),
      rating: _toDouble(info['rating']),
      duration: _toStr(info['duration']),
      image: _toStr(info['movie_image']),
      backdrop: backdrops is List && backdrops.isNotEmpty
          ? _toStr(backdrops.first)
          : '',
      containerExtension: _toStr(data['container_extension']).isEmpty
          ? 'mp4'
          : _toStr(data['container_extension']),
    );
  }
}

class Series {
  final int seriesId;
  final String name;
  final String cover;
  final String plot;
  final String genre;
  final double rating;
  final String releaseDate;
  final String categoryId;
  Series(
    this.seriesId,
    this.name,
    this.cover,
    this.plot,
    this.genre,
    this.rating,
    this.releaseDate,
    this.categoryId,
  );
  factory Series.fromJson(Map<String, dynamic> j) => Series(
    _toInt(j['series_id']),
    _toStr(j['name']),
    _toStr(j['cover']),
    _toStr(j['plot']),
    _toStr(j['genre']),
    _toDouble(j['rating']),
    _toStr(j['releaseDate'] ?? j['release_date']),
    _toStr(j['category_id']),
  );
}

class Episode {
  final String id;
  final int episodeNum;
  final String title;
  final String containerExtension;
  final int season;
  final String image;
  Episode(
    this.id,
    this.episodeNum,
    this.title,
    this.containerExtension,
    this.season,
    this.image,
  );
  factory Episode.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] ?? {}) as Map<String, dynamic>;
    return Episode(
      _toStr(j['id']),
      _toInt(j['episode_num']),
      _toStr(j['title']),
      _toStr(j['container_extension']).isEmpty
          ? 'mp4'
          : _toStr(j['container_extension']),
      _toInt(j['season']),
      _toStr(info['movie_image']),
    );
  }
}

class SeriesInfo {
  final String cover;
  final String backdrop;
  final String plot;
  final String genre;
  final double rating;
  final String releaseDate;
  final Map<int, List<Episode>> episodes; // season -> episodes
  SeriesInfo({
    required this.cover,
    required this.backdrop,
    required this.plot,
    required this.genre,
    required this.rating,
    required this.releaseDate,
    required this.episodes,
  });
  factory SeriesInfo.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] ?? {}) as Map<String, dynamic>;
    final backdrops = info['backdrop_path'];
    final eps = <int, List<Episode>>{};
    final raw = j['episodes'];
    if (raw is Map) {
      raw.forEach((season, list) {
        final s = int.tryParse('$season') ?? 0;
        if (list is List) {
          eps[s] = list
              .whereType<Map>()
              .map((e) => Episode.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }
    return SeriesInfo(
      cover: _toStr(info['cover']),
      backdrop: backdrops is List && backdrops.isNotEmpty
          ? _toStr(backdrops.first)
          : '',
      plot: _toStr(info['plot']),
      genre: _toStr(info['genre']),
      rating: _toDouble(info['rating']),
      releaseDate: _toStr(
        info['releaseDate'] ?? info['release_date'] ?? info['releasedate'],
      ),
      episodes: eps,
    );
  }
}
