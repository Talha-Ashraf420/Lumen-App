import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/epg.dart';
import 'package:lumen_tv/epg_repository.dart';
import 'package:lumen_tv/epg_loader.dart';
import 'package:lumen_tv/epg_settings.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = CatalogStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.useInMemoryForTests();
  });

  tearDown(() => store.close());

  test('short EPG loading stays silent until programme data changes', () async {
    final pending = Completer<http.Response>();
    final transport = MockClient((_) => pending.future);
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user',
        password: 'pass',
      ),
      httpClient: transport,
    );
    final repository = EpgRepository(client: client, store: store);
    addTearDown(() {
      repository.dispose();
      client.close();
    });
    var notifications = 0;
    repository.addListener(() => notifications++);

    await repository.primeVisible([LiveStream(42, 'Channel', '', 'all')]);
    expect(repository.shortRequestsInFlight, 1);
    expect(notifications, 0);

    final now = DateTime.now().toUtc();
    pending.complete(
      http.Response(
        jsonEncode({
          'epg_listings': [
            {
              'channel_id': '42',
              'title': 'Playing now',
              'start_timestamp':
                  now
                      .subtract(const Duration(minutes: 5))
                      .millisecondsSinceEpoch ~/
                  1000,
              'stop_timestamp':
                  now.add(const Duration(minutes: 55)).millisecondsSinceEpoch ~/
                  1000,
            },
          ],
        }),
        200,
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (repository.shortRequestsInFlight > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(repository.nowNextFor(42).now?.title, 'Playing now');
    expect(notifications, 1);
  });

  test('short EPG queue never exceeds two provider calls', () async {
    final fixedNow = DateTime.utc(2026, 9, 12, 10, 15);
    var active = 0;
    var maximum = 0;
    var calls = 0;
    final transport = MockClient((request) async {
      active++;
      calls++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final streamId = request.url.queryParameters['stream_id']!;
      active--;
      return http.Response(
        jsonEncode({
          'epg_listings': [
            {
              'channel_id': 'provider-$streamId',
              'title': 'Now $streamId',
              'start_timestamp':
                  fixedNow
                      .subtract(const Duration(minutes: 15))
                      .millisecondsSinceEpoch ~/
                  1000,
              'stop_timestamp':
                  fixedNow
                      .add(const Duration(minutes: 45))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
          ],
        }),
        200,
      );
    });
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user',
        password: 'pass',
      ),
      httpClient: transport,
    );
    final repository = EpgRepository(
      client: client,
      store: store,
      clock: () => fixedNow,
    );
    final channels = [
      for (var id = 1; id <= 7; id++) LiveStream(id, 'Channel $id', '', 'all'),
    ];

    await repository.primeVisible(channels);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (repository.nowNextFor(7).now == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(maximum, lessThanOrEqualTo(2));
    expect(calls, 7);
    expect(repository.nowNextFor(7).now?.title, 'Now 7');

    await repository.primeVisible(channels);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 7, reason: 'fresh visible channels should not be refetched');
    repository.dispose();
  });

  test('matches exact IDs first and only unique exact names', () {
    final channels = [
      LiveStream(1, 'Fallback News', '', 'all', epgId: 'NEWS.US'),
      LiveStream(2, 'Unique Sports HD', '', 'all'),
      LiveStream(3, 'Duplicate', '', 'all'),
    ];
    const guide = [
      EpgChannel(channelKey: 'news.us', displayNames: ['Other']),
      EpgChannel(channelKey: 'sport', displayNames: ['Unique Sports']),
      EpgChannel(channelKey: 'duplicate-a', displayNames: ['Duplicate']),
      EpgChannel(channelKey: 'duplicate-b', displayNames: ['Duplicate']),
    ];

    expect(matchEpgChannels(channels, guide), {1: 'news.us', 2: 'sport'});
  });

  test(
    'rapid visible-window changes prune stale queued provider calls',
    () async {
      final fixedNow = DateTime.utc(2026, 9, 12, 10, 15);
      final calls = <int>[];
      final transport = MockClient((request) async {
        final id = int.parse(request.url.queryParameters['stream_id']!);
        calls.add(id);
        await Future<void>.delayed(const Duration(milliseconds: 35));
        return http.Response(jsonEncode({'epg_listings': <Object>[]}), 200);
      });
      final repository = EpgRepository(
        client: XtreamClient(
          const XtreamCredentials(
            baseUrl: 'https://tv.example',
            username: 'user',
            password: 'pass',
          ),
          httpClient: transport,
        ),
        store: store,
        clock: () => fixedNow,
      );
      final channels = [
        for (var id = 1; id <= 7; id++)
          LiveStream(id, 'Channel $id', '', 'all'),
      ];

      final first = repository.primeVisible(channels.take(6));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = repository.primeVisible(channels.skip(5));
      await Future.wait([first, second]);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(calls.where((id) => id >= 3 && id <= 5), isEmpty);
      expect(calls, containsAll(<int>[6, 7]));
      repository.dispose();
    },
  );

  test(
    'M3U Live reads Now and Next from cached XMLTV without redownloading',
    () async {
      final fixedNow = DateTime.utc(2026, 9, 12, 10, 15);
      var playlistCalls = 0;
      var guideCalls = 0;
      final transport = MockClient((request) async {
        if (request.url.host == 'playlist.example') {
          playlistCalls++;
          return http.Response('''
#EXTM3U url-tvg="https://guide.example/epg.xml"
#EXTINF:-1 tvg-id="news.example" group-title="News",World News
https://stream.example/news.m3u8
''', 200);
        }
        guideCalls++;
        return http.Response('Unexpected guide request', 500);
      });
      final client = XtreamClient(
        const XtreamCredentials(
          baseUrl: 'https://playlist.example',
          username: '',
          password: '',
          m3uUrl: 'https://playlist.example/list.m3u',
        ),
        httpClient: transport,
      );
      final guideUri = Uri.parse('https://guide.example/epg.xml');
      final sourceKey = epgSourceKey(guideUri);
      await store.beginEpgImport(repositoryScope(client), sourceKey, 12);
      await store.appendEpgChannels(
        repositoryScope(client),
        sourceKey,
        12,
        const [
          EpgChannel(channelKey: 'news.example', displayNames: ['World News']),
        ],
      );
      await store.appendEpgProgrammes(repositoryScope(client), sourceKey, 12, [
        EpgProgramme(
          channelKey: 'news.example',
          startUtc: fixedNow.subtract(const Duration(minutes: 15)),
          stopUtc: fixedNow.add(const Duration(minutes: 15)),
          title: 'Cached current show',
        ),
        EpgProgramme(
          channelKey: 'news.example',
          startUtc: fixedNow.add(const Duration(minutes: 15)),
          stopUtc: fixedNow.add(const Duration(minutes: 45)),
          title: 'Cached next show',
        ),
      ]);
      await store.completeEpgImport(
        repositoryScope(client),
        sourceKey,
        12,
        fetchedAt: fixedNow,
      );
      final repository = EpgRepository(
        client: client,
        store: store,
        clock: () => fixedNow,
      );

      await repository.primeVisible([
        LiveStream(1, 'World News', '', 'News', epgId: 'news.example'),
      ]);

      expect(repository.nowNextFor(1).now?.title, 'Cached current show');
      expect(repository.nowNextFor(1).next?.title, 'Cached next show');
      expect(playlistCalls, 1);
      expect(guideCalls, 0);
      repository.dispose();
    },
  );

  test('manual XMLTV source is refreshed before the provider source', () async {
    final calls = <Uri>[];
    final transport = MockClient((request) async {
      calls.add(request.url);
      if (request.url.host == 'guide.example') {
        return http.Response('''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="news.example"><display-name>World News</display-name></channel>
  <programme channel="news.example" start="20260912100000 +0000" stop="20260912110000 +0000">
    <title>Manual guide show</title>
  </programme>
</tv>
''', 200);
      }
      return http.Response('Provider guide unavailable', 503);
    });
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user',
        password: 'pass',
      ),
      httpClient: transport,
    );
    await EpgSettings.save(
      client.creds,
      manualUrl: 'https://guide.example/custom.xml',
      offsetMinutes: 0,
    );
    final repository = EpgRepository(
      client: client,
      store: store,
      clock: () => DateTime.utc(2026, 9, 12, 10, 30),
    );

    await repository.ensureFullGuide(force: true);

    expect(calls.first.host, 'guide.example');
    expect(
      await store.epgSourceState(
        repositoryScope(client),
        epgSourceKey(Uri.parse('https://guide.example/custom.xml')),
      ),
      isNotNull,
    );
    repository.dispose();
  });

  test(
    'time correction shifts display results without rewriting cache',
    () async {
      final fixedNow = DateTime.utc(2026, 9, 12, 10, 30);
      final client = XtreamClient(
        const XtreamCredentials(
          baseUrl: 'https://tv.example',
          username: 'user',
          password: 'pass',
        ),
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      final uri = (await client.epgGuideUrls()).single;
      final source = epgSourceKey(uri);
      await store.beginEpgImport(repositoryScope(client), source, 1);
      await store.appendEpgChannels(repositoryScope(client), source, 1, const [
        EpgChannel(channelKey: 'news.example', displayNames: ['World News']),
      ]);
      await store.appendEpgProgrammes(repositoryScope(client), source, 1, [
        EpgProgramme(
          channelKey: 'news.example',
          startUtc: DateTime.utc(2026, 9, 12, 9),
          stopUtc: DateTime.utc(2026, 9, 12, 10),
          title: 'Shifted show',
        ),
      ]);
      await store.completeEpgImport(repositoryScope(client), source, 1);
      await EpgSettings.save(client.creds, manualUrl: '', offsetMinutes: 60);
      final repository = EpgRepository(
        client: client,
        store: store,
        clock: () => fixedNow,
      );
      final channel = LiveStream(
        1,
        'World News',
        '',
        'News',
        epgId: 'news.example',
      );

      final result = await repository.guideWindow(
        [channel],
        startUtc: DateTime.utc(2026, 9, 12, 9, 30),
        endUtc: DateTime.utc(2026, 9, 12, 11, 30),
      );
      final raw = await store.epgWindow(
        repositoryScope(client),
        source,
        channelKeys: const ['news.example'],
        startUtc: DateTime.utc(2026, 9, 12, 8),
        endUtc: DateTime.utc(2026, 9, 12, 11),
      );

      expect(result[1]!.single.startUtc, DateTime.utc(2026, 9, 12, 10));
      expect(raw.single.startUtc, DateTime.utc(2026, 9, 12, 9));
      repository.dispose();
    },
  );

  test('manual mapping overrides an otherwise valid automatic match', () async {
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://tv.example',
        username: 'user',
        password: 'pass',
      ),
      httpClient: MockClient((_) async => http.Response('', 200)),
    );
    final uri = (await client.epgGuideUrls()).single;
    final source = epgSourceKey(uri);
    final scope = repositoryScope(client);
    await store.beginEpgImport(scope, source, 1);
    await store.appendEpgChannels(scope, source, 1, const [
      EpgChannel(channelKey: 'news.auto', displayNames: ['World News']),
      EpgChannel(channelKey: 'news.manual', displayNames: ['Other News']),
    ]);
    await store.appendEpgProgrammes(scope, source, 1, [
      EpgProgramme(
        channelKey: 'news.auto',
        startUtc: DateTime.utc(2026, 9, 12, 9),
        stopUtc: DateTime.utc(2026, 9, 12, 11),
        title: 'Automatic programme',
      ),
      EpgProgramme(
        channelKey: 'news.manual',
        startUtc: DateTime.utc(2026, 9, 12, 9),
        stopUtc: DateTime.utc(2026, 9, 12, 11),
        title: 'Manually selected programme',
      ),
    ]);
    await store.completeEpgImport(scope, source, 1);
    await store.setManualEpgChannelMapping(
      scope,
      liveStreamId: 9,
      sourceKey: source,
      epgChannelKey: 'news.manual',
    );
    final repository = EpgRepository(client: client, store: store);

    final guide = await repository.guideWindow(
      [LiveStream(9, 'World News', '', 'News')],
      startUtc: DateTime.utc(2026, 9, 12, 9, 30),
      endUtc: DateTime.utc(2026, 9, 12, 10, 30),
    );

    expect(guide[9]!.map((programme) => programme.title), [
      'Manually selected programme',
    ]);
    repository.dispose();
  });
}

String repositoryScope(XtreamClient client) => Store.profileScope(client.creds);
