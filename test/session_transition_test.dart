import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/main.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/multi_source.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/store.dart';
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
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'unchanged service reload retains the active client and Home state',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lumen_legal_acceptance_v1': true,
        'lumen_active': jsonEncode(XtreamCredentials.demoProfile.toJson()),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          home: SessionGate(profileActivator: (_) async {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final shell = tester.widget<HomeShell>(find.byType(HomeShell));
      final state = tester.state(find.byType(HomeShell));
      await shell.onServicesChanged!();
      await tester.pump();
      expect(
        tester.widget<HomeShell>(find.byType(HomeShell)).client,
        same(shell.client),
      );
      expect(tester.state(find.byType(HomeShell)), same(state));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('disabling a combined service remounts cached catalog tabs', (
    tester,
  ) async {
    const first = XtreamCredentials(
      baseUrl: 'https://one.example',
      username: 'first',
      password: 'first-password',
    );
    const second = XtreamCredentials(
      baseUrl: 'https://two.example',
      username: 'second',
      password: 'second-password',
    );
    SharedPreferences.setMockInitialValues({
      'lumen_legal_acceptance_v1': true,
      'lumen_active': jsonEncode(first.toJson()),
      'lumen_profiles': jsonEncode([first.toJson(), second.toJson()]),
      'lumen_enabled_sources_v1': jsonEncode([
        Store.profileScope(first),
        Store.profileScope(second),
      ]),
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: SessionGate(profileActivator: (_) async {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final before = tester.widget<HomeShell>(find.byType(HomeShell));
    final beforeState = tester.state(find.byType(HomeShell));
    expect(before.client, isA<MultiSourceXtreamClient>());

    await Store.setProfileEnabled(second, false);
    await before.onServicesChanged!();
    await tester.pump();

    final after = tester.widget<HomeShell>(find.byType(HomeShell));
    expect(after.client, isNot(same(before.client)));
    expect(after.client, isNot(isA<MultiSourceXtreamClient>()));
    expect(tester.state(find.byType(HomeShell)), isNot(same(beforeState)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
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
    await tester.tap(find.text('Accounts & services'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Sign out of Lumen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of Lumen'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Sign out').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('SIGNING OUT SECURELY'), findsNothing);
    expect(
      await SharedPreferences.getInstance().then(
        (value) => value.getBool('lumen_signed_out'),
      ),
      isTrue,
    );
  });

  testWidgets('Back on the root login cannot leave a black navigator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(darkPalette), home: const SessionGate()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Exit Lumen?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'No'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Exit Lumen?'), findsNothing);
  });
}
