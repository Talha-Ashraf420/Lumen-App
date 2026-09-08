import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/main.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/profile_screen.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/updater.dart';
import 'package:lumen_tv/widgets.dart';
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CatalogStore.instance.disableForWidgetTests();
    activePalette = darkPalette;
  });

  Future<void> pumpProfile(
    WidgetTester tester,
    Size size, {
    double? contentWidth,
    Future<void> Function()? onLogout,
    XtreamClient? client,
    ValueChanged<XtreamCredentials>? onSwitch,
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
                client: client ?? _ProfileTestClient(),
                onLogout: onLogout ?? () async {},
                onSwitch: onSwitch ?? (_) {},
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

  testWidgets(
    'TV D-pad switches and removes saved accounts without pointer input',
    (tester) async {
      const active = XtreamCredentials(
        baseUrl: 'https://provider.example',
        username: 'Living room',
        password: 'test-only',
      );
      const bedroom = XtreamCredentials(
        baseUrl: 'https://bedroom.example',
        username: 'Bedroom',
        password: 'test-only',
      );
      const guest = XtreamCredentials(
        baseUrl: 'https://guest.example',
        username: 'Guest',
        password: 'test-only',
      );
      SharedPreferences.setMockInitialValues({
        'lumen_profiles': jsonEncode([
          active.toJson(),
          bedroom.toJson(),
          guest.toJson(),
        ]),
      });
      DeviceProfile.isTelevision = true;
      addTearDown(() => DeviceProfile.isTelevision = false);
      XtreamCredentials? switchedTo;

      await pumpProfile(
        tester,
        const Size(1280, 900),
        client: _ProfileTestClient(),
        onSwitch: (profile) => switchedTo = profile,
      );

      FocusNode node(String label) => FocusManager
          .instance
          .rootScope
          .descendants
          .firstWhere((candidate) => candidate.debugLabel == label);

      node('Profile add account').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Switch account Bedroom',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(switchedTo?.username, 'Bedroom');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Remove account Bedroom',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Remove account?'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Cancel account removal',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Confirm account removal',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Remove account?'), findsNothing);
      expect(find.text('Bedroom'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Profile add account',
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('profile appearance tiles repaint in dark, light and System', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    addTearDown(() {
      ThemeController.instance.mode.value = ThemeMode.dark;
      activePalette = darkPalette;
    });
    ThemeController.instance.mode.value = ThemeMode.dark;
    final client = _ProfileTestClient();
    addTearDown(client.close);

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: ThemeController.instance.listenable,
        builder: (context, _) {
          final mode = ThemeController.instance.mode.value;
          return MaterialApp(
            theme: buildTheme(lightPalette),
            darkTheme: buildTheme(darkPalette),
            themeMode: mode,
            builder: (context, child) => LumenPaletteScope(
              mode: mode,
              child: child ?? const SizedBox.shrink(),
            ),
            home: ProfileScreen(
              client: client,
              onLogout: () async {},
              onSwitch: (_) {},
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(activePalette.brightness, Brightness.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(activePalette.brightness, Brightness.light);
    final lightTile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('profile-theme-light')),
    );
    expect((lightTile.decoration! as BoxDecoration).color, accent);
    final unselectedAccent = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('profile-accent-tidal teal')),
    );
    expect(
      (unselectedAccent.decoration! as BoxDecoration).color,
      lightPalette.surfaceHi,
      reason: 'Cached accent tiles must repaint to the light surface.',
    );

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.mode.value, ThemeMode.system);
    expect(activePalette.brightness, Brightness.light);
    final systemTile = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('profile-theme-system')),
    );
    expect((systemTile.decoration! as BoxDecoration).color, accent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV profile four-way graph reaches every settings control', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final client = _ProfileTestClient();
    final rail = FocusNode(debugLabel: 'Profile test rail');
    final top = FocusNode(debugLabel: 'Profile test top');
    final entry = FocusNode(debugLabel: 'Profile add account');
    addTearDown(client.close);
    addTearDown(rail.dispose);
    addTearDown(top.dispose);
    addTearDown(entry.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: FocusTraversalGroup(
          policy: RemoteFocusTraversalPolicy(),
          child: Column(
            children: [
              RemoteTap(
                focusNode: top,
                onTap: () {},
                child: const SizedBox(width: 300, height: 50),
              ),
              Expanded(
                child: Row(
                  children: [
                    RemoteTap(
                      focusNode: rail,
                      onTap: () {},
                      child: const SizedBox(width: 72, height: 600),
                    ),
                    Expanded(
                      child: ProfileScreen(
                        client: client,
                        onLogout: () async {},
                        onSwitch: (_) {},
                        shellRailFocusNode: rail,
                        shellTopFocusNode: top,
                        entryFocusNode: entry,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> move(LogicalKeyboardKey key, String expectedLabel) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, expectedLabel);
    }

    entry.requestFocus();
    await tester.pump();
    await move(LogicalKeyboardKey.arrowDown, 'Dark appearance');
    await move(LogicalKeyboardKey.arrowRight, 'Light appearance');
    await move(LogicalKeyboardKey.arrowRight, 'System appearance');
    await move(
      LogicalKeyboardKey.arrowDown,
      '${accentSchemes.first.name} accent',
    );
    for (final scheme in accentSchemes.skip(1)) {
      await move(LogicalKeyboardKey.arrowRight, '${scheme.name} accent');
    }
    await move(LogicalKeyboardKey.arrowRight, 'Custom accent');
    for (final label in <String>[
      'Live playback mode',
      'Watch insights',
      'Downloads',
      'Refresh library',
      'Clear watch history',
      'Diagnostics & feedback',
      'Lumen community',
      'Legal & privacy',
      if (Updater.instance.isEnabled) 'Check for updates',
      'Sign out of Lumen',
    ]) {
      await move(LogicalKeyboardKey.arrowDown, label);
    }

    final profileScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(profileScrollable.position.pixels, greaterThan(0));
    entry.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(
      profileScrollable.position.pixels,
      profileScrollable.position.minScrollExtent,
    );
    await move(LogicalKeyboardKey.arrowUp, 'Profile test top');
    expect(
      profileScrollable.position.pixels,
      profileScrollable.position.minScrollExtent,
    );
    entry.requestFocus();
    await tester.pump();

    final expected = <String>{
      'Profile add account',
      'Dark appearance',
      'Light appearance',
      'System appearance',
      for (final scheme in accentSchemes) '${scheme.name} accent',
      'Custom accent',
      'Live playback mode',
      'Watch insights',
      'Downloads',
      'Refresh library',
      'Clear watch history',
      'Diagnostics & feedback',
      'Lumen community',
      'Legal & privacy',
      if (Updater.instance.isEnabled) 'Check for updates',
      'Sign out of Lumen',
    };
    final reached = <String>{'Profile add account'};
    final pending = <String>['Profile add account'];
    const directions = [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ];

    FocusNode? nodeNamed(String label) {
      for (final node in FocusManager.instance.rootScope.traversalDescendants) {
        if (node.debugLabel == label) return node;
      }
      return null;
    }

    while (pending.isNotEmpty) {
      final sourceLabel = pending.removeAt(0);
      final source = nodeNamed(sourceLabel);
      expect(source, isNotNull, reason: '$sourceLabel must stay mounted.');
      for (final direction in directions) {
        source!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(direction);
        await tester.pumpAndSettle();
        final destination = FocusManager.instance.primaryFocus?.debugLabel;
        if (destination != null &&
            expected.contains(destination) &&
            reached.add(destination)) {
          pending.add(destination);
        }
      }
    }

    expect(
      reached,
      containsAll(expected),
      reason: 'Unreachable: ${expected.difference(reached)}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom accent dialog is fully operable with a TV D-pad', (
    tester,
  ) async {
    final originalAccent = ThemeController.instance.accent.value;
    ThemeController.instance.accent.value = const Color(0xFF4A8FD8);
    addTearDown(() {
      ThemeController.instance.accent.value = originalAccent;
      activePalette = darkPaletteFor(originalAccent);
    });

    await pumpProfile(tester, const Size(1280, 900));
    await tester.tap(find.byKey(const ValueKey('profile-accent-custom')));
    await tester.pumpAndSettle();

    expect(find.text('Custom accent'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Custom accent hue');

    double sliderValue(int index) =>
        tester.widgetList<Slider>(find.byType(Slider)).elementAt(index).value;

    final hue = sliderValue(0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(sliderValue(0), greaterThan(hue));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Custom accent saturation',
    );
    final saturation = sliderValue(1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sliderValue(1), lessThan(saturation));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Custom accent brightness',
    );
    final brightness = sliderValue(2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sliderValue(2), lessThan(brightness));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Custom accent apply',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Custom accent cancel',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Custom accent apply',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Custom accent'), findsNothing);
    expect(
      ThemeController.instance.accent.value,
      isNot(const Color(0xFF4A8FD8)),
    );
    expect(tester.takeException(), isNull);
  });
}
