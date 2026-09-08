import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/login_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';
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
    DeviceProfile.isTelevision = false;
  });

  Future<void> pumpLogin(
    WidgetTester tester, {
    required LoginClientFactory clientFactory,
    void Function(XtreamCredentials)? onLogin,
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
          onLogin: onLogin ?? (_) {},
          clientFactory: clientFactory,
          credentialSaver: credentialSaver,
          connectionTimeout: connectionTimeout,
          storageTimeout: storageTimeout,
        ),
      ),
    );
    await tester.pump();
    for (final entry in <(int, String)>[
      (0, 'provider.example'),
      (1, 'viewer'),
      (2, 'secret'),
    ]) {
      final field = tester.widget<TextField>(
        find.byType(TextField).at(entry.$1),
      );
      field.controller!.text = entry.$2;
      field.onChanged?.call(entry.$2);
    }
    await tester.pump(const Duration(seconds: 1));
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

  testWidgets(
    'successful login releases its spinner after notifying the host',
    (tester) async {
      XtreamCredentials? loggedIn;
      await pumpLogin(
        tester,
        clientFactory: _SuccessfulLoginClient.new,
        credentialSaver: (_) async {},
        onLogin: (credentials) => loggedIn = credentials,
      );

      await tester.tap(find.text('Enter Lumen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(loggedIn?.username, 'viewer');
      expect(find.text('Opening your library…'), findsNothing);
      final submit = tester.widget<RemoteTap>(
        find.byKey(const ValueKey('login-submit')),
      );
      expect(submit.onTap, isNotNull);
    },
  );

  testWidgets('HTTP provider login is accepted with a transport warning', (
    tester,
  ) async {
    XtreamCredentials? received;
    await pumpLogin(
      tester,
      clientFactory: (credentials) {
        received = credentials;
        return _SuccessfulLoginClient(credentials);
      },
      credentialSaver: (_) async {},
    );
    await tester.enterText(
      find.byType(TextField).first,
      'http://legacy-provider.example:8080',
    );
    await tester.pump();

    expect(find.textContaining('Legacy HTTP is supported'), findsOneWidget);
    await tester.tap(find.text('Enter Lumen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(received?.baseUrl, 'http://legacy-provider.example:8080');
    expect(find.textContaining('HTTPS sources only'), findsNothing);
  });

  testWidgets('post-login host failure is not shown as a provider failure', (
    tester,
  ) async {
    await pumpLogin(
      tester,
      clientFactory: _SuccessfulLoginClient.new,
      credentialSaver: (_) async {},
      onLogin: (_) => throw StateError('host transition failed'),
    );

    await tester.tap(find.text('Enter Lumen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('could not connect to this provider'),
      findsNothing,
    );
    expect(find.text('Checking provider…'), findsNothing);
    expect(find.text('Enter Lumen'), findsOneWidget);
  });

  testWidgets('TV D-pad follows the complete login route', (tester) async {
    await pumpLogin(tester, clientFactory: _SuccessfulLoginClient.new);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    final submit = tester.widget<RemoteTap>(
      find.byKey(const ValueKey('login-submit')),
    );
    final playlist = tester.widget<TextButton>(find.bySubtype<TextButton>());
    final demo = tester.widget<OutlinedButton>(
      find.bySubtype<OutlinedButton>(),
    );

    submit.focusNode!.requestFocus();
    await tester.pump();
    expect(submit.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 220));
    expect(fields[1].focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 220));
    expect(fields[2].focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 220));
    expect(fields[0].focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 220));
    expect(fields[1].focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 220));
    expect(submit.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 220));
    expect(playlist.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 220));
    expect(demo.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 220));
    expect(playlist.focusNode!.hasFocus, isTrue);
  });

  testWidgets('TV login starts on the server field instead of submit', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: LoginScreen(
          onLogin: (_) {},
          clientFactory: _SuccessfulLoginClient.new,
        ),
      ),
    );
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    final submit = tester.widget<RemoteTap>(
      find.byKey(const ValueKey('login-submit')),
    );
    expect(fields.first.focusNode!.hasFocus, isTrue);
    expect(submit.focusNode!.hasFocus, isFalse);
  });

  testWidgets('TV submit has an unmistakable high-contrast focus treatment', (
    tester,
  ) async {
    await pumpLogin(tester, clientFactory: _SuccessfulLoginClient.new);

    final submitFinder = find.byKey(const ValueKey('login-submit'));
    final submit = tester.widget<RemoteTap>(submitFinder);
    expect(submit.focusRingColor, Colors.white);

    submit.focusNode!.requestFocus();
    await tester.pump(lumenMotionFast);

    final scales = tester.widgetList<AnimatedScale>(
      find.descendant(of: submitFinder, matching: find.byType(AnimatedScale)),
    );
    expect(scales.single.scale, greaterThan(1));
    expect(submit.focusNode!.hasFocus, isTrue);
  });

  testWidgets('TV OK opens the keyboard for a focused login field', (
    tester,
  ) async {
    final textInputCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null),
    );

    await pumpLogin(tester, clientFactory: _SuccessfulLoginClient.new);
    final urlField = tester.widget<TextField>(find.byType(TextField).first);
    urlField.focusNode!.requestFocus();
    await tester.pump();
    textInputCalls.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));

    expect(
      textInputCalls.where((call) => call.method == 'TextInput.show'),
      isNotEmpty,
    );
    expect(urlField.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('TV OK opens a D-pad keyboard that edits the login field', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    const nativeChannel = MethodChannel('lumen/tv_text_input');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          nativeChannel,
          (_) async => throw MissingPluginException(),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null),
    );

    await pumpLogin(tester, clientFactory: _SuccessfulLoginClient.new);
    final urlFinder = find.byType(TextField).first;
    final urlField = tester.widget<TextField>(urlFinder);
    urlField.focusNode!.requestFocus();
    await tester.pump();
    expect(urlField.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('TYPE WITH YOUR REMOTE'), findsOneWidget);

    // The first keyboard key is focused automatically, so remote OK must
    // write directly to the controller even on TVs with a broken vendor IME.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(urlField.controller!.text, 'provider.example1');

    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.text('TYPE WITH YOUR REMOTE'), findsNothing);
    expect(urlField.focusNode!.hasFocus, isTrue);
  });

  testWidgets('TV native editor returns text to the focused login field', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    const channel = MethodChannel('lumen/tv_text_input');
    MethodCall? request;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          request = call;
          return 'native.example';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await pumpLogin(tester, clientFactory: _SuccessfulLoginClient.new);
    final urlField = tester.widget<TextField>(find.byType(TextField).first);
    urlField.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(request?.method, 'show');
    expect(request?.arguments, containsPair('initial', 'provider.example'));
    expect(urlField.controller!.text, 'native.example');
    expect(find.text('TYPE WITH YOUR REMOTE'), findsNothing);
    expect(urlField.focusNode!.hasFocus, isTrue);
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
