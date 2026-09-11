import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/epg.dart';

void main() {
  group('XMLTV timestamps', () {
    test('normalizes explicit offsets and missing zones to UTC', () {
      expect(
        parseXmltvTimestamp('20260912153000 +0500'),
        DateTime.utc(2026, 9, 12, 10, 30),
      );
      expect(
        parseXmltvTimestamp('20260912103000Z'),
        DateTime.utc(2026, 9, 12, 10, 30),
      );
      expect(
        parseXmltvTimestamp('20260912103000'),
        DateTime.utc(2026, 9, 12, 10, 30),
      );
      expect(parseXmltvTimestamp('not-a-date'), isNull);
      expect(parseXmltvTimestamp('20260912109900 +0000'), isNull);
    });
  });

  group('XMLTV streaming parser', () {
    const guide = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="news.example">
    <display-name>World News</display-name>
    <icon src="https://img.example/news.png" />
  </channel>
  <programme channel="news.example" start="20260912100000 +0000">
    <title>Morning &amp; Noon</title>
    <desc><![CDATA[Headlines first]]></desc>
    <category>News</category>
  </programme>
  <programme channel="news.example" start="20260912103000 +0000" stop="20260912110000 +0000">
    <title>Market Update</title>
    <sub-title>Opening bell</sub-title>
  </programme>
  <programme channel="news.example" start="20260913000000 +0000" stop="20260913010000 +0000">
    <title>Outside requested window</title>
  </programme>
</tv>
''';

    test('emits bounded channel and programme batches', () async {
      final channels = <EpgChannel>[];
      final programmes = <EpgProgramme>[];
      final bytes = utf8.encode(guide);
      final chunks = <List<int>>[
        bytes.sublist(0, 37),
        bytes.sublist(37, 151),
        bytes.sublist(151),
      ];

      final summary =
          await const EpgXmltvParser(
            channelBatchSize: 1,
            programmeBatchSize: 1,
          ).parse(
            Stream.fromIterable(chunks),
            windowStartUtc: DateTime.utc(2026, 9, 12, 9),
            windowEndUtc: DateTime.utc(2026, 9, 12, 12),
            onChannels: channels.addAll,
            onProgrammes: programmes.addAll,
          );

      expect(summary.channelCount, 1);
      expect(summary.programmeCount, 3);
      expect(summary.storedProgrammeCount, 2);
      expect(summary.compressedBytes, bytes.length);
      expect(summary.decompressedBytes, bytes.length);
      expect(channels.single.channelKey, 'news.example');
      expect(channels.single.displayNames, ['World News']);
      expect(channels.single.icon, 'https://img.example/news.png');
      expect(programmes.map((item) => item.title), [
        'Morning & Noon',
        'Market Update',
      ]);
      expect(programmes.first.stopUtc, DateTime.utc(2026, 9, 12, 10, 30));
      expect(programmes.first.stopInferred, isTrue);
      expect(programmes.first.categories, ['News']);
      expect(programmes.first.description, 'Headlines first');
    });

    test('decodes gzip without building a full document', () async {
      final programmes = <EpgProgramme>[];
      final compressed = gzip.encode(utf8.encode(guide));
      final summary = await const EpgXmltvParser().parse(
        Stream.value(compressed),
        onProgrammes: programmes.addAll,
      );

      expect(summary.programmeCount, 3);
      expect(programmes, hasLength(3));
      expect(summary.compressedBytes, compressed.length);
      expect(summary.decompressedBytes, utf8.encode(guide).length);
    });

    test('accepts a plain body without relying on transport headers', () async {
      final programmes = <EpgProgramme>[];
      await const EpgXmltvParser().parse(
        Stream.value(utf8.encode(guide)),
        onProgrammes: programmes.addAll,
      );

      expect(programmes, hasLength(3));
    });

    test('rejects guides over the configured resource limit', () async {
      await expectLater(
        const EpgXmltvParser(
          maxDecompressedBytes: 8,
        ).parse(Stream.value(utf8.encode('<tv></tv>'))),
        throwsA(
          isA<EpgParseException>().having(
            (error) => error.message,
            'message',
            contains('expanded EPG'),
          ),
        ),
      );
    });

    test('applies the smaller compressed-payload guard to gzip', () async {
      await expectLater(
        const EpgXmltvParser(
          maxCompressedBytes: 8,
        ).parse(Stream.value(gzip.encode(utf8.encode(guide)))),
        throwsA(
          isA<EpgParseException>().having(
            (error) => error.message,
            'message',
            contains('compressed EPG'),
          ),
        ),
      );
    });
  });

  test('normalizes Xtream short EPG and decodes Base64 metadata', () {
    final programmes = parseXtreamEpg({
      'epg_listings': [
        {
          'id': '55',
          'channel_id': 'news.example',
          'title': base64.encode(utf8.encode('Evening News')),
          'description': base64.encode(utf8.encode('Daily headlines')),
          'start_timestamp': '1789221600',
          'stop_timestamp': 1789223400,
          'has_archive': '1',
        },
      ],
    }, fallbackChannelKey: '42');

    expect(programmes.single.channelKey, 'news.example');
    expect(programmes.single.title, 'Evening News');
    expect(programmes.single.description, 'Daily headlines');
    expect(programmes.single.hasArchive, isTrue);
    expect(programmes.single.catchupId, '55');
  });
}
