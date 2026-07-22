import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'library.dart';
import 'models.dart';
import 'stats.dart';

/// Reconnect configuration — tweak via [PlaybackController.reconnectConfig].
class ReconnectConfig {
  /// Maximum number of automatic retry attempts before giving up.
  final int maxAttempts;

  /// Base delay before the first retry. Each subsequent attempt doubles this
  /// (exponential back-off), capped at [maxDelay].
  final Duration baseDelay;

  /// Upper bound for the back-off delay.
  final Duration maxDelay;

  /// Only auto-reconnect live streams (VOD errors are usually fatal).
  final bool liveOnly;

  const ReconnectConfig({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 16),
    this.liveOnly = true,
  });
}

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
  final Map<String, String> httpHeaders;
  final MediaRef? favRef; // what the heart toggles (movie/series/channel)
  final Future<List<EpgEntry>> Function()? epg; // now/next for live channels (lazy)
  const PlayerItem(this.url, this.title,
      {this.isLive = false, this.progressKey, this.poster = '', this.ext = '',
       this.httpHeaders = const {}, this.favRef, this.epg});
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
  // Whether to auto-play the next item when this one finishes (user can cancel
  // from the "Up next" card to watch the credits). Reset per item.
  bool autoAdvance = true;

  bool _resumed = false;
  int _lastSave = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  Timer? _statsTimer;
  Timer? _watchdog; // live stall detector (drives auto-reconnect)
  Duration _lastPos = Duration.zero;
  int _lastProgressMs =
      0; // last time playback was healthy (advancing / not buffering)
  int _openedAtMs = 0;
  int _lastStatsTickMs = 0;
  bool _wantsPlayback = false;

  // ---- auto-reconnect state ----
  /// Active reconnect configuration (can be overridden by the user).
  ReconnectConfig reconnectConfig = const ReconnectConfig();

  /// Current reconnect attempt number (0 = not reconnecting).
  int reconnectAttempt = 0;

  /// Human-readable reconnect status shown in the UI, e.g. "Reconnecting (2/3)…".
  /// Null when idle.
  String? reconnectStatus;
  String? playbackError;

  Timer? _reconnectTimer;

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
        if (done && !isLive && hasNext && autoAdvance) go(index + 1);
      });
      _errorSub = player!.stream.error.listen(_onPlayerError);
      _statsTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _tickStats(),
      );
      // Reconnect is driven by a stall watchdog (below), NOT by libmpv error
      // events — those fire spuriously during normal startup/buffering and were
      // both slowing loads (reopening mid-load) and failing real drops.
      _watchdog = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkStall(),
      );
    }
    items = newItems;
    index = i.clamp(0, newItems.length - 1);
    minimized = false;
    _openCurrent();
    notifyListeners();
  }

  void go(int i) {
    if (i < 0 || i >= items.length) return;
    _cancelReconnect();
    index = i;
    _openCurrent();
    notifyListeners();
  }

  void cancelAutoAdvance() {
    autoAdvance = false;
    notifyListeners();
  }

  void _openCurrent() {
    _resumed = false;
    autoAdvance = true;
    epg = const [];
    _cancelReconnect();
    playbackError = null;
    _wantsPlayback = true;
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    _lastStatsTickMs = _openedAtMs;
    _lastPos = Duration.zero;
    player!.open(_mediaForCurrent());
    if (item.favRef != null) Library.instance.addRecent(item.favRef!);
    _loadEpg();
  }

  // ---- reconnect logic ----

  Media _mediaForCurrent() => Media(
    item.url,
    httpHeaders: {
      'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
      ...item.httpHeaders,
    },
  );

  void _onPlayerError(String error) {
    if (!_wantsPlayback || !isLive) return;
    playbackError = error.trim().isEmpty
        ? 'The stream stopped unexpectedly.'
        : error.trim();
    // The watchdog decides whether to reopen. libmpv may report recoverable
    // segment errors, so reacting immediately here causes reconnect loops.
  }

  /// Runs every few seconds. A live stream that is *playing* (not user-paused)
  /// but has been *buffering with no progress* for a sustained period is a real
  /// connection drop → schedule a reconnect. Anything healthy resets the clock,
  /// so this never fires during normal startup or short re-buffers.
  void _checkStall() {
    if (player == null || items.isEmpty) return;
    if (reconnectConfig.liveOnly && !isLive) return;
    if (!_wantsPlayback) return;
    if (_reconnectTimer != null) return; // a reconnect is already pending
    final s = player!.state;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Give initial loads and retries enough time for DNS, manifests and a
    // first buffer before judging them as stalled.
    if (now - _openedAtMs < 15000) return;
    if (s.playing && !s.buffering) {
      _lastProgressMs = now;
      if (reconnectStatus != null || reconnectAttempt != 0) {
        _cancelReconnect();
        playbackError = null;
        notifyListeners();
      }
      return;
    }
    if (now - _lastProgressMs <= 12000) return;
    if (reconnectAttempt >= reconnectConfig.maxAttempts) {
      if (reconnectStatus != null) {
        reconnectStatus = null;
        playbackError ??=
            'Stream unavailable after ${reconnectConfig.maxAttempts} retries.';
        notifyListeners();
      }
      return;
    }
    // Both prolonged buffering and an unexpected playing=false state are
    // treated as drops. User pauses are excluded by _wantsPlayback.
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    reconnectAttempt++;
    // Exponential back-off: 2s, 4s, 8s … capped at maxDelay.
    final rawMs = reconnectConfig.baseDelay.inMilliseconds * (1 << (reconnectAttempt - 1));
    final delay = Duration(milliseconds: rawMs.clamp(0, reconnectConfig.maxDelay.inMilliseconds));
    reconnectStatus = 'Reconnecting (${reconnectAttempt}/${reconnectConfig.maxAttempts})…';
    notifyListeners();
    _reconnectTimer = Timer(delay, _doReconnect);
  }

  void _doReconnect() {
    _reconnectTimer = null;
    if (player == null || items.isEmpty) return;
    // Give the reopened stream a fresh grace window before the watchdog judges it.
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    _lastPos = Duration.zero;
    player!.open(_mediaForCurrent());
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectAttempt = 0;
    reconnectStatus = null;
  }

  /// Call this from the UI when the user taps "Retry" after all attempts fail.
  void retryNow() {
    _cancelReconnect();
    if (player == null || items.isEmpty) return;
    playbackError = null;
    _wantsPlayback = true;
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    player!.open(_mediaForCurrent());
    notifyListeners();
  }

  void play() {
    if (player == null) return;
    _wantsPlayback = true;
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    player!.play();
  }

  void pause() {
    _wantsPlayback = false;
    _cancelReconnect();
    player?.pause();
    notifyListeners();
  }

  void togglePlayPause() {
    if (player?.state.playing ?? false) {
      pause();
    } else {
      play();
    }
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
    if (player == null) return;
    // Watchdog health signal for ALL stream types: playback advanced → healthy,
    // so refresh the clock and clear any in-progress reconnect (recovery).
    if (pos > _lastPos) {
      _lastPos = pos;
      _lastProgressMs = DateTime.now().millisecondsSinceEpoch;
      if (reconnectStatus != null || reconnectAttempt != 0) {
        _cancelReconnect();
        playbackError = null;
        notifyListeners();
      }
    }
    if (isLive || item.progressKey == null) return;
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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsed = ((nowMs - _lastStatsTickMs) ~/ 1000).clamp(0, 15);
    _lastStatsTickMs = nowMs;
    if (player == null ||
        items.isEmpty ||
        !player!.state.playing ||
        player!.state.buffering ||
        elapsed == 0) {
      return;
    }
    final kind = isLive
        ? 'live'
        : ((item.progressKey?.startsWith('ep:') ?? false) ? 'series' : 'movie');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${now.year}-${two(now.month)}-${two(now.day)}';
    WatchStats.instance.add(
      seconds: elapsed,
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
    _cancelReconnect();
    _posSub?.cancel();
    _posSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _errorSub?.cancel();
    _errorSub = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    _wantsPlayback = false;
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
