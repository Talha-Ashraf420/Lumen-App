import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/catalog_cache.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
    CatalogCache.instance.clear();
    DeviceProfile.isTelevision = false;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform search to Live category stays on Live', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final client = XtreamClient(XtreamCredentials.demoProfile);
      addTearDown(client.close);
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
      await tester.pump(const Duration(seconds: 1));

      Future<void> tab(String label) async {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Establish a previous Home focus before opening the search keyboard.
      await tab('Movies');
      await tab('Home');
      await tab('Search');
      await tester.enterText(find.byType(TextField), 'Aerial Night');
      await tester.pump(const Duration(milliseconds: 500));
      await tab('Live');
      expect(find.byKey(const ValueKey('shell-page-6')), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byTooltip('Category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Culture').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('shell-page-6')), findsOneWidget);
      expect(find.text('Culture'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('mobile-tab-6')))
            .properties
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('mobile-tab-0')))
            .properties
            .selected,
        isFalse,
      );

      // Canceling a popup also must not restore an old destination.
      await tester.tap(find.byTooltip('Category'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('shell-page-6')), findsOneWidget);
      await tab('Search');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Aerial Night',
      );
      await tab('Live');
      expect(find.text('Culture'), findsOneWidget);

      // Restored focus is not a navigation command. Hardware activation is.
      final homeFocus = tester
          .widget<RemoteTap>(
            find.descendant(
              of: find.byTooltip('Home'),
              matching: find.byType(RemoteTap),
            ),
          )
          .focusNode!;
      homeFocus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('shell-page-6')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byKey(const ValueKey('shell-page-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('small phone tabs fit large text and track every destination', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = XtreamClient(XtreamCredentials.demoProfile);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: HomeShell(
          client: client,
          onLogout: () async {},
          onSwitch: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (final (label, page) in [
      ('Movies', 4),
      ('Series', 5),
      ('Live', 6),
      ('Search', 1),
      ('Home', 0),
    ]) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(ValueKey('shell-page-$page')), findsOneWidget);
      final indicator = find.byKey(const ValueKey('mobile-tab-indicator'));
      expect(
        tester.widget<AnimatedPositionedDirectional>(indicator).duration,
        Duration.zero,
      );
      final selectedTab = find.byKey(ValueKey('mobile-tab-$page'));
      expect(
        tester.getCenter(indicator).dx,
        closeTo(tester.getCenter(selectedTab).dx, 1),
      );
      for (final destination in [0, 4, 5, 6, 1]) {
        final tab = find.byKey(ValueKey('mobile-tab-$destination'));
        expect(
          tester.widget<Semantics>(tab).properties.selected,
          destination == page,
        );
        expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPad rail focus restoration does not navigate', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = XtreamClient(XtreamCredentials.demoProfile);
    addTearDown(client.close);
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
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Live'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final home = tester.widget<FocusableActionDetector>(
      find
          .descendant(
            of: find.byTooltip('Home'),
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    );
    home.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('shell-page-6')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey('shell-page-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
