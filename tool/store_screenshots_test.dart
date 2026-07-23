import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/screens/legal_screen.dart';
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    final spaceGrotesk = FontLoader('SpaceGrotesk')
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/SpaceGrotesk-Bold.ttf'));
    await Future.wait([materialIcons.load(), spaceGrotesk.load()]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size physicalSize,
    required double devicePixelRatio,
    required Widget child,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = physicalSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(darkPalette),
        home: RepaintBoundary(
          key: const ValueKey('store-screenshot'),
          child: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('renders licensed phone welcome screenshot', (tester) async {
    await pumpScreen(
      tester,
      physicalSize: const Size(1170, 2532),
      devicePixelRatio: 3,
      child: LoginScreen(onLogin: (_) {}),
    );

    expect(find.text('Welcome to Lumen'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('store-screenshot')),
      matchesGoldenFile(
        '../fastlane/metadata/android/en-US/images/phoneScreenshots/'
        '01-welcome.png',
      ),
    );
  });

  testWidgets('renders phone privacy screenshot', (tester) async {
    await pumpScreen(
      tester,
      physicalSize: const Size(1170, 2532),
      devicePixelRatio: 3,
      child: const LegalScreen(),
    );

    expect(find.text('Clear terms, private by design'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('store-screenshot')),
      matchesGoldenFile(
        '../fastlane/metadata/android/en-US/images/phoneScreenshots/'
        '02-privacy.png',
      ),
    );
  });

  testWidgets('renders licensed Android TV welcome screenshot', (tester) async {
    await pumpScreen(
      tester,
      physicalSize: const Size(1920, 1080),
      devicePixelRatio: 1,
      child: LoginScreen(onLogin: (_) {}),
    );

    expect(find.text('Your screen.\nYour signal.'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('store-screenshot')),
      matchesGoldenFile(
        '../fastlane/metadata/android/en-US/images/tvScreenshots/'
        '01-tv-welcome.png',
      ),
    );
  });
}
