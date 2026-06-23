import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:window_manager/window_manager.dart';
import '../library.dart';
import '../pip.dart';
import '../playback.dart';
import '../theme.dart';

/// The one and only player view — a persistent app-level overlay. A single
/// [Video] (never recreated) animates between full-screen and a docked mini, so
/// playback is continuous and there's never a second video surface (which races
/// / crashes libmpv on desktop).
class PlayerHost extends StatefulWidget {
  const PlayerHost({super.key});
  @override
  State<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends State<PlayerHost> {
  final pc = PlaybackController.instance;
  final FocusNode _focus = FocusNode();

  bool _controls = true;
  bool _fullscreen = false;
  bool _muted = false;
  Timer? _hideTimer;
  BoxFit _fit = BoxFit.contain;
  double _rate = 1.0;
  double _zoomScale = 1.0, _zoomStart = 1.0;
  bool _hadMedia = false;

  // gesture state
  String? _gMode;
  double _curVol = 100, _curBri = 0.5, _gAccum = 0;
  Duration _gStartPos = Duration.zero, _gSeekTarget = Duration.zero;
  double _doubleTapX = 0;

  // HUD
  String? _hud;
  IconData? _hudIcon;
  double? _hudValue;
  Timer? _hudTimer;

  // sleep
  Timer? _sleepTimer;
  int _sleepMin = 0;

  // in-player panel ('subs' | 'settings' | null) — used instead of bottom
  // sheets since the player isn't inside a Navigator.
  String? _panelKind;

  // subtitle appearance + sync
  double _subScale = 1.0;
  bool _subBg = false;
  double _subDelay = 0;

  // hold-to-speed
  double _savedRate = 1.0;
  bool _holding = false;

  // mini position
  Offset? _miniPos;

  static final bool _isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  static final bool _isAndroid = !kIsWeb && Platform.isAndroid;

  PlayerItem get _item => pc.item;
  bool get _isLive => pc.isLive;
  bool get _hasNext => pc.hasNext;
  bool get _hasPrev => pc.hasPrev;

  @override
  void initState() {
    super.initState();
    pc.addListener(_onPc);
    Pip.instance.init();
    Pip.instance.active.addListener(_onPip);
    ScreenBrightness.instance.current.then((b) => _curBri = b).catchError((_) => _curBri = 0.5);
  }

  @override
  void dispose() {
    pc.removeListener(_onPc);
    Pip.instance.active.removeListener(_onPip);
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _sleepTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onPip() {
    if (mounted) setState(() {});
  }

  void _onPc() {
    final has = pc.hasMedia;
    // Only allow the OS to enter PiP when a video is actually loaded.
    Pip.instance.setAllowed(has);
    if (has && !_hadMedia) {
      // fresh playback
      _controls = true;
      _zoomScale = 1.0;
      _fit = BoxFit.contain;
      _rate = 1.0;
      _panelKind = null;
      _scheduleHide();
    } else if (!has && _hadMedia) {
      _exitFullscreen();
    }
    _hadMedia = has;
    if (mounted) setState(() {});
  }

  void _exitFullscreen() {
    if (_isDesktop) {
      if (_fullscreen) windowManager.setFullScreen(false);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _fullscreen = false;
  }

  void _minimize() {
    if (_isDesktop && _fullscreen) windowManager.setFullScreen(false);
    _fullscreen = false;
    _panelKind = null;
    pc.minimize();
  }

  void _close() {
    _exitFullscreen();
    pc.stop();
  }

  void _expand() {
    pc.expand();
    _controls = true;
    _scheduleHide();
    _focus.requestFocus();
  }

  void _go(int i) {
    pc.go(i);
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !pc.minimized && (pc.player?.state.playing ?? false)) setState(() => _controls = false);
    });
  }

  void _tap() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _seekBy(int secs) {
    final p = pc.player!.state.position + Duration(seconds: secs);
    pc.player!.seek(p < Duration.zero ? Duration.zero : p);
    _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    if (_isDesktop) {
      await windowManager.setFullScreen(_fullscreen);
    } else if (_fullscreen) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
  }

