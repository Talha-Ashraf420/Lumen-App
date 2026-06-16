import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../theme.dart';

/// Native playback via libmpv — decodes TS / MKV / HLS / MP4 directly from the
/// provider URL. No proxy, no transcode.
class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const PlayerScreen({super.key, required this.url, required this.title});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    // a player-like UA helps with providers that gate on it
    _player.open(Media(widget.url, httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'}));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: const MaterialVideoControlsThemeData(
          seekBarThumbColor: accent,
          seekBarPositionColor: accent,
          topButtonBar: [],
        ),
        fullscreen: const MaterialVideoControlsThemeData(
          seekBarThumbColor: accent,
          seekBarPositionColor: accent,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Video(controller: _controller, fit: BoxFit.contain),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(color: Colors.black, blurRadius: 8)]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
