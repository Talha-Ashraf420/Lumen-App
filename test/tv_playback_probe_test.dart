import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/tv_playback_probe.dart';

void main() {
  test('TV playback payload keeps useful states but strips private data', () {
    final report = TvPlaybackProbe.sanitize({
      'report_id': '1234abcd',
      'live': true,
      'mode': 'BALANCED',
      'url': 'http://private.example/live/user/password',
      'title': 'Private channel',
      'events': [
        {'at_ms': 10, 'name': 'state', 'detail': 'buffering'},
        {'at_ms': 30, 'name': 'tracks', 'detail': 'audio=0,video=1'},
        {
          'at_ms': 40,
          'name': 'player_error',
          'detail': 'http://private.example',
        },
        {'at_ms': 50, 'name': 'private_channel', 'detail': 'Private channel'},
      ],
    });

    expect(report['report_id'], '1234abcd');
    expect(report['url'], isNull);
    expect(report['title'], isNull);
    final events = report['events']! as List<Map<String, Object?>>;
    expect(events, hasLength(3));
    expect(events[0]['detail'], 'buffering');
    expect(events[1]['detail'], 'audio=0,video=1');
    expect(events[2]['detail'], isNull);
  });
}
