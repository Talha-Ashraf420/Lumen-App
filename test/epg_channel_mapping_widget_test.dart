import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/epg_channel_mapping_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = CatalogStore.instance;
  const credentials = XtreamCredentials(
    baseUrl: 'https://provider.example',
    username: 'viewer',
    password: 'secret',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // sqflite's transaction lock uses real timers, while widget tests run on a
    // fake clock. Storage and mapping mutations are covered by focused unit
    // tests; this test verifies that the route renders without provider I/O.
    await store.disableForWidgetTests();
    activePalette = darkPalette;
  });

  tearDown(() => store.close());

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int attempts = 40,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('channel mapping route renders without provider requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: EpgChannelMappingScreen(client: XtreamClient(credentials)),
      ),
    );
    await pumpUntil(tester, find.text('No downloaded guide source'));

    expect(find.text('Channel mapping'), findsOneWidget);
    expect(find.text('Search live channels'), findsOneWidget);
    expect(find.text('No downloaded guide source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
