import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/android_subtitle_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lumen/subtitles');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android subtitle picker returns imported subtitle data', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pick');
          return <String, dynamic>{
            'name': 'movie.en.srt',
            'data': '1\n00:00:00,000 --> 00:00:01,000\nHello',
            'mimeType': 'application/x-subrip',
          };
        });

    final subtitle = await AndroidSubtitlePicker.pick();
    expect(subtitle?.name, 'movie.en.srt');
    expect(subtitle?.data, contains('Hello'));
    expect(subtitle?.mimeType, 'application/x-subrip');
  });

  test('cancelling the Android subtitle picker is harmless', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await AndroidSubtitlePicker.pick(), isNull);
  });
}
