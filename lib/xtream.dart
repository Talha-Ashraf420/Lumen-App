import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:http/http.dart' as http;
import 'channel_logos.dart';
import 'demo_catalog.dart';
import 'models.dart';

class XtreamException implements Exception {
  final String message;
  XtreamException(this.message);
  @override
  String toString() => message;
}

/// Convert transport failures into short, actionable copy without ever
/// rendering a request URI. Xtream URLs contain the username and password in
/// their query string, and `ClientException.toString()` may include that URI.
String safeProviderError(Object error) {
  if (error is XtreamException) return error.message;
  if (error is TimeoutException) {
    return 'The provider took too long to respond. Check the server address '
        'and try again.';
  }
  if (error is HandshakeException) {
    return 'The provider’s secure connection could not be verified. Check '
        'the server address or ask the provider to fix its certificate.';
  }
  if (error is SocketException) {
    return 'Lumen could not reach the provider. Check the server address, '
        'internet connection, or provider status.';
  }
  if (error is http.ClientException) {
    return 'The provider closed the connection before login completed. '
        'Please try again.';
  }
  return 'Lumen could not connect to this provider. Check the details and '
      'try again.';
}

/// Normalize a user-entered base URL: ensure scheme, strip trailing slash/path.
String normalizeBaseUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return '';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url))
    url = 'https://$url';
  try {
    final u = Uri.parse(url);
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  } catch (_) {
    return url.replaceAll(RegExp(r'/+$'), '');
  }
}

/// Extract Xtream credentials from a pasted playlist / panel URL, e.g.
/// `https://host:port/get.php?username=U&password=P&type=m3u_plus` or
/// `https://host:port/player_api.php?username=U&password=P`. Most "M3U URL"
/// links from IPTV providers are Xtream-backed get.php links, so this lets the
/// user paste their playlist URL and get the full catalog. Returns null
/// if the URL carries no username/password (a plain, non-Xtream playlist).
XtreamCredentials? credentialsFromUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s))
    s = 'https://$s';
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
  return XtreamCredentials(
    baseUrl: '${u.scheme}://${u.host}$port',
    username: user,
    password: pass,
  );
}

/// Parsed representation of a plain M3U playlist. Kept separate from the
/// network client so parsing can be tested without contacting a provider.
class ParsedM3uPlaylist {
  final List<Category> categories;
  final List<LiveStream> channels;
  final Map<int, String> urls;
  final Map<int, Map<String, String>> headers;
  final List<String> epgUrls;

  const ParsedM3uPlaylist({
    required this.categories,
    required this.channels,
    required this.urls,
    required this.headers,
    required this.epgUrls,
  });
}

