import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/device_profile.dart';
import 'package:lumen_tv/player_chrome.dart';
import 'package:lumen_tv/theme.dart';
import 'package:lumen_tv/widgets.dart';

void main() {
  for (final size in [const Size(844, 390), const Size(390, 844)]) {
    testWidgets('panel uses edge safe area and dismisses outside: $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final landscape = size.width > size.height;
      final safe = landscape
          ? const EdgeInsets.fromLTRB(59, 0, 59, 21)
          : const EdgeInsets.fromLTRB(0, 59, 0, 34);
      var dismissed = 0;
      var videoTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, padding: safe),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => videoTaps++,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                PlayerSidePanel(
                  onClose: () => dismissed++,
                  child: const SizedBox.expand(key: ValueKey('panel-content')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final content = tester.getRect(
        find.byKey(const ValueKey('panel-content')),
      );
      expect(content.width, closeTo(landscape ? 380 : size.width * .92, .1));
      expect(content.right, size.width - safe.right);
      expect(content.top, safe.top);
      expect(content.bottom, size.height - safe.bottom);
      await tester.tapAt(content.center);
      expect(dismissed, 0);
      await tester.tapAt(Offset(content.left / 2, size.height / 2));
      await tester.pump();
      expect(dismissed, 1);
      expect(videoTaps, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('status follows header height instead of overlapping it', (
    tester,
  ) async {
    for (final height in [64.0, 130.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: PlayerHeaderLane(
              header: SizedBox(key: const ValueKey('header'), height: height),
              status: const SizedBox(key: ValueKey('status'), height: 44),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('status'))).dy,
        tester.getBottomLeft(find.byKey(const ValueKey('header'))).dy,
      );
    }
  });

  for (final tv in [false, true]) {
    testWidgets(
      'navigation focus visuals are ${tv ? 'visible on TV' : 'hidden on iPhone'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = tv
            ? TargetPlatform.android
            : TargetPlatform.iOS;
        DeviceProfile.isTelevision = tv;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          DeviceProfile.isTelevision = false;
        });
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final remoteFocus = FocusNode();
        addTearDown(remoteFocus.dispose);
        var active = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(darkPalette),
            home: Scaffold(
              body: FocusableTap(
                focusNode: focus,
                onTap: () {},
                builder: (_, value) {
                  active = value;
                  return const SizedBox(width: 60, height: 60);
                },
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(active, tv);
        final animated = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(FocusableTap),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(animated.foregroundDecoration != null, tv);
        expect(lumenControlSide().resolve({WidgetState.focused}) != null, tv);
        final theme = buildTheme(darkPalette);
        expect(
          theme.iconButtonTheme.style!.side!.resolve({WidgetState.focused}) !=
              null,
          tv,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RemoteTap(
              focusNode: remoteFocus,
              onTap: () {},
              child: const SizedBox(width: 60, height: 60),
            ),
          ),
        );
        remoteFocus.requestFocus();
        await tester.pumpAndSettle();
        final remote = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(RemoteTap),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(remote.foregroundDecoration != null, tv);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
