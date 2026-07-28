import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:lumen_tv/screens/splash_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    activePalette = darkPalette;
  });

  Future<void> pumpSplash(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(darkPalette), home: const LaunchSplash()),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('launch film renders its Lottie brand sequence on TV', (
    tester,
  ) async {
    await pumpSplash(tester, const Size(1920, 1080));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('LUMEN'), findsOneWidget);
    expect(find.text('YOUR SCREEN. YOUR SIGNAL.'), findsOneWidget);
    expect(find.text('TUNING YOUR EXPERIENCE'), findsOneWidget);
    expect(find.byType(ScaleTransition), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch film remains clean on a narrow phone', (tester) async {
    await pumpSplash(tester, const Size(390, 844));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('LUMEN'), findsOneWidget);
    expect(find.text('LIVE   •   FILMS   •   SERIES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session operations use a neutral brand state, not a skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: const SessionLoading(message: 'SIGNING OUT SECURELY'),
      ),
    );

    expect(find.text('SIGNING OUT SECURELY'), findsOneWidget);
    expect(find.byType(LumenMark), findsOneWidget);
    expect(find.byType(BrandedLoading), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch waits for startup while the app initializes underneath', (
    tester,
  ) async {
    final startup = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: LaunchGate(
          startup: startup.future,
          minimumDuration: const Duration(milliseconds: 100),
          child: const ColoredBox(
            color: Colors.black,
            child: Center(child: Text('READY HOME')),
          ),
        ),
      ),
    );

    expect(find.text('READY HOME'), findsOneWidget);
    expect(find.byKey(const ValueKey('lumen-launch-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('lumen-launch-splash')), findsOneWidget);

    startup.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('lumen-launch-splash')), findsNothing);
    expect(find.text('READY HOME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
