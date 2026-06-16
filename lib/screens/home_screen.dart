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

String _year(String s) => RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '';

/// A single browsable item for shelves / hero.
class HItem {
  final String name;
  final String image;
  final double rating;
  final String subtitle;
  final VoidCallback onTap;
  HItem(this.name, this.image, this.rating, this.subtitle, this.onTap);
}

class HomeScreen extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onBrowse;
  const HomeScreen({super.key, required this.client, required this.onBrowse});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  late Future<_HomeData> _future;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _loadHome();
  }

  Future<_HomeData> _loadHome() async {
    final c = widget.client;
    final results = await Future.wait([c.vodCategories(), c.seriesCategories(), c.liveCategories()]);
    return _HomeData(results[0], results[1], results[2]);
  }

  HItem _movie(VodStream m) => HItem(m.name, m.icon, m.rating, _year(m.name),
      () => _push(MovieDetailScreen(client: widget.client, movie: m)));
  HItem _series(Series s) => HItem(s.name, s.cover, s.rating, _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
      () => _push(SeriesDetailScreen(client: widget.client, seriesId: s.seriesId, title: s.name)));
  HItem _live(LiveStream s) => HItem(s.name, s.icon, 0, 'Live',
      () => _push(PlayerScreen(url: widget.client.streamUrl('live', s.streamId, ext: 'ts'), title: s.name, isLive: true)));

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const BrandedLoading();
        }
        if (snap.hasError || snap.data == null) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${snap.error ?? "Couldn't load."}',
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8FA3))),
          ));
        }
        final d = snap.data!;
        final c = widget.client;
        final movieCats = d.vodCats.take(4).toList();
        final seriesCats = d.seriesCats.take(3).toList();
        final liveCat = d.liveCats.isNotEmpty ? d.liveCats.first : null;

        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _searchBar(),
            const SizedBox(height: 14),
            // hero carousel from the first movie category
            if (movieCats.isNotEmpty)
              _HeroCarousel(
                future: c
                    .vodStreams(movieCats.first.id)
                    .then((l) => l.where((m) => m.icon.isNotEmpty).take(6).map(_movie).toList())
                    .catchError((_) => <HItem>[]),
              ),
            // interleave movie + series shelves
            for (var i = 0; i < movieCats.length; i++) ...[
              _Shelf(
                title: movieCats[i].name,
                future: c.vodStreams(movieCats[i].id).then((l) => l.take(16).map(_movie).toList()).catchError((_) => <HItem>[]),
                onMore: widget.onBrowse,
              ),
              if (i < seriesCats.length)
                _Shelf(
                  title: seriesCats[i].name,
                  future: c.series(seriesCats[i].id).then((l) => l.take(16).map(_series).toList()).catchError((_) => <HItem>[]),
                  onMore: widget.onBrowse,
                ),
            ],
            if (liveCat != null)
              _Shelf(
                title: 'Live · ${liveCat.name}',
                future: c.liveStreams(liveCat.id).then((l) => l.take(16).map(_live).toList()).catchError((_) => <HItem>[]),
                live: true,
                onMore: widget.onBrowse,
              ),
          ],
        );
      },
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SearchField(
        hint: 'Movies, series, channels…',
        readOnly: true,
        onTap: widget.onBrowse,
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(11)),
          child: const Icon(Icons.tune_rounded, color: muted, size: 18),
        ),
      ),
    );
  }
}

class _HomeData {
  final List<Category> vodCats, seriesCats, liveCats;
  _HomeData(this.vodCats, this.seriesCats, this.liveCats);
}

/// Featured hero — a peeking PageView of big rounded backdrop cards.
class _HeroCarousel extends StatefulWidget {
  final Future<List<HItem>> future;
  const _HeroCarousel({required this.future});
  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _ctrl = PageController(viewportFraction: 0.84);
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HItem>>(
      future: widget.future,
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Container(
            height: 210,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
            child: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2))
                : null,
          );
        }
        return Column(
          children: [
            SizedBox(
              height: 440,
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (p) => setState(() => _page = p),
                itemCount: items.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _HeroCard(item: items[i]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: i == _page ? accentGradient : null,
                      color: i == _page ? null : subtle.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  final HItem item;
  const _HeroCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: surfaceHi),
            if (item.image.isNotEmpty) CachedNetworkImage(imageUrl: item.image, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF0000000), Colors.transparent],
                  stops: [0.05, 0.75],
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_arrow_rounded, color: bg, size: 20),
                        SizedBox(width: 4),
                        Text('Play', style: TextStyle(color: bg, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    if (item.rating > 0)
                      Glass(
                        radius: 12,
                        blur: 8,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, color: gold, size: 15),
                          const SizedBox(width: 3),
                          Text(item.rating.toStringAsFixed(1),
                              style: const TextStyle(color: gold, fontWeight: FontWeight.w700, fontSize: 13)),
                        ]),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

/// Horizontal shelf: header + a row of poster cards.
class _Shelf extends StatelessWidget {
  final String title;
  final Future<List<HItem>> future;
  final bool live;
  final VoidCallback? onMore;
  const _Shelf({required this.title, required this.future, this.live = false, this.onMore});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HItem>>(
      future: future,
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (snap.connectionState == ConnectionState.done && items.isEmpty) return const SizedBox.shrink();
        final h = posterShelfHeight(live: live);
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: title, onSeeAll: onMore),
              SizedBox(
                height: h,
                child: items.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => SizedBox(
                          width: kPosterW,
                          child: PosterCard(
                            name: items[i].name,
                            image: items[i].image,
                            rating: items[i].rating,
                            subtitle: live ? null : (items[i].subtitle.isEmpty ? null : items[i].subtitle),
                            badge: live ? 'LIVE' : null,
                            live: live,
                            index: i,
                            onTap: items[i].onTap,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
