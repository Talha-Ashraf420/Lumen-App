import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_pairing.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/device_pairing_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUp(() => activePalette = darkPalette);

  testWidgets(
    'small phone offers saved and new accounts without overflow or secret labels',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ticket = PairingTicket(
        host: '192.168.1.2',
        port: 12345,
        session: 'a' * 22,
        key: base64UrlEncode(List.filled(32, 1)).replaceAll('=', ''),
        expires: DateTime.now().add(const Duration(minutes: 3)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: PhonePairingScreen(
            profiles: () async => [
              XtreamCredentials.demoProfile,
              const XtreamCredentials(
                baseUrl: 'https://provider.example',
                username: 'viewer',
                password: 'hidden-secret',
              ),
            ],
            scan: (_) async => ticket.link,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan TV QR'));
      await tester.pumpAndSettle();
      expect(find.text('Demo profile'), findsNothing);
      expect(find.textContaining('viewer'), findsOneWidget);
      expect(find.textContaining('hidden-secret'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Send account to TV'));
      await tester.tap(find.text('Send account to TV'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a valid HTTP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TV network failure provides retry and manual login', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(lightPalette),
        home: TvPairingScreen(addresses: () async => []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not start local setup'), findsOneWidget);
    expect(find.text('Generate new QR'), findsOneWidget);
    expect(find.text('Cancel and use manual login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TV D-pad reaches approval and rejection, background invalidates QR',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PairingReceiver receiver;
      late PairingSender sender;
      await tester.runAsync(() async {
        receiver = await PairingReceiver.start(
          '127.0.0.1',
          allowLoopbackForTesting: true,
        );
        sender = HttpOverrides.runWithHttpOverrides(
          () => PairingSender(receiver.ticket),
          _RealHttpOverrides(),
        );
      });
      addTearDown(sender.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(darkPalette),
          home: TvPairingScreen(
            addresses: () async => ['127.0.0.1'],
            receiverFactory: (_) async => receiver,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.runAsync(() async {
        await sender.send(
          const XtreamCredentials(
            baseUrl: 'https://provider.example',
            username: 'viewer',
            password: 'secret',
          ),
        );
      });
      await tester.pump();
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      final reject = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Reject'),
      );
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve and connect'),
      );
      expect(reject.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(approve.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(reject.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(receiver.state, PairingState.rejected);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(receiver.state, PairingState.closed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
