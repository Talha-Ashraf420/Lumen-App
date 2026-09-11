import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/epg.dart';

void main() {
  final store = CatalogStore.instance;

  setUp(() async {
    await store.useInMemoryForTests();
  });

  tearDown(() => store.close());

  EpgProgramme programme(String title, int hour) => EpgProgramme(
    channelKey: 'news.example',
    startUtc: DateTime.utc(2026, 9, 12, hour),
    stopUtc: DateTime.utc(2026, 9, 12, hour + 1),
    title: title,
    categories: const ['News'],
  );

  test('activates a complete generation and returns overlap windows', () async {
    await store.beginEpgImport('profile-a', 'source-a', 10);
    await store.appendEpgChannels('profile-a', 'source-a', 10, const [
      EpgChannel(
        channelKey: 'news.example',
        displayNames: ['World News'],
        icon: 'https://img.example/news.png',
      ),
    ]);
    await store.appendEpgProgrammes('profile-a', 'source-a', 10, [
      programme('Morning', 9),
      programme('Midday', 10),
      programme('Evening', 18),
    ]);
    await store.completeEpgImport(
      'profile-a',
      'source-a',
      10,
      etag: '"guide-10"',
      fetchedAt: DateTime.utc(2026, 9, 12, 8),
      validFrom: DateTime.utc(2026, 9, 12, 2),
      validUntil: DateTime.utc(2026, 9, 14, 8),
    );

    final result = await store.epgWindow(
      'profile-a',
      'source-a',
      channelKeys: const ['news.example'],
      startUtc: DateTime.utc(2026, 9, 12, 9, 30),
      endUtc: DateTime.utc(2026, 9, 12, 10, 30),
    );
    expect(result.map((item) => item.title), ['Morning', 'Midday']);
    expect(
      (await store.epgChannels('profile-a', 'source-a')).single.icon,
      'https://img.example/news.png',
    );
    final state = await store.epgSourceState('profile-a', 'source-a');
    expect(state?.activeGeneration, 10);
    expect(state?.etag, '"guide-10"');
    expect(state?.status, 'ready');

    expect(
      await store.epgWindow(
        'profile-b',
        'source-a',
        channelKeys: const ['news.example'],
        startUtc: DateTime.utc(2026, 9, 12),
        endUtc: DateTime.utc(2026, 9, 13),
      ),
      isEmpty,
    );
  });

  test('aborted staging cannot replace the last successful guide', () async {
    await store.beginEpgImport('profile', 'source', 1);
    await store.appendEpgProgrammes('profile', 'source', 1, [
      programme('Last good guide', 9),
    ]);
    await store.completeEpgImport('profile', 'source', 1);

    await store.beginEpgImport('profile', 'source', 2);
    await store.appendEpgProgrammes('profile', 'source', 2, [
      programme('Truncated replacement', 10),
    ]);
    await store.abortEpgImport(
      'profile',
      'source',
      2,
      sanitizedError: 'Malformed XMLTV.',
    );

    final result = await store.epgWindow(
      'profile',
      'source',
      channelKeys: const ['news.example'],
      startUtc: DateTime.utc(2026, 9, 12),
      endUtc: DateTime.utc(2026, 9, 13),
    );
    expect(result.single.title, 'Last good guide');
    expect((await store.epgSourceState('profile', 'source'))?.status, 'stale');
  });

  test('new successful generation removes superseded rows', () async {
    for (final entry in [(1, 'Old'), (2, 'New')]) {
      await store.beginEpgImport('profile', 'source', entry.$1);
      await store.appendEpgProgrammes('profile', 'source', entry.$1, [
        programme(entry.$2, 9),
      ]);
      await store.completeEpgImport('profile', 'source', entry.$1);
    }

    final result = await store.epgWindow(
      'profile',
      'source',
      channelKeys: const ['news.example'],
      startUtc: DateTime.utc(2026, 9, 12),
      endUtc: DateTime.utc(2026, 9, 13),
    );
    expect(result.single.title, 'New');
  });

  test('a late EPG import cannot resurrect a deleted profile', () async {
    await store.beginEpgImport('profile', 'source', 1);
    await store.appendEpgProgrammes('profile', 'source', 1, [
      programme('Staged guide', 9),
    ]);
    await store.deleteProfile('profile');

    await expectLater(
      store.completeEpgImport('profile', 'source', 1),
      throwsStateError,
    );
    expect(await store.epgSourceState('profile', 'source'), isNull);
  });

  test('short EPG replaces only the requested channel', () async {
    EpgProgramme short(String channel, String title) => EpgProgramme(
      channelKey: channel,
      startUtc: DateTime.utc(2026, 9, 12, 9),
      stopUtc: DateTime.utc(2026, 9, 12, 10),
      title: title,
    );

    await store.replaceShortEpgChannel('profile', 'short', '1', [
      short('1', 'Old one'),
    ]);
    await store.replaceShortEpgChannel('profile', 'short', '2', [
      short('2', 'Channel two'),
    ]);
    await store.replaceShortEpgChannel('profile', 'short', '1', [
      short('1', 'New one'),
    ]);

    final values = await store.epgWindow(
      'profile',
      'short',
      channelKeys: const ['1', '2'],
      startUtc: DateTime.utc(2026, 9, 12, 9),
      endUtc: DateTime.utc(2026, 9, 12, 10),
    );
    expect(values.map((item) => item.title), ['New one', 'Channel two']);
  });
}
