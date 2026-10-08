import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/main.dart';
import 'package:lumen_tv/catalog_store.dart';
import 'package:lumen_tv/catalog_organization.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/screens/profile_screen.dart';
import 'package:lumen_tv/screens/viewer_picker_screen.dart';
import 'package:lumen_tv/store.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';
import 'package:lumen_tv/xtream.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProfileTestClient extends XtreamClient {
  int authenticationCalls = 0;
  _ProfileTestClient()
    : super(
        const XtreamCredentials(
          baseUrl: 'https://provider.example',
          username: 'Living room',
          password: 'test-only',
        ),
      );

  @override
  Future<Map<String, dynamic>> authenticate() async {
    authenticationCalls++;
    return {
      'status': 'Active',
      'exp_date': '1893456000',
      'active_cons': 1,
      'max_connections': 3,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CatalogOrganizationStore.instance.clearMemory();
    await CatalogStore.instance.disableForWidgetTests();
    ThemeController.instance.font.value = LumenFont.lumen;
    ThemeController.instance.corners.value = LumenCornerStyle.balanced;
    ThemeController.instance.focus.value = LumenFocusStyle.lift;
    activePalette = darkPalette;
  });

  Future<void> pumpProfile(
    WidgetTester tester,
    Size size, {
    double? contentWidth,
    Future<void> Function()? onLogout,
    XtreamClient? client,
    ValueChanged<XtreamCredentials>? onSwitch,
    Future<void> Function()? onServicesChanged,
    ProfileCredentialValidator? profileValidator,
    ProfilePage page = ProfilePage.accounts,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: contentWidth,
              child: ProfileScreen(
                page: page,
                client: client ?? _ProfileTestClient(),
                onLogout: onLogout ?? () async {},
                onSwitch: onSwitch ?? (_) {},
                onServicesChanged: onServicesChanged,
                profileValidator: profileValidator,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact settings shows only a menu, not every control', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(390, 844), page: ProfilePage.menu);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CURRENT ACCOUNT'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Playback'), findsOneWidget);
    expect(find.text('Help & about'), findsOneWidget);
    expect(find.text('Your Lumen'), findsNothing);
    expect(find.byType(LumenAvatar), findsOneWidget);
    expect(find.text('Your library'), findsOneWidget);
    expect(find.text('Your experience'), findsOneWidget);
    expect(find.byType(Glass), findsNWidgets(3));
    // Use the phone's height for useful groups, not a half-empty dashboard.
    expect(
      tester.getBottomLeft(find.text('Help & about')).dy,
      greaterThan(580),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('Color mode'), findsNothing);
    expect(find.text('Sign out of Lumen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide settings keeps a readable menu instead of a dashboard', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(1280, 900), page: ProfilePage.menu);
    expect(find.text('Accounts & services'), findsOneWidget);
    expect(find.text('Color mode'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance fits a small phone with enlarged text', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      const Size(320, 740),
      page: ProfilePage.appearance,
      textScale: 1.5,
    );
    expect(find.text('Your next great watch'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings destinations are separate routes and restore menu focus',
    (tester) async {
      final client = _ProfileTestClient();
      addTearDown(client.close);
      await pumpProfile(
        tester,
        const Size(390, 844),
        client: client,
        page: ProfilePage.menu,
      );
      expect(
        client.authenticationCalls,
        0,
        reason: 'The menu must not authenticate a provider.',
      );
      for (final page in ProfilePage.values.skip(1)) {
        await tester.ensureVisible(find.text(page.title));
        await tester.tap(find.text(page.title));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate((w) => w is ProfileScreen && w.page == page),
          findsOneWidget,
        );
        expect(find.text('Your space. Your way to watch.'), findsNothing);
        if (page != ProfilePage.appearance) {
          expect(find.text('Color mode'), findsNothing);
        }
        await tester.tap(find.byTooltip('Back to Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          page == ProfilePage.accounts
              ? 'Profile add account'
              : 'Settings ${page.title}',
        );
        expect(tester.takeException(), isNull);
      }
      expect(
        client.authenticationCalls,
        1,
        reason: 'Only opening Accounts fetches provider status.',
      );
    },
  );

  testWidgets(
    'TV remote opens settings pages and Back returns to selected menu row',
    (tester) async {
      DeviceProfile.isTelevision = true;
      addTearDown(() => DeviceProfile.isTelevision = false);
      await pumpProfile(tester, const Size(1280, 900), page: ProfilePage.menu);
      FocusManager.instance.rootScope.descendants
          .firstWhere((node) => node.debugLabel == 'Profile add account')
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Settings Viewing profiles',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Color mode'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Settings Appearance',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TV D-pad reaches viewer management from account controls', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    await pumpProfile(tester, const Size(1280, 900));
    final edit = FocusManager.instance.rootScope.descendants.firstWhere(
      (node) => node.debugLabel == 'Edit current service',
    );
    edit.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Switch or manage viewers',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPickerScreen), findsOneWidget);
  });

  testWidgets('phone accent choices form an even three-column grid', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      const Size(390, 844),
      page: ProfilePage.appearance,
    );
    await tester.scrollUntilVisible(
      find.text('Accent color'),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final signal = tester.getRect(
      find.byKey(const ValueKey('profile-accent-signal lime')),
    );
    final electric = tester.getRect(
      find.byKey(const ValueKey('profile-accent-electric blue')),
    );
    final custom = tester.getRect(
      find.byKey(const ValueKey('profile-accent-custom')),
    );
    expect(signal.width, closeTo(electric.width, .1));
    expect(signal.width, closeTo(custom.width, .1));
    expect(signal.top, closeTo(electric.top, .1));
    expect(custom.top, greaterThan(signal.bottom));
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
      var serviceChanges = 0;

      await pumpProfile(
        tester,
        const Size(1280, 900),
        client: _ProfileTestClient(),
        onSwitch: (profile) => switchedTo = profile,
        onServicesChanged: () async => serviceChanges++,
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
        'Combine service Bedroom',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(serviceChanges, 1);
      expect(
        await Store.enabledSourceScopes(),
        contains(
          Store.profileScope(
            const XtreamCredentials(
              baseUrl: 'https://bedroom.example',
              username: 'Bedroom',
              password: 'test-only',
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Edit service Bedroom',
      );
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

  testWidgets('current IPTV hostname can be edited without adding an account', (
    tester,
  ) async {
    const active = XtreamCredentials(
      baseUrl: 'https://provider.example',
      username: 'Living room',
      password: 'test-only',
    );
    await Store.setActive(active);
    XtreamCredentials? validated;
    XtreamCredentials? switchedTo;

    await pumpProfile(
      tester,
      const Size(390, 844),
      onSwitch: (profile) => switchedTo = profile,
      profileValidator: (profile) async => validated = profile,
    );

    await tester.tap(find.byKey(const ValueKey('edit-current-service')));
    await tester.pumpAndSettle();
    expect(find.text('Edit server'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('edit-service-address')),
      'https://replacement.example',
    );
    await tester.tap(find.byKey(const ValueKey('save-service-address')));
    await tester.pumpAndSettle();

    expect(validated?.baseUrl, 'https://replacement.example');
    expect(switchedTo?.baseUrl, 'https://replacement.example');
    final profiles = await Store.savedProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.baseUrl, 'https://replacement.example');
    expect(profiles.single.username, active.username);
    expect(profiles.single.password, active.password);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop settings remains a single menu', (tester) async {
    await pumpProfile(
      tester,
      const Size(930, 900),
      contentWidth: 760,
      page: ProfilePage.menu,
    );

    final accountsTopLeft = tester.getTopLeft(find.text('Accounts & services'));
    final settingsTopLeft = tester.getTopLeft(find.text('Appearance'));
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
              page: ProfilePage.appearance,
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

    await tester.tap(find.text('Inter').first);
    await tester.pumpAndSettle();
    expect(ThemeController.instance.font.value, LumenFont.inter);
    expect(
      Theme.of(
        tester.element(find.byType(ProfileScreen)),
      ).textTheme.bodyMedium?.fontFamily,
      'Inter',
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('lumen_font'), LumenFont.inter.name);

    await tester.scrollUntilVisible(
      find.text('Soft'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Soft'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.corners.value, LumenCornerStyle.soft);
    expect(
      preferences.getString('lumen_corner_style'),
      LumenCornerStyle.soft.name,
    );

    await tester.tap(find.text('Glow'));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.focus.value, LumenFocusStyle.glow);
    expect(
      preferences.getString('lumen_focus_style'),
      LumenFocusStyle.glow.name,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV appearance four-way graph reaches every visual setting', (
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
                        page: ProfilePage.appearance,
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

    FocusManager.instance.rootScope.descendants
        .firstWhere((node) => node.debugLabel == 'Dark appearance')
        .requestFocus();
    await tester.pump();
    await move(LogicalKeyboardKey.arrowRight, 'Light appearance');
    await move(LogicalKeyboardKey.arrowRight, 'System appearance');
    await move(LogicalKeyboardKey.arrowDown, 'Lumen font');
    await move(LogicalKeyboardKey.arrowRight, 'Inter font');
    await move(LogicalKeyboardKey.arrowRight, 'Device font');
    await move(LogicalKeyboardKey.arrowDown, 'Crisp corners');
    await move(LogicalKeyboardKey.arrowRight, 'Balanced corners');
    await move(LogicalKeyboardKey.arrowRight, 'Soft corners');
    await move(LogicalKeyboardKey.arrowDown, 'Outline focus');
    await move(LogicalKeyboardKey.arrowRight, 'Lift focus');
    await move(LogicalKeyboardKey.arrowRight, 'Glow focus');
    await move(
      LogicalKeyboardKey.arrowDown,
      '${accentSchemes.first.name} accent',
    );
    for (final scheme in accentSchemes.skip(1)) {
      await move(LogicalKeyboardKey.arrowRight, '${scheme.name} accent');
    }
    await move(LogicalKeyboardKey.arrowRight, 'Custom accent');
    await move(LogicalKeyboardKey.arrowDown, 'Settings back');

    final expected = <String>{
      'Dark appearance',
      'Light appearance',
      'System appearance',
      for (final option in LumenFont.values) '${option.label} font',
      for (final option in LumenCornerStyle.values) '${option.label} corners',
      for (final option in LumenFocusStyle.values) '${option.label} focus',
      for (final scheme in accentSchemes) '${scheme.name} accent',
      'Custom accent',
    };
    final reached = <String>{'Dark appearance'};
    final pending = <String>['Dark appearance'];
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

  testWidgets('corner and focus preferences change shared interaction tokens', (
    tester,
  ) async {
    DeviceProfile.isTelevision = true;
    addTearDown(() => DeviceProfile.isTelevision = false);
    final node = FocusNode(debugLabel: 'Token preview');
    addTearDown(node.dispose);
    ThemeController.instance.corners.value = LumenCornerStyle.soft;
    ThemeController.instance.focus.value = LumenFocusStyle.glow;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(darkPalette),
        home: Scaffold(
          body: Center(
            child: RemoteTap(
              focusNode: node,
              focusRadius: 16,
              onTap: () {},
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();

    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(RemoteTap),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, LumenFocusStyle.glow.scale);

    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: find.byType(RemoteTap),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = container.foregroundDecoration! as BoxDecoration;
    expect(decoration.border!.top.width, LumenFocusStyle.glow.ringWidth);
    expect(decoration.borderRadius, BorderRadius.circular(lumenCorner(16)));
    expect(decoration.boxShadow, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus preview exposes distinct treatments on touch screens', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      const Size(390, 844),
      page: ProfilePage.appearance,
    );
    BoxDecoration preview() =>
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const ValueKey('settings-focus-preview')),
                )
                .decoration!
            as BoxDecoration;
    ThemeController.instance.focus.value = LumenFocusStyle.outline;
    await tester.pumpAndSettle();
    expect(preview().border!.top.width, 3);
    expect(preview().boxShadow, isEmpty);
    ThemeController.instance.focus.value = LumenFocusStyle.lift;
    await tester.pumpAndSettle();
    expect(preview().boxShadow!.single.offset.dy, greaterThan(0));
    ThemeController.instance.focus.value = LumenFocusStyle.glow;
    await tester.pumpAndSettle();
    expect(preview().boxShadow!.single.offset, Offset.zero);
    expect(preview().boxShadow!.single.spreadRadius, greaterThan(0));
    ThemeController.instance.corners.value = LumenCornerStyle.crisp;
    await tester.pumpAndSettle();
    final crisp = preview().borderRadius! as BorderRadius;
    ThemeController.instance.corners.value = LumenCornerStyle.soft;
    await tester.pumpAndSettle();
    final soft = preview().borderRadius! as BorderRadius;
    expect(soft.topLeft.x, greaterThan(crisp.topLeft.x * 3));
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

    await pumpProfile(
      tester,
      const Size(1280, 900),
      page: ProfilePage.appearance,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-accent-custom')),
    );
    await tester.pumpAndSettle();
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
