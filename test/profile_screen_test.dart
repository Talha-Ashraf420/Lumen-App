import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/profile_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileTestClient extends XtreamClient {
  _ProfileTestClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'Living room',
          password: 'test-only',
        ),
      );

  @override
  Future<Map<String, dynamic>> authenticate() async => {
    'status': 'Active',
    'exp_date': '1893456000',
    'active_cons': 1,
    'max_connections': 3,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
  });

  Future<void> pumpProfile(
    WidgetTester tester,
    Size size, {
    double? contentWidth,
    Future<void> Function()? onLogout,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: contentWidth,
              child: ProfileScreen(
                client: _ProfileTestClient(),
                onLogout: onLogout ?? () async {},
                onSwitch: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact profile is grouped, scrollable and overflow-free', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(390, 844));

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('CURRENT ACCOUNT'), findsOneWidget);
    expect(find.text('Make Lumen yours'), findsOneWidget);
    expect(find.text('Library & playback'), findsOneWidget);
    expect(find.text('Privacy & app'), findsOneWidget);
    expect(find.text('Your Lumen'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Sign out of Lumen'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sign out of Lumen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV profile uses account rail and settings column', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(1280, 900));

    final accountTopLeft = tester.getTopLeft(find.text('CURRENT ACCOUNT'));
    final settingsTopLeft = tester.getTopLeft(find.text('Make Lumen yours'));
    expect(accountTopLeft.dx, lessThan(settingsTopLeft.dx));
    expect((accountTopLeft.dy - settingsTopLeft.dy).abs(), lessThan(80));
    expect(find.text('Profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop keeps shell title and stacks dashboard', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(930, 900), contentWidth: 760);

    final accountsTopLeft = tester.getTopLeft(find.text('Other accounts'));
    final settingsTopLeft = tester.getTopLeft(find.text('Make Lumen yours'));
    expect(settingsTopLeft.dy, greaterThan(accountsTopLeft.dy));
    expect(find.text('Profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign out confirms and awaits the root session callback', (
    tester,
  ) async {
    var calls = 0;
    final completion = Completer<void>();
    await pumpProfile(
      tester,
      const Size(390, 844),
      onLogout: () {
        calls++;
        return completion.future;
      },
    );
    await tester.scrollUntilVisible(
      find.text('Sign out of Lumen'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Sign out of Lumen'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of Lumen?'), findsOneWidget);
    expect(calls, 0);

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Signing out…'), findsOneWidget);

    completion.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
