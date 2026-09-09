import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/screens/shell.dart';

void main() {
  test('TV playback pauses when the app or display leaves the foreground', () {
    expect(
      shouldPauseTelevisionPlayback(
        AppLifecycleState.paused,
        isTelevision: true,
      ),
      isTrue,
    );
    expect(
      shouldPauseTelevisionPlayback(
        AppLifecycleState.hidden,
        isTelevision: true,
      ),
      isTrue,
    );
    expect(
      shouldPauseTelevisionPlayback(
        AppLifecycleState.resumed,
        isTelevision: true,
      ),
      isFalse,
    );
  });

  test('phone lifecycle changes do not interrupt picture-in-picture', () {
    expect(
      shouldPauseTelevisionPlayback(
        AppLifecycleState.paused,
        isTelevision: false,
      ),
      isFalse,
    );
  });
}
