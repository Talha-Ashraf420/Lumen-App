import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'library.dart';
import 'models.dart';
import 'stats.dart';

/// Root navigator key so the floating mini-player overlay (which lives above the
/// Navigator) can push the full player route.
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

/// A playable entry (episode / channel / movie).
class PlayerItem {
  final String url;
  final String title;
  final bool isLive;
  final String? progressKey; // continue-watching key, e.g. 'movie:123' / 'ep:456'
  final String poster; // thumbnail for continue-watching / recents
  final String ext;
  final MediaRef? favRef; // what the heart toggles (movie/series/channel)
  final Future<List<EpgEntry>> Function()? epg; // now/next for live channels (lazy)
  const PlayerItem(this.url, this.title,
      {this.isLive = false, this.progressKey, this.poster = '', this.ext = '', this.favRef, this.epg});
}

/// App-level playback so the video keeps running while you browse. The full
/// PlayerScreen and the floating mini-player are both views over this one
/// Player/VideoController; the controller owns the playlist, EPG, and
/// continue-watching persistence.
class PlaybackController extends ChangeNotifier {
  PlaybackController._();
  static final PlaybackController instance = PlaybackController._();

  Player? player;
  VideoController? controller;
  List<PlayerItem> items = [];
  int index = 0;
  bool minimized = false;
  List<EpgEntry> epg = const [];

  bool _resumed = false;
  int _lastSave = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _completedSub;
  Timer? _statsTimer;

  bool get hasMedia => player != null && items.isNotEmpty;
  PlayerItem get item => items[index];
  bool get isLive => hasMedia && item.isLive;
  bool get hasNext => index < items.length - 1;
  bool get hasPrev => index > 0;

  void open(List<PlayerItem> newItems, int i) {
    if (newItems.isEmpty) return;
    if (player == null) {
      player = Player();
      controller = VideoController(player!);
      _posSub = player!.stream.position.listen(_onPosition);
      _completedSub = player!.stream.completed.listen((done) {
        if (done && !isLive && hasNext) go(index + 1);
      });
      _statsTimer = Timer.periodic(const Duration(seconds: 15), (_) => _tickStats());
    }
    items = newItems;
    index = i.clamp(0, newItems.length - 1);
    minimized = false;
    _openCurrent();
    notifyListeners();
  }

  void go(int i) {
    if (i < 0 || i >= items.length) return;
    index = i;
    _openCurrent();
    notifyListeners();
  }

  void _openCurrent() {
    _resumed = false;
    epg = const [];
    player!.open(Media(item.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));
    if (item.favRef != null) Library.instance.addRecent(item.favRef!);
    _loadEpg();
  }

  void _loadEpg() {
    final fetch = item.epg;
    if (fetch == null) return;
    final forItem = item;
    fetch().then((list) {
      if (player != null && items.isNotEmpty && item == forItem) {
        epg = list;
        notifyListeners();
      }
    }).catchError((_) {});
  }

  EpgEntry? get epgNow {
    for (final e in epg) {
      if (e.isNow) return e;
    }
    return epg.isNotEmpty ? epg.first : null;
  }

  EpgEntry? get epgNext {
    final now = epgNow;
    if (now == null) return null;
    final i = epg.indexOf(now);
    return (i >= 0 && i + 1 < epg.length) ? epg[i + 1] : null;
  }

  void _onPosition(Duration pos) {
    if (player == null || isLive || item.progressKey == null) return;
    final dur = player!.state.duration;
    if (dur.inSeconds <= 0) return;
    if (!_resumed) {
      _resumed = true;
      final saved = Library.instance.progress[item.progressKey];
      if (saved != null && saved.position > 10 && saved.position < dur.inSeconds * 0.95) {
        player!.seek(Duration(seconds: saved.position));
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSave > 5000) {
      _lastSave = now;
      persistProgress();
    }
  }

  void _tickStats() {
    if (player == null || items.isEmpty || !(player!.state.playing)) return;
    final kind = isLive ? 'live' : ((item.progressKey?.startsWith('ep:') ?? false) ? 'series' : 'movie');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${now.year}-${two(now.month)}-${two(now.day)}';
    WatchStats.instance.add(
      seconds: 15,
      kind: kind,
      cat: item.favRef?.cat ?? '',
      titleKey: item.favRef?.key ?? item.progressKey ?? '',
      day: day,
    );
  }

  void persistProgress() {
    if (player == null || isLive || item.progressKey == null) return;
    final dur = player!.state.duration, pos = player!.state.position;
    if (dur.inSeconds <= 0) return;
    Library.instance.saveProgress(Progress(
      key: item.progressKey!,
      title: item.title,
      poster: item.poster,
      url: item.url,
      ext: item.ext,
      position: pos.inSeconds,
      duration: dur.inSeconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void minimize() {
    if (!hasMedia) return;
    minimized = true;
    notifyListeners();
  }

  void expand() {
    minimized = false;
    notifyListeners();
  }

  void stop() {
    persistProgress();
    _posSub?.cancel();
    _posSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    player?.dispose();
    player = null;
    controller = null;
    items = [];
    index = 0;
    epg = const [];
    minimized = false;
    notifyListeners();
  }
}