  void _toggleMute() {
    _muted = !_muted;
    pc.player!.setVolume(_muted ? 0 : 100);
    setState(() {});
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    if (!pc.hasMedia || pc.controller == null) {
      return const IgnorePointer(child: SizedBox.expand());
    }
    // In PiP the OS shows the whole activity shrunk — force the video full-bleed
    // and drop all chrome so only the picture is visible.
    final pip = Pip.instance.active.value;
    final mini = pc.minimized && !pip;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, con) {
          final w = con.maxWidth, h = con.maxHeight;
          final wide = w >= 900;
          final mw = wide ? 340.0 : 200.0, mh = (wide ? 340.0 : 200.0) * 9 / 16;
          final margin = wide ? 24.0 : 12.0, bottomGap = wide ? 24.0 : 108.0;
          _miniPos ??= Offset(w - mw - margin, h - mh - bottomGap);
          final mx = _miniPos!.dx.clamp(8.0, (w - mw - 8).clamp(8.0, w));
          final my = _miniPos!.dy.clamp(8.0, (h - mh - 8).clamp(8.0, h));

          return Stack(
            children: [
              if (!mini) const Positioned.fill(child: ColoredBox(color: Colors.black)),
              // The single persistent video — only its rect/shape animate.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: mini ? mx : 0,
                top: mini ? my : 0,
                width: mini ? mw : w,
                height: mini ? mh : h,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(mini ? 14 : 0),
                    border: mini ? Border.all(color: Colors.white24) : null,
                    boxShadow: mini ? const [BoxShadow(color: Colors.black54, blurRadius: 22, offset: Offset(0, 10))] : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Transform.scale(
                    scale: mini ? 1.0 : _zoomScale,
                    child: Video(
                      controller: pc.controller!,
                      controls: NoVideoControls,
                      fit: mini ? BoxFit.cover : _fit,
                      subtitleViewConfiguration: SubtitleViewConfiguration(
                        visible: !mini,
                        style: TextStyle(
                          height: 1.4,
                          fontSize: 32.0 * _subScale,
                          color: Colors.white,
                          backgroundColor: _subBg ? Colors.black54 : Colors.transparent,
                          fontWeight: FontWeight.w600,
                          shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      ),
                    ),
                  ),
                ),
              ),
              if (mini) _miniLayer(mx, my, mw, mh) else if (!pip) _fullLayer(),
            ],
          );
        },
      ),
    );
  }

  // Desktop: any mouse movement reveals the controls, and the cursor is hidden
  // while they're hidden during playback (like a native video player).
  void _onHover(PointerHoverEvent e) {
    if (!_isDesktop) return;
    if (!_controls && mounted) setState(() => _controls = true);
    _scheduleHide();
  }

  Widget _fullLayer() {
    return Positioned.fill(
      child: MouseRegion(
        opaque: false,
        cursor: (_isDesktop && !_controls) ? SystemMouseCursors.none : MouseCursor.defer,
        onHover: _onHover,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
        onDoubleTapDown: (d) => _doubleTapX = d.localPosition.dx,
        onDoubleTap: _onDoubleTap,
        onLongPressStart: _isLive ? null : (_) => _holdSpeedStart(),
        onLongPressEnd: _isLive ? null : (_) => _holdSpeedEnd(),
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _hudOverlay(),
            StreamBuilder<bool>(
              stream: pc.player!.stream.buffering,
              builder: (_, s) => (s.data ?? false)
                  ? Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2.6))
                  : const SizedBox.shrink(),
            ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(ignoring: !_controls, child: _overlay()),
            ),
            if (_panelKind != null) _panel(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _miniLayer(double mx, double my, double mw, double mh) {
    return Positioned(
      left: mx,
      top: my,
      width: mw,
      height: mh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _expand,
        onPanUpdate: (d) => setState(() => _miniPos = Offset(mx, my) + d.delta),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.transparent, Colors.black45],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: StreamBuilder<bool>(
                stream: pc.player!.stream.playing,
                builder: (_, s) => _miniBtn((s.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () => pc.player!.playOrPause(), 28),
              ),
            ),
            Positioned(right: 2, top: 2, child: _miniBtn(Icons.close_rounded, _close, 18)),
            Positioned(left: 2, top: 2, child: _miniBtn(Icons.open_in_full_rounded, _expand, 18)),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap, double size) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (pc.minimized || (e is! KeyDownEvent && e is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // TV remote / D-pad center, gamepad A, keyboard space/enter → show controls
    // first if hidden, otherwise play/pause (direct transport — the expected
    // TV video UX, no focus-hunting among tiny buttons).
    final isSelect = k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.gameButtonA;
    if (isSelect) {
      if (!_controls) {
        setState(() => _controls = true);
      } else {
        pc.player!.playOrPause();
      }
      _scheduleHide();
    } else if (k == LogicalKeyboardKey.mediaPlayPause) {
      pc.player!.playOrPause();
      setState(() => _controls = true);
      _scheduleHide();
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaTrackNext) {
      if (!_isLive) {
        _seekBy(10);
        _flashHud('+10s', Icons.forward_10_rounded);
      } else if (_hasNext) {
        _go(pc.index + 1);
      }
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (!_isLive) {
        _seekBy(-10);
        _flashHud('−10s', Icons.replay_10_rounded);
      } else if (_hasPrev) {
        _go(pc.index - 1);
      }
    } else if (k == LogicalKeyboardKey.arrowUp) {
      // reveal controls (and bump volume hint on keyboard)
      setState(() => _controls = true);
      _scheduleHide();
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.arrowDown) {
      _minimize();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- gestures ----
  void _onDoubleTap() {
    final w = MediaQuery.of(context).size.width;
    if (_zoomScale > 1.05) {
      setState(() => _zoomScale = 1.0);
      _scheduleHide();
      return;
    }
    if (!_isLive && _doubleTapX < w * 0.35) {
      _seekBy(-10);
      _flashHud('−10s', Icons.replay_10_rounded);
    } else if (!_isLive && _doubleTapX > w * 0.65) {
      _seekBy(10);
      _flashHud('+10s', Icons.forward_10_rounded);
    } else {
      pc.player!.playOrPause();
      _scheduleHide();
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gMode = null;
    _gAccum = 0;
    _zoomStart = _zoomScale;
    _gStartPos = pc.player!.state.position;
    _curVol = pc.player!.state.volume;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      setState(() => _zoomScale = (_zoomStart * d.scale).clamp(1.0, 4.0));
      return;
    }
    final w = MediaQuery.of(context).size.width;
    final dx = d.focalPointDelta.dx, dy = d.focalPointDelta.dy;
    _gMode ??= dx.abs() > dy.abs()
        ? (_isLive ? 'none' : 'seek')
        : (d.localFocalPoint.dx < w / 2 ? 'bri' : 'vol');

    switch (_gMode) {
      case 'seek':
        _gAccum += dx;
        final dur = pc.player!.state.duration.inSeconds;
        var target = (_gStartPos.inSeconds + (_gAccum * 0.25)).round();
        if (dur > 0) target = target.clamp(0, dur);
        if (target < 0) target = 0;
        _gSeekTarget = Duration(seconds: target);
        final delta = target - _gStartPos.inSeconds;
        _flashHud('${delta >= 0 ? '+' : '−'}${_fmt(Duration(seconds: delta.abs()))}   ${_fmt(_gSeekTarget)}',
            delta >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            persist: true);
      case 'vol':
        _curVol = (_curVol - dy * 0.4).clamp(0.0, 100.0);
        pc.player!.setVolume(_curVol);
        _muted = _curVol == 0;
        _flashHud('${_curVol.round()}%', _curVol == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            value: _curVol / 100, persist: true);
      case 'bri':
        _curBri = (_curBri - dy * 0.003).clamp(0.0, 1.0);
        ScreenBrightness.instance.setApplicationScreenBrightness(_curBri).catchError((_) {});
        _flashHud('${(_curBri * 100).round()}%', Icons.brightness_6_rounded, value: _curBri, persist: true);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gMode == 'seek') pc.player!.seek(_gSeekTarget);
    _gMode = null;
    _hideHud();
    _scheduleHide();
  }

  void _holdSpeedStart() {
    _holding = true;
    _savedRate = _rate;
    pc.player!.setRate(2.0);
    _flashHud('2× speed', Icons.fast_forward_rounded, persist: true);
  }

  void _holdSpeedEnd() {
    if (!_holding) return;
    _holding = false;
    pc.player!.setRate(_savedRate);
    _hideHud();
  }

  Future<void> _setSubDelay(double v) async {
    _subDelay = double.parse(v.toStringAsFixed(1));
    try {
      await (pc.player!.platform as dynamic)?.setProperty('sub-delay', '$_subDelay');
    } catch (_) {}
    setState(() {});
  }

  void _flashHud(String text, IconData icon, {double? value, bool persist = false}) {
    _hudTimer?.cancel();
    setState(() {
      _hud = text;
      _hudIcon = icon;
      _hudValue = value;
    });
    if (!persist) _hudTimer = Timer(const Duration(milliseconds: 650), () => mounted ? setState(() => _hud = null) : null);
  }

  void _hideHud() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 450), () => mounted ? setState(() => _hud = null) : null);
  }

  Widget _hudOverlay() {
    if (_hud == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_hudIcon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(_hud!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (_hudValue != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _hudValue,
                    minHeight: 4,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _setSleep(int minutes) {
    _sleepMin = minutes;
    _sleepTimer?.cancel();
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        pc.player?.pause();
        if (mounted) setState(() => _sleepMin = 0);
      });
    }
    setState(() {});
  }

  // ---- full controls ----
  Widget _overlay() {
    return Column(children: [_topBar(), const Spacer(), _centerControls(), const Spacer(), _bottomBar()]);
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]),
      ),
      child: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        child: Row(
          children: [
            IconButton(onPressed: _minimize, icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30)),
            if (_isLive)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFF3B5C), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, color: Colors.white, size: 7),
                  SizedBox(width: 5),
                  Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ]),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
                  if (_isLive && pc.epgNow != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text('Now · ${pc.epgNow!.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w600)),
                        ),
                        if (pc.epgNext != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('Next · ${pc.epgNext!.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pc.epgNow!.progress.toDouble(),
                        minHeight: 2.5,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_item.favRef != null)
              AnimatedBuilder(
                animation: Library.instance,
                builder: (_, __) {
                  final fav = Library.instance.isFav(_item.favRef!.key);
                  return IconButton(
                    onPressed: () => Library.instance.toggleFav(_item.favRef!),
                    icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? accent2 : Colors.white),
                  );
                },
              ),
            IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _centerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _smallBtn(Icons.skip_previous_rounded, _hasPrev ? () => _go(pc.index - 1) : null),
        const SizedBox(width: 18),
        if (!_isLive) _roundBtn(Icons.replay_10_rounded, () => _seekBy(-10)),
        const SizedBox(width: 22),
        StreamBuilder<bool>(
          stream: pc.player!.stream.playing,
          builder: (_, s) {
            final playing = s.data ?? false;
            return GestureDetector(
              onTap: () {
                pc.player!.playOrPause();
                _scheduleHide();
              },
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent, a: 0.5)),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 42),
              ),
            );
          },
        ),
        const SizedBox(width: 22),
        if (!_isLive) _roundBtn(Icons.forward_10_rounded, () => _seekBy(10)),
        const SizedBox(width: 18),
        _smallBtn(Icons.skip_next_rounded, _hasNext ? () => _go(pc.index + 1) : null),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      );

  Widget _smallBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white, size: 34),
      );

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Colors.transparent]),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 30, 12, 12),
        child: Column(
          children: [
            if (!_isLive) _seekBar(),
            Row(
              children: [
                IconButton(onPressed: _toggleMute, icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white)),
                IconButton(onPressed: _pickSubtitles, icon: const Icon(Icons.closed_caption_rounded, color: Colors.white)),
                IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune_rounded, color: Colors.white)),
                if (_isAndroid)
                  IconButton(
                    tooltip: 'Picture-in-picture',
                    onPressed: () => Pip.instance.enter(),
                    icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
                  ),
                const Spacer(),
                if (_isLive)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, color: Color(0xFFFF3B5C), size: 9),
                      SizedBox(width: 6),
                      Text('LIVE', style: TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                IconButton(
                  onPressed: _toggleFullscreen,
                  icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: pc.player!.stream.position,
      builder: (_, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final dur = pc.player!.state.duration;
        final max = dur.inMilliseconds.toDouble();
        final val = max <= 0 ? 0.0 : pos.inMilliseconds.toDouble().clamp(0, max);
        return Row(
          children: [
            const SizedBox(width: 4),
            Text(_fmt(pos), style: const TextStyle(fontSize: 12, color: Colors.white)),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbColor: accent,
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white24,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: val.toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0 ? null : (v) => pc.player!.seek(Duration(milliseconds: v.round())),
                  onChangeEnd: (_) => _scheduleHide(),
                ),
              ),
            ),
            Text(_fmt(dur), style: const TextStyle(fontSize: 12, color: Colors.white)),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  // ---- in-player panels (no Navigator available, so not bottom sheets) ----
  void _pickSubtitles() {
    _hideTimer?.cancel();
    setState(() {
      _controls = true;
      _panelKind = 'subs';
    });
  }

  void _openSettings() {
    _hideTimer?.cancel();
    setState(() {
      _controls = true;
      _panelKind = 'settings';
    });
  }

  void _closePanel() {
    setState(() => _panelKind = null);
    _scheduleHide();
  }

  Widget _panel() {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closePanel, child: const ColoredBox(color: Colors.black54)),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(child: _panelKind == 'subs' ? _subsContent() : _settingsContent()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subsContent() {
    final current = pc.player!.state.track.subtitle;
    final real = pc.player!.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: subtle, borderRadius: BorderRadius.circular(2)))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Align(alignment: Alignment.centerLeft, child: Text('Subtitles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        ),
        _subRow('Off', current.id == 'no', () {
          pc.player!.setSubtitleTrack(SubtitleTrack.no());
          _closePanel();
        }),
        ...real.map((t) {
          final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
          return _subRow(label.isEmpty ? 'Track ${t.id}' : label, current.id == t.id, () {
            pc.player!.setSubtitleTrack(t);
            _closePanel();
          });
        }),
        if (real.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text('No subtitles available in this stream.', style: TextStyle(color: subtle))),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _subRow(String label, bool sel, VoidCallback onTap) => ListTile(
        onTap: onTap,
        leading: Icon(sel ? Icons.check_circle_rounded : Icons.subtitles_outlined, color: sel ? accent : muted),
        title: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      );

  Widget _settingsContent() {
    final audio = pc.player!.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final curAudio = pc.player!.state.track.audio;
    final subs = pc.player!.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final curSub = pc.player!.state.track.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: subtle, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(children: [
            const Text('Playback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(onTap: _closePanel, child: Icon(Icons.close_rounded, color: muted)),
          ]),
        ),
        _settingLabel('Video fit'),
        _chipRow([
          ('Fit', _fit == BoxFit.contain, () => setState(() => _fit = BoxFit.contain)),
          ('Fill', _fit == BoxFit.cover, () => setState(() => _fit = BoxFit.cover)),
          ('Stretch', _fit == BoxFit.fill, () => setState(() => _fit = BoxFit.fill)),
        ]),
        if (!_isLive) ...[
          _settingLabel('Speed'),
          _chipRow([
            for (final r in const [0.5, 1.0, 1.25, 1.5, 2.0])
              ('${r}x', _rate == r, () {
                pc.player!.setRate(r);
                setState(() => _rate = r);
              }),
          ]),
        ],
        _settingLabel('Sleep timer'),
        _chipRow([
          for (final mn in const [0, 15, 30, 45, 60]) (mn == 0 ? 'Off' : '${mn}m', _sleepMin == mn, () => _setSleep(mn)),
        ]),
        _settingLabel('Audio'),
        if (audio.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 4), child: Text('Only one audio track.', style: TextStyle(color: subtle)))
        else
          ...audio.map((t) {
            final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
            return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curAudio.id == t.id, () {
              pc.player!.setAudioTrack(t);
              setState(() {});
            });
          }),
        _settingLabel('Subtitles'),
        _trackRow('Off', curSub.id == 'no', () {
          pc.player!.setSubtitleTrack(SubtitleTrack.no());
          setState(() {});
        }),
        ...subs.map((t) {
          final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
          return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curSub.id == t.id, () {
            pc.player!.setSubtitleTrack(t);
            setState(() {});
          });
        }),
        _settingLabel('Subtitle size'),
        _chipRow([
          ('S', _subScale == 0.8, () => setState(() => _subScale = 0.8)),
          ('M', _subScale == 1.0, () => setState(() => _subScale = 1.0)),
          ('L', _subScale == 1.25, () => setState(() => _subScale = 1.25)),
          ('XL', _subScale == 1.6, () => setState(() => _subScale = 1.6)),
          ('Box ${_subBg ? 'on' : 'off'}', _subBg, () => setState(() => _subBg = !_subBg)),
        ]),
        _settingLabel('Subtitle sync'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _stepBtn(Icons.remove_rounded, () => _setSubDelay(_subDelay - 0.5)),
              Expanded(
                child: Text(
                  _subDelay == 0 ? 'In sync' : '${_subDelay > 0 ? '+' : ''}${_subDelay.toStringAsFixed(1)}s',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _stepBtn(Icons.add_rounded, () => _setSubDelay(_subDelay + 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _settingLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(s, style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _chipRow(List<(String, bool, VoidCallback)> chips) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, sel, onTap) in chips)
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? accent : surfaceHi.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sel ? Colors.white : muted)),
                ),
              ),
          ],
        ),
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.7), shape: BoxShape.circle),
          child: Icon(icon, color: accent, size: 22),
        ),
      );

  Widget _trackRow(String label, bool sel, VoidCallback onTap) => ListTile(
        onTap: onTap,
        dense: true,
        leading: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: sel ? accent : muted),
        title: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      );
}
