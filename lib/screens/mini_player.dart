import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../playback.dart';
import '../theme.dart';
import 'player_screen.dart';

/// Floating, draggable mini-player shown (above the Navigator) whenever playback
/// is minimised. Tap to expand back to the full player; X to stop.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final pc = PlaybackController.instance;
  static const double _w = 176, _h = 99;
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    pc.addListener(_onPc);
  }

  @override
  void dispose() {
    pc.removeListener(_onPc);
    super.dispose();
  }

  void _onPc() {
    if (mounted) setState(() {});
  }

  void _expand() {
    pc.expand();
    rootNavKey.currentState?.push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final show = pc.minimized && pc.hasMedia && pc.controller != null;
    if (!show) return const IgnorePointer(child: SizedBox.expand());

    return LayoutBuilder(
      builder: (context, con) {
        final maxW = con.maxWidth, maxH = con.maxHeight;
        _pos ??= Offset(maxW - _w - 12, maxH - _h - 120); // default: above the nav bar
        final dx = _pos!.dx.clamp(8.0, maxW - _w - 8);
        final dy = _pos!.dy.clamp(44.0, maxH - _h - 8);
        return Stack(
          children: [
            Positioned(
              left: dx,
              top: dy,
              child: GestureDetector(
                onTap: _expand,
                onPanUpdate: (d) => setState(() => _pos = Offset(dx, dy) + d.delta),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: _w,
                    height: _h,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
                      border: Border.all(color: Colors.white12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Video(controller: pc.controller!, controls: NoVideoControls, fit: BoxFit.contain),
                        // play/pause
                        Positioned(
                          left: 4,
                          bottom: 2,
                          child: StreamBuilder<bool>(
                            stream: pc.player!.stream.playing,
                            builder: (_, s) {
                              final playing = s.data ?? false;
                              return _miniBtn(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                () => pc.player!.playOrPause(),
                              );
                            },
                          ),
                        ),
                        // close
                        Positioned(
                          right: 2,
                          top: 2,
                          child: _miniBtn(Icons.close_rounded, pc.stop, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap, {double size = 22}) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      );
}
