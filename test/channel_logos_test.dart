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

  test('shared country artwork is replaced only across unrelated brands', () {
    const flag = 'https://provider.example/india-flag.png';
    final channels = [
      LiveStream(1, 'IN: PTV Sports HD', flag, 'India'),
      LiveStream(2, 'IN: Zee Cinema', flag, 'India'),
      LiveStream(3, 'IN: Sony Sports 2', flag, 'India'),
      LiveStream(4, 'IN: Times Now World', flag, 'India'),
    ];
    expect(sharedProviderPlaceholderLogos(channels), {flag});
    expect(
      sharedProviderPlaceholderLogos([
        for (var index = 1; index <= 5; index++)
          LiveStream(index, 'Sky Sports $index', flag, 'Sports'),
      ]),
      isEmpty,
    );
  });

  test('shared provider flags yield to exact catalog logos', () async {
    const flag = 'https://provider.example/india-flag.png';
    final resolver = ChannelLogoResolver(
      httpClient: MockClient((_) async => throw StateError('no network')),
      catalogLoader: () async => ChannelLogoCatalog.parse(
        '[{"id":"PTVSports.pk","name":"PTV Sports","country":"PK"},'
            '{"id":"ZeeCinema.in","name":"Zee Cinema","country":"IN"},'
            '{"id":"SonySports.in","name":"Sony Sports 2","country":"IN"}]',
        '[{"channel":"PTVSports.pk","in_use":true,"width":400,'
            '"height":200,"format":"PNG","url":"https://logos.example/ptv.png"},'
            '{"channel":"ZeeCinema.in","in_use":true,"width":400,'
            '"height":200,"format":"PNG","url":"https://logos.example/zee.png"},'
            '{"channel":"SonySports.in","in_use":true,"width":400,'
            '"height":200,"format":"PNG","url":"https://logos.example/sony.png"}]',
      ),
    );
    final channels = await resolver.resolve([
      LiveStream(1, 'IN: PTV Sports HD', flag, 'India'),
      LiveStream(2, 'IN: Zee Cinema', flag, 'India'),
      LiveStream(3, 'IN: Sony Sports 2', flag, 'India'),
      LiveStream(4, 'IN: Times Now World', flag, 'India'),
    ]);

    expect(channels[0].icon, 'https://logos.example/ptv.png');
    expect(channels[1].icon, 'https://logos.example/zee.png');
    expect(channels[2].icon, 'https://logos.example/sony.png');
    expect(channels[3].icon, isEmpty);
    expect(channels.every((channel) => channel.icon != flag), isTrue);
  });

  test(
    'keeps a distinct provider logo and adds a public failure fallback',
    () async {
      final resolver = ChannelLogoResolver(
        httpClient: MockClient((_) async => throw StateError('no network')),
        catalogLoader: () async => ChannelLogoCatalog.parse(
          '[{"id":"BBCOne.uk","name":"BBC One","country":"GB"}]',
          '[{"channel":"BBCOne.uk","in_use":true,"width":400,'
              '"height":200,"format":"PNG","url":"https://logos.example/bbc.png"}]',
        ),
      );

      final channels = await resolver.resolve([
        LiveStream(
          1,
          'BBC One',
          'https://provider.example/bbc.png',
          'News',
          epgId: 'BBCOne.uk',
        ),
      ]);
      expect(channels.single.icon, 'https://provider.example/bbc.png');
      expect(channels.single.fallbackIcon, 'https://logos.example/bbc.png');
    },
  );

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