String _m3uUnescape(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

String _m3uAttribute(String key, String line) => _m3uUnescape(
  RegExp(
        '${RegExp.escape(key)}\\s*=\\s*"([^"]*)"',
        caseSensitive: false,
      ).firstMatch(line)?.group(1) ??
      '',
);

int _stableM3uId(String value) {
  // FNV-1a, constrained to a positive 31-bit value accepted everywhere an
  // Xtream stream_id is used. Unlike a list index, this survives reordering.
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

void _addHeader(Map<String, String> headers, String rawKey, String value) {
  if (value.trim().isEmpty) return;
  switch (rawKey.trim().toLowerCase()) {
    case 'user-agent':
    case 'http-user-agent':
      headers['User-Agent'] = value.trim();
      return;
    case 'referer':
    case 'referrer':
    case 'http-referrer':
    case 'http-referer':
      headers['Referer'] = value.trim();
      return;
    case 'origin':
    case 'http-origin':
      headers['Origin'] = value.trim();
      return;
    case 'cookie':
    case 'http-cookie':
      headers['Cookie'] = value.trim();
      return;
  }
}

void _parseHeaderQuery(String raw, Map<String, String> headers) {
  for (final part in raw.split('&')) {
    final at = part.indexOf('=');
    if (at <= 0) continue;
    final key = Uri.decodeComponent(part.substring(0, at));
    final value = Uri.decodeComponent(part.substring(at + 1));
    _addHeader(headers, key, value);
  }
}

/// Parse common IPTV playlist extensions used for protected streams:
/// EXTVLCOPT, KODIPROP, EXTVLC HTTP JSON and URL pipe headers.
ParsedM3uPlaylist parseM3uPlaylist(String body) {
  final groups = <String>{};
  final channels = <LiveStream>[];
  final urls = <int, String>{};
  final headersById = <int, Map<String, String>>{};
  final usedIds = <int>{};
  final seenSources = <String>{};
  final epgUrls = <String>[];

  String? extinf;
  String? extGroup;
  var pendingHeaders = <String, String>{};

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final upper = line.toUpperCase();
    if (upper.startsWith('#EXTM3U')) {
      for (final key in ['url-tvg', 'x-tvg-url']) {
        final value = _m3uAttribute(key, line);
        if (value.isEmpty) continue;
        for (final url in value.split(',')) {
          final trimmed = url.trim();
          if (trimmed.isNotEmpty && !epgUrls.contains(trimmed)) {
            epgUrls.add(trimmed);
          }
        }
      }
      continue;
    }
    if (upper.startsWith('#EXTINF')) {
      extinf = line;
      extGroup = null;
      pendingHeaders = <String, String>{};
      continue;
    }
    if (extinf == null) continue;
    if (upper.startsWith('#EXTGRP:')) {
      extGroup = line.substring(line.indexOf(':') + 1).trim();
      continue;
    }
    if (upper.startsWith('#EXTVLCOPT:') || upper.startsWith('#KODIPROP:')) {
      final option = line.substring(line.indexOf(':') + 1);
      final at = option.indexOf('=');
      if (at > 0) {
        final key = option.substring(0, at);
        final value = option.substring(at + 1);
        if (key.toLowerCase().contains('stream_headers') ||
            key.toLowerCase().contains('manifest_headers')) {
          _parseHeaderQuery(value, pendingHeaders);
        } else {
          _addHeader(pendingHeaders, key, value);
        }
      }
      continue;
    }
    if (upper.startsWith('#EXTHTTP:')) {
      try {
        final decoded = jsonDecode(line.substring(line.indexOf(':') + 1));
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            _addHeader(pendingHeaders, '${entry.key}', '${entry.value}');
          }
        }
      } catch (_) {
        // A malformed optional directive must not discard the channel.
      }
      continue;
    }
    if (line.startsWith('#')) continue;

    var url = line;
    final pipe = url.indexOf('|');
    if (pipe > 0) {
      _parseHeaderQuery(url.substring(pipe + 1), pendingHeaders);
      url = url.substring(0, pipe);
    }
    final title = extinf.contains(',')
        ? extinf.substring(extinf.lastIndexOf(',') + 1).trim()
        : 'Channel';
    final name = title.isEmpty ? 'Channel' : title;
    final groupAttr = _m3uAttribute('group-title', extinf);
    final group = groupAttr.isNotEmpty
        ? groupAttr
        : ((extGroup ?? '').isNotEmpty ? extGroup! : 'Uncategorized');
    final logo = _m3uAttribute('tvg-logo', extinf);
    final epgId = _m3uAttribute('tvg-id', extinf);
    final epgName = _m3uAttribute('tvg-name', extinf);
    final sourceKey = '$name\n$url';
    if (!seenSources.add(sourceKey)) {
      extinf = null;
      pendingHeaders = <String, String>{};
      continue;
    }
    var id = _stableM3uId(sourceKey);
    var collision = 1;
    while (!usedIds.add(id)) {
      id = _stableM3uId('$sourceKey#${collision++}');
    }

    groups.add(group);
    channels.add(
      LiveStream(id, name, logo, group, epgId: epgId, epgName: epgName),
    );
    urls[id] = url;
    if (pendingHeaders.isNotEmpty) {
      headersById[id] = Map.unmodifiable(pendingHeaders);
    }
    extinf = null;
    pendingHeaders = <String, String>{};
  }

  return ParsedM3uPlaylist(
    categories: groups.map((g) => Category(g, g)).toList(growable: false),
    channels: List.unmodifiable(channels),
    urls: Map.unmodifiable(urls),
    headers: Map.unmodifiable(headersById),
    epgUrls: List.unmodifiable(epgUrls),
  );
}

class XtreamClient {
  final XtreamCredentials creds;
  final http.Client _http;
  final bool _ownsHttpClient;

