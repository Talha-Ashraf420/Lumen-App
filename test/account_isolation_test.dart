import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/downloads.dart';
import 'package:lumen_tv/device_profile.dart';
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

class _FullCatalogClient extends XtreamClient {
  _FullCatalogClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://full.example',
          username: 'viewer',
          password: 'secret',
        ),
      );

  @override
  Future<List<Category>> vodCategories() async => [Category('movie', 'Movies')];

  @override
  Future<List<Category>> seriesCategories() async => [
    Category('series', 'Series'),
  ];

  @override
  Future<List<Category>> liveCategories() async => [Category('live', 'Live')];

  @override
  Future<Map<String, dynamic>> authenticate() async => {
    'status': 'Active',
    'active_cons': 1,
    'max_connections': 2,
  };
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

  test('catalog refreshes after a genuine app background and resume', () {
    final backgroundedAt = DateTime(2026, 9, 9, 12);

    expect(
      shouldRefreshCatalogAfterResume(
        null,
        backgroundedAt.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
    expect(
      shouldRefreshCatalogAfterResume(
        backgroundedAt,
        backgroundedAt.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    expect(
      shouldRefreshCatalogAfterResume(
        backgroundedAt,
        backgroundedAt.add(catalogResumeRefreshGrace),
      ),
      isTrue,
    );
  });

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

  testWidgets('live-only M3U hides unavailable movie and series destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
    await tester.pump(const Duration(seconds: 2));

    expect(find.byTooltip('Live'), findsOneWidget);
    expect(find.byTooltip('Guide'), findsOneWidget);
    expect(find.byTooltip('Movies'), findsNothing);
    expect(find.byTooltip('Series'), findsNothing);
    expect(find.byTooltip('Discover'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('full catalog has no Discover destination', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Discover'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('focusing Search in the TV rail does not steal focus', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    addTearDown(client.close);
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final searchControl = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('Search'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    searchControl.focusNode!.requestFocus();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const ValueKey('shell-page-1')), findsOneWidget);
    expect(searchControl.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 180));
    final myListControl = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('My List'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    expect(myListControl.focusNode!.hasFocus, isTrue);

    searchControl.focusNode!.requestFocus();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(searchControl.focusNode!.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('TV command bar is reachable and directional on every page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    addTearDown(client.close);
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final homeControl = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('Home'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    homeControl.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      if (FocusManager.instance.primaryFocus?.debugLabel ==
          'Command find anything') {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Command find anything',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Command refresh');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Command profile');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Profile add account',
    );
    for (var i = 0; i < 8; i++) {
      if (FocusManager.instance.primaryFocus?.debugLabel ==
          'Command find anything') {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Command find anything',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 50));
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(FocusManager.instance.rootScope)),
    );

    for (var i = 0; i < 8; i++) {
      if (FocusManager.instance.primaryFocus?.debugLabel ==
          'Command find anything') {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search library');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Command refresh');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Command profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 50));
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(FocusManager.instance.rootScope)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search library');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Command refresh');

    final moviesControl = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('Movies'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    moviesControl.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'movie category all',
    );
    for (var i = 0; i < 4; i++) {
      if (FocusManager.instance.primaryFocus?.debugLabel ==
          'Command find anything') {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Command find anything',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Home spotlight reaches its first two tiles before the rail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    DeviceProfile.isTelevision = true;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => DeviceProfile.isTelevision = false);
    final client = XtreamClient(XtreamCredentials.demoProfile);
    addTearDown(client.close);

    await tester.runAsync(() async {
      await CatalogCache.instance.vod(client, priority: true);
      await CatalogCache.instance.vodStreams(
        client,
        'demo_featured',
        priority: true,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
          homeCategoryLoader: () async => [
            Category('demo_featured', 'Featured stories'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(seconds: 2));

    final focusControls = tester
        .widgetList<FocusableActionDetector>(
          find.byType(FocusableActionDetector),
        )
        .toList();
    final focusLabels = focusControls
        .map((control) => control.focusNode?.debugLabel)
        .whereType<String>()
        .toList();
    expect(
      focusLabels,
      contains('Home spotlight tile 0'),
      reason: 'Mounted focus controls: $focusLabels',
    );
    FocusNode tileFocus(int index) => focusControls
        .singleWhere(
          (control) =>
              control.focusNode?.debugLabel == 'Home spotlight tile $index',
        )
        .focusNode!;

    final first = tileFocus(0);
    final second = tileFocus(1);
    final third = tileFocus(2);
    third.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(second.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final homeControl = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('Home'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    expect(homeControl.focusNode!.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('every TV destination has stable content and top-bar routes', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    addTearDown(client.close);
    await Library.instance.activate(client.creds);
    Library.instance.toggleFav(
      const MediaRef(kind: 'movie', id: 91, name: 'Focus matrix movie'),
    );
    Downloads.instance.items
      ..clear()
      ..add(
        DownloadItem(
          id: 'movie:91',
          title: 'Focus matrix download',
          poster: '',
          kind: 'movie',
          remoteUrl: 'https://example.invalid/movie.mp4',
          fileName: 'focus.mp4',
          progressKey: 'movie:91',
          status: DlStatus.paused,
        ),
      );
    addTearDown(Downloads.instance.items.clear);
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final routes = <(String, (String, String))>[
      ('Search', ('Search library', 'Command refresh')),
      ('My List', ('My List filter 0', 'Command find anything')),
      ('Profile', ('Profile add account', 'Command find anything')),
      ('Movies', ('movie category all', 'Command find anything')),
      ('Series', ('series category all', 'Command find anything')),
      ('Live', ('live category all', 'Command find anything')),
      ('Guide', ('Guide first category', 'Command find anything')),
      ('Downloads', ('Downloads filter 0', 'Command find anything')),
    ];

    for (final route in routes) {
      final dock = tester.widget<FocusableActionDetector>(
        find
            .descendant(
              of: find.byTooltip(route.$1),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      dock.focusNode!.requestFocus();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        route.$2.$1,
        reason: '${route.$1} must have a stable page entry.',
      );
      for (var i = 0; i < 5; i++) {
        if (FocusManager.instance.primaryFocus?.debugLabel == route.$2.$2) {
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        route.$2.$2,
        reason: '${route.$1} must reach the global command bar with Up.',
      );
      if (route.$1 == 'Movies' ||
          route.$1 == 'Series' ||
          route.$1 == 'Live' ||
          route.$1 == 'Guide') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Command refresh',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Command profile',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Command find anything',
        );
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'TV utility tabs enter content and return to the rail with D-pad',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final client = _FullCatalogClient();
      addTearDown(client.close);
      await Library.instance.activate(client.creds);
      Library.instance.toggleFav(
        const MediaRef(kind: 'movie', id: 71, name: 'Remote focus movie'),
      );
      await tester.runAsync(
        () => Future.wait([
          CatalogCache.instance.vod(client, priority: true),
          CatalogCache.instance.series(client, priority: true),
          CatalogCache.instance.live(client, priority: true),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          home: HomeShell(
            client: client,
            onLogout: () async {},
            onSwitch: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final myListControl = tester.widget<FocusableActionDetector>(
        find
            .descendant(
              of: find.byTooltip('My List'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      myListControl.focusNode!.requestFocus();
      await tester.pump();
      expect(myListControl.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'My List filter 0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'My List tile 0');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'My List filter 0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Command find anything',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'My List dock');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final profileControl = tester.widget<FocusableActionDetector>(
        find
            .descendant(
              of: find.byTooltip('Profile'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      expect(profileControl.focusNode!.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(profileControl.focusNode!.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Shortcuts'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'TV My List keeps a direct focus path when the first favorite is added',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final client = _FullCatalogClient();
      addTearDown(client.close);
      await Library.instance.activate(client.creds);
      await tester.runAsync(
        () => Future.wait([
          CatalogCache.instance.vod(client, priority: true),
          CatalogCache.instance.series(client, priority: true),
          CatalogCache.instance.live(client, priority: true),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          home: HomeShell(
            client: client,
            onLogout: () async {},
            onSwitch: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final myListControl = tester.widget<FocusableActionDetector>(
        find
            .descendant(
              of: find.byTooltip('My List'),
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      );
      myListControl.focusNode!.requestFocus();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Save the good stuff'), findsOneWidget);

      Library.instance.toggleFav(
        const MediaRef(kind: 'movie', id: 72, name: 'New favorite'),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'My List filter 0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Command find anything',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'My List filter 0',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'My List tile 0');

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('remote Back follows shell history then asks before exit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    addTearDown(client.close);
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-0')), findsOneWidget);

    await tester.tap(find.byTooltip('Movies'));
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-4')), findsOneWidget);

    await tester.tap(find.byTooltip('Series'));
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-5')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-4')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-0')), findsOneWidget);

    final homeBack = tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Exit Lumen?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'No'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Yes'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'No'));
    await tester.pump();
    await homeBack;
    expect(find.text('Exit Lumen?'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('phone dock hides Guide and Back safely returns to Home', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.byTooltip('Guide'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('My List'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Live'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Guide'), findsNothing);
    expect(find.byTooltip('You & library'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('You & library'), findsOneWidget);
    expect(find.byTooltip('Guide'), findsNothing);

    final utilityRect = tester.getRect(find.byTooltip('You & library'));
    expect(utilityRect.top, lessThan(100));
    expect(utilityRect.right, greaterThan(340));

    await tester.tap(find.byTooltip('You & library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Your Lumen'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Profile & settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android tablet rail also hides Guide', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DeviceProfile.isTelevision = false;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      DeviceProfile.isTelevision = false;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _FullCatalogClient();
    await tester.runAsync(
      () => Future.wait([
        CatalogCache.instance.vod(client, priority: true),
        CatalogCache.instance.series(client, priority: true),
        CatalogCache.instance.live(client, priority: true),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Live'), findsOneWidget);
    expect(find.byTooltip('Guide'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}
