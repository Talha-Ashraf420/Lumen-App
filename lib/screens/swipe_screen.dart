import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../discovery.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../responsive.dart';
import '../theme.dart';
import '../tmdb.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';

String _clean(String s) {
  var t = s;
  t = t.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), '');
  t = t.replaceAll(RegExp(r'\b(?:4K|UHD|FHD|HD|SD|HQ|1080p|720p|2160p|HEVC|x26[45]|DV|HDR)\b', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'[._]+'), ' ');
  t = t.replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '');
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  t = t.replaceAll(RegExp(r'[-|·•:]\s*$'), '').trim();
  return t.isEmpty ? s : t;
}

int _yearOf(String s) => int.tryParse(RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '') ?? 0;

/// Tinder-style discovery: swipe right to save to My List, left to skip, tap to
/// open. On desktop it's a two-pane layout (card + live info panel) with
/// arrow-key support; on phone it's a stacked card with buttons below.
class SwipeScreen extends StatefulWidget {
  final XtreamClient client;
  const SwipeScreen({super.key, required this.client});
  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _controller = CardSwiperController();
  List<VodStream> _pool = [];
  bool _loading = true;
  bool _done = false;
  int _index = 0;
  int _liked = 0;
  final Map<int, TmdbInfo?> _meta = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pool = await Discovery.pool(widget.client, target: 80);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _loading = false;
        _done = pool.isEmpty;
        _index = 0;
      });
      _prefetch(0);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Fetch TMDB for the current card and the next couple, so the panel is ready.
  void _prefetch(int i) {
    for (var k = i; k < i + 3 && k < _pool.length; k++) {
      _fetchMeta(_pool[k]);
    }
  }

  void _fetchMeta(VodStream m) {
    if (_meta.containsKey(m.streamId)) return;
    _meta[m.streamId] = null;
    Tmdb.movie(m.name).then((t) => mounted ? setState(() => _meta[m.streamId] = t) : null);
  }

  MediaRef _ref(VodStream m) => MediaRef(kind: 'movie', id: m.streamId, name: m.name, image: m.icon, cat: m.categoryId);

  bool _onSwipe(int prev, int? current, CardSwiperDirection dir) {
    if (dir == CardSwiperDirection.right) {
      final m = _pool[prev];
      if (!Library.instance.isFav(_ref(m).key)) Library.instance.toggleFav(_ref(m));
      HapticFeedback.mediumImpact();
      setState(() => _liked++);
    } else {
      HapticFeedback.selectionClick();
    }
    if (current != null) {
      setState(() => _index = current);
      _prefetch(current);
    }
    return true;
  }

  void _open([VodStream? m]) {
    final movie = m ?? (_index >= 0 && _index < _pool.length ? _pool[_index] : null);
    if (movie == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(client: widget.client, movie: movie)));
  }

  void _play(VodStream m) {
    final ext = m.containerExtension.isEmpty ? 'mp4' : m.containerExtension;
    PlaybackController.instance.open([
      PlayerItem(widget.client.streamUrl('movie', m.streamId, ext: ext), m.name, progressKey: 'movie:${m.streamId}', poster: m.icon, ext: ext, favRef: _ref(m)),
    ], 0);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _loading || _done || _pool.isEmpty) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _controller.swipe(CardSwiperDirection.left);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _controller.swipe(CardSwiperDirection.right);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        _open();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Aurora(),
          SafeArea(
            child: Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: Column(
                children: [
                  _header(),
                  Expanded(
                    child: _loading
                        ? BrandedLoading()
                        : _done
                            ? _doneView()
                            : wide
                                ? _wideBody()
                                : _narrowBody(),
                  ),
                  if (!wide && !_loading && !_done) _actions(),
                  SizedBox(height: wide ? 20 : 96),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
        child: Row(
          children: [
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 4),
            const Text('For you', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Text('Swipe to build your taste', style: TextStyle(color: subtle, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_liked > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.favorite_rounded, color: accent, size: 18),
                const SizedBox(width: 5),
                Text('$_liked saved', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
          ],
        ),
      );

  // ── Desktop: card on the left, live info panel on the right ───────────────
  Widget _wideBody() {
    final m = _pool[_index.clamp(0, _pool.length - 1)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 40, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 360, child: _swiper()),
          const SizedBox(width: 48),
          Expanded(child: Center(child: SingleChildScrollView(child: _infoPanel(m)))),
        ],
      ),
    );
  }

  Widget _infoPanel(VodStream m) {
    final t = _meta[m.streamId];
    final rating = (t?.rating ?? 0) > 0 ? t!.rating : m.rating;
    final year = _yearOf(m.name) > 0 ? _yearOf(m.name) : _yearOf(t?.releaseDate ?? '');
    final genre = t?.genres ?? '';
    final overview = t?.overview ?? '';
    final cast = t?.cast ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('FOR YOU', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 3)),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(_clean(m.name), key: ValueKey(m.streamId), maxLines: 2, overflow: TextOverflow.ellipsis, style: kDisplay()),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (rating > 0)
              _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, color: gold, size: 15),
                const SizedBox(width: 4),
                Text(rating.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: 13)),
              ])),
            if (year > 0) _chip(Text('$year', style: TextStyle(color: textHi, fontWeight: FontWeight.w700, fontSize: 13))),
            if (genre.isNotEmpty) _chip(Text(genre, style: TextStyle(color: muted, fontSize: 13))),
          ]),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(overview, maxLines: 5, overflow: TextOverflow.ellipsis, style: kBody()),
          ],
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Cast', style: TextStyle(color: subtle, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(cast, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textHi, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 26),
          Row(children: [
            _panelBtn(Icons.close_rounded, 'Skip', const Color(0xFFFF5277), () => _controller.swipe(CardSwiperDirection.left)),
            const SizedBox(width: 12),
            _panelBtn(Icons.favorite_rounded, 'Save', const Color(0xFF36E27A), () => _controller.swipe(CardSwiperDirection.right)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            PillButton(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => _play(m)),
            const SizedBox(width: 12),
            _ghostBtn(Icons.info_outline_rounded, 'Details', () => _open(m)),
          ]),
          const SizedBox(height: 18),
          Text('← Skip     → Save     Enter to open', style: TextStyle(color: subtle, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _chip(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
        child: child,
      );

  Widget _panelBtn(IconData icon, String label, Color color, VoidCallback onTap) => HoverScale(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ),
      );

  Widget _ghostBtn(IconData icon, String label, VoidCallback onTap) => HoverScale(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            decoration: BoxDecoration(color: surfaceHi, borderRadius: BorderRadius.circular(30), border: Border.all(color: line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: textHi, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: textHi, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ),
      );

  // ── Phone: stacked card + buttons below ───────────────────────────────────
  Widget _narrowBody() => _swiper();

  Widget _swiper() => CardSwiper(
        controller: _controller,
        cardsCount: _pool.length,
        numberOfCardsDisplayed: math.min(3, _pool.length),
        isLoop: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backCardOffset: const Offset(0, 28),
        onSwipe: _onSwipe,
        onEnd: () => setState(() => _done = true),
        cardBuilder: (context, index, hpct, vpct) => _card(_pool[index], hpct),
      );

  Widget _doneView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: accent, size: 44),
            const SizedBox(height: 14),
            Text('That’s all for now', style: TextStyle(color: textHi, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 6),
            Text(_liked > 0 ? 'Added $_liked to My List' : 'Swipe right to save favourites', style: TextStyle(color: subtle)),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () {
                setState(() => _loading = true);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                child: const Text('More', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );

  Widget _card(VodStream m, int hpct) {
    final t = _meta[m.streamId];
    final year = _yearOf(m.name) > 0 ? _yearOf(m.name) : _yearOf(t?.releaseDate ?? '');
    final genre = t?.genres ?? '';
    return GestureDetector(
      onTap: () => _open(m),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: surfaceHi),
            if (m.icon.isNotEmpty)
              CachedNetworkImage(
                imageUrl: m.icon,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorWidget: (_, _, _) => Center(child: Icon(Icons.movie_outlined, color: subtle, size: 40)),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_clean(m.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (m.rating > 0 || (t?.rating ?? 0) > 0)
                      _darkChip(Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, color: gold, size: 14),
                        const SizedBox(width: 3),
                        Text(((t?.rating ?? 0) > 0 ? t!.rating : m.rating).toStringAsFixed(1),
                            style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: 12)),
                      ])),
                    if (year > 0) _darkChip(Text('$year', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                    if (genre.isNotEmpty) _darkChip(Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                  ]),
                ],
              ),
            ),
            if (hpct.abs() > 8)
              Positioned(
                top: 24,
                left: hpct > 0 ? 20 : null,
                right: hpct < 0 ? 20 : null,
                child: Transform.rotate(
                  angle: hpct > 0 ? -0.3 : 0.3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hpct > 0 ? const Color(0xFF36E27A) : const Color(0xFFFF5277), width: 3),
                    ),
                    child: Text(
                      hpct > 0 ? 'SAVE' : 'SKIP',
                      style: TextStyle(
                        color: hpct > 0 ? const Color(0xFF36E27A) : const Color(0xFFFF5277),
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _darkChip(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: 0.22))),
        child: child,
      );

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _btn(Icons.close_rounded, const Color(0xFFFF5277), 64, () => _controller.swipe(CardSwiperDirection.left)),
          const SizedBox(width: 22),
          _btn(Icons.info_outline_rounded, accent, 52, () => _open()),
          const SizedBox(width: 22),
          _btn(Icons.favorite_rounded, const Color(0xFF36E27A), 64, () => _controller.swipe(CardSwiperDirection.right)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, Color color, double size, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            boxShadow: glow(color),
          ),
          child: Icon(icon, color: color, size: size * 0.42),
        ),
      );
}
