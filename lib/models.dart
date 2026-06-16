// Xtream Codes data models.

class XtreamCredentials {
  final String baseUrl; // scheme + host[:port], no trailing slash
  final String username;
  final String password;
  const XtreamCredentials({required this.baseUrl, required this.username, required this.password});

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'username': username, 'password': password};
  factory XtreamCredentials.fromJson(Map<String, dynamic> j) =>
      XtreamCredentials(baseUrl: j['baseUrl'], username: j['username'], password: j['password']);
}

int _toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _toStr(dynamic v) => v == null ? '' : '$v';

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
  final String epgChannelId;
  LiveStream(this.streamId, this.name, this.icon, this.categoryId, this.epgChannelId);
  factory LiveStream.fromJson(Map<String, dynamic> j) => LiveStream(
        _toInt(j['stream_id']),
        _toStr(j['name']),
        _toStr(j['stream_icon']),
        _toStr(j['category_id']),
        _toStr(j['epg_channel_id']),
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
  VodStream(this.streamId, this.name, this.icon, this.categoryId, this.containerExtension,
      this.rating, this.added);
  factory VodStream.fromJson(Map<String, dynamic> j) => VodStream(
        _toInt(j['stream_id']),
        _toStr(j['name']),
        _toStr(j['stream_icon']),
        _toStr(j['category_id']),
        _toStr(j['container_extension']).isEmpty ? 'mp4' : _toStr(j['container_extension']),
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
      backdrop: backdrops is List && backdrops.isNotEmpty ? _toStr(backdrops.first) : '',
      containerExtension:
          _toStr(data['container_extension']).isEmpty ? 'mp4' : _toStr(data['container_extension']),
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
  Series(this.seriesId, this.name, this.cover, this.plot, this.genre, this.rating, this.releaseDate);
  factory Series.fromJson(Map<String, dynamic> j) => Series(
        _toInt(j['series_id']),
        _toStr(j['name']),
        _toStr(j['cover']),
        _toStr(j['plot']),
        _toStr(j['genre']),
        _toDouble(j['rating']),
        _toStr(j['releaseDate'] ?? j['release_date']),
      );
}

class Episode {
  final String id;
  final int episodeNum;
  final String title;
  final String containerExtension;
  final int season;
  final String image;
  Episode(this.id, this.episodeNum, this.title, this.containerExtension, this.season, this.image);
  factory Episode.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] ?? {}) as Map<String, dynamic>;
    return Episode(
      _toStr(j['id']),
      _toInt(j['episode_num']),
      _toStr(j['title']),
      _toStr(j['container_extension']).isEmpty ? 'mp4' : _toStr(j['container_extension']),
      _toInt(j['season']),
      _toStr(info['movie_image']),
    );
  }
}

class SeriesInfo {
  final String cover;
  final String plot;
  final String genre;
  final Map<int, List<Episode>> episodes; // season -> episodes
  SeriesInfo({required this.cover, required this.plot, required this.genre, required this.episodes});
  factory SeriesInfo.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] ?? {}) as Map<String, dynamic>;
    final eps = <int, List<Episode>>{};
    final raw = j['episodes'];
    if (raw is Map) {
      raw.forEach((season, list) {
        final s = int.tryParse('$season') ?? 0;
        if (list is List) {
          eps[s] = list.whereType<Map>().map((e) => Episode.fromJson(e.cast<String, dynamic>())).toList();
        }
      });
    }
    return SeriesInfo(
      cover: _toStr(info['cover']),
      plot: _toStr(info['plot']),
      genre: _toStr(info['genre']),
      episodes: eps,
    );
  }
}
