import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/home_screen.dart';
import 'package:lumen_tv/screens/movie_detail_screen.dart';
import 'package:lumen_tv/screens/search_screen.dart';
import 'package:lumen_tv/screens/series_detail_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailClient extends XtreamClient {
  _DetailClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'viewer',
          password: 'test-only',
        ),
      );

  final movieInfo = Completer<VodInfo>();
  int movieInfoCalls = 0;
  int seriesInfoCalls = 0;

  @override
  Future<VodInfo> vodInfo(int id) {
    movieInfoCalls++;
    return movieInfo.future;
  }

  @override
  Future<SeriesInfo> seriesInfo(int id) async {
    seriesInfoCalls++;
    return SeriesInfo(
      cover: '',
      backdrop: '',
      plot: 'A patient story told across two seasons.',
      genre: 'Drama',
      rating: 8.4,
      releaseDate: '2025-01-10',
      episodes: {
        1: [
          Episode('101', 1, 'The Signal', 'mp4', 1, ''),
          Episode('102', 2, 'Afterglow', 'mp4', 1, ''),
        ],
        2: [Episode('201', 1, 'A New Frequency', 'mp4', 2, '')],
      },
    );
  }
}

class _CacheClient extends XtreamClient {
  _CacheClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'viewer',
          password: 'test-only',
        ),
      );

  final categories = Completer<List<Category>>();
  final streams = Completer<List<VodStream>>();
  int categoryCalls = 0;
  int streamCalls = 0;

  @override
  Future<List<Category>> vodCategories() {
    categoryCalls++;
    return categories.future;
  }

  @override
  Future<List<VodStream>> vodStreams(String? categoryId) {
    streamCalls++;
    return streams.future;
  }
}

