import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

/// Wraps a tappable element so it responds to BOTH mouse hover AND TV
/// remote / D-pad focus. [builder] is given an `active` flag (hovered or
/// focused) so callers can reuse their existing hover styling as the focus
/// highlight. Enter / Space / D-pad-center / gamepad-A all activate [onTap];
/// arrow keys move focus between [FocusableTap]s automatically (Flutter's
/// default directional traversal), and the focused widget scrolls into view.
class FocusableTap extends StatefulWidget {
  final Widget Function(BuildContext context, bool active) builder;
  final VoidCallback onTap;
  final bool autofocus;
  const FocusableTap({super.key, required this.builder, required this.onTap, this.autofocus = false});
  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _hover = false;
  bool _focus = false;

  static const _activators = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      shortcuts: _activators,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _hover || _focus),
      ),
    );
  }
}

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

/// Just the beam mark (no wordmark) — used where space is tight (collapsed rail).
class LumenMark extends StatelessWidget {
  final double size; // height of the mark
  const LumenMark({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size * 0.72, size), painter: _BeamMark(accent));
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
    if (onTap != null) {
      return FocusableTap(
        onTap: onTap!,
        builder: (context, active) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? accent : Colors.transparent, width: 1.5),
          ),
          child: field,
        ),
      );
    }
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
/// Wraps a skeleton layout in a single "light" band that sweeps across it —
/// the shared engine behind [BrandedLoading] and [GridLoading].
class _ShimmerSweep extends StatefulWidget {
  final Widget child;
  const _ShimmerSweep({required this.child});
  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1350))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = surfaceHi;
    final hi = Color.alphaBlend(Colors.white.withValues(alpha: isDark ? 0.10 : 0.65), surfaceHi);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final x = -1.4 + 2.8 * _c.value; // band travels left → right, off-screen both ends
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.6, 0),
            end: Alignment(x + 0.6, 0),
            colors: [base, hi, base],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

Widget _skelBox(double w, double h, {double r = 12}) =>
    Container(width: w, height: h, decoration: BoxDecoration(color: surfaceHi, borderRadius: BorderRadius.circular(r)));

/// A shimmer skeleton loader — a hero block + poster rows with a light sweep
/// gliding across. No spinner, no logo, no text; it reads as the page
/// materialising. Used for full pages (Home, Discover, detail).
class BrandedLoading extends StatelessWidget {
  final bool background;
  const BrandedLoading({super.key, this.background = false});

  Widget _posterRow() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(children: [
          for (var i = 0; i < 8; i++) Padding(padding: const EdgeInsets.only(right: 14), child: _skelBox(120, 180, r: 16)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final skeleton = Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skelBox(double.infinity, 260, r: 26),
            const SizedBox(height: 30),
            _skelBox(170, 18, r: 6),
            const SizedBox(height: 16),
            _posterRow(),
            const SizedBox(height: 30),
            _skelBox(220, 18, r: 6),
            const SizedBox(height: 16),
            _posterRow(),
          ],
        ),
      ),
    );
    final shimmer = _ShimmerSweep(child: skeleton);
    if (!background) return shimmer;
    return Stack(children: [Aurora(), shimmer]);
  }
}

/// A shimmer skeleton shaped like a poster/channel grid — matches what's about
/// to load on Search / Movies / Series / Live, so there's no misleading hero
/// block. Fills its parent.
class GridLoading extends StatelessWidget {
  final bool channel;
  const GridLoading({super.key, this.channel = false});
  @override
  Widget build(BuildContext context) {
    return _ShimmerSweep(
      child: LayoutBuilder(
        builder: (context, c) {
          final tile = channel ? 150.0 : 136.0;
          final cols = (c.maxWidth / tile).floor().clamp(2, 8);
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: channel ? 0.82 : 0.66,
              crossAxisSpacing: 13,
              mainAxisSpacing: 20,
            ),
            itemCount: cols * 3,
            itemBuilder: (_, i) => DecoratedBox(
              decoration: BoxDecoration(color: surfaceHi, borderRadius: BorderRadius.circular(14)),
            ),
          );
        },
      ),
    );
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
    const fg = Colors.white;
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) => AnimatedScale(
        scale: active ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: filled
                ? accent
                : Colors.white.withValues(alpha: active ? 0.26 : 0.14),
            borderRadius: BorderRadius.circular(30),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: active ? 0.7 : 0.28), width: active ? 1.5 : 1),
            boxShadow: filled
                ? glow(accent, blur: active ? 34 : 26, y: 10)
                : (active ? glow(Colors.white, blur: 18, y: 6, a: 0.18) : null),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
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
const double kPosterW = 134;
double posterShelfHeight({bool live = false}) =>
    live ? kPosterW + 44 : kPosterW * 1.5 + 4; // poster (info overlaid) / channel logo + name

/// Premium movie/series poster tile: art fills the card, title + year + rating
/// overlaid on a gradient; hover reveals a play affordance + accent glow.
class PosterCard extends StatelessWidget {
  final String name;
  final String image;
  final double rating;
  final String? subtitle; // year
  final int index;
  final VoidCallback onTap;
  final bool autofocus;
  const PosterCard({
    super.key,
    required this.name,
    required this.image,
    required this.onTap,
    this.rating = 0,
    this.subtitle,
    this.index = 0,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, active) => _visual(context, active),
    )
        .animate()
        .fadeIn(duration: 320.ms, delay: (index.clamp(0, 12) * 30).ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _visual(BuildContext context, bool active) {
    final w = this;
    final card = AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _Fallback(),
            if (w.image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: w.image,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 250),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            // bottom scrim for the title
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0.0, 0.55],
                ),
              ),
            ),
            // title + year
            Positioned(
              left: 11,
              right: 11,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(w.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.15)),
                  if (w.subtitle != null && w.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(w.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                    ),
                ],
              ),
            ),
            if (w.rating > 0)
              Positioned(
                left: 8,
                top: 8,
                child: Glass(
                  radius: 9,
                  blur: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, color: gold, size: 12),
                    const SizedBox(width: 3),
                    Text(w.rating.toStringAsFixed(1), style: TextStyle(color: gold, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            // hover / focus veil + play
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.32),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent)),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
            // hairline edge
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedScale(
      scale: active ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [BoxShadow(color: accent.withValues(alpha: 0.34), blurRadius: 26, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18), blurRadius: 14, offset: const Offset(0, 7))],
        ),
        child: card,
      ),
    );
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
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) => AnimatedScale(
        scale: active ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: active
                ? [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10))]
                : null,
          ),
          child: tile,
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: (index.clamp(0, 12) * 28).ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}
