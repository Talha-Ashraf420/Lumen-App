import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/home_config.dart';
import 'package:lumen_tv/library.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/stats.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accountA = XtreamCredentials(
  baseUrl: 'https://one.example',
  username: 'alice',
  password: 'secret-a',
);
const _accountB = XtreamCredentials(
  baseUrl: 'https://two.example',
  username: 'bob',
  password: 'secret-b',
);

class _CategoryClient extends XtreamClient {
  _CategoryClient(super.credentials, this.category);
  final String category;

  @override
  Future<List<Category>> vodCategories() async => [Category('1', category)];
}

class _LiveOnlyClient extends XtreamClient {
  _LiveOnlyClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://playlist.example',
          username: '',
          password: '',
          m3uUrl: 'https://playlist.example/channels.m3u',
        ),
      );

  @override
  Future<List<Category>> liveCategories() async => [Category('live', 'News')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
    CatalogCache.instance.clear();
    await Library.instance.activate(null);
    await HomeConfig.instance.activate(null);
    await WatchStats.instance.activate(null);
  });

  test(
    'profile scope is stable, distinct, and does not expose credentials',
    () {
      final first = Store.profileScope(_accountA);
      expect(first, Store.profileScope(_accountA));
      expect(first, isNot(Store.profileScope(_accountB)));
      expect(first, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(first, isNot(contains('alice')));
      expect(first, isNot(contains('secret')));
    },
  );

  test(
    'logout clears the active session but keeps the saved account',
    () async {
      await Store.setActive(_accountA);
      expect(await Store.active(), isNotNull);

      await Store.logout();

      expect(await Store.active(), isNull);
      expect(await Store.savedProfiles(), hasLength(1));
      expect(
        Store.sameProfile((await Store.savedProfiles()).single, _accountA),
        isTrue,
      );
    },
  );

  test(
    'library, Home shelves, and playback stats stay with their account',
    () async {
      await Library.instance.activate(_accountA);
      Library.instance.toggleFav(
        const MediaRef(kind: 'movie', id: 7, name: 'Account A movie'),
      );
      Library.instance.saveProgress(
        const Progress(
          key: 'movie:7',
          title: 'Account A movie',
          poster: '',
          url: 'https://one.example/movie/7',
          ext: 'mp4',
          position: 60,
          duration: 600,
          updatedAt: 1,
        ),
      );
      await HomeConfig.instance.activate(_accountA);
      HomeConfig.instance.toggle(const ShelfRef('movie', '7', 'A shelf'));
      await WatchStats.instance.activate(_accountA);
      WatchStats.instance.add(
        seconds: 30,
        kind: 'movie',
        cat: '7',
        titleKey: 'movie:7',
        day: '2026-07-23',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await Future.wait([
        Library.instance.activate(_accountB),
        HomeConfig.instance.activate(_accountB),
        WatchStats.instance.activate(_accountB),
      ]);
      expect(Library.instance.favourites, isEmpty);
      expect(Library.instance.continueWatching(), isEmpty);
      expect(HomeConfig.instance.shelves, isEmpty);
      expect(WatchStats.instance.total, 0);

      Library.instance.toggleFav(
        const MediaRef(kind: 'live', id: 9, name: 'Account B channel'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await Future.wait([
        Library.instance.activate(_accountA),
        HomeConfig.instance.activate(_accountA),
        WatchStats.instance.activate(_accountA),
      ]);
      expect(Library.instance.favourites.single.name, 'Account A movie');
      expect(Library.instance.continueWatching().single.key, 'movie:7');
      expect(HomeConfig.instance.shelves.single.name, 'A shelf');
      expect(WatchStats.instance.total, 30);
    },
  );

  test('catalog cache cannot reuse one client account for another', () async {
    final first = _CategoryClient(_accountA, 'Account A');
    final second = _CategoryClient(_accountB, 'Account B');

    expect((await CatalogCache.instance.vod(first)).single.name, 'Account A');
    expect((await CatalogCache.instance.vod(second)).single.name, 'Account B');
  });

  testWidgets('live-only M3U hides movie, series, and discovery destinations', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: _LiveOnlyClient(),
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Live'), findsOneWidget);
    expect(find.byTooltip('Guide'), findsOneWidget);
    expect(find.byTooltip('Movies'), findsNothing);
    expect(find.byTooltip('Series'), findsNothing);
    expect(find.byTooltip('Discover'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
