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

/// Ambient drifting aurora background (cheap, gradient blobs).
class Aurora extends StatelessWidget {
  const Aurora({super.key});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: bg)),
          Positioned(top: -140, left: -100, child: _blob(accent.withValues(alpha: 0.30), 360)),
          Positioned(top: 120, right: -120, child: _blob(accent2.withValues(alpha: 0.22), 320)),
          Positioned(bottom: -120, left: 40, child: _blob(const Color(0xFF3B2D6B).withValues(alpha: 0.5), 300)),
        ],
      ),
    );
  }

  Widget _blob(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -16, end: 16, duration: 6.seconds, curve: Curves.easeInOut);
}

/// Premium poster/channel card with depth, gradient scrim + entrance animation.
class PosterCard extends StatelessWidget {
  final String name;
  final String image;
  final double rating;
  final String? badge;
  final bool circle; // live channels look better as rounded tiles
  final int index;
  final VoidCallback onTap;
  const PosterCard({
    super.key,
    required this.name,
    required this.image,
    required this.onTap,
    this.rating = 0,
    this.badge,
    this.circle = false,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: glow(Colors.black, blur: 18, y: 10, a: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: surface),
              if (image.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: image,
                  fit: circle ? BoxFit.contain : BoxFit.cover,
                  errorWidget: (_, _, _) => const _Fallback(),
                  placeholder: (_, _) => const ColoredBox(color: surfaceHi),
                )
              else
                const _Fallback(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Color(0xE6000000), Colors.transparent],
                  ),
                ),
              ),
              if (rating > 0)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Glass(
                    radius: 10,
                    blur: 8,
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: gold, size: 13),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              if (badge != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge!,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.15)),
              ),
            ],
          ),
        ),
      ),
    );
    return card
        .animate()
        .fadeIn(duration: 350.ms, delay: (index.clamp(0, 12) * 35).ms)
        .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [surfaceHi, surface])),
        child: Center(child: Icon(Icons.movie_creation_outlined, color: subtle, size: 30)),
      );
}
