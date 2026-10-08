// Optional real-widget previews, using only Lumen's bundled demo artwork.
// flutter test test/ui_refresh_preview_test.dart --dart-define=CAPTURE_UI=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/player_chrome.dart';
import 'package:lumen_tv/screens/shell.dart';
import 'package:lumen_tv/screens/profile_screen.dart';
import 'package:lumen_tv/screens/split_picker.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('render navigation and player design review', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    DeviceProfile.isTelevision = false;
    activePalette = darkPalette;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    for (final entry in {
      'SpaceGrotesk': [
        'assets/fonts/SpaceGrotesk-Regular.ttf',
        'assets/fonts/SpaceGrotesk-Bold.ttf',
      ],
      'Inter': ['assets/fonts/inter/Inter-Variable.ttf'],
      'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = XtreamClient(XtreamCredentials.demoProfile);
    addTearDown(client.close);
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      if (name.endsWith('live')) {
        for (var attempt = 0; attempt < 40; attempt++) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          if (find.text('Lumen One').evaluate().isNotEmpty) break;
        }
        expect(find.text('Lumen One'), findsOneWidget);
      }
      await tester.runAsync(() async {
        for (final asset in [
          'meridian',
          'aerial_night',
          'afterlight',
          'glass_harbor',
        ]) {
          await precacheImage(
            AssetImage('assets/demo/$asset.jpg'),
            boundary.currentContext!,
          );
        }
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/private/tmp/lumen-ui-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(darkPalette),
          home: HomeShell(
            client: client,
            onLogout: () async {},
            onSwitch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await capture('home');
    await tester.tap(find.byTooltip('Live'));
    await tester.pump();
    await capture('live');
    activePalette = lightPalette;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(lightPalette),
          home: HomeShell(
            client: client,
            onLogout: () async {},
            onSwitch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await capture('light-live');
    activePalette = darkPalette;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(darkPalette),
          home: Scaffold(
            body: ProfileScreen(
              client: client,
              onLogout: () async {},
              onSwitch: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await capture('settings-menu');
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await capture('settings-appearance');
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-font-inter')),
    );
    await tester.pump();
    await capture('settings-fonts');
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-focus-preview')),
    );
    for (final style in LumenFocusStyle.values) {
      ThemeController.instance.focus.value = style;
      await tester.pump();
      await capture('settings-focus-${style.name}');
    }
    ThemeController.instance.focus.value = LumenFocusStyle.lift;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          key: const ValueKey('split-preview'),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(darkPalette),
          home: Scaffold(
            backgroundColor: const Color(0xFF15181C),
            body: SplitPicker(client: client, onPick: (_) {}, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('split-categories');
    await tester.tap(find.text('Lumen Live'));
    await tester.pumpAndSettle();
    await capture('split-channels');
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          key: const ValueKey('landscape-panel-preview'),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(darkPalette),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(844, 390),
              padding: EdgeInsets.fromLTRB(59, 0, 59, 21),
            ),
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/demo/aerial_night.jpg',
                    fit: BoxFit.cover,
                  ),
                  PlayerSidePanel(
                    onClose: () {},
                    child: SplitPicker(
                      client: client,
                      onPick: (_) {},
                      onClose: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('player-panel-landscape');
    await tester.tap(find.text('Lumen Live'));
    await tester.pumpAndSettle();
    await capture('player-panel-channels-landscape');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(darkPalette),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/demo/aerial_night.jpg', fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.black26, Colors.black87],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Aerial Night',
                            style: buildTheme(
                              darkPalette,
                            ).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          const Icon(Icons.close, color: Colors.white),
                        ],
                      ),
                      const Spacer(),
                      Center(
                        child: PlayerTransport(
                          playing: true,
                          live: false,
                          onPlayPause: () {},
                          onRewind: () {},
                          onForward: () {},
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(value: .32, onChanged: (_) {}),
                      PlayerActionBar(
                        fullscreen: true,
                        onSubtitles: () {},
                        onMore: () {},
                        onFullscreen: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await capture('player-controls');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));
}
