import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/epg_loader.dart';

void main() {
  final store = CatalogStore.instance;

  setUp(() async {
    await store.useInMemoryForTests();
  });

  tearDown(() => store.close());

  const xml = '''
<tv>
  <channel id="one"><display-name>One</display-name></channel>
  <programme channel="one" start="20260912100000 +0000" stop="20260912110000 +0000">
    <title>First show</title>
  </programme>
</tv>
''';

  test(
    'persists a successful guide and revalidates it conditionally',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (requests == 1) {
          expect(request.headers['If-None-Match'], isNull);
          return http.Response(
            xml,
            200,
            headers: {
              'etag': '"v1"',
              'content-type': 'application/xml',
              // Mock an IO transport that already expanded the body but kept
              // the provider's original encoding header.
              'content-encoding': 'gzip',
            },
          );
        }
        expect(request.headers['If-None-Match'], '"v1"');
        return http.Response('', 304, headers: {'etag': '"v1"'});
      });
      final loader = EpgXmltvLoader(httpClient: client, store: store);
      final uri = Uri.parse(
        'https://guide.example/xmltv.php?username=secret&password=hidden',
      );

      final first = await loader.sync(
        profileScope: 'profile',
        uri: uri,
        now: DateTime.utc(2026, 9, 12, 9),
      );
      expect(first.notModified, isFalse);
      expect(first.sourceKey, isNot(contains('secret')));
      expect(first.summary?.storedProgrammeCount, 1);

      final second = await loader.sync(
        profileScope: 'profile',
        uri: uri,
        now: DateTime.utc(2026, 9, 12, 10),
      );
      expect(second.notModified, isTrue);
      expect(
        (await store.epgSourceState('profile', first.sourceKey))?.fetchedAt,
        DateTime.utc(2026, 9, 12, 10),
      );
    },
  );

  test('malformed replacement keeps the last complete generation', () async {
    var valid = true;
    final client = MockClient(
      (_) async => http.Response(
        valid ? xml : '<tv><programme>',
        200,
        headers: {'content-type': 'application/xml'},
      ),
    );
    final loader = EpgXmltvLoader(httpClient: client, store: store);
    final uri = Uri.parse('https://guide.example/epg.xml');
    final first = await loader.sync(
      profileScope: 'profile',
      uri: uri,
      now: DateTime.utc(2026, 9, 12, 9),
    );
    valid = false;

    await expectLater(
      loader.sync(
        profileScope: 'profile',
        uri: uri,
        now: DateTime.utc(2026, 9, 12, 10),
      ),
      throwsA(isA<EpgSyncException>()),
    );
    final cached = await store.epgWindow(
      'profile',
      first.sourceKey,
      channelKeys: const ['one'],
      startUtc: DateTime.utc(2026, 9, 12, 9),
      endUtc: DateTime.utc(2026, 9, 12, 12),
    );
    expect(cached.single.title, 'First show');
  });
}
