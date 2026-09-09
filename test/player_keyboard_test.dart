import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/screens/player_host.dart';

void main() {
  test('TV seek feedback stays clear of the center transport', () {
    expect(
      playerSeekHudPlacementFor(isTelevision: true, seconds: -10),
      PlayerHudPlacement.left,
    );
    expect(
      playerSeekHudPlacementFor(isTelevision: true, seconds: 10),
      PlayerHudPlacement.right,
    );
    expect(
      playerSeekHudPlacementFor(isTelevision: false, seconds: 10),
      PlayerHudPlacement.center,
    );
  });

  test('held seeking accelerates from ten seconds into minute stages', () {
    expect(playerHeldSeekDistanceSeconds(0), 10);
    expect(playerHeldSeekDistanceSeconds(1), 60);
    expect(playerHeldSeekDistanceSeconds(8), 60);
    expect(playerHeldSeekDistanceSeconds(9), 120);
    expect(playerHeldSeekDistanceSeconds(17), 180);
    expect(playerSeekHudLabelFor(10), '+10s');
    expect(playerSeekHudLabelFor(60), '+1m');
    expect(playerSeekHudLabelFor(-120), '−2m');
  });

  test('subtitle Off hides the rendered subtitle layer', () {
    expect(
      playerSubtitleViewVisibleFor(minimized: false, subtitlesDisabled: false),
      isTrue,
    );
    expect(
      playerSubtitleViewVisibleFor(minimized: false, subtitlesDisabled: true),
      isFalse,
    );
    expect(
      playerSubtitleViewVisibleFor(minimized: true, subtitlesDisabled: false),
      isFalse,
    );
  });

  test('recovery focus enters actions and returns to the player', () {
    expect(
      playerRecoveryFocusTargetFor(
        wasExhausted: false,
        isExhausted: true,
        hasMedia: true,
        minimized: false,
      ),
      PlayerRecoveryFocusTarget.retryAction,
    );
    expect(
      playerRecoveryFocusTargetFor(
        wasExhausted: true,
        isExhausted: false,
        hasMedia: true,
        minimized: false,
      ),
      PlayerRecoveryFocusTarget.player,
    );
    expect(
      playerRecoveryFocusTargetFor(
        wasExhausted: false,
        isExhausted: true,
        hasMedia: true,
        minimized: true,
      ),
      PlayerRecoveryFocusTarget.none,
    );
  });

  test('desktop player maps standard transport shortcuts', () {
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.space, isTelevision: false),
      PlayerKeyboardCommand.togglePlayPause,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.arrowLeft,
        isTelevision: false,
      ),
      PlayerKeyboardCommand.seekBackward,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.arrowRight,
        isTelevision: false,
      ),
      PlayerKeyboardCommand.seekForward,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyS, isTelevision: false),
      PlayerKeyboardCommand.stop,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyP, isTelevision: false),
      PlayerKeyboardCommand.previousItem,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyN, isTelevision: false),
      PlayerKeyboardCommand.nextItem,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.mediaTrackPrevious,
        isTelevision: false,
      ),
      PlayerKeyboardCommand.previousItem,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.mediaTrackNext,
        isTelevision: false,
      ),
      PlayerKeyboardCommand.nextItem,
    );
  });

  test('TV arrows remain available to D-pad focus traversal', () {
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.arrowLeft,
        isTelevision: true,
      ),
      isNull,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.arrowRight,
        isTelevision: true,
      ),
      isNull,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyJ, isTelevision: true),
      PlayerKeyboardCommand.seekBackward,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyL, isTelevision: true),
      PlayerKeyboardCommand.seekForward,
    );
  });

  test('volume, mute, and fullscreen shortcuts are mapped', () {
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.arrowUp, isTelevision: false),
      PlayerKeyboardCommand.volumeUp,
    );
    expect(
      playerKeyboardCommandFor(
        LogicalKeyboardKey.arrowDown,
        isTelevision: false,
      ),
      PlayerKeyboardCommand.volumeDown,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyM, isTelevision: false),
      PlayerKeyboardCommand.toggleMute,
    );
    expect(
      playerKeyboardCommandFor(LogicalKeyboardKey.keyF, isTelevision: false),
      PlayerKeyboardCommand.toggleFullscreen,
    );
  });
}
