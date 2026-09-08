import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_tv/models.dart';
import 'package:lumen_tv/playback.dart';
import 'package:lumen_tv/playback_mode.dart';
import 'package:lumen_tv/xtream.dart';

void main() {
  test('playback startup and retry policy is bounded', () {
    const config = ReconnectConfig(
      maxAttempts: 3,
      baseDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 4),
    );

    expect(PlaybackPolicy.startupTimeout(false), const Duration(seconds: 45));
    expect(PlaybackPolicy.startupTimeout(true), const Duration(seconds: 35));
    expect(
      PlaybackPolicy.startupTimeout(false, hasBufferedData: true),
      const Duration(seconds: 75),
    );
    expect(
      PlaybackPolicy.startupTimeout(true, hasBufferedData: true),
      const Duration(seconds: 75),
    );
    expect(PlaybackPolicy.retryLimit(false, config), 1);
    expect(PlaybackPolicy.retryLimit(true, config), 3);
    expect(PlaybackPolicy.retryDelay(1, config), const Duration(seconds: 1));
    expect(PlaybackPolicy.retryDelay(2, config), const Duration(seconds: 2));
    expect(PlaybackPolicy.retryDelay(3, config), const Duration(seconds: 4));
    expect(PlaybackPolicy.retryDelay(4, config), const Duration(seconds: 4));
    expect(PlaybackPolicy.stallTimeout(true), const Duration(seconds: 15));
    expect(PlaybackPolicy.stallTimeout(false), const Duration(seconds: 35));
    expect(const ReconnectConfig().liveOnly, isFalse);
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

  test('stale playlist indexes are safe during session cleanup', () {
    const item = PlayerItem(
      'https://provider.example/movie.mp4',
      'Movie',
      progressKey: 'movie:1',
    );

    expect(playbackItemAt(const [], 0), isNull);
    expect(playbackItemAt(const [item], -1), isNull);
    expect(playbackItemAt(const [item], 1), isNull);
    expect(playbackItemAt(const [item], 0), same(item));
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

  test('playback failures are classified into actionable safe codes', () {
    expect(classifyPlaybackFailure('HTTP 403 forbidden').code, 'ACCESS');
    expect(classifyPlaybackFailure('HTTP 403 forbidden').retryable, isFalse);
    expect(classifyPlaybackFailure('404 not found').code, 'SOURCE');
    expect(classifyPlaybackFailure('network timeout').code, 'TIMEOUT');
    expect(classifyPlaybackFailure('TLS certificate error').code, 'TLS');
    expect(classifyPlaybackFailure('decoder codec failed').code, 'CODEC');
    expect(
      classifyPlaybackFailure('connection refused by host').code,
      'NETWORK',
    );
    expect(classifyPlaybackFailure('', stalled: true).code, 'STALL');
    expect(classifyPlaybackFailure('', invalidAddress: true).code, 'ADDRESS');
  });

  test(
    'Xtream sources get safe format alternatives without leaking secrets',
    () {
      const live = PlayerItem(
        'https://provider.example/live/viewer/secret/19.ts',
        'Channel',
        isLive: true,
      );
      final liveSources = playbackSourceCandidates(live);
      expect(liveSources, hasLength(2));
      expect(liveSources.first, endsWith('/19.ts'));
      expect(liveSources.last, endsWith('/19.m3u8'));

      const hlsLive = PlayerItem(
        'https://provider.example/live/viewer/secret/20.m3u8',
        'HLS channel',
        isLive: true,
      );
      expect(playbackSourceCandidates(hlsLive), [
        'https://provider.example/live/viewer/secret/20.m3u8',
        'https://provider.example/live/viewer/secret/20.ts',
      ]);

      const movie = PlayerItem(
        'https://provider.example/movie/viewer/secret/8.mp4',
        'Movie',
      );
      expect(playbackSourceCandidates(movie).last, endsWith('/8.mkv'));

      const arbitraryM3u = PlayerItem(
        'https://cdn.example/channels/news.ts?token=private',
        'News',
        isLive: true,
      );
      expect(playbackSourceCandidates(arbitraryM3u), [arbitraryM3u.url]);

      final safeEndpoint = playbackEndpointLabel(live.url);
      expect(safeEndpoint, 'HTTPS · provider.example');
      expect(safeEndpoint, isNot(contains('viewer')));
      expect(safeEndpoint, isNot(contains('secret')));
    },
  );

  test('buffer policy keeps live responsive and VOD resilient', () {
    expect(
      streamingPlayerConfiguration.bufferSize,
      PlaybackBufferPolicy.maxMemoryBytes,
    );
    expect(
      PlaybackBufferPolicy.aheadFor(true, mode: PlaybackMode.balanced),
      const Duration(seconds: 30),
    );
    expect(
      PlaybackBufferPolicy.resumeFor(true, mode: PlaybackMode.balanced),
      const Duration(seconds: 3),
    );
    expect(
      PlaybackBufferPolicy.aheadFor(true, mode: PlaybackMode.stable),
      const Duration(seconds: 60),
    );
    expect(
      PlaybackBufferPolicy.resumeFor(true, mode: PlaybackMode.stable),
      const Duration(seconds: 6),
    );
    expect(
      PlaybackBufferPolicy.aheadFor(true, mode: PlaybackMode.lowLatency),
      const Duration(seconds: 12),
    );
    expect(
      PlaybackBufferPolicy.resumeFor(true, mode: PlaybackMode.lowLatency),
      const Duration(seconds: 1),
    );
    expect(PlaybackBufferPolicy.aheadFor(false), const Duration(seconds: 90));
    expect(PlaybackBufferPolicy.resumeFor(false), const Duration(seconds: 15));

    final baseProperties = streamingPropertiesFor(TargetPlatform.android);
    expect(
      baseProperties['demuxer-max-back-bytes'],
      '${PlaybackBufferPolicy.maxBackBufferBytes}',
    );
  });

  test('Android phones keep codec fallback while TVs use a native surface', () {
    final phone = videoConfigurationFor(
      TargetPlatform.android,
      television: false,
    );
    // Null selects media_kit's Android defaults: gpu + auto-safe. This can
    // fall back when an IPTV channel uses a codec the phone cannot decode in
    // hardware instead of leaving audio playing over a black frame.
    expect(phone.vo, isNull);
    expect(phone.hwdec, isNull);
    expect(phone.enableHardwareAcceleration, isTrue);

    final television = videoConfigurationFor(
      TargetPlatform.android,
      television: true,
    );
    expect(television.vo, 'mediacodec_embed');
    expect(television.hwdec, 'mediacodec');
    expect(television.enableHardwareAcceleration, isTrue);
    expect(television.androidAttachSurfaceAfterVideoParameters, isFalse);
  });

  test('Android streaming follows the audio clock to prevent drift', () {
    final properties = streamingPropertiesFor(TargetPlatform.android);
    expect(properties['video-sync'], 'audio');
    expect(properties['autosync'], '30');
    expect(properties['framedrop'], 'vo');
    expect(properties['untimed'], 'no');

    const live = PlayerItem(
      'http://provider.example/live.ts',
      'Live',
      isLive: true,
    );
    const vod = PlayerItem('http://provider.example/movie.mp4', 'Movie');
    final liveProperties = streamingPropertiesForItem(
      TargetPlatform.android,
      live,
      mode: PlaybackMode.balanced,
    );
    final vodProperties = streamingPropertiesForItem(
      TargetPlatform.android,
      vod,
    );
    expect(liveProperties['audio-delay'], '0');
    expect(liveProperties['cache-secs'], '30');
    expect(liveProperties['cache-pause-wait'], '3');
    expect(liveProperties['stream-lavf-o'], contains('reconnect_at_eof=1'));
    expect(vodProperties['cache-secs'], '90');
    expect(vodProperties['cache-pause-wait'], '15');
    expect(vodProperties['stream-lavf-o'], contains('reconnect_at_eof=0'));
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
