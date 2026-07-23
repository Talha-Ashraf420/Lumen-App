import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';

void main() {
  final store = CatalogStore.instance;

  setUp(() async {
    await store.useInMemoryForTests();
  });

  tearDown(() => store.close());

  test('catalog pages are isolated by profile and query', () async {
    final alpha = [
      VodStream(1, 'Arrival', 'a.jpg', 'sci-fi', 'mp4', 8, '1'),
      VodStream(2, 'Blade Runner', 'b.jpg', 'sci-fi', 'mkv', 9, '2'),
      VodStream(3, 'Contact', 'c.jpg', 'sci-fi', 'mp4', 7, '3'),
    ];
    await store.replaceVod('profile-a', 'sci-fi', alpha, generation: 10);
    await store.replaceVod('profile-b', 'sci-fi', [
      VodStream(4, 'Different account', '', 'sci-fi', 'mp4', 0, ''),
    ], generation: 11);

    final first = await store.vodPage('profile-a', bucket: 'sci-fi', limit: 2);
    expect(first.items.map((item) => item.name), ['Arrival', 'Blade Runner']);
    expect(first.hasMore, isTrue);

    final search = await store.vodPage(
      'profile-a',
      bucket: 'sci-fi',
      query: 'contact',
    );
    expect(search.items.single.streamId, 3);
    expect(
      search.items.any((item) => item.name == 'Different account'),
      isFalse,
    );
  });

  test(
    'catalog pages preserve provider order and support indexed sorts',
    () async {
      final movies = List.generate(
        60,
        (index) => VodStream(
          index + 1,
          switch (index) {
            0 => 'Zulu Premiere (2021)',
            1 => 'Alpha Feature (2026)',
            2 => 'Middle Story (2024)',
            _ => 'Movie ${index.toString().padLeft(2, '0')} (2023)',
          },
          '',
          'large',
          'mp4',
          switch (index) {
            0 => 7.1,
            1 => 8.2,
            2 => 9.7,
            _ => 5.0,
          },
          switch (index) {
            0 => '100',
            1 => '300',
            2 => '200',
            _ => '${99 - index}',
          },
        ),
      );
      await store.replaceVod('profile', 'large', movies, generation: 10);

      final first = await store.vodPage('profile', bucket: 'large', limit: 48);
      final second = await store.vodPage(
        'profile',
        bucket: 'large',
        offset: 48,
        limit: 48,
      );
      expect(first.items, hasLength(48));
      expect(first.items.first.streamId, 1);
      expect(first.hasMore, isTrue);
      expect(second.items, hasLength(12));
      expect(second.items.first.streamId, 49);
      expect(second.hasMore, isFalse);

      final highestRated = await store.vodPage(
        'profile',
        bucket: 'large',
        sort: 'rating',
        limit: 1,
      );
      expect(highestRated.items.single.name, 'Middle Story (2024)');

      final newestAdded = await store.vodPage(
        'profile',
        bucket: 'large',
        sort: 'recent',
        limit: 1,
      );
      expect(newestAdded.items.single.name, 'Alpha Feature (2026)');

      final newestYear = await store.vodPage(
        'profile',
        bucket: 'large',
        sort: 'year',
        limit: 1,
      );
      expect(newestYear.items.single.name, 'Alpha Feature (2026)');

      final descending = await store.vodPage(
        'profile',
        bucket: 'large',
        sort: 'za',
        limit: 1,
      );
      expect(descending.items.single.name, 'Zulu Premiere (2021)');
    },
  );

  test(
    'series and live pages use the same query and offset contract',
    () async {
      await store.replaceSeries(
        'profile',
        'shows',
        List.generate(
          50,
          (index) => Series(
            index + 1,
            'Series ${(index + 1).toString().padLeft(2, '0')}',
            '',
            '',
            '',
            7,
            '2025',
            'shows',
          ),
        ),
        generation: 10,
      );
      await store.replaceLive('profile', 'channels', [
        LiveStream(1, 'World News', '', 'channels', ''),
        LiveStream(2, 'Sports Arena', '', 'channels', ''),
      ], generation: 11);

      final secondSeriesPage = await store.seriesPage(
        'profile',
        bucket: 'shows',
        offset: 48,
        limit: 48,
      );
      expect(secondSeriesPage.items.map((item) => item.seriesId), [49, 50]);
      expect(secondSeriesPage.hasMore, isFalse);

      final liveSearch = await store.livePage(
        'profile',
        bucket: 'channels',
        query: 'sports',
      );
      expect(liveSearch.items.single.name, 'Sports Arena');
    },
  );

  test('an older refresh cannot overwrite a newer generation', () async {
    await store.replaceLive('profile', '*', [
      LiveStream(1, 'New channel', '', 'news', ''),
    ], generation: 20);
    final accepted = await store.replaceLive('profile', '*', [
      LiveStream(2, 'Stale channel', '', 'news', ''),
    ], generation: 19);

    expect(accepted, isFalse);
    final page = await store.livePage('profile');
    expect(page.items.single.name, 'New channel');
  });

  test('a late request cannot resurrect a deleted profile', () async {
    await store.replaceVod('profile', '*', [
      VodStream(1, 'Old movie', '', 'all', 'mp4', 0, ''),
    ], generation: 10);

    await store.deleteProfile('profile');
    final lateWrite = await store.replaceVod('profile', '*', [
      VodStream(2, 'Late movie', '', 'all', 'mp4', 0, ''),
    ], generation: 11);

    expect(lateWrite, isFalse);
    expect((await store.vodPage('profile')).items, isEmpty);

    final newRequest = DateTime.now().microsecondsSinceEpoch;
    expect(
      await store.replaceVod('profile', '*', [
        VodStream(3, 'New session movie', '', 'all', 'mp4', 0, ''),
      ], generation: newRequest),
      isTrue,
    );
  });

  test('category replacement is atomic and account scoped', () async {
    await store.replaceCategories('first', 'movie', [
      Category('1', 'Drama'),
      Category('2', 'Comedy'),
    ], generation: 1);
    await store.replaceCategories('second', 'movie', [
      Category('3', 'Documentary'),
    ], generation: 2);

    expect(
      (await store.categories('first', 'movie')).map((item) => item.name),
      ['Comedy', 'Drama'],
    );
    expect(
      (await store.categories('second', 'movie')).single.name,
      'Documentary',
    );
  });
}
