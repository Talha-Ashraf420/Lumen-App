import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../theme.dart';

export '../playback.dart' show PlayerItem;

/// Full-screen player — a view over the app-level [PlaybackController] so video
/// keeps running when minimised. Pass [items] to start new playback, or no
/// items to re-attach (expand) the current session.
class PlayerScreen extends StatefulWidget {
  final List<PlayerItem>? items;
  final int index;
  const PlayerScreen({super.key, this.items, this.index = 0});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final pc = PlaybackController.instance;

  bool _controls = true;
  bool _fullscreen = false;
  bool _muted = false;
  Timer? _hideTimer;
  BoxFit _fit = BoxFit.contain;
  double _rate = 1.0;
  double _zoomScale = 1.0, _zoomStart = 1.0;

  // gesture state (1-finger swipes)
  String? _gMode; // 'seek' | 'vol' | 'bri'
  double _curVol = 100, _curBri = 0.5, _gAccum = 0;
  Duration _gStartPos = Duration.zero, _gSeekTarget = Duration.zero;
  double _doubleTapX = 0;

  // transient gesture HUD
  String? _hud;
  IconData? _hudIcon;
  double? _hudValue;
  Timer? _hudTimer;

  // sleep timer
  int _sleepMin = 0;

  PlayerItem get _item => pc.item;
  bool get _isLive => pc.isLive;
  bool get _hasNext => pc.hasNext;
  bool get _hasPrev => pc.hasPrev;

  @override
  void initState() {
    super.initState();
    if (widget.items != null) {
      pc.open(widget.items!, widget.index);
    } else {
      pc.expand();
    }
    pc.addListener(_onPc);
    ScreenBrightness.instance.current.then((b) => _curBri = b).catchError((_) => _curBri = 0.5);
    _scheduleHide();
  }

  void _onPc() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    pc.removeListener(_onPc);
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Leave the full player but keep playing in the floating mini-player.
  void _minimize() {
    pc.minimize();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  /// Stop playback entirely and leave the player.
  void _close() {
    pc.stop();
    Navigator.of(context).pop();
  }

  void _go(int i) {
    pc.go(i);
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (pc.player?.state.playing ?? false)) setState(() => _controls = false);
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
    if (_fullscreen) {
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

  Future<void> _pickSubtitles() async {
    final subs = pc.player!.state.tracks.subtitle.where((t) => t.id != 'auto').toList();
    await showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final current = pc.player!.state.track.subtitle;
        final real = subs.where((t) => t.id != 'no').toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text('Subtitles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ),
              _subRow('Off', current.id == 'no', () {
                pc.player!.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              }),
              ...real.map((t) {
                final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                return _subRow(label.isEmpty ? 'Track ${t.id}' : label, current.id == t.id, () {
                  pc.player!.setSubtitleTrack(t);
                  Navigator.pop(context);
                });
              }),
              if (real.isEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Text('No subtitles available in this stream.', style: TextStyle(color: subtle))),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    _scheduleHide();
  }

  Widget _subRow(String label, bool sel, VoidCallback onTap) => ListTile(
        onTap: onTap,
        leading: Icon(sel ? Icons.check_circle_rounded : Icons.subtitles_outlined, color: sel ? accent : muted),
        title: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      );

  /// Unified playback settings: video fit, speed (VOD), audio track, subtitles.
  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final audio = pc.player!.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final curAudio = pc.player!.state.track.audio;
            final subs = pc.player!.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final curSub = pc.player!.state.track.subtitle;
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: subtle, borderRadius: BorderRadius.circular(2)))),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text('Playback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    _settingLabel('Video fit'),
                    _chipRow([
                      ('Fit', _fit == BoxFit.contain, () => setSheet(() => setState(() => _fit = BoxFit.contain))),
                      ('Fill', _fit == BoxFit.cover, () => setSheet(() => setState(() => _fit = BoxFit.cover))),
                      ('Stretch', _fit == BoxFit.fill, () => setSheet(() => setState(() => _fit = BoxFit.fill))),
                    ]),
                    if (!_isLive) ...[
                      _settingLabel('Speed'),
                      _chipRow([
                        for (final r in const [0.5, 1.0, 1.25, 1.5, 2.0])
                          ('${r}x', _rate == r, () {
                            pc.player!.setRate(r);
                            setSheet(() => setState(() => _rate = r));
                          }),
                      ]),
                    ],
                    _settingLabel('Sleep timer'),
                    _chipRow([
                      for (final mn in const [0, 15, 30, 45, 60])
                        (mn == 0 ? 'Off' : '${mn}m', _sleepMin == mn, () => setSheet(() => _setSleep(mn))),
                    ]),
                    _settingLabel('Audio'),
                    if (audio.isEmpty)
                      Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 4), child: Text('Only one audio track.', style: TextStyle(color: subtle)))
                    else
                      ...audio.map((t) {
                        final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                        return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curAudio.id == t.id, () {
                          pc.player!.setAudioTrack(t);
                          setSheet(() {});
                        });
                      }),
                    _settingLabel('Subtitles'),
                    _trackRow('Off', curSub.id == 'no', () {
                      pc.player!.setSubtitleTrack(SubtitleTrack.no());
                      setSheet(() {});
                    }),
                    ...subs.map((t) {
                      final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                      return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curSub.id == t.id, () {
                        pc.player!.setSubtitleTrack(t);
                        setSheet(() {});
                      });
                    }),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _scheduleHide();
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
                  child: Text(label,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sel ? Colors.white : muted)),
                ),
              ),
          ],
        ),
      );

  Widget _trackRow(String label, bool sel, VoidCallback onTap) => ListTile(
        onTap: onTap,
        dense: true,
        leading: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: sel ? accent : muted),
        title: Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      );

  @override
  Widget build(BuildContext context) {
    if (!pc.hasMedia) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onDoubleTapDown: (d) => _doubleTapX = d.localPosition.dx,
        onDoubleTap: _onDoubleTap,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Transform.scale(
                scale: _zoomScale,
                child: Video(controller: pc.controller!, controls: NoVideoControls, fit: _fit),
              ),
            ),
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
          ],
        ),
      ),
    );
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

  Timer? _sleepTimer;

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
}
