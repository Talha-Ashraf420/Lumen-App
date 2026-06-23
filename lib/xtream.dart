import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class XtreamException implements Exception {
  final String message;
  XtreamException(this.message);
  @override
  String toString() => message;
}

/// Normalize a user-entered base URL: ensure scheme, strip trailing slash/path.
String normalizeBaseUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return '';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) url = 'http://$url';
  try {
    final u = Uri.parse(url);
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  } catch (_) {
    return url.replaceAll(RegExp(r'/+$'), '');
  }
}

/// Extract Xtream credentials from a pasted playlist / panel URL, e.g.
/// `http://host:port/get.php?username=U&password=P&type=m3u_plus` or
/// `http://host:port/player_api.php?username=U&password=P`. Most "M3U URL"
/// links from IPTV providers are Xtream-backed get.php links, so this lets the
/// user paste their playlist URL and get the full catalog + EPG. Returns null
/// if the URL carries no username/password (a plain, non-Xtream playlist).
XtreamCredentials? credentialsFromUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) s = 'http://$s';
  Uri u;
  try {
    u = Uri.parse(s);
  } catch (_) {
    return null;
  }
  final user = u.queryParameters['username'];
  final pass = u.queryParameters['password'];
  if (user == null || user.isEmpty || pass == null) return null;
  final port = u.hasPort ? ':${u.port}' : '';
  return XtreamCredentials(baseUrl: '${u.scheme}://${u.host}$port', username: user, password: pass);
}

class XtreamClient {
  final XtreamCredentials creds;
  XtreamClient(this.creds);

  static const _ua = 'Lumen/1.0 (Flutter)';
  static const _timeout = Duration(seconds: 25);

  // ---- plain M3U mode state (populated lazily by _ensureM3u) ----
  Future<void>? _m3uLoad;
  final List<Category> _m3uCats = [];
  final List<LiveStream> _m3uChannels = [];
  final Map<int, String> _m3uUrlById = {}; // streamId -> direct stream URL
  final Map<int, String> _m3uTvgById = {}; // streamId -> tvg-id (XMLTV key)
  final Map<String, List<EpgEntry>> _xmltv = {}; // tvg-id -> programmes

  Future<void> _ensureM3u() => _m3uLoad ??= _loadM3u();

  Future<void> _loadM3u() async {
    final res = await http
        .get(Uri.parse(creds.m3uUrl!), headers: {'User-Agent': _ua})
        .timeout(_timeout, onTimeout: () => throw XtreamException('Playlist timed out.'));
    if (res.statusCode != 200) throw XtreamException('Playlist returned ${res.statusCode}');
    _parseM3u(res.body);
    if (_m3uChannels.isEmpty) throw XtreamException('No channels found in this playlist.');
    if ((creds.epgUrl ?? '').isNotEmpty) {
      try {
        final epg = await http.get(Uri.parse(creds.epgUrl!), headers: {'User-Agent': _ua}).timeout(_timeout);
        if (epg.statusCode == 200) _parseXmltv(epg.body);
      } catch (_) {/* EPG is best-effort */}
    }
  }

