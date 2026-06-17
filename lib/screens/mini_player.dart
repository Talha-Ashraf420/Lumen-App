import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../playback.dart';
import '../responsive.dart';
import '../theme.dart';
import 'player_screen.dart';

/// Floating, draggable mini-player shown (above the Navigator) whenever playback
/// is minimised. Tap to expand back to the full player; X to stop.
///
/// On desktop it shows the poster + controls (a second live video texture isn't
/// reliable there); on mobile it shows the live video.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final pc = PlaybackController.instance;
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

    final wide = isWide(context);
    final w = wide ? 340.0 : 200.0;
    final h = w * 9 / 16;
    final margin = wide ? 24.0 : 12.0;
    final bottomGap = wide ? 24.0 : 108.0; // clear the mobile nav bar

    return LayoutBuilder(
      builder: (context, con) {
        final maxW = con.maxWidth, maxH = con.maxHeight;
        _pos ??= Offset(maxW - w - margin, maxH - h - bottomGap);
        final dx = _pos!.dx.clamp(8.0, (maxW - w - 8).clamp(8.0, maxW));
        final dy = _pos!.dy.clamp(40.0, (maxH - h - 8).clamp(40.0, maxH));
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
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 22, offset: Offset(0, 10))],
                      border: Border.all(color: Colors.white24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _surface(wide),
                        // darken slightly so controls read on any artwork
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black26, Colors.transparent, Colors.black54],
                              stops: [0, 0.4, 1],
                            ),
                          ),
                        ),
                        // title (desktop)
                        if (wide)
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                              pc.item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        // play / pause
                        Align(
                          alignment: wide ? Alignment.center : Alignment.bottomLeft,
                          child: StreamBuilder<bool>(
                            stream: pc.player!.stream.playing,
                            builder: (_, s) {
                              final playing = s.data ?? false;
                              return _miniBtn(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                () => pc.player!.playOrPause(),
                                size: wide ? 30 : 22,
                              );
                            },
                          ),
                        ),
                        // close
                        Positioned(
                          right: 2,
                          top: 2,
                          child: _miniBtn(Icons.close_rounded, pc.stop, size: wide ? 20 : 18),
                        ),
                        // expand hint (desktop)
                        if (wide)
                          Positioned(
                            left: 2,
                            top: 2,
                            child: _miniBtn(Icons.open_in_full_rounded, _expand, size: 18),
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

  /// Mobile renders the live video; desktop shows the poster (macOS can't run a
  /// second live video view of the same player without racing/crashing).
  Widget _surface(bool wide) {
    if (!wide) {
      return Video(controller: pc.controller!, controls: NoVideoControls, fit: BoxFit.cover);
    }
    final poster = pc.item.poster;
    if (poster.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: poster,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => ColoredBox(color: surfaceHi),
      );
    }
    return ColoredBox(color: surfaceHi, child: Center(child: Icon(Icons.movie_rounded, color: subtle, size: 30)));
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap, {double size = 22}) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(5),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      );
}
