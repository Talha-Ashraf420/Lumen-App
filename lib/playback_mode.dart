import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-facing live playback trade-offs.
///
/// These modes only tune network/live buffering. Movies, episodes and local
/// files retain their resilient on-demand policy.
enum PlaybackMode {
  balanced,
  stable,
  lowLatency;

  String get label => switch (this) {
    PlaybackMode.balanced => 'Balanced',
    PlaybackMode.stable => 'Stable',
    PlaybackMode.lowLatency => 'Low latency',
  };

  String get description => switch (this) {
    PlaybackMode.balanced => 'Recommended for most channels and connections',
    PlaybackMode.stable => 'Builds a larger cushion for uneven providers',
    PlaybackMode.lowLatency => 'Starts fastest and stays closer to live',
  };
}

/// Persists the selected mode once for the whole installation so native
/// Android TV playback and the embedded mpv player use the same policy.
class PlaybackModeController {
  PlaybackModeController._();

  static final PlaybackModeController instance = PlaybackModeController._();
  static const _key = 'lumen_playback_mode';

  final ValueNotifier<PlaybackMode> mode = ValueNotifier(PlaybackMode.balanced);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_key);
    mode.value = PlaybackMode.values.firstWhere(
      (candidate) => candidate.name == stored,
      orElse: () => PlaybackMode.balanced,
    );
  }

  Future<void> set(PlaybackMode next) async {
    if (mode.value != next) mode.value = next;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, next.name);
  }
}
