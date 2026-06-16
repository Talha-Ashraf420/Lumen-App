import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../xtream.dart';
import 'player_screen.dart';
import 'series_detail_screen.dart';

class _Item {
  final String name;
  final String image;
  final double rating;
  final VoidCallback onTap;
  _Item(this.name, this.image, this.rating, this.onTap);
}

/// Browse screen for a content kind: 'live' | 'movie' | 'series'.
class CatalogScreen extends StatefulWidget {
  final XtreamClient client;
  final String kind;
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
            .map((s) => _Item(s.name, s.icon, 0, () => _play(c.streamUrl('live', s.streamId, ext: 'ts'), s.name)))
            .toList();
      case 'movie':
        final list = await c.vodStreams(cat);
        return list
            .map((m) => _Item(m.name, m.icon, m.rating,
                () => _play(c.streamUrl('movie', m.streamId, ext: m.containerExtension), m.name)))
            .toList();
      default:
        final list = await c.series(cat);
        return list
            .map((s) => _Item(s.name, s.cover, s.rating, () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SeriesDetailScreen(client: c, seriesId: s.seriesId, title: s.name)));
                }))
            .toList();
    }
  }

  void _play(String url, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(url: url, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final aspect = widget.kind == 'live' ? 1.0 : 2 / 3;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(child: _categoryDropdown()),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Filter…',
                    prefixIcon: Icon(Icons.search, color: subtle, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
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
                  child: Text('${snap.error}', style: const TextStyle(color: Color(0xFFFFB4B4))),
                ));
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  childAspectRatio: aspect,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _PosterCard(item: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _cat,
          dropdownColor: surfaceHi,
          icon: const Icon(Icons.expand_more, color: subtle),
          items: _cats
              .map((c) => DropdownMenuItem(
                  value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() {
            _cat = v;
            _items = _load(v);
          }),
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final _Item item;
  const _PosterCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: surface),
            if (item.image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.image,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const _Fallback(),
                placeholder: (_, __) => const ColoredBox(color: surfaceHi),
              )
            else
              const _Fallback(),
            // gradient + title
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
            if (item.rating > 0)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, color: accent2, size: 13),
                    const SizedBox(width: 2),
                    Text(item.rating.toStringAsFixed(1),
                        style: const TextStyle(color: accent2, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: surfaceHi, child: Center(child: Icon(Icons.movie_rounded, color: subtle)));
}
