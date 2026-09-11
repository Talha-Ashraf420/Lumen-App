import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/epg.dart';
import 'package:lumen_tv/epg_repository.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/epg_guide_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

String _xmltvTime(DateTime value) {
  final utc = value.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)} +0000';
}

Future<
  ({
    XtreamClient client,
    EpgRepository repository,
    EpgProgramme programme,
    EpgProgramme secondProgramme,
  })
>
_fixture() async {
  final now = DateTime.now().toUtc();
  final rounded = DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute < 30 ? 0 : 30,
  );
  final start = rounded.subtract(const Duration(minutes: 15));
  final stop = start.add(const Duration(hours: 1));
  final transport = MockClient((request) async {
    if (request.url.host == 'playlist.example') {
      return http.Response('''
#EXTM3U url-tvg="https://guide.example/epg.xml"
#EXTINF:-1 tvg-id="news.example" group-title="News",World News
https://stream.example/news.m3u8
''', 200);
    }
    if (request.url.host == 'guide.example') {
      return http.Response(
        '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="news.example"><display-name>World News</display-name></channel>
  <channel id="sport.example"><display-name>World Sport</display-name></channel>
  <programme channel="news.example" start="${_xmltvTime(start)}" stop="${_xmltvTime(stop)}">
    <title>EPG fixture programme</title>
  </programme>
  <programme channel="sport.example" start="${_xmltvTime(start)}" stop="${_xmltvTime(stop)}">
    <title>Sport fixture programme</title>
  </programme>
</tv>
''',
        200,
        headers: {'content-type': 'application/xml'},
      );
    }
    return http.Response('Not found', 404);
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
  final repository = EpgRepository(
    client: client,
    store: CatalogStore.instance,
  );
  return (
    client: client,
    repository: repository,
    programme: EpgProgramme(
      channelKey: 'news.example',
      startUtc: start,
      stopUtc: stop,
      title: 'EPG fixture programme',
    ),
    secondProgramme: EpgProgramme(
      channelKey: 'sport.example',
      startUtc: start,
      stopUtc: stop,
      title: 'Sport fixture programme',
    ),
  );
}

void main() {
  setUp(() async {
    await CatalogStore.instance.useInMemoryForTests();
  });

  tearDown(() => CatalogStore.instance.close());

  testWidgets('desktop guide lazily renders pinned grid programme', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = await _fixture();
    addTearDown(fixture.repository.dispose);
    await tester.runAsync(fixture.repository.ensureFullGuide);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: EpgGuideScreen(
          client: fixture.client,
          repository: fixture.repository,
          channels: [
            LiveStream(1, 'World News', '', 'News', epgId: 'news.example'),
          ],
          initialGuide: {
            1: [fixture.programme],
          },
        ),
      ),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('EPG fixture programme'), findsOneWidget);
    expect(find.byType(TableView), findsOneWidget);
  });

  testWidgets('phone guide uses readable agenda layout', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = await _fixture();
    addTearDown(fixture.repository.dispose);
    await tester.runAsync(fixture.repository.ensureFullGuide);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: EpgGuideScreen(
          client: fixture.client,
          repository: fixture.repository,
          channels: [
            LiveStream(1, 'World News', '', 'News', epgId: 'news.example'),
          ],
          initialGuide: {
            1: [fixture.programme],
          },
        ),
      ),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('World News'), findsOneWidget);
    expect(find.text('EPG fixture programme'), findsOneWidget);
    expect(find.byType(TableView), findsNothing);
  });

  testWidgets(
    'TV D-pad moves from toolbar through channels by programme time',
    (tester) async {
      DeviceProfile.isTelevision = true;
      addTearDown(() => DeviceProfile.isTelevision = false);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = await _fixture();
      addTearDown(fixture.repository.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          home: EpgGuideScreen(
            client: fixture.client,
            repository: fixture.repository,
            channels: [
              LiveStream(1, 'World News', '', 'News', epgId: 'news.example'),
              LiveStream(2, 'World Sport', '', 'Sport', epgId: 'sport.example'),
            ],
            initialGuide: {
              1: [fixture.programme],
              2: [fixture.secondProgramme],
            },
          ),
        ),
      );
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide now');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide channel 0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide programme 0 EPG fixture programme',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide programme 1 Sport fixture programme',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
