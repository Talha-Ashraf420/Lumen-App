import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme.dart';
import '../widgets.dart';

/// Keeps the real app mounted and initializing beneath a short launch film.
/// The splash never waits forever: startup failures are reported, then the
/// normal app UI is allowed to present its own actionable state.
class LaunchGate extends StatefulWidget {
  const LaunchGate({
    super.key,
    required this.child,
    this.startup,
    this.minimumDuration = const Duration(milliseconds: 1850),
  });

  final Widget child;
  final Future<void>? startup;
  final Duration minimumDuration;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _finishLaunch();
  }

  Future<void> _finishLaunch() async {
    final startup = widget.startup;
    await Future.wait([
      Future<void>.delayed(widget.minimumDuration),
      if (startup != null) _guardStartup(startup),
    ]);
    if (mounted) setState(() => _showSplash = false);
  }

  Future<void> _guardStartup(Future<void> startup) async {
    try {
      await startup;
    } catch (error, stack) {
      debugPrint('Launch preparation failed: $error\n$stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 520),
          reverseDuration: const Duration(milliseconds: 420),
          switchOutCurve: Curves.easeInCubic,
          // Scaling an entire full-screen layer makes text and the vector mark
          // look soft on some Android TV GPUs. Fade at native resolution.
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _showSplash
              ? const LaunchSplash(key: ValueKey('lumen-launch-splash'))
              : const SizedBox.shrink(key: ValueKey('lumen-launch-complete')),
        ),
      ],
    );
  }
}

