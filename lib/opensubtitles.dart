import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class OpenSubtitlesException implements Exception {
  final String message;
  const OpenSubtitlesException(this.message);
  @override
  String toString() => message;
}

/// One subtitle search result from the current OpenSubtitles REST API.
class SubResult {
  final int fileId;
  final String name;
  final String langName;
  final String iso;
  final double rating;
  final int downloads;
  const SubResult(
    this.fileId,
    this.name,
    this.langName,
    this.iso,
    this.rating,
    this.downloads,
  );
}

class OpenSubs {
  static const _base = 'https://api.opensubtitles.com/api/v1';
  static const _apiKey = String.fromEnvironment('OPENSUBTITLES_API_KEY');
  static const _userAgent = String.fromEnvironment(
    'OPENSUBTITLES_USER_AGENT',
    defaultValue: 'Lumen v1.1',
  );

  static bool get isConfigured => _apiKey.trim().isNotEmpty;

  static const langs = <(String, String)>[
    ('All', 'all'),
    ('English', 'en'),
    ('Arabic', 'ar'),
    ('Urdu', 'ur'),
    ('Hindi', 'hi'),
    ('Spanish', 'es'),
    ('French', 'fr'),
    ('German', 'de'),
    ('Portuguese', 'pt'),
    ('Italian', 'it'),
    ('Turkish', 'tr'),
    ('Russian', 'ru'),
  ];

  static Map<String, String> get _headers {
    if (!isConfigured) {
      throw const OpenSubtitlesException(
        'Online subtitles are not configured in this build.',
      );
    }
    return {
      'Api-Key': _apiKey,
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    };
  }

  static Future<List<SubResult>> search(
    String query, {
    String lang = 'en',
  }) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final uri = Uri.parse('$_base/subtitles').replace(
      queryParameters: {
        'query': value,
        if (lang != 'all') 'languages': lang,
        'order_by': 'download_count',
        'order_direction': 'desc',
      },
    );
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 429) {
      throw const OpenSubtitlesException(
        'OpenSubtitles rate limit reached. Try again later.',
      );
    }
    if (res.statusCode != 200) {
      throw OpenSubtitlesException(
        'Subtitle search failed (${res.statusCode}).',
      );
    }
    final decoded = jsonDecode(res.body);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) return const [];
    final results = <SubResult>[];
    final seen = <int>{};
    for (final row in data.whereType<Map>()) {
      final attributes = row['attributes'];
      if (attributes is! Map) continue;
      final files = attributes['files'];
      if (files is! List) continue;
      for (final file in files.whereType<Map>()) {
        final fileId = int.tryParse('${file['file_id'] ?? ''}') ?? 0;
        if (fileId <= 0 || !seen.add(fileId)) continue;
        final language = '${attributes['language'] ?? ''}';
        results.add(
          SubResult(
            fileId,
            '${file['file_name'] ?? attributes['release'] ?? 'Subtitle'}',
            languageName(language),
            language,
            double.tryParse('${attributes['ratings'] ?? 0}') ?? 0,
            int.tryParse('${attributes['download_count'] ?? 0}') ?? 0,
          ),
        );
      }
    }
    results.sort((a, b) => b.downloads.compareTo(a.downloads));
    return results.take(40).toList(growable: false);
  }

  static String languageName(String code) {
    for (final language in langs) {
      if (language.$2 == code) return language.$1;
    }
    return code.toUpperCase();
  }

  static Future<String> download(SubResult subtitle) async {
    final res = await http
        .post(
          Uri.parse('$_base/download'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'file_id': subtitle.fileId}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 406 || res.statusCode == 429) {
      throw const OpenSubtitlesException(
        'OpenSubtitles download limit reached. Try again later.',
      );
    }
    if (res.statusCode != 200) {
      throw OpenSubtitlesException(
        'Subtitle download failed (${res.statusCode}).',
      );
    }
    final decoded = jsonDecode(res.body);
    final link = decoded is Map ? '${decoded['link'] ?? ''}' : '';
    if (link.isEmpty) {
      throw const OpenSubtitlesException(
        'OpenSubtitles returned no download link.',
      );
    }
    final file = await http
        .get(Uri.parse(link), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 25));
    if (file.statusCode != 200) {
      throw OpenSubtitlesException(
        'Subtitle file failed (${file.statusCode}).',
      );
    }
    List<int> bytes = file.bodyBytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = gzip.decode(bytes);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}
