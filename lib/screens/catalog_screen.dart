import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';

class _Item {
  final String name;
  final String image;
  final double rating;
  final String? badge;
  final VoidCallback onTap;
  _Item(this.name, this.image, this.rating, this.badge, this.onTap);
}

class CatalogScreen extends StatefulWidget {
  final XtreamClient client;
  final String kind; // 'live' | 'movie' | 'series'
  const CatalogScreen({super.key, required this.client, required this.kind});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with AutomaticKeepAliveClientMixin {
  List<Category> _cats = [];
  String? _cat;
  Future<List<_Item>>? _items;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final c = widget.client;
    final cats = switch (widget.kind) {
      'live' => await c.liveCategories(),
      'movie' => await c.vodCategories(),
      _ => await c.seriesCategories(),
    };
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _cat = cats.isNotEmpty ? cats.first.id : null;
      _items = _load(_cat);
    });
  }

  Future<List<_Item>> _load(String? cat) async {
    final c = widget.client;
    switch (widget.kind) {
      case 'live':
        final list = await c.liveStreams(cat);
        return list
            .map((s) => _Item(s.name, s.icon, 0, 'LIVE',
                () => _open(PlayerScreen(url: c.streamUrl('live', s.streamId, ext: 'ts'), title: s.name))))
            .toList();
      case 'movie':
        final list = await c.vodStreams(cat);
        return list
            .map((m) => _Item(m.name, m.icon, m.rating, null,
                () => _open(MovieDetailScreen(client: c, movie: m))))
            .toList();
      default:
        final list = await c.series(cat);
        return list
            .map((s) => _Item(s.name, s.cover, s.rating, null,
                () => _open(SeriesDetailScreen(client: c, seriesId: s.seriesId, title: s.name))))
            .toList();
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLive = widget.kind == 'live';
    return Column(
      children: [
        _chipRail(),
        const SizedBox(height: 6),
        _search(),
        Expanded(
          child: FutureBuilder<List<_Item>>(
            future: _items,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: accent));
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snap.error}', style: const TextStyle(color: Color(0xFFFF8FA3))),
                  ),
                );
              }
              var items = snap.data ?? [];
              if (_query.trim().isNotEmpty) {
                final q = _query.toLowerCase();
                items = items.where((i) => i.name.toLowerCase().contains(q)).toList();
              }
              if (items.isEmpty) {
                return const Center(child: Text('Nothing here.', style: TextStyle(color: subtle)));
              }
              final hasHero = !isLive && _query.trim().isEmpty && items.isNotEmpty;
              final hero = hasHero ? items.first : null;
              final grid = hasHero ? items.sublist(1) : items;

              return CustomScrollView(
                slivers: [
                  if (hero != null)
                    SliverToBoxAdapter(child: _Hero(item: hero)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isLive ? 140 : 168,
                        childAspectRatio: isLive ? 1 : 2 / 3,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => PosterCard(
                          name: grid[i].name,
                          image: grid[i].image,
                          rating: grid[i].rating,
                          badge: isLive ? grid[i].badge : null,
                          circle: isLive,
                          index: i,
                          onTap: grid[i].onTap,
                        ),
                        childCount: grid.length,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chipRail() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _cats[i];
          final sel = c.id == _cat;
          return GestureDetector(
            onTap: () => setState(() {
              _cat = c.id;
              _items = _load(c.id);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: sel ? accentGradient : null,
                color: sel ? null : surfaceHi.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? Colors.transparent : line),
              ),
              child: Text(
                c.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: sel ? Colors.white : muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          hintText: 'Search…',
          prefixIcon: Icon(Icons.search_rounded, color: subtle, size: 20),
          isDense: true,
        ),
      ),
    );
  }
}

/// Cinematic featured banner for the first item in a movie/series category.
class _Hero extends StatelessWidget {
  final _Item item;
  const _Hero({required this.item});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GestureDetector(
        onTap: item.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: surfaceHi),
                if (item.image.isNotEmpty)
                  CachedNetworkImage(imageUrl: item.image, fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xF2000000), Colors.transparent],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(gradient: accentGradient, borderRadius: BorderRadius.circular(8)),
                        child: const Text('FEATURED',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 8),
                      Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: glow(Colors.white, blur: 18, y: 4, a: 0.25)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow_rounded, color: bg, size: 22),
                            SizedBox(width: 4),
                            Text('Play', style: TextStyle(color: bg, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
    );
  }
}
