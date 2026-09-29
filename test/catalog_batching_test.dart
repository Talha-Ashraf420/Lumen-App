import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/epg.dart';
import 'package:lumen_tv/models.dart';

// Measures synchronous serialization work between event-loop turns without
// relying on machine speed or flaky wall-clock thresholds.
class _ObservedList<T> extends ListBase<T> {
  _ObservedList(this.values, {this.throwAt});

  final List<T> values;
  final int? throwAt;
  int maxReadsPerTurn = 0;
  int _reads = 0;
  bool _resetScheduled = false;

  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  void operator []=(int index, T value) => throw UnsupportedError('read only');

  @override
  T operator [](int index) {
    if (index == throwAt) throw StateError('malformed provider item');
    maxReadsPerTurn = math.max(maxReadsPerTurn, ++_reads);
    if (!_resetScheduled) {
      _resetScheduled = true;
      Timer.run(() {
        _reads = 0;
        _resetScheduled = false;
      });
    }
    return values[index];
  }
}

void main() {
  final store = CatalogStore.instance;
  setUp(store.useInMemoryForTests);
  tearDown(store.close);

  test(
    'large catalog yields while preserving order, pages and generations',
    () async {
      final rows = _ObservedList(
        List.generate(1805, (i) => LiveStream(i, 'Channel $i', '', 'sports')),
      );
      expect(
        await store.replaceLive('viewer', 'sports', rows, generation: 20),
        isTrue,
      );
      expect(rows.maxReadsPerTurn, lessThanOrEqualTo(300));
      final boundary = await store.livePage(
        'viewer',
        bucket: 'sports',
        offset: 295,
        limit: 12,
      );
      expect(
        boundary.items.map((item) => item.streamId),
        List.generate(12, (i) => i + 295),
      );
      expect(boundary.hasMore, isTrue);
      final tail = await store.livePage(
        'viewer',
        bucket: 'sports',
        offset: 1800,
        limit: 48,
      );
      expect(tail.items.map((item) => item.streamId), [
        1800,
        1801,
        1802,
        1803,
        1804,
      ]);
      expect(tail.hasMore, isFalse);
      expect(
        await store.replaceLive('viewer', 'sports', [], generation: 19),
        isFalse,
      );
      expect(
        (await store.livePage('viewer', bucket: 'sports')).items.first.streamId,
        0,
      );
    },
  );

  test(
    'failure after committed chunks rolls back the entire catalog replacement',
    () async {
      await store.replaceLive('viewer', 'sports', [
        LiveStream(99, 'Last good channel', '', 'sports'),
      ], generation: 10);
      final broken = _ObservedList(
        List.generate(
          905,
          (i) => LiveStream(i, 'Replacement $i', '', 'sports'),
        ),
        throwAt: 650,
      );
      expect(
        await store.replaceLive('viewer', 'sports', broken, generation: 20),
        isFalse,
      );
      expect(
        (await store.livePage('viewer', bucket: 'sports')).items.single.name,
        'Last good channel',
      );
      // The failed transaction must also roll back its generation marker.
      expect(
        await store.replaceLive('viewer', 'sports', [
          LiveStream(42, 'Retry', '', 'sports'),
        ], generation: 15),
        isTrue,
      );
    },
  );

  test(
    'EPG chunks yield and stay hidden until the complete guide is activated',
    () async {
      final start = DateTime.utc(2026, 9, 30);
      final channels = _ObservedList(
        List.generate(
          905,
          (i) => EpgChannel(channelKey: '$i', displayNames: ['Channel $i']),
        ),
      );
      final programmes = _ObservedList(
        List.generate(
          905,
          (i) => EpgProgramme(
            channelKey: '$i',
            startUtc: start,
            stopUtc: start.add(const Duration(hours: 1)),
            title: 'Programme $i',
          ),
        ),
      );
      await store.beginEpgImport('viewer', 'guide', 10);
      await store.appendEpgChannels('viewer', 'guide', 10, channels);
      await store.appendEpgProgrammes('viewer', 'guide', 10, programmes);
      expect(channels.maxReadsPerTurn, lessThanOrEqualTo(300));
      expect(programmes.maxReadsPerTurn, lessThanOrEqualTo(300));
      expect(await store.epgChannels('viewer', 'guide'), isEmpty);
      await store.completeEpgImport('viewer', 'guide', 10);
      expect(await store.epgChannels('viewer', 'guide'), hasLength(905));
      final page = await store.epgWindow(
        'viewer',
        'guide',
        channelKeys: ['299', '300', '904'],
        startUtc: start,
        endUtc: start.add(const Duration(hours: 1)),
      );
      expect(
        page.map((p) => p.title),
        unorderedEquals(['Programme 299', 'Programme 300', 'Programme 904']),
      );
    },
  );
}
