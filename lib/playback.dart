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

  /// Restrict automatic stall recovery to live streams when enabled.
  final bool liveOnly;

  const ReconnectConfig({
    this.maxAttempts = 2,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 4),
    this.liveOnly = false,
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
  static const vodStallTimeout = Duration(seconds: 35);

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

  static Duration stallTimeout(bool live) =>
      live ? liveStallTimeout : vodStallTimeout;

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

Media mediaForPlayerItem(PlayerItem item, {String? sourceUrl}) => Media(
  (sourceUrl ?? item.url).trim(),
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

enum PlaybackFailureKind {
  invalidAddress,
  authorization,
  notFound,
  timeout,
  secureConnection,
  network,
  decoder,
  stalled,
  unknown,
}

/// A provider-safe failure description. Raw URLs and credentials are never
/// retained or displayed in diagnostics.
class PlaybackFailure {
  const PlaybackFailure({
    required this.kind,
    required this.code,
    required this.message,
    required this.suggestion,
    required this.retryable,
  });

  final PlaybackFailureKind kind;
  final String code;
  final String message;
  final String suggestion;
  final bool retryable;
}

PlaybackFailure classifyPlaybackFailure(
  String raw, {
  bool stalled = false,
  bool live = false,
  bool invalidAddress = false,
}) {
  if (invalidAddress) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.invalidAddress,
      code: 'ADDRESS',
      message: 'This item has no valid stream address.',
      suggestion: 'Refresh the library and try the item again.',
      retryable: false,
    );
  }
  if (stalled) {
    return PlaybackFailure(
      kind: PlaybackFailureKind.stalled,
      code: 'STALL',
      message: live
          ? 'The live stream stopped sending data.'
          : 'The video stopped receiving data.',
      suggestion: live
          ? 'Lumen will reconnect without changing the channel.'
          : 'Lumen will reopen the video and preserve your progress.',
      retryable: true,
    );
  }

  final value = raw.toLowerCase();
  if (value.contains('401') ||
      value.contains('403') ||
      value.contains('unauthorized') ||
      value.contains('forbidden')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.authorization,
      code: 'ACCESS',
      message:
          'The provider rejected this stream. Check the account or device limit.',
      suggestion: 'Confirm the subscription and disconnect another device.',
      retryable: false,
    );
  }
  if (value.contains('404') || value.contains('not found')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.notFound,
      code: 'SOURCE',
      message: 'The provider no longer has this stream at that address.',
      suggestion: 'Try an alternate provider format or refresh the library.',
      retryable: true,
    );
  }
  if (value.contains('timed out') || value.contains('timeout')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.timeout,
      code: 'TIMEOUT',
      message: 'The provider took too long to respond.',
      suggestion: 'Retry once the connection or provider is stable.',
      retryable: true,
    );
  }
  if (value.contains('tls') ||
      value.contains('ssl') ||
      value.contains('certificate')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.secureConnection,
      code: 'TLS',
      message: 'A secure connection to the provider could not be established.',
      suggestion: 'Check the device clock and the provider certificate.',
      retryable: false,
    );
  }
  if (value.contains('decoder') ||
      value.contains('codec') ||
      value.contains('decode')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.decoder,
      code: 'CODEC',
      message: 'This playback engine could not decode the stream format.',
      suggestion: 'Try the alternate source or Android compatibility player.',
      retryable: true,
    );
  }
  if (value.contains('network') ||
      value.contains('resolve') ||
      value.contains('dns') ||
      value.contains('connection refused') ||
      value.contains('connection reset') ||
      value.contains('host unreachable') ||
      value.contains('no route')) {
    return const PlaybackFailure(
      kind: PlaybackFailureKind.network,
      code: 'NETWORK',
      message: 'The provider could not be reached from this device.',
      suggestion: 'Check the network, VPN, DNS, and provider availability.',
      retryable: true,
    );
  }
  return const PlaybackFailure(
    kind: PlaybackFailureKind.unknown,
    code: 'STREAM',
    message: 'The provider did not start this stream.',
    suggestion: 'Try again or use a compatible playback option.',
    retryable: true,
  );
}

