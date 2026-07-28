import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/main.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedHydration {
  int calls = 0;
  final Completer<void> pending = Completer<void>();

  Future<void> call(XtreamCredentials? credentials) {
    calls++;
    if (calls == 1) return Future<void>.value();
    return pending.future;
  }
}

class _ThrowingHydration {
  int calls = 0;

  Future<void> call(XtreamCredentials? credentials) {
    calls++;
    if (calls == 1) return Future<void>.value();
    throw StateError('profile hydration failed synchronously');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'lumen_legal_acceptance_v1': true});
    activePalette = darkPalette;
  });

  testWidgets('Demo opens Home while profile hydration continues', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final hydration = _DelayedHydration();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: SessionGate(profileActivator: hydration.call),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Explore offline demo'), findsOneWidget);
    await tester.tap(find.text('Explore offline demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(hydration.calls, 2);
    expect(hydration.pending.isCompleted, isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Opening your library…'), findsNothing);

    hydration.pending.complete();
    await tester.pump();
  });

  testWidgets('saved login opens Home even when profile hydration fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final hydration = _ThrowingHydration();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: SessionGate(profileActivator: hydration.call),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Explore offline demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(hydration.calls, 2);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(
      find.textContaining('could not connect to this provider'),
      findsNothing,
    );
  });
}
