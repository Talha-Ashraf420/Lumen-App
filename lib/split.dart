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

  bool get active => player != null && controller != null && item != null;

  Future<void> open(PlayerItem it) async {
    player ??= Player();
    controller ??= VideoController(player!);
    item = it;
    await player!.open(Media(it.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));
    await player!.setVolume(0); // secondary is muted
    notifyListeners();
  }

  Future<void> close() async {
    final p = player;
    player = null;
    controller = null;
    item = null;
    notifyListeners();
    await p?.dispose();
  }
}
