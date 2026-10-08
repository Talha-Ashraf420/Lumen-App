import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/player_chrome.dart';
import 'package:lumen_tv/theme.dart';

void main() {
  testWidgets(
    'compact player exposes actions and keeps live transport honest',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = <String>[];
      final playFocus = FocusNode();
      addTearDown(playFocus.dispose);
      Widget player(bool live) => MaterialApp(
        theme: buildTheme(darkPalette),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayerTransport(
                    playing: false,
                    live: live,
                    playFocusNode: playFocus,
                    onPlayPause: () => calls.add('play'),
                    onRewind: () => calls.add('rewind'),
                    onForward: () => calls.add('forward'),
                    onPrevious: () => calls.add('previous'),
                    onNext: () => calls.add('next'),
                  ),
                  PlayerActionBar(
                    fullscreen: true,
                    onChannels: () => calls.add('channels'),
                    onSubtitles: () => calls.add('subtitles'),
                    onMore: () => calls.add('more'),
                    onFullscreen: () => calls.add('fullscreen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(player(false));
      for (final label in [
        'Previous episode',
        'Rewind 10 seconds',
        'Play',
        'Fast forward 10 seconds',
        'Next episode',
        'Channels',
        'Subtitles',
        'More',
        'Exit full screen',
      ]) {
        final control = find.byTooltip(label);
        expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
        await tester.tap(control);
      }
      expect(calls, [
        'previous',
        'rewind',
        'play',
        'forward',
        'next',
        'channels',
        'subtitles',
        'more',
        'fullscreen',
      ]);
      playFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.last, 'play');
      expect(calls.length, 10);
      await tester.pumpWidget(player(true));
      expect(find.byTooltip('Rewind 10 seconds'), findsNothing);
      expect(find.byTooltip('Fast forward 10 seconds'), findsNothing);
      expect(find.byTooltip('Previous channel'), findsOneWidget);
      expect(find.byTooltip('Next channel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('reduced motion shows player options immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PlayerPanelEntrance(child: Text('Playback options')),
        ),
      ),
    );
    await tester.pump();
    final opacity = find.descendant(
      of: find.byType(PlayerPanelEntrance),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    expect(tester.takeException(), isNull);
  });

  test(
    'font preferences retain a consistent heading and reading hierarchy',
    () {
      final controller = ThemeController.instance;
      final previous = controller.font.value;
      addTearDown(() => controller.font.value = previous);
      controller.font.value = LumenFont.lumen;
      var theme = buildTheme(darkPalette);
      expect(theme.textTheme.headlineMedium!.fontFamily, 'SpaceGrotesk');
      expect(theme.textTheme.bodyMedium!.fontFamily, 'SpaceGrotesk');
      controller.font.value = LumenFont.inter;
      theme = buildTheme(darkPalette);
      expect(theme.textTheme.headlineMedium!.fontFamily, 'Inter');
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      controller.font.value = LumenFont.device;
      theme = buildTheme(darkPalette);
      expect(theme.textTheme.bodyMedium!.fontFamily, isNot('Inter'));
    },
  );
}
