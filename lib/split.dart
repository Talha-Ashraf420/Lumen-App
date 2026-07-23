import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'playback.dart';

/// A second, independent libmpv player used for split-screen ("watch two at
/// once"). It's always the *secondary* stream: muted, no persistence. The main
/// audio + controls stay with [PlaybackController]. media_kit supports multiple
/// Player instances — the single-surface rule only forbids two Video widgets on
/// ONE controller, which we never do.
class SplitController extends ChangeNotifier {
  SplitController._();
  static final SplitController instance = SplitController._();

  Player? player;
  VideoController? controller;
  PlayerItem? item;
  Future<void>? _nativeSetup;

  bool get active => player != null && controller != null && item != null;

  Future<void> open(PlayerItem it) async {
    if (!isPlayableMediaUrl(it.url)) {
      throw StateError('The selected item has no valid stream address.');
    }
    if (player == null) {
      player = Player(configuration: streamingPlayerConfiguration);
      controller = VideoController(player!);
      _nativeSetup = configureStreamingPlayer(player!).catchError((_) {});
    }
    item = it;
    await _nativeSetup;
    await player!.open(mediaForPlayerItem(it));
    await player!.setVolume(0); // secondary is muted
    notifyListeners();
  }

  Future<void> close() async {
    final p = player;
    player = null;
    controller = null;
    item = null;
    _nativeSetup = null;
    notifyListeners();
    await p?.dispose();
  }
}
