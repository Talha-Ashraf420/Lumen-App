import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/catalog_organization.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/catalog_organization_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OrganizerClient extends XtreamClient {
  _OrganizerClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://organizer.example',
          username: 'viewer',
          password: 'test-only',
        ),
      );

  @override
  Future<List<Category>> vodCategories() async => [
    Category('movie-1', 'Cinema'),
    Category('movie-2', 'Documentaries'),
  ];

  @override
  Future<List<Category>> seriesCategories() async => [
    Category('series-1', 'Drama'),
  ];

  @override
  Future<List<Category>> liveCategories() async => [Category('live-1', 'News')];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CatalogCache.instance.clear();
    CatalogOrganizationStore.instance.clearMemory();
    await CatalogStore.instance.disableForWidgetTests();
    activePalette = darkPalette;
  });

  testWidgets('organizer is usable without overflow on a small phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: CatalogOrganizationScreen(client: _OrganizerClient()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Organize library'), findsOneWidget);
    expect(find.text('Cinema'), findsOneWidget);
    expect(find.text('Documentaries'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Hide category').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Hidden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
