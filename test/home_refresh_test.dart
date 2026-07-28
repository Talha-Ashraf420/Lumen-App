import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
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
}