  XtreamClient(this.creds, {http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  /// Release pooled network connections when a profile is replaced.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  static const _ua = 'Lumen/1.0 (Flutter)';
  static const _timeout = Duration(seconds: 25);

  // ---- plain M3U mode state (populated lazily by _ensureM3u) ----
  Future<void>? _m3uLoad;
  final List<Category> _m3uCats = [];
  final List<LiveStream> _m3uChannels = [];
  final Map<int, String> _m3uUrlById = {}; // streamId -> direct stream URL
  final Map<int, Map<String, String>> _m3uHeadersById = {};
  final List<Uri> _m3uEpgUrls = [];
  ChannelLogoResolver? _logoResolver;

  Future<void> _ensureM3u() async {
    final existing = _m3uLoad;
    if (existing != null) return existing;
    final load = _loadM3u();
    _m3uLoad = load;
    try {
      await load;
    } catch (_) {
      if (identical(_m3uLoad, load)) _m3uLoad = null;
      rethrow;
    }
  }

  Future<void> _loadM3u() async {
    final res = await _http
        .get(Uri.parse(creds.m3uUrl!), headers: {'User-Agent': _ua})
        .timeout(
          _timeout,
          onTimeout: () => throw XtreamException('Playlist timed out.'),
        );
    if (res.statusCode != 200)
      throw XtreamException('Playlist returned ${res.statusCode}');
    final parsed = parseM3uPlaylist(res.body);
    _m3uCats
      ..clear()
      ..addAll(parsed.categories);
    _m3uChannels
      ..clear()
      ..addAll(parsed.channels);
    _m3uUrlById
      ..clear()
      ..addAll(parsed.urls);
    _m3uHeadersById
      ..clear()
      ..addAll(parsed.headers);
    final playlistUri = Uri.parse(creds.m3uUrl!);
    _m3uEpgUrls
      ..clear()
      ..addAll(
        parsed.epgUrls
            .map(Uri.tryParse)
            .whereType<Uri>()
            .map(playlistUri.resolveUri)
            .where((uri) => uri.scheme == 'http' || uri.scheme == 'https'),
      );
    if (_m3uChannels.isEmpty)
      throw XtreamException('No channels found in this playlist.');
  }

  Uri _playerApi(Map<String, String> params) {
    return Uri.parse('${creds.baseUrl}/player_api.php').replace(
      queryParameters: {
        'username': creds.username,
        'password': creds.password,
        ...params,
      },
    );
  }

  Future<dynamic> _get(Map<String, String> params) async {
    final res = await _http
        .get(
          _playerApi(params),
          headers: {'User-Agent': _ua, 'Accept': 'application/json'},
        )
        .timeout(
          _timeout,
          onTimeout: () => throw XtreamException('Provider timed out.'),
        );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamException(
        'The provider rejected these credentials. Check the username and '
        'password.',
      );
    }
    if (res.statusCode == 404) {
      throw XtreamException(
        'The server was reached, but its Xtream API was not found. Check the '
        'server address.',
      );
    }
    if (res.statusCode == 429) {
      throw XtreamException(
        'The provider is limiting login attempts. Wait a minute before trying '
        'again; repeated attempts can extend the cooldown.',
      );
    }
    if (res.statusCode >= 500) {
      throw XtreamException(
        'The provider is temporarily unavailable (${res.statusCode}). '
        'Please try again shortly.',
      );
    }
    if (res.statusCode != 200) {
      throw XtreamException(
        'The provider could not complete login (${res.statusCode}).',
      );
    }
    if (res.body.isEmpty) return [];
    try {
      final body = res.body;
      // Whole-provider catalogs can be several megabytes. Decoding those on
      // Flutter's UI isolate makes navigation and remote input appear frozen.
      if (body.length >= 180000) {
        return await Isolate.run<dynamic>(() => jsonDecode(body));
      }
      return jsonDecode(body);
    } catch (_) {
      throw XtreamException(
        'Provider returned a non-JSON response (check URL/credentials).',
      );
    }
  }

  /// Validate credentials.
  Future<Map<String, dynamic>> authenticate() async {
    if (creds.isDemo) {
      return {
        'auth': 1,
        'username': 'Demo profile',
        'status': 'Ready',
        'exp_date': null,
        'active_cons': 0,
        'max_connections': 0,
      };
    }
    if (creds.isM3u) {
      await _ensureM3u();
      return {'auth': 1, 'username': creds.username};
    }
    final data = await _get({});
    if (data is! Map ||
        data['user_info'] == null ||
        (data['user_info']['auth'] ?? 0) == 0) {
      throw XtreamException('Invalid username or password.');
    }
    return (data['user_info'] as Map).cast<String, dynamic>();
  }

  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) f) {
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => f(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<Category>> liveCategories() async {
    if (creds.isDemo) return DemoCatalog.liveCategories;
    if (creds.isM3u) {
      await _ensureM3u();
      return List.of(_m3uCats);
    }
    return _list(
      await _get({'action': 'get_live_categories'}),
      Category.fromJson,
    );
  }

  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    if (creds.isDemo) return DemoCatalog.channels(categoryId);
    if (creds.isM3u) {
      await _ensureM3u();
      if (categoryId == null) return List.of(_m3uChannels);
      return _m3uChannels.where((c) => c.categoryId == categoryId).toList();
    }
    return _list(
      await _get({
        'action': 'get_live_streams',
        if (categoryId != null) 'category_id': categoryId,
      }),
      LiveStream.fromJson,
    );
  }

  /// Resolve missing channel artwork away from the foreground catalog fetch.
  /// CatalogCache invokes this after it has already returned cached/provider
  /// rows, then publishes one quiet revision when richer artwork is ready.
  Future<List<LiveStream>> enrichLiveLogos(List<LiveStream> channels) async {
    if (creds.isDemo || channels.isEmpty) return channels;
    final resolver = _logoResolver ??= ChannelLogoResolver(httpClient: _http);
    final guideUrls = creds.isM3u
        ? List<Uri>.of(_m3uEpgUrls)
        : [
            Uri.parse('${creds.baseUrl}/xmltv.php').replace(
              queryParameters: {
                'username': creds.username,
                'password': creds.password,
              },
            ),
          ];
    return resolver.resolve(channels, guideUrls: guideUrls);
  }

  // Plain M3U playlists carry only live channels — VOD/series are empty.
  Future<List<Category>> vodCategories() async => creds.isDemo
      ? DemoCatalog.movieCategories
      : creds.isM3u
      ? const []
      : _list(await _get({'action': 'get_vod_categories'}), Category.fromJson);
  Future<List<VodStream>> vodStreams(String? categoryId) async => creds.isDemo
      ? DemoCatalog.movies(categoryId)
      : creds.isM3u
      ? const []
      : _list(
          await _get({
            'action': 'get_vod_streams',
            if (categoryId != null) 'category_id': categoryId,
          }),
          VodStream.fromJson,
        );
  Future<VodInfo> vodInfo(int id) async {
    if (creds.isDemo) return DemoCatalog.movieInfo(id);
    return VodInfo.fromJson(
      (await _get({
        'action': 'get_vod_info',
        'vod_id': '$id',
      })).cast<String, dynamic>(),
    );
  }

  Future<List<Category>> seriesCategories() async => creds.isDemo
      ? DemoCatalog.seriesCategories
      : creds.isM3u
      ? const []
      : _list(
          await _get({'action': 'get_series_categories'}),
          Category.fromJson,
        );
  Future<List<Series>> series(String? categoryId) async => creds.isDemo
      ? DemoCatalog.series(categoryId)
      : creds.isM3u
      ? const []
      : _list(
          await _get({
            'action': 'get_series',
            if (categoryId != null) 'category_id': categoryId,
          }),
          Series.fromJson,
        );
  Future<SeriesInfo> seriesInfo(int id) async {
    if (creds.isDemo) return DemoCatalog.seriesInfo(id);
    return SeriesInfo.fromJson(
      (await _get({
        'action': 'get_series_info',
        'series_id': '$id',
      })).cast<String, dynamic>(),
    );
  }

  /// Request headers declared by a plain M3U entry. Xtream streams use the
  /// default player user-agent.
  Map<String, String> streamHeaders(Object id) {
    if (creds.isDemo || !creds.isM3u) return const {};
    final streamId = id is int ? id : int.tryParse('$id') ?? -1;
    return _m3uHeadersById[streamId] ?? const {};
  }

  /// Direct provider media URL — fed straight to the native (mpv) player.
  String streamUrl(String kind, Object id, {String ext = 'ts'}) {
    if (creds.isDemo) return DemoCatalog.playbackPath;
    if (creds.isM3u) {
      // M3U channels carry their own direct URL (loaded by liveStreams).
      return _m3uUrlById[id is int ? id : int.tryParse('$id') ?? -1] ?? '';
    }
    final normalizedExt = ext.trim().replaceFirst(RegExp(r'^\.'), '');
    final e = normalizedExt.isEmpty
        ? (kind.toLowerCase() == 'live' ? 'ts' : 'mp4')
        : normalizedExt;
    final base = Uri.parse(creds.baseUrl);
    return base
        .replace(
          pathSegments: [
            ...base.pathSegments.where((s) => s.isNotEmpty),
            kind,
            creds.username,
            creds.password,
            '$id.$e',
          ],
        )
        .toString();
  }
}
