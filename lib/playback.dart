import 'dart:async';
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
    this.maxAttempts = 2,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 4),
    this.liveOnly = true,
  });
}

/// Startup and recovery limits shared by movies, episodes, and live streams.
/// VOD gets one automatic clean retry; live streams get the configured retry
/// count because short provider-side disconnects are common.
class PlaybackPolicy {
  // Initial buffering is intentionally enabled, so the watchdog must leave
  // enough room for provider redirects, manifests, codec probing and prefetch.
  static const vodStartupTimeout = Duration(seconds: 45);
  static const liveStartupTimeout = Duration(seconds: 35);
  static const progressingStartupTimeout = Duration(seconds: 75);
  static const playerErrorGrace = Duration(seconds: 8);
  static const liveStallTimeout = Duration(seconds: 15);

  static Duration startupTimeout(bool live, {bool hasBufferedData = false}) =>
      hasBufferedData
      ? progressingStartupTimeout
      : (live ? liveStartupTimeout : vodStartupTimeout);

  static int retryLimit(bool live, ReconnectConfig config) =>
      live ? config.maxAttempts.clamp(0, 5) : 1;

  static Duration retryDelay(int attempt, ReconnectConfig config) {
    final safeAttempt = attempt.clamp(1, 8);
    final rawMs = config.baseDelay.inMilliseconds * (1 << (safeAttempt - 1));
    return Duration(
      milliseconds: rawMs.clamp(0, config.maxDelay.inMilliseconds),
    );
  }

  /// Startup/recovery owns the centre of the player. mpv reports "playing"
  /// optimistically while opening, so its transport must not cover that state.
  static bool showCenterTransport({
    required String? reconnectStatus,
    required bool retryExhausted,
  }) => reconnectStatus == null && !retryExhausted;
}

/// Memory-buffer targets for network playback.
///
/// Live streams keep a smaller window to avoid drifting too far behind the
/// broadcast. Movies and episodes trade a little startup time for a deeper
/// buffer that can absorb normal provider and Wi-Fi jitter.
class PlaybackBufferPolicy {
  static const maxMemoryBytes = 64 * 1024 * 1024;
  static const liveAhead = Duration(seconds: 12);
  static const vodAhead = Duration(seconds: 30);
  static const liveResume = Duration(seconds: 3);
  static const vodResume = Duration(seconds: 5);

  static Duration aheadFor(bool live) => live ? liveAhead : vodAhead;
  static Duration resumeFor(bool live) => live ? liveResume : vodResume;
}

const streamingPlayerConfiguration = PlayerConfiguration(
  bufferSize: PlaybackBufferPolicy.maxMemoryBytes,
  protocolWhitelist: [
    'udp',
    'rtp',
    'tcp',
    'tls',
    'data',
    'file',
    'http',
    'https',
    'crypto',
    'rtsp',
    'rtmp',
    'rtmps',
    'mms',
    'mmsh',
    'mmst',
  ],
);

bool isPlayableMediaUrl(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return false;
  if (raw.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw)) {
    return true;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return false;
  return const {
    'asset',
    'file',
    'http',
    'https',
    'rtp',
    'rtsp',
    'rtmp',
    'rtmps',
    'udp',
    'mms',
    'mmsh',
    'mmst',
  }.contains(uri.scheme.toLowerCase());
}

Media mediaForPlayerItem(PlayerItem item) => Media(
  item.url.trim(),
  httpHeaders: {
    'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
    'Accept': '*/*',
    ...item.httpHeaders,
  },
);

/// Keep network packets in memory so slow flash storage on phones and TVs does
/// not become part of the playback path.
Future<void> configureStreamingPlayer(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  await platform.setProperty('cache', 'yes');
  await platform.setProperty('cache-on-disk', 'no');
  await platform.setProperty('cache-pause', 'yes');
  await platform.setProperty('demuxer-hysteresis-secs', '0');
  await platform.setProperty('network-timeout', '15');
}

Future<void> configurePlayerForItem(Player player, PlayerItem item) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  final ahead = PlaybackBufferPolicy.aheadFor(item.isLive).inSeconds;
  final resume = PlaybackBufferPolicy.resumeFor(item.isLive).inSeconds;

  // Starting with a real cushion prevents the common start → stall → resume
  // cycle. The same refill threshold is used after an underrun.
  await platform.setProperty('cache-pause-initial', 'yes');
  await platform.setProperty('cache-secs', '$ahead');
  await platform.setProperty('demuxer-readahead-secs', '$ahead');
  await platform.setProperty('cache-pause-wait', '$resume');
}

