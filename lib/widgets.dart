import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'theme.dart';

/// Frosted "liquid glass" surface.
class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsets? padding;
  final Color tint;
  const Glass({
    super.key,
    required this.child,
    this.blur = 18,
    this.radius = 22,
    this.padding,
    this.tint = surfaceHi,
  });
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Ambient drifting aurora background.
class Aurora extends StatelessWidget {
  const Aurora({super.key});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: bg)),
          Positioned(top: -160, left: -120, child: _blob(accent.withValues(alpha: 0.28), 380)),
          Positioned(top: 80, right: -140, child: _blob(accent2.withValues(alpha: 0.20), 340)),
          Positioned(bottom: -140, left: 20, child: _blob(const Color(0xFF3B2D6B).withValues(alpha: 0.45), 320)),
        ],
      ),
    );
  }

  Widget _blob(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -18, end: 18, duration: 7.seconds, curve: Curves.easeInOut);
}

/// Branded loading splash — gradient wordmark + subtle loader on the dark canvas.
class BrandedLoading extends StatelessWidget {
  final bool background;
  const BrandedLoading({super.key, this.background = false});
  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => accentGradient.createShader(r),
            child: const Text('Lumen',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 600.ms).then().fade(begin: 1, end: 0.6, duration: 900.ms),
          const SizedBox(height: 22),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(color: accent, strokeWidth: 2.4),
          ),
        ],
      ),
    );
    if (!background) return content;
    return Stack(children: [const Aurora(), content]);
  }
}

/// Clean premium tile: image-only poster (depth + rating) with the title BELOW
/// in crisp type — far less cluttered than text-on-image.
class PosterCard extends StatelessWidget {
  final String name;
  final String image;
  final double rating;
  final String? subtitle;
  final String? badge;
  final bool live;
  final int index;
  final VoidCallback onTap;
  const PosterCard({
    super.key,
    required this.name,
    required this.image,
    required this.onTap,
    this.rating = 0,
    this.subtitle,
    this.badge,
    this.live = false,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final art = AspectRatio(
      aspectRatio: live ? 1 : 2 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: glow(Colors.black, blur: 16, y: 8, a: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _Fallback(),
              if (image.isNotEmpty)
                Padding(
                  padding: live ? const EdgeInsets.all(14) : EdgeInsets.zero,
                  child: CachedNetworkImage(
                    imageUrl: image,
                    fit: live ? BoxFit.contain : BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 250),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              // subtle top sheen + inner border for a premium edge
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color(0x22FFFFFF), Colors.transparent],
                  ),
                ),
              ),
              if (rating > 0)
                Positioned(
                  left: 7,
                  top: 7,
                  child: Glass(
                    radius: 9,
                    blur: 6,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: gold, size: 12),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(color: gold, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              if (badge != null)
                Positioned(
                  left: 7,
                  top: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B5C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(badge!, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: art),
        const SizedBox(height: 8),
        Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: subtle)),
          ),
      ],
    );

    return GestureDetector(onTap: onTap, child: tile)
        .animate()
        .fadeIn(duration: 300.ms, delay: (index.clamp(0, 12) * 30).ms)
        .slideY(begin: 0.10, end: 0, curve: Curves.easeOutCubic);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [surfaceHi, surface])),
        child: Center(child: Icon(Icons.movie_creation_outlined, color: subtle, size: 28)),
      );
}
