import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/multi_source.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/xtream.dart';

const _first = XtreamCredentials(
  baseUrl: 'https://one.example',
  username: 'viewer-one',
  password: 'one',
);
const _second = XtreamCredentials(
  baseUrl: 'https://two.example',
  username: 'viewer-two',
  password: 'two',
);

class _SourceClient extends XtreamClient {
  _SourceClient(super.credentials, {this.fail = false});

  bool fail;
  bool empty = false;
  String? requestedCategory;

  @override
  Future<List<Category>> liveCategories() async {
    if (fail) throw XtreamException('offline');
    if (empty) return [];
    return [Category('10', 'Sports')];
  }

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    requestedCategory = categoryId;
    if (fail) throw XtreamException('offline');
    if (empty) return [];
    return [LiveStream(123, 'News', '', categoryId ?? '10')];
  }

  @override
  String streamUrl(String kind, Object id, {String ext = 'ts'}) =>
      '${creds.baseUrl}/$kind/$id.$ext';
}

void main() {
  setUp(() async {
    CatalogCache.instance.clear();
    await CatalogStore.instance.useInMemoryForTests();
  });

  tearDown(() async {
    CatalogCache.instance.clear();
    await CatalogStore.instance.close();
  });

  test(
    'combined services namespace duplicate IDs and route playback',
    () async {
      final clients = <String, _SourceClient>{};
      final viewer = MultiSourceXtreamClient(
        _first,
        const [_first, _second],
        clientFactory: (credentials) =>
            clients[credentials.baseUrl] = _SourceClient(credentials),
      );
      addTearDown(viewer.close);

      final categories = await viewer.liveCategories();
      expect(categories, hasLength(2));
      expect(categories.map((value) => value.sourceLabel), {
        'one.example',
        'two.example',
      });
      expect(categories.first.id, isNot(categories.last.id));

      final channels = await viewer.liveStreams(null);
      expect(channels, hasLength(2));
      expect(channels.first.streamId, isNot(channels.last.streamId));
      expect(
        viewer.streamUrl('live', channels.last.streamId),
        'https://two.example/live/123.ts',
      );

      await viewer.liveStreams(categories.last.id);
      expect(clients['https://two.example']!.requestedCategory, '10');
    },
  );

  test('one unavailable service does not hide healthy services', () async {
    final viewer = MultiSourceXtreamClient(
      _first,
      const [_first, _second],
      clientFactory: (credentials) => _SourceClient(
        credentials,
        fail: credentials.baseUrl == _second.baseUrl,
      ),
    );
    addTearDown(viewer.close);

    final categories = await viewer.liveCategories();
    final channels = await viewer.liveStreams(null);
    expect(categories.map((value) => value.sourceLabel), ['one.example']);
    expect(channels.map((value) => value.sourceLabel), ['one.example']);
  });

  test('combined cache never overwrites raw provider fallback data', () async {
    final clients = <String, _SourceClient>{};
    final viewer = MultiSourceXtreamClient(
      _first,
      const [_first, _second],
      clientFactory: (credentials) =>
          clients[credentials.baseUrl] = _SourceClient(credentials),
    );
    addTearDown(viewer.close);

    final categories = await CatalogCache.instance.live(viewer, priority: true);
    final firstCategory = categories.firstWhere(
      (value) => value.sourceLabel == 'one.example',
    );
    await CatalogCache.instance.liveStreams(
      viewer,
      firstCategory.id,
      priority: true,
    );

    final rawScope = Store.profileScope(_first);
    expect(viewer.catalogScope, startsWith('multi_'));
    expect(viewer.catalogScope, isNot(rawScope));

    final rawCategories = await CatalogStore.instance.categories(
      rawScope,
      'live',
    );
    expect(rawCategories.single.id, '10');
    expect(rawCategories.single.name, 'Sports');
    expect(rawCategories.single.sourceScope, isEmpty);

    final combinedCategories = await CatalogStore.instance.categories(
      viewer.catalogScope,
      'live',
    );
    expect(combinedCategories, hasLength(2));
    expect(combinedCategories.map((value) => value.sourceLabel).toSet(), {
      'one.example',
      'two.example',
    });

    for (final client in clients.values) {
      client.fail = true;
    }
    final offlineCategories = await viewer.liveCategories();
    final offlineFirst = offlineCategories.firstWhere(
      (value) => value.sourceLabel == 'one.example',
    );
    expect(offlineFirst.id, '$rawScope::10');
    expect(offlineFirst.name, 'Sports · one.example');
    expect('::'.allMatches(offlineFirst.id), hasLength(1));

    final offlineChannels = await viewer.liveStreams(offlineFirst.id);
    expect(offlineChannels.single.sourceLabel, 'one.example');
    expect(offlineChannels.single.categoryId, '$rawScope::10');
    expect('::'.allMatches(offlineChannels.single.categoryId), hasLength(1));
  });

  test('temporary empty success does not erase a working service', () async {
    final clients = <String, _SourceClient>{};
    final viewer = MultiSourceXtreamClient(
      _first,
      const [_first, _second],
      clientFactory: (credentials) =>
          clients[credentials.baseUrl] = _SourceClient(credentials),
    );
    addTearDown(viewer.close);

    final categories = await viewer.liveCategories();
    final first = categories.firstWhere(
      (value) => value.sourceLabel == 'one.example',
    );
    await viewer.liveStreams(first.id);
    clients[_first.baseUrl]!.empty = true;

    expect((await viewer.liveCategories()), hasLength(2));
    expect((await viewer.liveStreams(first.id)).single.name, 'News');
    expect(
      (await CatalogStore.instance.categories(
        Store.profileScope(_first),
        'live',
      )).single.name,
      'Sports',
    );
  });
}