class _HomeClient extends XtreamClient {
  _HomeClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'viewer',
          password: 'test-only',
        ),
      );

  int vodCategoryCalls = 0;
  int seriesCategoryCalls = 0;
  int liveCategoryCalls = 0;
  final List<String?> vodStreamCategories = [];

  @override
  Future<List<Category>> vodCategories() async {
    vodCategoryCalls++;
    return [Category('1', 'Premieres'), Category('2', 'Critics picks')];
  }

  @override
  Future<List<Category>> seriesCategories() async {
    seriesCategoryCalls++;
    return [Category('3', 'Drama')];
  }

  @override
  Future<List<Category>> liveCategories() async {
    liveCategoryCalls++;
    return [Category('4', 'News')];
  }

  @override
  Future<List<VodStream>> vodStreams(String? categoryId) async {
    vodStreamCategories.add(categoryId);
    return [
      VodStream(42, 'The Last Signal', '', categoryId ?? '', 'mp4', 7.6, ''),
    ];
  }

  @override
  Future<List<Series>> series(String? categoryId) async => const [];

  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
    // SQLite persistence has focused CatalogStore tests. Widget tests run on a
    // fake clock that is incompatible with sqflite's transaction lock timer.
    await CatalogStore.instance.disableForWidgetTests();
    CatalogCache.instance.clear();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Widget child,
    Size size, {
    Palette? palette,
  }) async {
    final resolvedPalette = palette ?? darkPalette;
    activePalette = resolvedPalette;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(resolvedPalette), home: child),
    );
    await tester.pump();
  }

  Future<void> disposeUi(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!condition() && stopwatch.elapsed < timeout) {
      // SQLite FFI completes on the real event loop; advancing only Flutter's
      // fake frame clock can otherwise assert before the cached read returns.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(condition(), isTrue, reason: 'Timed out waiting for async catalog');
  }

  testWidgets('movie detail is useful before provider metadata arrives', (
    tester,
  ) async {
    final client = _DetailClient();
    final movie = VodStream(
      42,
      'The Last Signal (2025)(4K)',
      '',
      '7',
      'mp4',
      7.6,
      '1720000000',
    );

    await pumpAt(
      tester,
      MovieDetailScreen(client: client, movie: movie),
      const Size(390, 844),
    );
    expect(find.text('FEATURE PRESENTATION'), findsOneWidget);
    expect(find.text('The Last Signal'), findsOneWidget);
    expect(find.textContaining('(4K)'), findsNothing);
    expect(find.text('Play film'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('movie-detail-back'))),
      const Size(46, 46),
    );
    expect(client.movieInfoCalls, 1);
    expect(tester.takeException(), isNull);

    client.movieInfo.complete(
      VodInfo(
        plot: 'A film that follows a signal beyond the edge of the map.',
        cast: 'One, Two',
        director: 'A. Director',
        genre: 'Science fiction',
        releaseDate: '2025-02-03',
        rating: 8.1,
        duration: '1h 54m',
        image: '',
        backdrop: '',
        containerExtension: 'mp4',
      ),
    );
    await tester.pump();

    expect(find.text('THE STORY'), findsOneWidget);
    expect(find.text('THE CREDITS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  testWidgets('movie detail loading state stays readable in light mode', (
    tester,
  ) async {
    final client = _DetailClient();
    final movie = VodStream(
      43,
      'A Patient Story (2026)',
      '',
      '7',
      'mp4',
      7.2,
      '1720000000',
    );

    await pumpAt(
      tester,
      MovieDetailScreen(client: client, movie: movie),
      const Size(1280, 800),
      palette: lightPalette,
    );

    expect(find.byType(DetailMetadataSkeleton), findsOneWidget);
    expect(find.byType(DetailBackdropPlaceholder), findsWidgets);
    final playLabel = tester.widget<Text>(find.text('Play film'));
    expect(playLabel.style?.color, onAccent);

    const synopsis =
        'A clear synopsis remains readable while the artwork finishes loading.';
    client.movieInfo.complete(
      VodInfo(
        plot: synopsis,
        cast: '',
        director: '',
        genre: '',
        releaseDate: '',
        rating: 0,
        duration: '',
        image: '',
        backdrop: '',
        containerExtension: 'mp4',
      ),
    );
    await tester.pump();

    final synopsisCopies = tester.widgetList<Text>(find.text(synopsis));
    expect(synopsisCopies.any((text) => text.style?.color == muted), isTrue);
    expect(contrastRatio(muted, bg), greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  testWidgets('series detail becomes a TV season archive', (tester) async {
    final client = _DetailClient();
    await pumpAt(
      tester,
      SeriesDetailScreen(
        client: client,
        seriesId: 91,
        title: 'Signal House',
        preview: Series(
          91,
          'Signal House',
          '',
          'An unusual house broadcasts every night.',
          'Drama',
          8.2,
          '2025',
          '3',
        ),
      ),
      const Size(1280, 900),
    );
    await tester.pump();

    expect(find.text('SEASON ARCHIVE'), findsOneWidget);
    expect(find.text('CHOOSE A CHAPTER'), findsOneWidget);
    expect(find.text('EPISODE 01'), findsWidgets);
    expect(find.text('Play next'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('series-detail-back'))),
      const Size(46, 46),
    );
    expect(client.seriesInfoCalls, 1);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  test('catalog cache deduplicates in-flight categories and streams', () async {
    final client = _CacheClient();

    final firstCategories = CatalogCache.instance.vod(client);
    final secondCategories = CatalogCache.instance.vod(client);
    expect(identical(firstCategories, secondCategories), isTrue);
    client.categories.complete([Category('7', 'Cinema')]);
    expect(await firstCategories, hasLength(1));
    expect(await secondCategories, hasLength(1));
    expect(client.categoryCalls, 1);

    final firstStreams = CatalogCache.instance.vodStreams(client, '7');
    final secondStreams = CatalogCache.instance.vodStreams(client, '7');
    expect(identical(firstStreams, secondStreams), isTrue);
    client.streams.complete([
      VodStream(42, 'The Last Signal', '', '7', 'mp4', 7.6, ''),
    ]);
    expect(await firstStreams, hasLength(1));
    expect(await secondStreams, hasLength(1));
    expect(client.streamCalls, 1);
  });

  testWidgets('Home warms catalogs once and skips whole VOD', (tester) async {
    final client = _HomeClient();
    await pumpAt(
      tester,
      HomeScreen(client: client, onBrowse: () {}),
      const Size(390, 844),
    );
    await waitFor(tester, () => client.vodCategoryCalls == 1);

    expect(client.vodCategoryCalls, 1);
    await waitFor(tester, () => find.text('START HERE').evaluate().isNotEmpty);
    expect(client.vodStreamCategories, isNot(contains(null)));
    expect(client.vodStreamCategories.toSet().length, lessThanOrEqualTo(2));
    expect(find.text('START HERE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await waitFor(
      tester,
      () => client.seriesCategoryCalls == 1 && client.liveCategoryCalls == 1,
    );
    expect(client.seriesCategoryCalls, 1);
    expect(client.liveCategoryCalls, 1);
    await disposeUi(tester);
  });

  testWidgets('Movies browse loads one category instead of the whole catalog', (
    tester,
  ) async {
    final client = _HomeClient();
    addTearDown(client.close);

    await pumpAt(
      tester,
      SearchScreen(client: client, initialSection: 'movie'),
      const Size(1280, 800),
    );
    await waitFor(tester, () => client.vodCategoryCalls == 1);
    await waitFor(tester, () => client.vodStreamCategories.contains('1'));
    await waitFor(
      tester,
      () => find.text('The Last Signal').evaluate().isNotEmpty,
    );

    expect(client.vodCategoryCalls, 1);
    expect(client.seriesCategoryCalls, 0);
    expect(client.liveCategoryCalls, 0);
    expect(client.vodStreamCategories, contains('1'));
    expect(client.vodStreamCategories, isNot(contains(null)));
    expect(find.text('The Last Signal'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeUi(tester);
  });

  testWidgets('Search section chips use readable content on accent fills', (
    tester,
  ) async {
    final client = _HomeClient();
    addTearDown(client.close);

    await pumpAt(tester, SearchScreen(client: client), const Size(1280, 800));

    final selectedAllLabel = tester.widget<Text>(find.text('All'));
    expect(selectedAllLabel.style?.color, onAccent);
    expect(
      contrastRatio(selectedAllLabel.style!.color!, accent),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);

    await disposeUi(tester);
  });
}
