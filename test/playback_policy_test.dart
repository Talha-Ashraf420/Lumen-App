import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/playback.dart';
import 'package:lumen_tv/xtream.dart';

void main() {
  test('playback startup and retry policy is bounded', () {
    const config = ReconnectConfig(
      maxAttempts: 3,
      baseDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 4),
    );

    expect(PlaybackPolicy.startupTimeout(false), const Duration(seconds: 10));
    expect(PlaybackPolicy.startupTimeout(true), const Duration(seconds: 20));
    expect(PlaybackPolicy.retryLimit(false, config), 1);
    expect(PlaybackPolicy.retryLimit(true, config), 3);
    expect(PlaybackPolicy.retryDelay(1, config), const Duration(seconds: 1));
    expect(PlaybackPolicy.retryDelay(2, config), const Duration(seconds: 2));
    expect(PlaybackPolicy.retryDelay(3, config), const Duration(seconds: 4));
    expect(PlaybackPolicy.retryDelay(4, config), const Duration(seconds: 4));
    expect(
      PlaybackPolicy.showCenterTransport(
        reconnectStatus: 'Opening live channel…',
        retryExhausted: false,
      ),
      isFalse,
    );
    expect(
      PlaybackPolicy.showCenterTransport(
        reconnectStatus: null,
        retryExhausted: true,
      ),
      isFalse,
    );
    expect(
      PlaybackPolicy.showCenterTransport(
        reconnectStatus: null,
        retryExhausted: false,
      ),
      isTrue,
    );
  });

  test(
    'playback rejects missing addresses and accepts streaming protocols',
    () {
      expect(isPlayableMediaUrl(''), isFalse);
      expect(isPlayableMediaUrl('not a url'), isFalse);
      expect(isPlayableMediaUrl('ftp://provider.example/video'), isFalse);
      expect(
        isPlayableMediaUrl('https://provider.example/movie/1.mp4'),
        isTrue,
      );
      expect(isPlayableMediaUrl('rtsp://provider.example/live'), isTrue);
      expect(isPlayableMediaUrl('udp://239.0.0.1:1234'), isTrue);
      expect(isPlayableMediaUrl('/data/user/0/app/offline/movie.mp4'), isTrue);
    },
  );

  test('media keeps provider headers and a streaming-friendly default', () {
    const item = PlayerItem(
      'https://provider.example/live/1.ts',
      'Channel',
      httpHeaders: {
        'User-Agent': 'ProviderAgent/1.0',
        'Referer': 'https://provider.example/',
      },
    );

    final media = mediaForPlayerItem(item);
    expect(media.httpHeaders?['Accept'], '*/*');
    expect(media.httpHeaders?['User-Agent'], 'ProviderAgent/1.0');
    expect(media.httpHeaders?['Referer'], 'https://provider.example/');
  });

  test('Xtream URLs never end with an empty extension', () {
    final client = XtreamClient(
      const XtreamCredentials(
        baseUrl: 'https://provider.example',
        username: 'viewer',
        password: 'secret',
      ),
    );
    addTearDown(client.close);

    expect(client.streamUrl('series', 17, ext: ''), endsWith('/17.mp4'));
    expect(client.streamUrl('movie', 18, ext: '.'), endsWith('/18.mp4'));
    expect(client.streamUrl('live', 19, ext: ''), endsWith('/19.ts'));
  });
}
