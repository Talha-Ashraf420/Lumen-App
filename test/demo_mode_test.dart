import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NetworkTripwire extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    throw StateError('Demo Mode attempted a network request: ${request.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
  });

  test('demo identity survives storage and has a private profile scope', () {
    const demo = XtreamCredentials.demoProfile;
    final restored = XtreamCredentials.fromJson(
      (jsonDecode(jsonEncode(demo.toJson())) as Map).cast<String, dynamic>(),
    );
    const provider = XtreamCredentials(
      baseUrl: 'https://provider.example',
      username: 'viewer',
      password: 'secret',
    );

    expect(restored.isDemo, isTrue);
    expect(restored.password, isEmpty);
    expect(Store.profileScope(restored), Store.profileScope(demo));
    expect(Store.profileScope(restored), isNot(Store.profileScope(provider)));
  });

  test('demo catalog is complete and never touches the network', () async {
    final tripwire = _NetworkTripwire();
    final client = XtreamClient(
      XtreamCredentials.demoProfile,
      httpClient: tripwire,
    );

    final auth = await client.authenticate();
    final movieCategories = await client.vodCategories();
    final movies = await client.vodStreams(null);
    final movie = await client.vodInfo(movies.first.streamId);
    final seriesCategories = await client.seriesCategories();
    final shows = await client.series(null);
    final show = await client.seriesInfo(shows.first.seriesId);
    final liveCategories = await client.liveCategories();
    final channels = await client.liveStreams(null);
    final guide = await client.shortEpg(channels.first.streamId);

    expect(auth['auth'], 1);
    expect(movieCategories, isNotEmpty);
    expect(movies, hasLength(greaterThanOrEqualTo(6)));
    expect(movie.image, startsWith('asset://'));
    expect(seriesCategories, isNotEmpty);
    expect(shows, isNotEmpty);
    expect(show.episodes.values.expand((episodes) => episodes), isNotEmpty);
    expect(liveCategories, isNotEmpty);
    expect(channels, isNotEmpty);
    expect(guide, isNotEmpty);
    expect(client.streamHeaders(channels.first.streamId), isEmpty);
    expect(tripwire.requests, 0);
  });

  test('every bundled demo asset is available offline', () async {
    const assets = [
      'assets/demo/aerial_night.jpg',
      'assets/demo/glass_harbor.jpg',
      'assets/demo/meridian.jpg',
      'assets/demo/afterlight.jpg',
      'assets/demo/lumen_demo_preview.mp4',
    ];

    for (final asset in assets) {
      final bytes = await rootBundle.load(asset);
      expect(bytes.lengthInBytes, greaterThan(100), reason: asset);
    }
  });

  testWidgets('login enters Demo Mode without provider credentials', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    XtreamCredentials? loggedIn;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: LoginScreen(
          onLogin: (credentials) => loggedIn = credentials,
          credentialSaver: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Explore offline demo'), findsOneWidget);
    await tester.tap(find.text('Explore offline demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(loggedIn?.isDemo, isTrue);
    expect(loggedIn?.password, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
