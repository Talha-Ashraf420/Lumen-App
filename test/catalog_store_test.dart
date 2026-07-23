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
