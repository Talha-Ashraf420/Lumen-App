import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/xtream.dart';

void main() {
  group('Xtream URLs', () {
    test('extracts and decodes credentials from a playlist URL', () {
      final credentials = credentialsFromUrl(
        'https://tv.example/get.php?username=user%20name&password=p%40ss%2Fword&type=m3u_plus',
      );
      expect(credentials, isNotNull);
      expect(credentials!.username, 'user name');
      expect(credentials.password, 'p@ss/word');
    });

    test('encodes credentials as path segments', () {
      const credentials = XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user name',
        password: 'p@ss/word',
      );
      final uri = Uri.parse(
        XtreamClient(credentials).streamUrl('live', 42, ext: '.ts'),
      );
      expect(uri.pathSegments, ['live', 'user name', 'p@ss/word', '42.ts']);
    });
  });

  group('M3U parsing', () {
    const first = '''
#EXTM3U url-tvg="https://guide.example/epg.xml"
#EXTINF:-1 tvg-id="NewsOne.in" tvg-name="News One" group-title="News",News
#EXTVLCOPT:http-user-agent=Lumen Test
#KODIPROP:inputstream.adaptive.stream_headers=Referer=https%3A%2F%2Fportal.example
https://stream.example/news.m3u8
#EXTINF:-1 group-title="Sport",Sport
https://stream.example/sport.m3u8|User-Agent=PipeAgent&Origin=https%3A%2F%2Fportal.example
''';

    const reordered = '''
#EXTM3U
#EXTINF:-1 group-title="Sport",Sport
https://stream.example/sport.m3u8|User-Agent=PipeAgent&Origin=https%3A%2F%2Fportal.example
#EXTINF:-1 group-title="News",News
#EXTVLCOPT:http-user-agent=Lumen Test
#KODIPROP:inputstream.adaptive.stream_headers=Referer=https%3A%2F%2Fportal.example
https://stream.example/news.m3u8
''';

    test('keeps stable channel IDs when the playlist is reordered', () {
      final a = parseM3uPlaylist(first);
      final b = parseM3uPlaylist(reordered);
      int idFor(ParsedM3uPlaylist value, String name) =>
          value.channels.singleWhere((c) => c.name == name).streamId;

      expect(idFor(a, 'News'), idFor(b, 'News'));
      expect(idFor(a, 'Sport'), idFor(b, 'Sport'));
    });

    test('parses channel headers and groups', () {
      final parsed = parseM3uPlaylist(first);
      final news = parsed.channels.singleWhere((c) => c.name == 'News');
      final sport = parsed.channels.singleWhere((c) => c.name == 'Sport');

      expect(news.categoryId, 'News');
      expect(news.epgId, 'NewsOne.in');
      expect(news.epgName, 'News One');
      expect(parsed.epgUrls, ['https://guide.example/epg.xml']);
      expect(parsed.headers[news.streamId], {
        'User-Agent': 'Lumen Test',
        'Referer': 'https://portal.example',
      });
      expect(parsed.headers[sport.streamId], {
        'User-Agent': 'PipeAgent',
        'Origin': 'https://portal.example',
      });
    });
  });

  test('short EPG uses a bounded Xtream request', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/player_api.php');
      expect(request.url.queryParameters['action'], 'get_short_epg');
      expect(request.url.queryParameters['stream_id'], '42');
      expect(request.url.queryParameters['limit'], '12');
      return http.Response(
        jsonEncode({
          'epg_listings': [
            {
              'channel_id': 'news',
              'title': base64.encode(utf8.encode('News now')),
              'start_timestamp': 1789221600,
              'stop_timestamp': 1789223400,
            },
          ],
        }),
        200,
      );
    });
    final api = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user',
        password: 'pass',
      ),
      httpClient: client,
    );

    final guide = await api.shortEpg(42, limit: 99);
    expect(guide.single.title, 'News now');
  });
}
