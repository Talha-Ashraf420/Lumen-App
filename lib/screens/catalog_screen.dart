import 'package:flutter/material.dart';
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
  final String subtitle;
  final VoidCallback onTap;
  _Item(this.name, this.image, this.rating, this.subtitle, this.onTap);
}

String _year(String s) => RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '';

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
            .map((s) => _Item(s.name, s.icon, 0, '',
                () => _open(PlayerScreen(url: c.streamUrl('live', s.streamId, ext: 'ts'), title: s.name))))
            .toList();
      case 'movie':
        final list = await c.vodStreams(cat);
        return list
            .map((m) => _Item(m.name, m.icon, m.rating, _year(m.name),
                () => _open(MovieDetailScreen(client: c, movie: m))))
            .toList();
      default:
        final list = await c.series(cat);
        return list
            .map((s) => _Item(s.name, s.cover, s.rating, _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
                () => _open(SeriesDetailScreen(client: c, seriesId: s.seriesId, title: s.name))))
            .toList();
    }
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLive = widget.kind == 'live';
    return Column(
      children: [
        _searchBar(),
        const SizedBox(height: 12),
        _chipRail(),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<_Item>>(
            future: _items,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2.5));
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8FA3))),
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
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: isLive ? 0.80 : 0.52,
                  crossAxisSpacing: 13,
                  mainAxisSpacing: 18,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => PosterCard(
                  name: items[i].name,
                  image: items[i].image,
                  rating: items[i].rating,
                  subtitle: isLive ? null : items[i].subtitle,
                  badge: isLive ? 'LIVE' : null,
                  live: isLive,
                  index: i,
                  onTap: items[i].onTap,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Glass(
        radius: 18,
        blur: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: muted, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: InputBorder.none,
                  hintText: 'Search ${widget.kind == "live" ? "channels" : widget.kind == "movie" ? "movies" : "series"}…',
                  hintStyle: const TextStyle(color: subtle, fontSize: 15),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _query = ''),
                child: const Icon(Icons.close_rounded, color: subtle, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipRail() {
    if (_cats.isEmpty) return const SizedBox(height: 38);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                color: sel ? null : surfaceHi.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: sel ? Colors.transparent : line),
              ),
              child: Text(c.name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: sel ? Colors.white : muted)),
            ),
          );
        },
      ),
    );
  }
}