  void _parseM3u(String body) {
    final attr = (String key, String line) =>
        RegExp('$key="([^"]*)"', caseSensitive: false).firstMatch(line)?.group(1) ?? '';
    final lines = body.split(RegExp(r'\r?\n'));
    final groups = <String>{};
    int id = 1;
    String? extinf;
    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.toUpperCase().startsWith('#EXTINF')) {
        extinf = line;
      } else if (line.startsWith('#')) {
        continue; // other directives
      } else if (extinf != null) {
        final name = extinf.contains(',') ? extinf.substring(extinf.lastIndexOf(',') + 1).trim() : 'Channel $id';
        final group = attr('group-title', extinf).isEmpty ? 'Uncategorized' : attr('group-title', extinf);
        final logo = attr('tvg-logo', extinf);
        final tvg = attr('tvg-id', extinf);
        groups.add(group);
        _m3uChannels.add(LiveStream(id, name, logo, group, tvg));
        _m3uUrlById[id] = line;
        if (tvg.isNotEmpty) _m3uTvgById[id] = tvg;
        id++;
        extinf = null;
      }
    }
    _m3uCats
      ..clear()
      ..addAll(groups.map((g) => Category(g, g)));
  }

  void _parseXmltv(String xml) {
    // Lightweight regex parse (XMLTV is a flat list of <programme> elements).
    final re = RegExp(
      r'<programme\b[^>]*\bstart="([^"]+)"[^>]*\bstop="([^"]+)"[^>]*\bchannel="([^"]+)"[^>]*>(.*?)</programme>',
      caseSensitive: false,
      dotAll: true,
    );
    final titleRe = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);
    final descRe = RegExp(r'<desc[^>]*>(.*?)</desc>', caseSensitive: false, dotAll: true);
    String unescape(String s) => s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
    for (final m in re.allMatches(xml)) {
      final start = _xmltvTime(m.group(1)!);
      final stop = _xmltvTime(m.group(2)!);
      if (start == null || stop == null) continue;
      final ch = m.group(3)!;
      final inner = m.group(4)!;
      final title = unescape(titleRe.firstMatch(inner)?.group(1) ?? '');
      final desc = unescape(descRe.firstMatch(inner)?.group(1) ?? '');
      (_xmltv[ch] ??= []).add(EpgEntry(title, desc, start, stop));
    }
    for (final list in _xmltv.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
  }

  // XMLTV time: "YYYYMMDDHHMMSS +HHMM" (offset optional). Returns local time.
  DateTime? _xmltvTime(String s) {
    final m = RegExp(r'^\s*(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?').firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!), mi = int.parse(m.group(5)!), se = int.parse(m.group(6) ?? '0');
    final off = m.group(7);
    var dt = DateTime.utc(y, mo, d, h, mi, se);
    if (off != null && off.length == 5) {
      final sign = off[0] == '-' ? -1 : 1;
      dt = dt.subtract(Duration(hours: sign * int.parse(off.substring(1, 3)), minutes: sign * int.parse(off.substring(3, 5))));
    }
    return dt.toLocal();
  }

  List<EpgEntry> _m3uEpgFor(int streamId) {
    final tvg = _m3uTvgById[streamId];
    if (tvg == null) return const [];
    return _xmltv[tvg] ?? const [];
  }

  Uri _playerApi(Map<String, String> params) {
    return Uri.parse('${creds.baseUrl}/player_api.php').replace(queryParameters: {
      'username': creds.username,
      'password': creds.password,
      ...params,
    });
  }

  Future<dynamic> _get(Map<String, String> params) async {
    final res = await http
        .get(_playerApi(params), headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(_timeout, onTimeout: () => throw XtreamException('Provider timed out.'));
    if (res.statusCode != 200) throw XtreamException('Provider returned ${res.statusCode}');
    if (res.body.isEmpty) return [];
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw XtreamException('Provider returned a non-JSON response (check URL/credentials).');
    }
  }

  /// Validate credentials.
  Future<Map<String, dynamic>> authenticate() async {
    if (creds.isM3u) {
      await _ensureM3u();
      return {'auth': 1, 'username': creds.username};
    }
    final data = await _get({});
    if (data is! Map || data['user_info'] == null || (data['user_info']['auth'] ?? 0) == 0) {
      throw XtreamException('Invalid username or password.');
    }
    return (data['user_info'] as Map).cast<String, dynamic>();
  }

  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) f) {
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => f(e.cast<String, dynamic>())).toList();
  }

  Future<List<Category>> liveCategories() async {
    if (creds.isM3u) {
      await _ensureM3u();
      return List.of(_m3uCats);
    }
    return _list(await _get({'action': 'get_live_categories'}), Category.fromJson);
  }

  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    if (creds.isM3u) {
      await _ensureM3u();
      if (categoryId == null) return List.of(_m3uChannels);
      return _m3uChannels.where((c) => c.categoryId == categoryId).toList();
    }
    return _list(
        await _get({'action': 'get_live_streams', if (categoryId != null) 'category_id': categoryId}),
        LiveStream.fromJson);
  }

  // Plain M3U playlists carry only live channels — VOD/series are empty.
  Future<List<Category>> vodCategories() async =>
      creds.isM3u ? const [] : _list(await _get({'action': 'get_vod_categories'}), Category.fromJson);
  Future<List<VodStream>> vodStreams(String? categoryId) async => creds.isM3u
      ? const []
      : _list(await _get({'action': 'get_vod_streams', if (categoryId != null) 'category_id': categoryId}),
          VodStream.fromJson);
  Future<VodInfo> vodInfo(int id) async =>
      VodInfo.fromJson((await _get({'action': 'get_vod_info', 'vod_id': '$id'})).cast<String, dynamic>());

  Future<List<Category>> seriesCategories() async =>
      creds.isM3u ? const [] : _list(await _get({'action': 'get_series_categories'}), Category.fromJson);
  Future<List<Series>> series(String? categoryId) async => creds.isM3u
      ? const []
      : _list(await _get({'action': 'get_series', if (categoryId != null) 'category_id': categoryId}),
          Series.fromJson);
  Future<SeriesInfo> seriesInfo(int id) async => SeriesInfo.fromJson(
      (await _get({'action': 'get_series_info', 'series_id': '$id'})).cast<String, dynamic>());

  /// Now/next EPG for a live channel (base64 titles decoded in the model).
  Future<List<EpgEntry>> shortEpg(int streamId, {int limit = 4}) async {
    if (creds.isM3u) {
      await _ensureM3u();
      final all = _m3uEpgFor(streamId);
      final now = DateTime.now();
      return all.where((e) => e.end.isAfter(now)).take(limit).toList();
    }
    final data = await _get({'action': 'get_short_epg', 'stream_id': '$streamId', 'limit': '$limit'});
    final listings = (data is Map) ? data['epg_listings'] : null;
    return _list(listings, EpgEntry.fromJson);
  }

  /// Full-day EPG schedule for a live channel (used by the guide + catch-up).
  Future<List<EpgEntry>> simpleDataTable(int streamId) async {
    if (creds.isM3u) {
      await _ensureM3u();
      return List.of(_m3uEpgFor(streamId));
    }
    final data = await _get({'action': 'get_simple_data_table', 'stream_id': '$streamId'});
    final listings = (data is Map) ? data['epg_listings'] : null;
    return _list(listings, EpgEntry.fromJson);
  }

  /// Catch-up (timeshift) URL for a past programme. `start` is the provider-local
  /// programme start formatted as `YYYY-MM-DD:HH-MM`; `durationMinutes` its length.
  /// Uses the widely-supported `streaming/timeshift.php` endpoint.
  String timeshiftUrl(int streamId, String start, int durationMinutes) {
    return '${creds.baseUrl}/streaming/timeshift.php'
        '?username=${creds.username}&password=${creds.password}'
        '&stream=$streamId&start=$start&duration=$durationMinutes';
  }

  /// Direct provider media URL — fed straight to the native (mpv) player.
  String streamUrl(String kind, Object id, {String ext = 'ts'}) {
    if (creds.isM3u) {
      // M3U channels carry their own direct URL (loaded by liveStreams).
      return _m3uUrlById[id is int ? id : int.tryParse('$id') ?? -1] ?? '';
    }
    final e = ext.replaceFirst(RegExp(r'^\.'), '');
    return '${creds.baseUrl}/$kind/${creds.username}/${creds.password}/$id.$e';
  }
}