/// Safe alternate URLs for Xtream-style paths. Arbitrary M3U addresses are
/// intentionally left untouched; only a recognized /kind/user/pass/id.ext
/// shape is eligible.
List<String> playbackSourceCandidates(PlayerItem item) {
  final original = item.url.trim();
  if (!isPlayableMediaUrl(original)) return [original];
  final uri = Uri.tryParse(original);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return [original];
  }
  final segments = uri.pathSegments.toList();
  if (segments.length < 4) return [original];
  final kind = segments[segments.length - 4].toLowerCase();
  if (!const {'live', 'movie', 'series'}.contains(kind)) return [original];
  if ((kind == 'live') != item.isLive) return [original];

  final tail = RegExp(r'^(\d+)\.([a-zA-Z0-9]+)$').firstMatch(segments.last);
  if (tail == null) return [original];
  final id = tail.group(1)!;
  final currentExtension = tail.group(2)!.toLowerCase();
  final alternatives = kind == 'live'
      ? const ['ts', 'm3u8']
      : const ['mp4', 'mkv'];
  final sources = <String>[original];
  for (final extension in alternatives) {
    if (extension == currentExtension) continue;
    segments[segments.length - 1] = '$id.$extension';
    sources.add(uri.replace(pathSegments: segments).toString());
  }
  return sources;
}

String playbackEndpointLabel(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return 'Local media';
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme.toUpperCase()} · ${uri.host}$port';
}

class PlaybackDiagnosticEvent {
  const PlaybackDiagnosticEvent({
    required this.time,
    required this.label,
    required this.detail,
  });

  final DateTime time;
  final String label;
  final String detail;
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
  Timer? _watchdog; // startup/stall detector (drives bounded recovery)
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
  List<String> _sourceCandidates = const [];
  int _sourceIndex = 0;
  Duration? _resumeAfterRecovery;
  final List<PlaybackDiagnosticEvent> _diagnosticEvents = [];

  // ---- auto-reconnect state ----
  /// Active reconnect configuration (can be overridden by the user).
  ReconnectConfig reconnectConfig = const ReconnectConfig();

  /// Current reconnect attempt number (0 = not reconnecting).
  int reconnectAttempt = 0;

  /// Human-readable reconnect status shown in the UI, e.g. "Reconnecting (2/3)…".
  /// Null when idle.
  String? reconnectStatus;
  String? playbackError;
  PlaybackFailure? failure;

  Timer? _reconnectTimer;

  bool get hasMedia => player != null && items.isNotEmpty;
  PlayerItem get item => items[index];
  bool get isLive => hasMedia && item.isLive;
  bool get hasNext => index < items.length - 1;
  bool get hasPrev => index > 0;
  int get retryLimit =>
      hasMedia ? PlaybackPolicy.retryLimit(isLive, reconnectConfig) : 0;
  bool get retryExhausted => _retryExhausted;
  String get activeSourceUrl => _sourceCandidates.isEmpty
      ? (hasMedia ? item.url : '')
      : _sourceCandidates[_sourceIndex];
  int get sourceNumber => _sourceCandidates.isEmpty ? 0 : _sourceIndex + 1;
  int get sourceCount => _sourceCandidates.length;
  String get endpointLabel => playbackEndpointLabel(activeSourceUrl);
  String get playbackStateLabel {
    if (_retryExhausted) return 'Unavailable';
    if (reconnectStatus != null) {
      return reconnectAttempt > 0 ? 'Recovering' : 'Opening';
    }
    if (player?.state.buffering ?? false) return 'Buffering';
    if (player?.state.playing ?? false) return 'Playing';
    return _wantsPlayback ? 'Waiting' : 'Paused';
  }

  Duration get startupElapsed => _openedAtMs <= 0
      ? Duration.zero
      : Duration(
          milliseconds: DateTime.now().millisecondsSinceEpoch - _openedAtMs,
        );

  Duration get bufferedAhead {
    final state = player?.state;
    if (state == null) return Duration.zero;
    final value = state.buffer - state.position;
    return value.isNegative ? Duration.zero : value;
  }

  double get bufferingPercentage =>
      (player?.state.bufferingPercentage ?? 0).toDouble();
  String get sourceFormat {
    final uri = Uri.tryParse(activeSourceUrl);
    final tail = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : activeSourceUrl;
    final extension = tail.contains('.') ? tail.split('.').last : '';
    return extension.isEmpty ? 'Automatic' : extension.toUpperCase();
  }

  List<PlaybackDiagnosticEvent> get diagnosticEvents =>
      List.unmodifiable(_diagnosticEvents);

