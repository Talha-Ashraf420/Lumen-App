import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<T> _neverCompletes<T>() => Completer<T>().future;

class _HangingLoginClient extends XtreamClient {
  _HangingLoginClient(super.credentials);

  @override
  Future<Map<String, dynamic>> authenticate() =>
      _neverCompletes<Map<String, dynamic>>();
}

class _SuccessfulLoginClient extends XtreamClient {
  _SuccessfulLoginClient(super.credentials);

  @override
  Future<Map<String, dynamic>> authenticate() async => {'auth': 1};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    activePalette = darkPalette;
  });

  Future<void> pumpLogin(
    WidgetTester tester, {
    required LoginClientFactory clientFactory,
    LoginCredentialSaver? credentialSaver,
    Duration connectionTimeout = const Duration(milliseconds: 100),
    Duration storageTimeout = const Duration(milliseconds: 100),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: LoginScreen(
          onLogin: (_) {},
          clientFactory: clientFactory,
          credentialSaver: credentialSaver,
          connectionTimeout: connectionTimeout,
          storageTimeout: storageTimeout,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'provider.example');
    await tester.enterText(find.byType(TextField).at(1), 'viewer');
    await tester.enterText(find.byType(TextField).at(2), 'secret');
  }

  testWidgets('login timeout always releases the busy state', (tester) async {
    await pumpLogin(tester, clientFactory: _HangingLoginClient.new);

    await tester.tap(find.text('Enter Lumen'));
    await tester.pump();
    expect(find.text('Checking provider…'), findsOneWidget);
    expect(find.text('Cancel connection'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('did not respond within 1 second'), findsOne);
    expect(find.text('Enter Lumen'), findsOneWidget);
    expect(find.text('Cancel connection'), findsNothing);
  });

  testWidgets('a pending login can be cancelled immediately', (tester) async {
    await pumpLogin(
      tester,
      clientFactory: _HangingLoginClient.new,
      connectionTimeout: const Duration(seconds: 10),
    );

    await tester.tap(find.text('Enter Lumen'));
    await tester.pump();
    await tester.tap(find.text('Cancel connection'));
    await tester.pump();

    expect(find.textContaining('Connection cancelled'), findsOneWidget);
    expect(find.text('Enter Lumen'), findsOneWidget);
  });

  testWidgets('storage timeout is distinct from provider timeout', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      clientFactory: _SuccessfulLoginClient.new,
      credentialSaver: (_) => _neverCompletes<void>(),
    );

    await tester.tap(find.text('Enter Lumen'));
    await tester.pump();
    expect(find.text('Securing this account…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('could not save this account'), findsOneWidget);
    expect(find.text('Enter Lumen'), findsOneWidget);
  });

  test('provider errors never expose a credential-bearing URI', () {
    final error = http.ClientException(
      'request failed',
      Uri.parse(
        'https://provider.example/player_api.php'
        '?username=viewer&password=do-not-show',
      ),
    );
    final message = safeProviderError(error);
    expect(message, isNot(contains('viewer')));
    expect(message, isNot(contains('do-not-show')));
    expect(message, isNot(contains('player_api.php')));
  });
}
