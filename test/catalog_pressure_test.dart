import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/xtream.dart';

class _PressureClient extends XtreamClient {
  _PressureClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://pressure.example',
          username: 'test',
          password: 'test-only',
        ),
      );
  int count = 600;
  bool hold = false;
  final calls = <String?>[];
  final pending = <String?, Completer<List<VodStream>>>{};
  Completer<List<Category>>? pendingCategories;

  List<VodStream> items(String? category) => List.generate(
    count,
    (i) => VodStream(i + 1, 'Movie $i', '', category ?? 'one', 'mp4', 0, '$i'),
  );

  @override
  Future<List<Category>> vodCategories() async => pendingCategories == null
      ? [Category('one', 'One'), Category('two', 'Two')]
      : await pendingCategories!.future;

  @override
  Future<List<VodStream>> vodStreams(String? categoryId) {
    calls.add(categoryId);
    if (hold) return pending.putIfAbsent(categoryId, Completer.new).future;
    return Future.value(items(categoryId));
  }

  @override
  Future<List<Series>> series(String? categoryId) async => List.generate(
    120,
    (i) => Series(i, 'Series $i', '', '', '', 0, '', categoryId ?? 'series'),
  );

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async =>
      List.generate(
        120,
        (i) => LiveStream(i, 'Live $i', '', categoryId ?? 'live'),
      );

  @override
  Future<List<LiveStream>> enrichLiveLogos(List<LiveStream> channels) async =>
      channels;

  void release() {
    hold = false;
    for (final entry in pending.entries) {
      if (!entry.value.isCompleted) entry.value.complete(items(entry.key));
    }
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'Catalog work did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = CatalogCache.instance;
  final store = CatalogStore.instance;
  late _PressureClient client;

  setUp(() async {
    cache.clear();
    await store.useInMemoryForTests();
    client = _PressureClient();
  });
  tearDown(() async {
    cache.clear();
    client.release();
    client.close();
    await store.close();
  });

  test(
    'a 10000-item cached category only decodes visible database pages',
    () async {
      client.count = 10000;
      await store.replaceVod(
        client.catalogScope,
        'one',
        client.items('one'),
        generation: 1,
      );
      client.hold = true;
      final first = await cache.vodPage(client, categoryId: 'one');
      final second = await cache.vodPage(client, categoryId: 'one', offset: 48);
      expect(first.items.length, 48);
      expect(second.items.first.streamId, 49);
      expect(second.hasMore, isTrue);
      await _until(() => client.calls.isNotEmpty);
      expect(client.calls, ['one']);
      expect(store.debugMaxDecodedPageRows, 49);
      expect(cache.debugRetainedCatalogItems, 0);
      client.release();
      await _until(() => cache.debugPageRefreshes == 0);
      expect(cache.debugRetainedCatalogItems, 0);
      await cache.vodPage(client, categoryId: 'one', offset: 96);
      expect(client.calls, [
        'one',
      ], reason: 'Pagination must not re-fetch the provider');
    },
  );

  test(
    'rapid category changes remove queued work before a slow request completes',
    () async {
      client.hold = true;
      final requests = List.generate(23, (_) => CatalogRequest());
      final pages = [
        for (var i = 0; i < requests.length; i++)
          cache.vodPage(client, categoryId: '$i', request: requests[i]),
      ];
      await _until(() => cache.debugPendingRequests == 20);
      expect(cache.debugActiveRequests, 3);
      for (final request in requests) {
        request.cancel();
      }
      await _until(
        () => cache.debugPendingRequests == 0 && cache.debugPageRefreshes == 3,
      );
      expect(client.calls.length, 3);
      client.release();
      final results = await Future.wait(pages);
      expect(results.every((page) => page.items.isEmpty), isTrue);
      expect(await store.hasItems(client.catalogScope, 'movie'), isFalse);
      expect(cache.debugPageRefreshes, 0);
    },
  );

  test(
    'series and live use indexed pages without retaining full lists',
    () async {
      expect(
        (await cache.seriesPage(client, categoryId: 'series')).items.length,
        48,
      );
      expect(
        (await cache.livePage(client, categoryId: 'live')).items.length,
        48,
      );
      expect(
        (await cache.seriesPage(
          client,
          categoryId: 'series',
          offset: 96,
        )).items.length,
        24,
      );
      expect(
        (await cache.livePage(client, categoryId: 'live', offset: 96)).hasMore,
        isFalse,
      );
      expect(cache.debugRetainedCatalogItems, 0);
      expect(store.debugMaxDecodedPageRows, 49);
    },
  );

  test(
    'cancellation still prunes when another job sharing the token finishes',
    () async {
      client.hold = true;
      final token = CatalogRequest();
      final pages = [
        for (var i = 0; i < 8; i++)
          cache.vodPage(client, categoryId: '$i', request: token),
      ];
      await _until(() => cache.debugPendingRequests == 5);
      client.pending.values.first.complete(client.items('0'));
      await _until(() => cache.debugPageRefreshes == 7);
      token.cancel();
      await _until(() => cache.debugPendingRequests == 0);
      client.release();
      await Future.wait(pages);
      expect(client.calls.length, 4);
    },
  );

  test(
    'one cancelled reader does not cancel a shared request still in use',
    () async {
      client.hold = true;
      final firstRequest = CatalogRequest();
      final first = cache.vodPage(
        client,
        categoryId: 'one',
        request: firstRequest,
      );
      await _until(() => client.calls.isNotEmpty);
      final second = cache.vodPage(
        client,
        categoryId: 'one',
        request: CatalogRequest(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      firstRequest.cancel();
      client.release();
      expect((await first).items, isEmpty);
      expect((await second).items.length, 48);
      expect(client.calls, ['one']);
    },
  );

  test(
    'account switch drops old queued requests and rejects old writes',
    () async {
      client.hold = true;
      final requests = [
        for (var i = 0; i < 12; i++) cache.vodStreams(client, '$i'),
      ];
      await _until(() => cache.debugPendingRequests == 9);
      final demo = XtreamClient(XtreamCredentials.demoProfile);
      addTearDown(demo.close);
      final demoFuture = cache.vod(demo);
      expect(await demoFuture, isNotEmpty);
      client.release();
      await Future.wait(requests);
      expect(client.calls.length, 3);
      expect(await store.hasItems(client.catalogScope, 'movie'), isFalse);
      expect(identical(cache.vod(demo), demoFuture), isTrue);
    },
  );

  test(
    'an old all-category import cannot reclaim the active account',
    () async {
      await store.replaceVod(
        client.catalogScope,
        'one',
        client.items('one'),
        generation: 1,
      );
      client.pendingCategories = Completer<List<Category>>();
      await cache.vodPage(client);
      await _until(() => cache.debugActiveRequests == 1);
      final demo = XtreamClient(XtreamCredentials.demoProfile);
      addTearDown(demo.close);
      final demoFuture = cache.vod(demo);
      await demoFuture;
      client.pendingCategories!.complete([Category('old', 'Old')]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(client.calls, isEmpty);
      expect(identical(cache.vod(demo), demoFuture), isTrue);
    },
  );

  test(
    'legacy full-list consumers retain at most 2000 items per media kind',
    () async {
      for (var i = 0; i < 10; i++) {
        expect((await cache.vodStreams(client, '$i')).length, 600);
        await Future<void>.delayed(Duration.zero);
        expect(cache.debugRetainedCatalogItems, lessThanOrEqualTo(2000));
      }
      client.count = 3000;
      expect((await cache.vodStreams(client, 'large')).length, 3000);
      await Future<void>.delayed(Duration.zero);
      expect(cache.debugRetainedCatalogItems, lessThanOrEqualTo(2000));
    },
  );
}