  String get diagnosticSummary => [
    'Lumen playback diagnostic',
    'State: $playbackStateLabel',
    'Endpoint: $endpointLabel',
    'Format: $sourceFormat',
    'Source: $sourceNumber/$sourceCount',
    'Recovery: $reconnectAttempt/$retryLimit',
    'Buffered: ${bufferedAhead.inSeconds}s',
    if (failure != null) 'Failure: ${failure!.code}',
  ].join('\n');

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
    failure = null;
    _wantsPlayback = true;
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    _lastStatsTickMs = _openedAtMs;
    _lastPos = Duration.zero;
    _startedCurrent = false;
    _retryExhausted = false;
    _sourceCandidates = playbackSourceCandidates(item);
    _sourceIndex = 0;
    _resumeAfterRecovery = null;
    _diagnosticEvents.clear();
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    final current = item;
    if (!isPlayableMediaUrl(current.url)) {
      _setFailure(
        classifyPlaybackFailure('', invalidAddress: true),
        record: false,
      );
      _recordDiagnostic('Address rejected', failure!.code);
      _finishUnavailable(failure!.message);
      return;
    }
    _recordDiagnostic('Opening', _sourceDetail);
    final token = ++_openToken;
    unawaited(_openMedia(current, token));
    if (item.favRef != null) Library.instance.addRecent(item.favRef!);
    _loadEpg();
  }

  // ---- reconnect logic ----

  Future<void> _openMedia(PlayerItem target, int token) async {
    final source = activeSourceUrl;
    try {
      await _nativeSetup;
      if (token != _openToken || player == null || item != target) return;
      await configurePlayerForItem(player!, target);
      if (token != _openToken || player == null || item != target) return;
      await player!.open(mediaForPlayerItem(target, sourceUrl: source));
    } catch (error) {
      if (token != _openToken || player == null || item != target) return;
      _setFailure(classifyPlaybackFailure('$error'));
      _handleFailedAttempt();
    }
  }

  void _onPlayerError(String error) {
    if (!_wantsPlayback) return;
    _setFailure(classifyPlaybackFailure(error));
    notifyListeners();
    // The watchdog gives libmpv a short grace period before reopening because
    // some HLS segment errors recover without intervention.
  }

  String get _sourceDetail => sourceCount <= 1
      ? endpointLabel
      : '$endpointLabel · source $sourceNumber/$sourceCount';

  void _recordDiagnostic(String label, String detail) {
    _diagnosticEvents.insert(
      0,
      PlaybackDiagnosticEvent(
        time: DateTime.now(),
        label: label,
        detail: detail,
      ),
    );
    if (_diagnosticEvents.length > 10) {
      _diagnosticEvents.removeRange(10, _diagnosticEvents.length);
    }
  }

  void _setFailure(PlaybackFailure next, {bool record = true}) {
    final changed = failure?.code != next.code;
    failure = next;
    playbackError = next.message;
    if (record && changed) {
      _recordDiagnostic('Player report', next.code);
    }
  }

  void _markHealthy(int now) {
    final firstFrame = !_startedCurrent;
    _startedCurrent = true;
    _lastProgressMs = now;
    if (firstFrame) {
      _recordDiagnostic(
        'Playback ready',
        '${Duration(milliseconds: now - _openedAtMs).inSeconds}s · '
            'source $sourceNumber/$sourceCount',
      );
      final resume = _resumeAfterRecovery;
      _resumeAfterRecovery = null;
      if (!isLive && resume != null && resume > const Duration(seconds: 5)) {
        unawaited(player?.seek(resume));
        _recordDiagnostic(
          'Position restored',
          '${resume.inMinutes}m ${resume.inSeconds.remainder(60)}s',
        );
      }
    }
    if (reconnectStatus != null ||
        reconnectAttempt != 0 ||
        playbackError != null) {
      _cancelReconnect();
      playbackError = null;
      failure = null;
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
  /// monitoring already-started streams for sustained stalls.
  void _checkStall() {
    if (player == null || items.isEmpty) return;
    if (!_wantsPlayback) return;
    if (_reconnectTimer != null) return; // a reconnect is already pending
    final s = player!.state;
    final now = DateTime.now().millisecondsSinceEpoch;

    // libmpv can report "playing" before it has presented a frame. Only
    // position advancement marks startup healthy; after that, a non-buffering
    // playing state keeps the stall clock fresh.
    if (_startedCurrent && s.playing && !s.buffering) {
      _lastProgressMs = now;
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
      if (failure == null) {
        _setFailure(classifyPlaybackFailure('timeout'));
      }
      _handleFailedAttempt();
      return;
    }

    if (reconnectConfig.liveOnly && !isLive) return;
    final sinceProgress = Duration(milliseconds: now - _lastProgressMs);
    if (sinceProgress > PlaybackPolicy.stallTimeout(isLive)) {
      _setFailure(classifyPlaybackFailure('', stalled: true, live: isLive));
      _handleFailedAttempt();
    }
  }

  void _handleFailedAttempt() {
    if (!_wantsPlayback || _reconnectTimer != null) return;
    if (failure != null && !failure!.retryable) {
      _finishUnavailable(failure!.message);
      return;
    }
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
    _openToken++;
    reconnectStatus = null;
    playbackError = message;
    _retryExhausted = true;
    _wantsPlayback = false;
    _recordDiagnostic('Recovery stopped', failure?.code ?? 'UNAVAILABLE');
    unawaited(player?.stop());
    notifyListeners();
  }

  void _scheduleReconnect() {
    _rememberRecoveryPosition();
    reconnectAttempt++;
    final delay = PlaybackPolicy.retryDelay(reconnectAttempt, reconnectConfig);
    reconnectStatus = isLive
        ? 'Reconnecting live channel ($reconnectAttempt/$retryLimit)…'
        : 'Trying the stream again…';
    _recordDiagnostic(
      'Recovery scheduled',
      'attempt $reconnectAttempt/$retryLimit',
    );
    notifyListeners();
    _reconnectTimer = Timer(delay, _doReconnect);
  }

  void _doReconnect() {
    _reconnectTimer = null;
    if (player == null || items.isEmpty) return;
    if (_shouldAdvanceSource) {
      _sourceIndex++;
      _recordDiagnostic('Alternate source', _sourceDetail);
    }
    // Give the reopened stream a fresh grace window before the watchdog judges it.
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    _lastPos = Duration.zero;
    _startedCurrent = false;
    failure = null;
    playbackError = null;
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    final current = item;
    final token = ++_openToken;
    notifyListeners();
    unawaited(_openMedia(current, token));
  }

  bool get _shouldAdvanceSource {
    if (_sourceIndex + 1 >= _sourceCandidates.length) return false;
    return switch (failure?.kind) {
      PlaybackFailureKind.notFound ||
      PlaybackFailureKind.decoder ||
      PlaybackFailureKind.unknown => true,
      PlaybackFailureKind.stalled ||
      PlaybackFailureKind.timeout ||
      PlaybackFailureKind.network => reconnectAttempt > 1,
      _ => false,
    };
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _openToken++;
    reconnectAttempt = 0;
    reconnectStatus = null;
  }

  /// Call this from the UI when the user taps "Retry" after all attempts fail.
  void retryNow() {
    _cancelReconnect();
    if (player == null || items.isEmpty) return;
    _rememberRecoveryPosition();
    playbackError = null;
    failure = null;
    _wantsPlayback = true;
    _openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastProgressMs = _openedAtMs;
    _lastPos = Duration.zero;
    _startedCurrent = false;
    _retryExhausted = false;
    if (_sourceCandidates.length > 1) {
      _sourceIndex = (_sourceIndex + 1) % _sourceCandidates.length;
    }
    _recordDiagnostic('Manual retry', _sourceDetail);
    reconnectStatus = isLive ? 'Opening live channel…' : 'Starting playback…';
    if (!isPlayableMediaUrl(item.url)) {
      _setFailure(classifyPlaybackFailure('', invalidAddress: true));
      _finishUnavailable(failure!.message);
      return;
    }
    final current = item;
    final token = ++_openToken;
    unawaited(_openMedia(current, token));
    notifyListeners();
  }

  /// Stops automatic recovery but keeps the selected item available for a
  /// later manual retry.
  void cancelRecovery() {
    if (player == null || items.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _openToken++;
    _wantsPlayback = false;
    reconnectStatus = null;
    failure = const PlaybackFailure(
      kind: PlaybackFailureKind.unknown,
      code: 'PAUSED',
      message: 'Automatic recovery was stopped.',
      suggestion: 'Choose Try again whenever you want to resume this item.',
      retryable: true,
    );
    playbackError = failure!.message;
    _retryExhausted = true;
    _recordDiagnostic('Recovery paused', 'User action');
    unawaited(player?.stop());
    notifyListeners();
  }

  void _rememberRecoveryPosition() {
    if (isLive || player == null) return;
    final position = player!.state.position;
    if (position > const Duration(seconds: 5)) {
      _resumeAfterRecovery = position;
    }
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
    failure = null;
    playbackError = null;
    _openToken++;
    _nativeSetup = null;
    player?.dispose();
    player = null;
    controller = null;
    items = [];
    _sourceCandidates = const [];
    _sourceIndex = 0;
    _resumeAfterRecovery = null;
    _diagnosticEvents.clear();
    index = 0;
    epg = const [];
    minimized = false;
    notifyListeners();
  }
}
