import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/library.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/refresh.dart';
import 'package:lumen_tv/screens/home_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RefreshClient extends XtreamClient {
  _RefreshClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://refresh-regression.example',
          username: 'viewer',
          password: 'secret',
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
    CatalogCache.instance.clear();
    Library.instance.recent.clear();
    Library.instance.progress.clear();
    Library.instance.watched.clear();
  });

  test('Home spotlight prefers a clean English movies category', () {
    final categories = [
      Category('awards', 'OSCAR WINNING MOVIES'),
      Category('4k', 'ENGLISH (4K)'),
      Category('cam', 'ENGLISH (2027) (CAM)'),
      Category('fresh', 'ENGLISH FHD (2026)'),
      Category('movies', 'English Movies'),
    ];

    expect(preferredEnglishMovieCategory(categories)?.id, 'movies');
    expect(
      preferredEnglishMovieCategory(
        categories.where((c) => c.id != 'movies'),
      )?.id,
      'fresh',
    );
    expect(
      preferredEnglishMovieCategory([Category('news', 'World News')]),
      isNull,
    );
  });

  testWidgets('Home keeps visible content mounted during a slow refresh', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _RefreshClient();
    Completer<List<Category>>? nextCategories;
    Future<List<Category>> loadCategories() =>
        nextCategories?.future ?? Future.value(<Category>[]);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeScreen(
          client: client,
          onBrowse: () {},
          categoryLoader: loadCategories,
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      if (find.byType(BrandedLoading).evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BrandedLoading), findsNothing);

    nextCategories = Completer<List<Category>>();
    refreshContent();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BrandedLoading), findsNothing);

    nextCategories.complete(<Category>[]);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('Home exposes a recently played live channel separately', (
    tester,
  ) async {
    Library.instance.addRecent(
      const MediaRef(
        kind: 'live',
        id: 7,
        name: 'Evening News',
        image: '',
        url: 'https://stream.example/live.ts',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeScreen(
          client: _RefreshClient(),
          onBrowse: () {},
          categoryLoader: () async => <Category>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent channels'), findsOneWidget);
    expect(find.text('Evening News'), findsOneWidget);
    expect(find.text('Watch live'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-recent-channels-viewport')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-recent-channels-viewport')),
        matching: find.byWidgetPredicate(
          (widget) => widget is ClipRect && widget.child is ShaderMask,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home separates resumable VOD from recent live channels', (
    tester,
  ) async {
    Library.instance.progress['movie:42'] = Progress(
      key: 'movie:42',
      title: 'A Half Watched Film',
      poster: '',
      url: 'https://stream.example/movie.mp4',
      ext: 'mp4',
      position: 1200,
      duration: 3600,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    Library.instance.recent.add(
      const MediaRef(
        kind: 'live',
        id: 9,
        name: 'Live Sports',
        url: 'https://stream.example/live.ts',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: HomeScreen(
          client: _RefreshClient(),
          onBrowse: () {},
          categoryLoader: () async => <Category>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('A Half Watched Film'), findsOneWidget);
    expect(find.text('Film · 40m left'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Recent channels'), findsOneWidget);
    expect(find.text('Live Sports'), findsOneWidget);
  });
}
