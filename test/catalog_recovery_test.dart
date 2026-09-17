import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/xtream.dart';

class _ProviderClient extends XtreamClient {
  _ProviderClient(String host)
    : super(
        XtreamCredentials(
          baseUrl: 'https://$host',
          username: 'viewer',
          password: 'test-only',
        ),
      );

  bool fail = false;
  Completer<List<Category>>? pendingMovies;
  final Completer<void> movieRequested = Completer<void>();
  int movieCategoryRequests = 0;

  @override
  Future<List<Category>> vodCategories() {
    movieCategoryRequests++;
    if (!movieRequested.isCompleted) movieRequested.complete();
    if (pendingMovies case final pending?) return pending.future;
    if (fail) throw StateError('provider unavailable');
    return Future.value([Category('movies', 'Movies')]);
  }

  @override
  Future<List<Category>> seriesCategories() {
    if (fail) throw StateError('provider unavailable');
    return Future.value([Category('series', 'Series')]);
  }

  @override
  Future<List<Category>> liveCategories() {
    if (fail) throw StateError('provider unavailable');
    return Future.value([Category('live', 'Live')]);
  }

  @override
  Future<List<VodStream>> vodStreams(String? categoryId) {
    if (fail) throw StateError('provider unavailable');
    return Future.value([
      VodStream(1, 'Fresh movie', '', categoryId ?? 'movies', 'mp4', 0, ''),
    ]);
  }

  @override
  Future<List<Series>> series(String? categoryId) {
    if (fail) throw StateError('provider unavailable');
    return Future.value([
      Series(2, 'Fresh series', '', '', '', 0, '', categoryId ?? 'series'),
    ]);
  }

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) {
    if (fail) throw StateError('provider unavailable');
    return Future.value([
      LiveStream(3, 'Fresh channel', '', categoryId ?? 'live'),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = CatalogCache.instance;
  final store = CatalogStore.instance;

  setUp(() async {
    cache.clear();
    await store.useInMemoryForTests();
  });

  tearDown(() async {
    cache.clear();
    await store.close();
  });

  test(
    'provider failure keeps all three catalog sections usable offline',
    () async {
      final client = _ProviderClient('cached.example')..fail = true;
      final scope = client.catalogScope;
      await store.replaceCategories(scope, 'movie', [
        Category('movies', 'Cached movies'),
      ], generation: 1);
      await store.replaceCategories(scope, 'series', [
        Category('series', 'Cached series'),
      ], generation: 1);
      await store.replaceCategories(scope, 'live', [
        Category('live', 'Cached live'),
      ], generation: 1);
      await store.replaceVod(scope, 'movies', [
        VodStream(11, 'Saved movie', '', 'movies', 'mp4', 0, ''),
      ], generation: 1);
      await store.replaceSeries(scope, 'series', [
        Series(12, 'Saved series', '', '', '', 0, '', 'series'),
      ], generation: 1);
      await store.replaceLive(scope, 'live', [
        LiveStream(13, 'Saved channel', '', 'live'),
      ], generation: 1);

      expect((await cache.vod(client)).single.name, 'Cached movies');
      expect((await cache.series(client)).single.name, 'Cached series');
      expect((await cache.live(client)).single.name, 'Cached live');
      expect(
        (await cache.vodPage(client, categoryId: 'movies')).items.single.name,
        'Saved movie',
      );
      expect(
        (await cache.seriesPage(
          client,
          categoryId: 'series',
        )).items.single.name,
        'Saved series',
      );
      expect(
        (await cache.livePage(client, categoryId: 'live')).items.single.name,
        'Saved channel',
      );
      expect(client.movieCategoryRequests, 1);
    },
  );

  test(
    'switching to Demo ignores an unfinished provider catalog request',
    () async {
      final provider = _ProviderClient('slow.example');
      final pending = provider.pendingMovies = Completer<List<Category>>();

      final oldRequest = cache.vod(provider);
      await provider.movieRequested.future;
      expect(provider.movieCategoryRequests, 1);

      final demo = XtreamClient(XtreamCredentials.demoProfile);
      addTearDown(demo.close);
      final demoCategories = await cache.vod(demo);
      expect(demoCategories, isNotEmpty);
      expect(demoCategories.first.name, 'Featured stories');

      pending.complete([Category('old', 'Old provider movies')]);
      await oldRequest;
      expect((await cache.vod(demo)).first.name, 'Featured stories');
      expect((await cache.series(demo)), isNotEmpty);
      expect((await cache.live(demo)), isNotEmpty);
    },
  );

  test(
    'manual cache reset can recover after an empty provider response',
    () async {
      final client = _ProviderClient('recover.example')..fail = true;

      expect(await cache.vod(client), isEmpty);
      client.fail = false;
      cache.clear();

      expect((await cache.vod(client)).single.name, 'Movies');
      expect(client.movieCategoryRequests, greaterThan(1));
    },
  );
}
