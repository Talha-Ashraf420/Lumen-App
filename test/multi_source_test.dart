import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/multi_source.dart';
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

  final bool fail;
  String? requestedCategory;

  @override
  Future<List<Category>> liveCategories() async {
    if (fail) throw XtreamException('offline');
    return [Category('10', 'Sports')];
  }

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    requestedCategory = categoryId;
    if (fail) throw XtreamException('offline');
    return [LiveStream(123, 'News', '', categoryId ?? '10')];
  }

  @override
  String streamUrl(String kind, Object id, {String ext = 'ts'}) =>
      '${creds.baseUrl}/$kind/$id.$ext';
}

void main() {
  setUp(() async {
    await CatalogStore.instance.useInMemoryForTests();
  });

  tearDown(() async {
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
}