/// Root navigator key so the floating mini-player overlay (which lives above the
/// Navigator) can push the full player route.
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

/// A playable entry (episode / channel / movie).
class PlayerItem {
  final String url;
  final String title;
  final bool isLive;
  final String?
  progressKey; // continue-watching key, e.g. 'movie:123' / 'ep:456'
  final String poster; // thumbnail for continue-watching / recents
  final String ext;
  final Map<String, String> httpHeaders;
  final MediaRef? favRef; // what the heart toggles (movie/series/channel)
  final Future<List<EpgEntry>> Function()?
  epg; // now/next for live channels (lazy)
  const PlayerItem(
    this.url,
    this.title, {
    this.isLive = false,
    this.progressKey,
    this.poster = '',
    this.ext = '',
    this.httpHeaders = const {},
    this.favRef,
    this.epg,
  });
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
  bool _startedCurrent = false;
  bool _retryExhausted = false;
  int _openToken = 0;
  Future<void>? _nativeSetup;

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
  int get retryLimit =>
      hasMedia ? PlaybackPolicy.retryLimit(isLive, reconnectConfig) : 0;
  bool get retryExhausted => _retryExhausted;

  /// Starts native decoder/video initialization without opening media. Called
  /// after the app's first frame so the first Play tap does not pay this cost.
  void prewarm() => _ensurePlayer();

