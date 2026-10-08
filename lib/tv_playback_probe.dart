import 'package:flutter/services.dart';

/// Only the separately packaged reviewer build exposes this manual report.
const tvPlaybackProbeEnabled = bool.fromEnvironment('LUMEN_TEST_DIAGNOSTICS');

class TvPlaybackProbe {
  TvPlaybackProbe._();

  static const _channel = MethodChannel('lumen/tv_playback_probe');
  static const _eventNames = <String>{
    'opened',
    'state',
    'player_error',
    'tracks',
    'first_frame',
    'first_frame_timeout',
    'startup_timeout',
    'live_stall',
    'prepare',
    'alternate_source',
    'retry',
    'embedded_fallback',
    'terminal_error',
    'closed',
  };

  static Future<Map<String, Object?>?> read() async {
    if (!tvPlaybackProbeEnabled) return null;
    final raw = await _channel.invokeMapMethod<String, Object?>('readReport');
    if (raw == null) return null;
    return sanitize(raw);
  }

  static Map<String, Object?> sanitize(Map<String, Object?> raw) {
    // This explicit allowlist protects against accidental additions to a
    // manually shared trace. Never include media URLs, titles or headers.
    final events =
        (raw['events'] as List?)
            ?.whereType<Map>()
            .where((event) => _eventNames.contains(event['name']))
            .map(
              (event) => <String, Object?>{
                'at_ms': event['at_ms'] is num ? event['at_ms'] : 0,
                'name': _shortName(event['name']),
                'detail': _safeDetail(event['detail']),
                'value': event['value'] is num ? event['value'] : null,
              },
            )
            .take(80)
            .toList() ??
        <Map<String, Object?>>[];
    return <String, Object?>{
      'report_id':
          RegExp(r'^[a-f0-9]{8}$').hasMatch((raw['report_id'] ?? '').toString())
          ? raw['report_id']
          : '',
      'live': raw['live'] == true,
      'mode': {'BALANCED', 'STABLE', 'LOW_LATENCY'}.contains(raw['mode'])
          ? raw['mode']
          : 'unknown',
      'events': events,
    };
  }

  static String _shortName(Object? value) {
    final name = value?.toString() ?? '';
    return name.length > 40 ? name.substring(0, 40) : name;
  }

  static String? _safeDetail(Object? value) {
    final detail = value?.toString() ?? '';
    // Refuse anything outside the fixed state/source/error/track vocabulary.
    return RegExp(
          r'^(idle|buffering|ready|ended|unknown|primary|alternate|ERROR_CODE_[A-Z0-9_]+|audio=\d+,video=\d+)$',
        ).hasMatch(detail)
        ? detail
        : null;
  }
}
