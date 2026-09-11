import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lumen_tv/channel_logos.dart';
import 'package:lumen_tv/epg.dart';
import 'package:lumen_tv/models.dart';

void main() {
  test('normalizes IPTV quality and country decorations', () {
    expect(normalizeChannelName('IN: Star Plus (FHD)'), 'starplus');
    expect(normalizeChannelName('BBC One UK [HEVC]'), 'bbconeuk');
  });

  test('XMLTV matches tvg-id first and rejects ambiguous display names', () {
    final index = XmltvLogoIndex.parse('''
      <tv>
        <channel id="BBCOne.uk">
          <display-name>BBC One</display-name>
          <icon src="https://guide.example/bbc.png" />
        </channel>
        <channel id="NewsOne.in">
          <display-name>News One</display-name>
          <icon src="https://guide.example/news-a.png" />
        </channel>
        <channel id="NewsOne.pk">
          <display-name>News One</display-name>
          <icon src="https://guide.example/news-b.png" />
        </channel>
      </tv>
    ''');

    expect(
      index.logoFor(
        LiveStream(1, 'Renamed by provider', '', 'UK', epgId: 'BBCOne.uk'),
      ),
      'https://guide.example/bbc.png',
    );
    expect(index.logoFor(LiveStream(2, 'News One', '', 'News')), isNull);
  });

  test('cached EPG channels provide the same conservative logo index', () {
    final index = XmltvLogoIndex.fromEpgChannels(const [
      EpgChannel(
        channelKey: 'BBCOne.uk',
        displayNames: ['BBC One'],
        icon: 'https://guide.example/bbc.png',
      ),
    ]);

    expect(
      index.logoFor(
        LiveStream(1, 'Provider label', '', 'UK', epgId: 'BBCOne.uk'),
      ),
      'https://guide.example/bbc.png',
    );
  });

  test('public catalog uses exact IDs and conservative country matching', () {
    final catalog = ChannelLogoCatalog.parse(
      '''
      [
        {"id":"NewsOne.in","name":"News One","alt_names":[],"country":"IN"},
        {"id":"NewsOne.pk","name":"News One","alt_names":[],"country":"PK"},
        {"id":"BBCOne.uk","name":"BBC One","alt_names":["BBC 1"],"country":"GB"}
      ]
    ''',
      '''
      [
        {"channel":"NewsOne.in","in_use":true,"width":400,"height":200,"format":"PNG","url":"https://logos.example/news-in.png"},
        {"channel":"NewsOne.pk","in_use":true,"width":400,"height":200,"format":"PNG","url":"https://logos.example/news-pk.png"},
        {"channel":"BBCOne.uk","in_use":true,"width":400,"height":200,"format":"PNG","url":"https://logos.example/bbc.png"}
      ]
    ''',
    );

    expect(
      catalog.logoFor(
        LiveStream(1, 'Anything', '', 'News', epgId: 'BBCOne.uk'),
      ),
      'https://logos.example/bbc.png',
    );
    expect(
      catalog.logoFor(LiveStream(2, 'PK: News One HD', '', 'Pakistan')),
      'https://logos.example/news-pk.png',
    );
    expect(catalog.logoFor(LiveStream(3, 'News One', '', 'News')), isNull);
  });

  test(
    'resolver preserves provider artwork and fills missing XMLTV logos',
    () async {
      var catalogLoaded = false;
      final resolver = ChannelLogoResolver(
        httpClient: MockClient((_) async => throw StateError('no network')),
        guideLoader: (_) async => XmltvLogoIndex.parse('''
        <tv>
          <channel id="One.in"><display-name>One</display-name>
            <icon src="https://guide.example/one.png" /></channel>
          <channel id="Two.in"><display-name>Two</display-name>
            <icon src="https://guide.example/two.png" /></channel>
        </tv>
      '''),
        catalogLoader: () async {
          catalogLoaded = true;
          return ChannelLogoCatalog.parse('[]', '[]');
        },
      );

      final result = await resolver.resolve(
        [
          LiveStream(
            1,
            'One',
            'https://provider.example/one.png',
            'India',
            epgId: 'One.in',
          ),
          LiveStream(2, 'Two', '', 'India', epgId: 'Two.in'),
        ],
        guideUrls: [Uri.parse('https://guide.example/epg.xml')],
      );

      expect(result[0].icon, 'https://provider.example/one.png');
      expect(result[0].fallbackIcon, 'https://guide.example/one.png');
      expect(result[1].icon, 'https://guide.example/two.png');
      expect(result[1].logoSource, 'xmltv');
      expect(catalogLoaded, isFalse);
    },
  );
}