/// Lumen's launch film: a signal finding the screen, then resolving into the
/// product mark. Lottie drives the organic beam/ripple while Flutter keeps the
/// typography and geometry perfectly sharp at phone, desktop, and TV sizes.
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({super.key});

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  double _interval(double start, double end, {Curve curve = Curves.easeOut}) {
    return CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: curve),
    ).value;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.shortestSide < 560;
    final markSize = compact ? 104.0 : 136.0;
    final brandSize = compact ? 43.0 : 58.0;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: const Color(0xFF070909),
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            final fieldIn = _interval(0, .35, curve: Curves.easeOutCubic);
            final markIn = _interval(.08, .48, curve: Curves.easeOutBack);
            final nameIn = _interval(.28, .62, curve: Curves.easeOutCubic);
            final copyIn = _interval(.48, .78, curve: Curves.easeOutCubic);
            final progress = _interval(.08, .92, curve: Curves.easeInOutCubic);

            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF070909)),
                Opacity(
                  opacity: .24 * fieldIn,
                  child: CustomPaint(
                    painter: _LaunchFieldPainter(
                      phase: reducedMotion ? 1 : _intro.value,
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 24 : 48,
                        vertical: 28,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.translate(
                              offset: Offset(0, 20 * (1 - markIn)),
                              child: Opacity(
                                opacity: markIn.clamp(0, 1),
                                child: SizedBox.square(
                                  dimension: compact ? 184 : 240,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Lottie.asset(
                                        'assets/lumen_loader.json',
                                        width: compact ? 184 : 240,
                                        height: compact ? 184 : 240,
                                        repeat: !reducedMotion,
                                        animate: !reducedMotion,
                                        fit: BoxFit.contain,
                                        delegates: LottieDelegates(
                                          values: [
                                            ValueDelegate.color(const [
                                              '**',
                                            ], value: defaultAccent),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: markSize,
                                        height: markSize,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0E1210),
                                          borderRadius: BorderRadius.circular(
                                            markSize * .28,
                                          ),
                                          border: Border.all(
                                            color: defaultAccent.withValues(
                                              alpha: .7,
                                            ),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: LumenMark(
                                          size: markSize * .68,
                                          signal: defaultAccent,
                                          frame: const Color(0xFFF4F1E8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 14),
                            Transform.translate(
                              offset: Offset(0, 16 * (1 - nameIn)),
                              child: Opacity(
                                opacity: nameIn.clamp(0, 1),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'LUMEN',
                                      style: TextStyle(
                                        color: const Color(0xFFF4F1E8),
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: brandSize,
                                        fontWeight: FontWeight.w600,
                                        height: .9,
                                        letterSpacing: -2.4,
                                      ),
                                    ),
                                    SizedBox(width: brandSize * .16),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: brandSize * .15,
                                        vertical: brandSize * .08,
                                      ),
                                      decoration: BoxDecoration(
                                        color: defaultAccent,
                                        borderRadius: BorderRadius.circular(
                                          brandSize * .15,
                                        ),
                                      ),
                                      child: Text(
                                        'TV',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: 'SpaceGrotesk',
                                          fontSize: brandSize * .28,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 24),
                            Transform.translate(
                              offset: Offset(0, 12 * (1 - copyIn)),
                              child: Opacity(
                                opacity: copyIn.clamp(0, 1),
                                child: Column(
                                  children: [
                                    Text(
                                      'YOUR SCREEN. YOUR SIGNAL.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: const Color(0xFFF4F1E8),
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: compact ? 13 : 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: compact ? 2.7 : 4.2,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'LIVE   •   FILMS   •   SERIES',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: const Color(
                                          0xFFA2A6A3,
                                        ).withValues(alpha: .9),
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: compact ? 9 : 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: compact ? 2.2 : 3.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 42 : 54),
                            Opacity(
                              opacity: copyIn.clamp(0, 1),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compact ? 230 : 300,
                                ),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: SizedBox(
                                        height: 3,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            const ColoredBox(
                                              color: Color(0xFF252A26),
                                            ),
                                            FractionallySizedBox(
                                              alignment: Alignment.centerLeft,
                                              widthFactor: progress.clamp(0, 1),
                                              child: const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Color(0xFF24C7B0),
                                                      Color(0xFFC7F36B),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'TUNING YOUR EXPERIENCE',
                                      style: TextStyle(
                                        color: Color(0xFF747A75),
                                        fontFamily: 'SpaceGrotesk',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
        ),
      ),
    );
  }
}

/// A neutral session operation state. Unlike [BrandedLoading], this never
/// implies that a movie catalog is loading and therefore cannot leak a home
/// page skeleton into startup or sign-out.
class SessionLoading extends StatelessWidget {
  const SessionLoading({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tv = MediaQuery.sizeOf(context).shortestSide >= 560;
    final markSize = tv ? 84.0 : 64.0;
    return Material(
      color: const Color(0xFF070909),
      child: SafeArea(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: message,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: markSize * 1.5,
                  height: markSize * 1.5,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1210),
                    borderRadius: BorderRadius.circular(markSize * .34),
                    border: Border.all(
                      color: defaultAccent.withValues(alpha: .6),
                    ),
                  ),
                  child: LumenMark(
                    size: markSize,
                    signal: defaultAccent,
                    frame: const Color(0xFFF4F1E8),
                  ),
                ),
                SizedBox(height: tv ? 28 : 22),
                Text(
                  message,
                  style: TextStyle(
                    color: const Color(0xFFA2A6A3),
                    fontFamily: 'SpaceGrotesk',
                    fontSize: tv ? 13 : 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: tv ? 2.8 : 2.2,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: tv ? 240 : 190,
                  child: const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Color(0xFF252A26),
                    color: defaultAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchFieldPainter extends CustomPainter {
  const _LaunchFieldPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFC7F36B).withValues(alpha: .22)
      ..strokeWidth = 1;
    final spacing = size.shortestSide < 560 ? 54.0 : 84.0;
    final drift = (phase * spacing * .32) % spacing;

    for (var x = -spacing + drift; x < size.width + spacing; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = -spacing + drift; y < size.height + spacing; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final beam = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFC7F36B).withValues(alpha: .23),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 1.2;
    final sweep = size.width * (.15 + .7 * phase);
    canvas.save();
    canvas.translate(sweep, size.height * .5);
    canvas.rotate(-math.pi / 7);
    canvas.drawLine(Offset(0, -size.height), Offset(0, size.height), beam);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaunchFieldPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