  void _ensurePlayer() {
    if (player != null) return;
    player = Player(configuration: streamingPlayerConfiguration);
    controller = VideoController(player!);
    _nativeSetup = configureStreamingPlayer(player!).catchError((_) {});
    _posSub = player!.stream.position.listen(_onPosition);
    _completedSub = player!.stream.completed.listen((done) {
      if (done && !isLive && hasNext && autoAdvance) go(index + 1);
    });
    _errorSub = player!.stream.error.listen(_onPlayerError);
    _statsTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _tickStats(),
    );
    // Reconnect is driven by a stall watchdog (below), NOT directly by libmpv
    // error events, some of which are recoverable HLS segment failures.
    _watchdog = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkStall(),
    );
  }

  void open(List<PlayerItem> newItems, int i) {
    if (newItems.isEmpty) return;
    _ensurePlayer();
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
    _startedCurrent = false;
    _retryExhausted = false;
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    final current = item;
    if (!isPlayableMediaUrl(current.url)) {
      _finishUnavailable(
        'This item has no valid stream address. Refresh the library and try again.',
      );
      return;
    }
    final token = ++_openToken;
    unawaited(_openMedia(current, token));
    if (item.favRef != null) Library.instance.addRecent(item.favRef!);
    _loadEpg();
  }

  // ---- reconnect logic ----

  Future<void> _openMedia(PlayerItem target, int token) async {
    try {
      await _nativeSetup;
      if (token != _openToken || player == null || item != target) return;
      await configurePlayerForItem(player!, target);
      if (token != _openToken || player == null || item != target) return;
      await player!.open(mediaForPlayerItem(target));
    } catch (error) {
      if (token != _openToken || player == null || item != target) return;
      playbackError = _friendlyPlayerError('$error');
      _handleFailedAttempt();
    }
  }

  void _onPlayerError(String error) {
    if (!_wantsPlayback) return;
    playbackError = _friendlyPlayerError(error);
    notifyListeners();
    // The watchdog gives libmpv a short grace period before reopening because
    // some HLS segment errors recover without intervention.
  }

  String _friendlyPlayerError(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('401') || value.contains('403')) {
      return 'The provider rejected this stream. Check the account or device limit.';
    }
    if (value.contains('404')) {
      return 'The provider no longer has this stream.';
    }
    if (value.contains('timed out') || value.contains('timeout')) {
      return 'The provider took too long to respond.';
    }
    if (value.contains('tls') ||
        value.contains('ssl') ||
        value.contains('certificate')) {
      return 'A secure connection to the provider could not be established.';
    }
    if (value.contains('decoder') || value.contains('codec')) {
      return 'This device cannot decode the stream format.';
    }
    return 'The provider did not start this stream.';
  }

  void _markHealthy(int now) {
    _startedCurrent = true;
    _lastProgressMs = now;
    if (reconnectStatus != null ||
        reconnectAttempt != 0 ||
        playbackError != null) {
      _cancelReconnect();
      playbackError = null;
      _retryExhausted = false;
      notifyListeners();
    }
  }

  void _updateStartupStatus(Duration elapsed, bool buffering) {
    if (!buffering || reconnectAttempt > 0) return;
    final next = elapsed >= const Duration(seconds: 25)
        ? 'Provider is responding slowly…'
        : elapsed >= const Duration(seconds: 8)
        ? (isLive
              ? 'Building a stable live buffer…'
              : 'Building a stable video buffer…')
        : null;
    if (next != null && reconnectStatus != next) {
      reconnectStatus = next;
      notifyListeners();
    }
  }

  /// Enforces a bounded first-frame deadline for every media type, then keeps
  /// monitoring already-started live streams for sustained stalls.
  void _checkStall() {
    if (player == null || items.isEmpty) return;
    if (!_wantsPlayback) return;
    if (_reconnectTimer != null) return; // a reconnect is already pending
    final s = player!.state;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (s.playing && !s.buffering) {
      _markHealthy(now);
      return;
    }

    final sinceOpen = Duration(milliseconds: now - _openedAtMs);
    if (!_startedCurrent) {
      final hasBufferedData =
          s.buffer > s.position || s.bufferingPercentage > 0;
      _updateStartupStatus(sinceOpen, s.buffering || hasBufferedData);
      final errorReady =
          playbackError != null &&
          !s.buffering &&
          !hasBufferedData &&
          sinceOpen >= PlaybackPolicy.playerErrorGrace;
      final deadline = PlaybackPolicy.startupTimeout(
        isLive,
        hasBufferedData: hasBufferedData,
      );
      if (!errorReady && sinceOpen < deadline) {
        return;
      }
      playbackError ??= isLive
          ? 'The provider took too long to start this channel.'
          : 'The provider took too long to start this video.';
      _handleFailedAttempt();
      return;
    }

    if (reconnectConfig.liveOnly && !isLive) return;
    final sinceProgress = Duration(milliseconds: now - _lastProgressMs);
    if (sinceProgress > PlaybackPolicy.liveStallTimeout) {
      playbackError ??= 'The live stream stopped sending data.';
      _handleFailedAttempt();
    }
  }

  void _handleFailedAttempt() {
    if (!_wantsPlayback || _reconnectTimer != null) return;
    if (reconnectAttempt >= retryLimit) {
      _finishUnavailable(
        playbackError ?? 'The stream is currently unavailable.',
      );
      return;
    }
    _scheduleReconnect();
  }

  void _finishUnavailable(String message) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectStatus = null;
    playbackError = message;
    _retryExhausted = true;
    _wantsPlayback = false;
    notifyListeners();
  }

  void _scheduleReconnect() {
    reconnectAttempt++;
    final delay = PlaybackPolicy.retryDelay(reconnectAttempt, reconnectConfig);
    reconnectStatus = isLive
        ? 'Reconnecting live channel ($reconnectAttempt/$retryLimit)…'
        : 'Trying the stream again…';
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
    _startedCurrent = false;
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    final current = item;
    final token = ++_openToken;
    notifyListeners();
    unawaited(_openMedia(current, token));
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
    _lastPos = Duration.zero;
    _startedCurrent = false;
    _retryExhausted = false;
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    if (!isPlayableMediaUrl(item.url)) {
      _finishUnavailable(
        'This item has no valid stream address. Refresh the library and try again.',
      );
      return;
    }
    final current = item;
    final token = ++_openToken;
    unawaited(_openMedia(current, token));
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
    fetch()
        .then((list) {
          if (player != null && items.isNotEmpty && item == forItem) {
            epg = list;
            notifyListeners();
          }
        })
        .catchError((_) {});
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
      _markHealthy(DateTime.now().millisecondsSinceEpoch);
    }
    if (isLive || item.progressKey == null) return;
    final dur = player!.state.duration;
    if (dur.inSeconds <= 0) return;
    if (!_resumed) {
      _resumed = true;
      final saved = Library.instance.progress[item.progressKey];
      if (saved != null &&
          saved.position > 10 &&
          saved.position < dur.inSeconds * 0.95) {
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
    Library.instance.saveProgress(
      Progress(
        key: item.progressKey!,
        title: item.title,
        poster: item.poster,
        url: item.url,
        ext: item.ext,
        position: pos.inSeconds,
        duration: dur.inSeconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
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
    _startedCurrent = false;
    _retryExhausted = false;
    _openToken++;
    _nativeSetup = null;
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
