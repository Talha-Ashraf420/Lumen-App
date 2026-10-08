import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Video chrome has its own always-dark surface, independent of app theme.
/// Transport is deliberately separate from browsing/settings actions.
class PlayerTransport extends StatelessWidget {
  const PlayerTransport({
    super.key,
    required this.playing,
    required this.live,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
    this.onPrevious,
    this.onNext,
    this.playFocusNode,
  });

  final bool playing;
  final bool live;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (onPrevious != null)
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          label: live ? 'Previous channel' : 'Previous episode',
          onTap: onPrevious!,
        ),
      if (!live)
        _TransportButton(
          icon: Icons.replay_10_rounded,
          label: 'Rewind 10 seconds',
          onTap: onRewind,
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Tooltip(
          message: playing ? 'Pause' : 'Play',
          child: RemoteTap(
            focusNode: playFocusNode,
            focusRadius: 999,
            semanticLabel: playing ? 'Pause' : 'Play',
            onTap: onPlayPause,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: AnimatedSwitcher(
                duration: lumenMotionDuration(context, lumenMotionFast),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  color: onAccent,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ),
      if (!live)
        _TransportButton(
          icon: Icons.forward_10_rounded,
          label: 'Fast forward 10 seconds',
          onTap: onForward,
        ),
      if (onNext != null)
        _TransportButton(
          icon: Icons.skip_next_rounded,
          label: live ? 'Next channel' : 'Next episode',
          onTap: onNext!,
        ),
    ],
  );
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: RemoteTap(
      focusRadius: 999,
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(icon, size: 27, color: Colors.white),
      ),
    ),
  );
}

class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({
    super.key,
    required this.fullscreen,
    required this.onSubtitles,
    required this.onMore,
    required this.onFullscreen,
    this.onChannels,
  });

  final bool fullscreen;
  final VoidCallback onSubtitles;
  final VoidCallback onMore;
  final VoidCallback onFullscreen;
  final VoidCallback? onChannels;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Row(
        children: [
          if (onChannels != null)
            Expanded(
              child: _PlayerAction(
                icon: Icons.view_list_rounded,
                label: 'Channels',
                onTap: onChannels!,
              ),
            ),
          Expanded(
            child: _PlayerAction(
              icon: Icons.closed_caption_outlined,
              label: 'Subtitles',
              onTap: onSubtitles,
            ),
          ),
          Expanded(
            child: _PlayerAction(
              icon: Icons.tune_rounded,
              label: 'More',
              onTap: onMore,
            ),
          ),
          Expanded(
            child: _PlayerAction(
              icon: fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: fullscreen ? 'Exit full screen' : 'Full screen',
              onTap: onFullscreen,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: RemoteTap(
      semanticLabel: label,
      respectFocusHighlightMode: true,
      focusRingColor: Colors.white,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlayerPanelEntrance extends StatelessWidget {
  const PlayerPanelEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: lumenMotionDuration(context, const Duration(milliseconds: 220)),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => Transform.translate(
      offset: Offset(20 * (1 - value), 0),
      child: Opacity(opacity: value, child: child),
    ),
    child: child,
  );
}

/// A modal player panel. Only the screen-facing edge consumes a horizontal
/// safe inset; the inside edge isn't next to the phone's notch/home indicator.
class PlayerSidePanel extends StatelessWidget {
  const PlayerSidePanel({
    super.key,
    required this.child,
    required this.onClose,
  });
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final safeRight = MediaQuery.paddingOf(context).right;
      final width = (380 + safeRight).clamp(0.0, box.maxWidth * .92);
      return Stack(
        children: [
          Positioned.fill(
            child: ModalBarrier(
              key: const ValueKey('player-panel-barrier'),
              color: Colors.black54,
              dismissible: true,
              onDismiss: onClose,
              semanticsLabel: 'Close playback panel',
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: width,
            child: PlayerPanelEntrance(
              child: ClipRRect(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(lumenCorner(22)),
                ),
                child: ColoredBox(
                  color: const Color(0xFF15181C),
                  child: SafeArea(left: false, child: child),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Status belongs below the measured header, never at a fixed screen offset.
class PlayerHeaderLane extends StatelessWidget {
  const PlayerHeaderLane({
    super.key,
    required this.header,
    required this.status,
  });
  final Widget header;
  final Widget status;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [header, status]);
}
