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

class XtreamClient {
  final XtreamCredentials creds;
  XtreamClient(this.creds);

  static const _ua = 'Lumen/1.0 (Flutter)';
  static const _timeout = Duration(seconds: 25);

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

  Future<List<Category>> liveCategories() async =>
      _list(await _get({'action': 'get_live_categories'}), Category.fromJson);
  Future<List<LiveStream>> liveStreams(String? categoryId) async => _list(
      await _get({'action': 'get_live_streams', if (categoryId != null) 'category_id': categoryId}),
      LiveStream.fromJson);

  Future<List<Category>> vodCategories() async =>
      _list(await _get({'action': 'get_vod_categories'}), Category.fromJson);
  Future<List<VodStream>> vodStreams(String? categoryId) async => _list(
      await _get({'action': 'get_vod_streams', if (categoryId != null) 'category_id': categoryId}),
      VodStream.fromJson);
  Future<VodInfo> vodInfo(int id) async =>
      VodInfo.fromJson((await _get({'action': 'get_vod_info', 'vod_id': '$id'})).cast<String, dynamic>());

  Future<List<Category>> seriesCategories() async =>
      _list(await _get({'action': 'get_series_categories'}), Category.fromJson);
  Future<List<Series>> series(String? categoryId) async => _list(
      await _get({'action': 'get_series', if (categoryId != null) 'category_id': categoryId}),
      Series.fromJson);
  Future<SeriesInfo> seriesInfo(int id) async => SeriesInfo.fromJson(
      (await _get({'action': 'get_series_info', 'series_id': '$id'})).cast<String, dynamic>());

  /// Direct provider media URL — fed straight to the native (mpv) player.
  String streamUrl(String kind, Object id, {String ext = 'ts'}) {
    final e = ext.replaceFirst(RegExp(r'^\.'), '');
    return '${creds.baseUrl}/$kind/${creds.username}/${creds.password}/$id.$e';
  }
}
