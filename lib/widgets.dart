import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'theme.dart';

/// The Lumen wordmark: a violet play-beam mark + "Lumen" in Manrope. Rendered
/// natively (not from SVG) so the font renders reliably and it adapts to theme.
class Wordmark extends StatelessWidget {
  final double size; // text font size
  const Wordmark({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(size: Size(size * 0.66, size * 0.92), painter: _BeamMark(accent)),
        SizedBox(width: size * 0.26),
        Text('Lumen',
            style: GoogleFonts.manrope(
                fontSize: size, fontWeight: FontWeight.w800, color: textHi, letterSpacing: -0.5, height: 1)),
      ],
    );
  }
}

/// A right-pointing play triangle with an accent underline (matches the icon).
class _BeamMark extends CustomPainter {
  final Color color;
  _BeamMark(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    final triH = h * 0.74;
    final tri = Path()
      ..moveTo(0, 0)
      ..lineTo(0, triH)
      ..lineTo(w, triH / 2)
      ..close();
    canvas.drawPath(tri, p);
    final barTop = h * 0.85;
    canvas.drawRRect(
      RRect.fromLTRBR(0, barTop, w * 0.86, h, Radius.circular(h * 0.06)),
      p,
    );
  }

  @override
  bool shouldRepaint(_BeamMark old) => old.color != color;
}

/// Subtle scale-up on mouse hover (desktop affordance; no-op on touch).
class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const HoverScale({super.key, required this.child, this.scale = 1.04});
  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Frosted "liquid glass" surface (used for nav / menus / sheets).
class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsets? padding;
  final Color? tint;
  const Glass({super.key, required this.child, this.blur = 18, this.radius = 22, this.padding, this.tint});
  @override
  Widget build(BuildContext context) {
    final tintColor = tint ?? surfaceHi;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The single, consistent search field used across the whole app.
class SearchField extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap; // read-only mode (e.g. Home → opens Search)
  final bool readOnly;
  final Widget? trailing;
  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      decoration: BoxDecoration(
        color: surfaceHi.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: readOnly
                ? Align(alignment: Alignment.centerLeft, child: Text(hint, style: TextStyle(color: subtle, fontSize: 15)))
                : TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(fontSize: 15.5),
                    cursorColor: accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: hint,
                      hintStyle: TextStyle(color: subtle, fontSize: 15),
                    ),
                  ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: field);
    return field;
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
          Positioned.fill(child: ColoredBox(color: bg)),
          Positioned(top: -160, left: -120, child: _blob(accent.withValues(alpha: 0.22), 380)),
          Positioned(top: 80, right: -140, child: _blob(accent2.withValues(alpha: 0.14), 340)),
          Positioned(bottom: -160, left: 20, child: _blob(const Color(0xFF11433A).withValues(alpha: 0.4), 320)),
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

/// Branded loading splash.
class BrandedLoading extends StatelessWidget {
  final bool background;
  const BrandedLoading({super.key, this.background = false});
  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset('assets/lumen_loader.json', width: 132, height: 132, repeat: true),
          const SizedBox(height: 10),
          const Wordmark(size: 30),
        ],
      ),
    );
    if (!background) return content;
    return Stack(children: [Aurora(), content]);
  }
}

/// Pill action button (filled accent or glass) used by hero / detail.
class PillButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const PillButton({super.key, required this.label, required this.onTap, this.icon, this.filled = true});
  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : Colors.white;
    return HoverScale(
      scale: 1.03,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: filled ? accent : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30),
            border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.28)),
            boxShadow: filled ? glow(accent, blur: 26, y: 10) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

/// Section header with a tidy "See all" pill.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const SectionHeader({super.key, required this.title, this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ),
          const SizedBox(width: 12),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('See all', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  Icon(Icons.chevron_right_rounded, color: accent, size: 17),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Standard width for a poster card in a shelf (keeps everything consistent).
const double kPosterW = 128;
double posterShelfHeight({bool live = false}) =>
    live ? kPosterW + 44 : kPosterW * 1.5 + 48; // image + title block (with slack)

/// The single poster/channel card used everywhere: fixed full-width poster
/// (no Expanded/AspectRatio mismatch) + crisp title below. Never clips.
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
    final poster = AspectRatio(
      aspectRatio: live ? 1 : 2 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: glow(Colors.black, blur: 14, y: 7, a: 0.5)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
                    fadeInDuration: const Duration(milliseconds: 220),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                      Icon(Icons.star_rounded, color: gold, size: 12),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1), style: TextStyle(color: gold, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              if (badge != null)
                Positioned(
                  left: 7,
                  top: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFFF3B5C), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(badge!, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Colors.white)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poster,
        const SizedBox(height: 8),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: subtle)),
          ),
      ],
    );

    return HoverScale(child: GestureDetector(onTap: onTap, child: tile))
        .animate()
        .fadeIn(duration: 300.ms, delay: (index.clamp(0, 12) * 28).ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: surfaceHi),
        child: Center(child: Icon(Icons.movie_creation_outlined, color: subtle, size: 28)),
      );
}

/// A polished live-TV tile: the channel logo centred on an elevated surface
/// (logos are often transparent/odd-shaped, so they get a clean backdrop),
/// a LIVE badge, and the channel name below.
class ChannelCard extends StatelessWidget {
  final String name;
  final String logo;
  final VoidCallback onTap;
  final int index;
  const ChannelCard({super.key, required this.name, required this.logo, required this.onTap, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [surfaceHi, surface],
              ),
              border: Border.all(color: line),
              boxShadow: glow(Colors.black, blur: 12, y: 6, a: 0.4),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: logo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: logo,
                          fit: BoxFit.contain,
                          fadeInDuration: const Duration(milliseconds: 200),
                          errorWidget: (_, _, _) => Icon(Icons.live_tv_rounded, color: subtle, size: 30),
                        )
                      : Icon(Icons.live_tv_rounded, color: subtle, size: 30),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFFF3B5C), borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, color: Colors.white, size: 5),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Colors.white)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
    return HoverScale(child: GestureDetector(onTap: onTap, child: tile))
        .animate()
        .fadeIn(duration: 300.ms, delay: (index.clamp(0, 12) * 28).ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}
