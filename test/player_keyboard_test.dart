import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/screens/player_host.dart';

void main() {
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
