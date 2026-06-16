import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../theme.dart';

/// Native playback (libmpv) with a full custom control set.
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final bool isLive;
  const PlayerScreen({super.key, required this.url, required this.title, this.isLive = false});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  bool _controls = true;
  bool _fullscreen = false;
  bool _muted = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _player.open(Media(widget.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player.state.playing) setState(() => _controls = false);
    });
  }

  void _tap() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _seekBy(int secs) {
    final p = _player.state.position + Duration(seconds: secs);
    _player.seek(p < Duration.zero ? Duration.zero : p);
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
    _player.setVolume(_muted ? 0 : 100);
    setState(() {});
  }

  Future<void> _pickSubtitles() async {
    final subs = _player.state.tracks.subtitle.where((t) => t.id != 'auto').toList();
    await showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final current = _player.state.track.subtitle;
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
                _player.setSubtitleTrack(SubtitleTrack.no());
                Navigator.pop(context);
              }),
              ...real.map((t) {
                final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                return _subRow(label.isEmpty ? 'Track ${t.id}' : label, current.id == t.id, () {
                  _player.setSubtitleTrack(t);
                  Navigator.pop(context);
                });
              }),
              if (real.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text('No subtitles available in this stream.', style: TextStyle(color: subtle))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _tap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain)),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (_, s) => (s.data ?? false)
                  ? const Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2.6))
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

  Widget _overlay() {
    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          const Spacer(),
          _centerControls(),
          const Spacer(),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]),
      ),
      child: Row(
        children: [
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          if (widget.isLive)
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
            child: Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
          ),
        ],
      ),
    );
  }

  Widget _centerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!widget.isLive) _roundBtn(Icons.replay_10_rounded, () => _seekBy(-10)),
        const SizedBox(width: 28),
        StreamBuilder<bool>(
          stream: _player.stream.playing,
          builder: (_, s) {
            final playing = s.data ?? false;
            return GestureDetector(
              onTap: () {
                _player.playOrPause();
                _scheduleHide();
              },
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(gradient: accentGradient, shape: BoxShape.circle, boxShadow: glow(accent, a: 0.5)),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 42),
              ),
            );
          },
        ),
        const SizedBox(width: 28),
        if (!widget.isLive) _roundBtn(Icons.forward_10_rounded, () => _seekBy(10)),
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

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 30, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Colors.transparent]),
      ),
      child: Column(
        children: [
          if (!widget.isLive) _seekBar(),
          Row(
            children: [
              IconButton(onPressed: _toggleMute, icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white)),
              IconButton(onPressed: _pickSubtitles, icon: const Icon(Icons.closed_caption_rounded, color: Colors.white)),
              const Spacer(),
              if (widget.isLive)
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
    );
  }

  Widget _seekBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      builder: (_, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final dur = _player.state.duration;
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
                  onChanged: max <= 0 ? null : (v) => _player.seek(Duration(milliseconds: v.round())),
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
