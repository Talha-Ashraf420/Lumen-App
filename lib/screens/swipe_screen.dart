import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import '../discovery.dart';
import '../library.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';

/// Tinder-style discovery: swipe right to save to My List, left to skip, tap to
/// open. Builds your taste (and powers the globe) as you go.
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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MediaRef _ref(VodStream m) =>
      MediaRef(kind: 'movie', id: m.streamId, name: m.name, image: m.icon, cat: m.categoryId);

  bool _onSwipe(int prev, int? current, CardSwiperDirection dir) {
    if (dir == CardSwiperDirection.right) {
      final m = _pool[prev];
      if (!Library.instance.isFav(_ref(m).key)) Library.instance.toggleFav(_ref(m));
      HapticFeedback.mediumImpact();
      setState(() => _liked++);
    } else {
      HapticFeedback.selectionClick();
    }
    if (current != null) setState(() => _index = current);
    return true;
  }

  void _open() {
    if (_index < 0 || _index >= _pool.length) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(client: widget.client, movie: _pool[_index]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(child: _body()),
                if (!_loading && !_done) _actions(),
                const SizedBox(height: 96),
              ],
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
            const Spacer(),
            if (_liked > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.favorite_rounded, color: accent, size: 18),
                const SizedBox(width: 5),
                Text('$_liked', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
          ],
        ),
      );

  Widget _body() {
    if (_loading) return const BrandedLoading();
    if (_done) {
      return Center(
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
    }
    return CardSwiper(
      controller: _controller,
      cardsCount: _pool.length,
      numberOfCardsDisplayed: math.min(3, _pool.length),
      isLoop: false,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      backCardOffset: const Offset(0, 28),
      onSwipe: _onSwipe,
      onEnd: () => setState(() => _done = true),
      cardBuilder: (context, index, hpct, vpct) => _card(_pool[index], hpct),
    );
  }

  Widget _card(VodStream m, int hpct) {
    return GestureDetector(
      onTap: _open,
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
                errorWidget: (_, _, _) => Center(child: Icon(Icons.movie_outlined, color: subtle, size: 40)),
              ),
            // bottom scrim + title
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
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
                  Text(m.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
                  if (m.rating > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.star_rounded, color: gold, size: 16),
                      const SizedBox(width: 4),
                      Text(m.rating.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
                    ]),
                  ],
                ],
              ),
            ),
            // LIKE / NOPE stamp based on drag direction
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

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _btn(Icons.close_rounded, const Color(0xFFFF5277), 64, () => _controller.swipe(CardSwiperDirection.left)),
          const SizedBox(width: 22),
          _btn(Icons.info_outline_rounded, accent, 52, _open),
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
