import 'package:flutter_test/flutter_test.dart';
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
#EXTM3U
#EXTINF:-1 tvg-id="news.uk" group-title="News" catchup="append" catchup-days="3" catchup-source="https://catch.example/watch?start={utc}&end={utcend}",News
#EXTVLCOPT:http-user-agent=Lumen Test
#KODIPROP:inputstream.adaptive.stream_headers=Referer=https%3A%2F%2Fportal.example
https://stream.example/news.m3u8
#EXTINF:-1 tvg-id="sport.uk" group-title="Sport",Sport
https://stream.example/sport.m3u8|User-Agent=PipeAgent&Origin=https%3A%2F%2Fportal.example
''';

    const reordered = '''
#EXTM3U
#EXTINF:-1 tvg-id="sport.uk" group-title="Sport",Sport
https://stream.example/sport.m3u8|User-Agent=PipeAgent&Origin=https%3A%2F%2Fportal.example
#EXTINF:-1 tvg-id="news.uk" group-title="News" catchup="append" catchup-days="3" catchup-source="https://catch.example/watch?start={utc}&end={utcend}",News
#EXTVLCOPT:http-user-agent=Lumen Test
#KODIPROP:inputstream.adaptive.stream_headers=Referer=https%3A%2F%2Fportal.example
https://stream.example/news.m3u8
''';

    test('keeps stable channel IDs when the playlist is reordered', () {
      final a = parseM3uPlaylist(first);
      final b = parseM3uPlaylist(reordered);
      int idFor(ParsedM3uPlaylist value, String tvg) =>
          value.channels.singleWhere((c) => c.epgChannelId == tvg).streamId;

      expect(idFor(a, 'news.uk'), idFor(b, 'news.uk'));
      expect(idFor(a, 'sport.uk'), idFor(b, 'sport.uk'));
    });

    test('parses headers, groups, and catch-up metadata', () {
      final parsed = parseM3uPlaylist(first);
      final news = parsed.channels.singleWhere(
        (c) => c.epgChannelId == 'news.uk',
      );
      final sport = parsed.channels.singleWhere(
        (c) => c.epgChannelId == 'sport.uk',
      );

      expect(news.categoryId, 'News');
      expect(news.hasArchive, isTrue);
      expect(news.tvArchiveDuration, 3);
      expect(parsed.headers[news.streamId], {
        'User-Agent': 'Lumen Test',
        'Referer': 'https://portal.example',
      });
      expect(parsed.headers[sport.streamId], {
        'User-Agent': 'PipeAgent',
        'Origin': 'https://portal.example',
      });
      expect(parsed.catchupSources[news.streamId], contains('{utc}'));
    });
  });

  group('XMLTV parsing', () {
    test('accepts arbitrary attribute order, CDATA, and entities', () {
      final guide = parseXmltvGuide('''
<?xml version="1.0"?>
<tv>
  <programme channel="news.uk" stop="20260722220000 +0500" start="20260722210000 +0500">
    <title><![CDATA[News & Weather]]></title>
    <desc>Headlines &amp; analysis</desc>
  </programme>
</tv>
''');
      final entry = guide['news.uk']!.single;
      expect(entry.title, 'News & Weather');
      expect(entry.description, 'Headlines & analysis');
      expect(entry.start.toUtc(), DateTime.utc(2026, 7, 22, 16));
      expect(entry.end.toUtc(), DateTime.utc(2026, 7, 22, 17));
    });
  });
}
