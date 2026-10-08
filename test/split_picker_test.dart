import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/playback.dart';
import 'package:lumen_tv/screens/split_picker.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends XtreamClient {
  _Client() : super(XtreamCredentials.demoProfile);
  Completer<List<Category>>? delayedCategories;
  Completer<List<LiveStream>>? delayedChannels;
  int channelCalls = 0;
  bool failEpisodes = true;
  @override
  String streamUrl(String kind, Object id, {String ext = 'ts'}) =>
      'https://sample.example/$kind/$id.$ext';
  @override
  Future<List<Category>> liveCategories() async =>
      delayedCategories?.future ?? [Category('live', 'Sports')];
  @override
  Future<List<Category>> vodCategories() async => [
    Category('movies', 'Cinema'),
  ];
  @override
  Future<List<Category>> seriesCategories() async => [
    Category('series', 'Shows'),
  ];
  @override
  Future<List<LiveStream>> liveStreams(String? categoryId) async {
    channelCalls++;
    return delayedChannels?.future ??
        [
          LiveStream(
            1,
            'World Sports',
            '',
            'live',
            sourceLabel: 'Family service',
          ),
          LiveStream(2, 'City News', '', 'live'),
        ];
  }

  @override
  Future<List<Series>> series(String? categoryId) async => [
    Series(1, 'Test show', '', '', '', 0, '', 'series'),
  ];
  @override
  Future<SeriesInfo> seriesInfo(int id) async {
    if (failEpisodes) throw StateError('offline');
    return super.seriesInfo(id);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogCache.instance.clear();
    activePalette = darkPalette;
  });
  Future<void> pump(
    WidgetTester tester,
    _Client client, {
    ValueChanged<PlayerItem>? onPick,
    String? primaryUrl,
    Size size = const Size(380, 720),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF15181C),
          body: SplitPicker(
            client: client,
            onPick: onPick ?? (_) {},
            primaryUrl: primaryUrl,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'search filters loaded channels without provider calls and marks main stream',
    (tester) async {
      final client = _Client();
      PlayerItem? picked;
      await pump(
        tester,
        client,
        onPick: (item) => picked = item,
        primaryUrl: client.streamUrl('live', 1, ext: 'ts'),
      );
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();
      expect(find.text('On main screen'), findsOneWidget);
      await tester.tap(find.text('World Sports'));
      expect(picked, isNull);
      await tester.enterText(find.byType(TextField), 'city');
      await tester.pumpAndSettle();
      expect(find.text('World Sports'), findsNothing);
      expect(client.channelCalls, 1);
      await tester.tap(find.text('City News'));
      expect(picked?.title, 'City News');
      expect(picked?.isLive, isTrue);
    },
  );

  testWidgets('late categories cannot replace a newer section', (tester) async {
    final client = _Client()..delayedCategories = Completer<List<Category>>();
    await pump(tester, client);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.text('Cinema'), findsOneWidget);
    client.delayedCategories!.complete([Category('old', 'Outdated')]);
    await tester.pumpAndSettle();
    expect(find.text('Outdated'), findsNothing);
    expect(find.text('Cinema'), findsOneWidget);
  });

  testWidgets('Back during loading ignores a stale channel response', (
    tester,
  ) async {
    final client = _Client()..delayedChannels = Completer<List<LiveStream>>();
    await pump(tester, client);
    await tester.tap(find.text('Sports'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back to categories'));
    await tester.pumpAndSettle();
    client.delayedChannels!.complete([
      LiveStream(1, 'Late channel', '', 'live'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('Late channel'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'failed episode loading offers retry instead of spinning forever',
    (tester) async {
      await pump(tester, _Client());
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shows'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test show'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load episodes.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('small landscape picker fits and supports keyboard selection', (
    tester,
  ) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = previousStrategy,
    );
    final client = _Client();
    PlayerItem? picked;
    await pump(
      tester,
      client,
      size: const Size(320, 390),
      scale: 1.3,
      onPick: (item) => picked = item,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sports'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Split browser first result',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked?.title, 'City News');
    expect(tester.takeException(), isNull);
  });
}
