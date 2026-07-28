import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/main.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/screens/login_screen.dart';
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

  testWidgets('logout reaches Login even when profile cleanup fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lumen_legal_acceptance_v1': true,
      'lumen_active': jsonEncode(XtreamCredentials.demoProfile.toJson()),
    });
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomeShell), findsOneWidget);

    await tester.tap(find.byTooltip('Profile'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Sign out of Lumen'), 280);
    await tester.tap(find.text('Sign out of Lumen'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Sign out').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('SIGNING OUT SECURELY'), findsNothing);
    expect(
      await SharedPreferences.getInstance().then(
        (value) => value.getBool('lumen_signed_out'),
      ),
      isTrue,
    );
  });
}
