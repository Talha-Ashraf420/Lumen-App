import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../library.dart';
import '../models.dart';
import '../theme.dart';

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

/// Native playback (libmpv) with a full custom control set + playlist
/// (next/previous episode or channel, with auto-advance for VOD).
class PlayerScreen extends StatefulWidget {
  final List<PlayerItem> items;
  final int index;
  const PlayerScreen({super.key, required this.items, this.index = 0});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  late int _index = widget.index;
  StreamSubscription<bool>? _completedSub;

  bool _controls = true;
  bool _fullscreen = false;
  bool _muted = false;
  bool _resumed = false;
  int _lastSave = 0;
  Timer? _hideTimer;
  StreamSubscription<Duration>? _posSub;
  List<EpgEntry> _epg = const [];
  BoxFit _fit = BoxFit.contain;
  double _rate = 1.0;

  PlayerItem get _item => widget.items[_index];
  bool get _isLive => _item.isLive;
  bool get _hasNext => _index < widget.items.length - 1;
  bool get _hasPrev => _index > 0;

  @override
  void initState() {
    super.initState();
    _openCurrent();
    _completedSub = _player.stream.completed.listen((done) {
      if (done && !_isLive && _hasNext) _go(_index + 1);
    });
    _posSub = _player.stream.position.listen(_onPosition);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _completedSub?.cancel();
    _posSub?.cancel();
    _persistProgress();
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _openCurrent() {
    _resumed = false;
    _epg = const [];
    _player.open(Media(_item.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));
    if (_item.favRef != null) Library.instance.addRecent(_item.favRef!);
    _loadEpg();
  }

  void _loadEpg() {
    final fetch = _item.epg;
    if (fetch == null) return;
    fetch().then((list) {
      if (mounted) setState(() => _epg = list);
    }).catchError((_) {});
  }

  EpgEntry? get _epgNow {
    for (final e in _epg) {
      if (e.isNow) return e;
    }
    return _epg.isNotEmpty ? _epg.first : null;
  }

  EpgEntry? get _epgNext {
    final now = _epgNow;
    if (now == null) return null;
    final i = _epg.indexOf(now);
    return (i >= 0 && i + 1 < _epg.length) ? _epg[i + 1] : null;
  }

  void _onPosition(Duration pos) {
    if (_isLive || _item.progressKey == null) return;
    final dur = _player.state.duration;
    if (dur.inSeconds <= 0) return;
    // resume once
    if (!_resumed) {
      _resumed = true;
      final saved = Library.instance.progress[_item.progressKey];
      if (saved != null && saved.position > 10 && saved.position < dur.inSeconds * 0.95) {
        _player.seek(Duration(seconds: saved.position));
      }
      return;
    }
    // throttled progress save
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSave > 5000) {
      _lastSave = now;
      _persistProgress();
    }
  }

  void _persistProgress() {
    if (_isLive || _item.progressKey == null) return;
    final dur = _player.state.duration, pos = _player.state.position;
    if (dur.inSeconds <= 0) return;
    Library.instance.saveProgress(Progress(
      key: _item.progressKey!,
      title: _item.title,
      poster: _item.poster,
      url: _item.url,
      ext: _item.ext,
      position: pos.inSeconds,
      duration: dur.inSeconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _go(int i) {
    if (i < 0 || i >= widget.items.length) return;
    setState(() {
      _index = i;
      _controls = true;
    });
    _openCurrent();
    _scheduleHide();
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
            final audio = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final curAudio = _player.state.track.audio;
            final subs = _player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
            final curSub = _player.state.track.subtitle;
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
                            _player.setRate(r);
                            setSheet(() => setState(() => _rate = r));
                          }),
                      ]),
                    ],
                    _settingLabel('Audio'),
                    if (audio.isEmpty)
                      Padding(padding: const EdgeInsets.fromLTRB(20, 2, 20, 4), child: Text('Only one audio track.', style: TextStyle(color: subtle)))
                    else
                      ...audio.map((t) {
                        final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                        return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curAudio.id == t.id, () {
                          _player.setAudioTrack(t);
                          setSheet(() {});
                        });
                      }),
                    _settingLabel('Subtitles'),
                    _trackRow('Off', curSub.id == 'no', () {
                      _player.setSubtitleTrack(SubtitleTrack.no());
                      setSheet(() {});
                    }),
                    ...subs.map((t) {
                      final label = [t.title, t.language].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
                      return _trackRow(label.isEmpty ? 'Track ${t.id}' : label, curSub.id == t.id, () {
                        _player.setSubtitleTrack(t);
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _tap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: Video(controller: _controller, controls: NoVideoControls, fit: _fit)),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
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

  Widget _overlay() {
    // Guarantee insets so controls clear the notch / home indicator in landscape.
    return SafeArea(
      minimum: EdgeInsets.symmetric(horizontal: _fullscreen ? 28 : 4, vertical: _fullscreen ? 12 : 0),
      child: Column(children: [_topBar(), const Spacer(), _centerControls(), const Spacer(), _bottomBar()]),
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
                if (_isLive && _epgNow != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text('Now · ${_epgNow!.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w600)),
                      ),
                      if (_epgNext != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('Next · ${_epgNext!.title}',
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
                      value: _epgNow!.progress.toDouble(),
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
        ],
      ),
    );
  }

  Widget _centerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _smallBtn(Icons.skip_previous_rounded, _hasPrev ? () => _go(_index - 1) : null),
        const SizedBox(width: 18),
        if (!_isLive) _roundBtn(Icons.replay_10_rounded, () => _seekBy(-10)),
        const SizedBox(width: 22),
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
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent, a: 0.5)),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 42),
              ),
            );
          },
        ),
        const SizedBox(width: 22),
        if (!_isLive) _roundBtn(Icons.forward_10_rounded, () => _seekBy(10)),
        const SizedBox(width: 18),
        _smallBtn(Icons.skip_next_rounded, _hasNext ? () => _go(_index + 1) : null),
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
      padding: const EdgeInsets.fromLTRB(12, 30, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Colors.transparent]),
      ),
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
