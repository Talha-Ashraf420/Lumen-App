import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/playback_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playback mode persists and restores', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = PlaybackModeController.instance;

    await controller.load();
    expect(controller.mode.value, PlaybackMode.balanced);

    await controller.set(PlaybackMode.stable);
    expect(controller.mode.value, PlaybackMode.stable);

    controller.mode.value = PlaybackMode.lowLatency;
    await controller.load();
    expect(controller.mode.value, PlaybackMode.stable);
  });

  test('every playback mode has concise user-facing copy', () {
    for (final mode in PlaybackMode.values) {
      expect(mode.label, isNotEmpty);
      expect(mode.description, isNotEmpty);
    }
  });
}
