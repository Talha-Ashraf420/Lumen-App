import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/home_config.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/customize_home_screen.dart';
import 'package:lumen_tv/screens/downloads_screen.dart';
import 'package:lumen_tv/screens/legal_screen.dart';
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/screens/mylist_screen.dart';
import 'package:lumen_tv/screens/stats_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

XtreamClient testClient() => XtreamClient(
  const XtreamCredentials(
    baseUrl: 'https://provider.example',
    username: 'Test viewer',
    password: 'test-only',
  ),
);

class _EditorialTestClient extends XtreamClient {
  _EditorialTestClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'Test viewer',
          password: 'test-only',
        ),
      );

  @override
  Future<List<Category>> vodCategories() async => [
    Category('1', 'New cinema'),
    Category('2', 'Award winners'),
  ];

  @override
  Future<List<Category>> seriesCategories() async => [
    Category('3', 'Prestige drama'),
  ];

  @override
  Future<List<Category>> liveCategories() async => [Category('4', 'News')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
    await CatalogStore.instance.disableForWidgetTests();
  });

  Future<void> pumpAt(WidgetTester tester, Widget child, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  Future<void> disposeUi(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('editorial library pages render cleanly on a phone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      MyListScreen(client: testClient()),
      const Size(390, 844),
    );
    expect(find.text('My list'), findsOneWidget);
    expect(find.text('Save the good stuff'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpAt(
      tester,
      DownloadsScreen(client: testClient()),
      const Size(390, 844),
    );
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(find.text('Your offline shelf is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  testWidgets('TV library and trust centre use spacious layouts', (
    tester,
  ) async {
    await pumpAt(
      tester,
      MyListScreen(client: testClient()),
      const Size(1280, 900),
    );
    expect(find.text('Saved for later'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpAt(tester, const LegalScreen(), const Size(1280, 900));
    expect(find.text('Clear terms, private by design'), findsOneWidget);
    expect(find.text('THE IMPORTANT PARTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  testWidgets('sign in becomes a two-pane welcome on TV', (tester) async {
    await pumpAt(tester, LoginScreen(onLogin: (_) {}), const Size(1280, 900));
    await tester.pump();
    expect(find.text('Your screen.\nYour signal.'), findsOneWidget);
    expect(find.text('Welcome to Lumen'), findsOneWidget);
    expect(find.text('Enter Lumen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });

  testWidgets('customization studio and insights render on TV', (tester) async {
    final client = _EditorialTestClient();
    CatalogCache.instance.clear();
    HomeConfig.instance.clear();
    await pumpAt(
      tester,
      CustomizeHomeScreen(client: client),
      const Size(1280, 900),
    );
    await tester.pump();
    expect(find.text('Build your own front row'), findsOneWidget);
    expect(find.text('New cinema'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpAt(tester, StatsScreen(client: client), const Size(1280, 900));
    await tester.pump();
    expect(find.text('Time well watched'), findsOneWidget);
    expect(find.text('Your story starts with Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeUi(tester);
  });
}
