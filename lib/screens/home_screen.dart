import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import '../catalog_cache.dart';
import '../home_config.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../theme.dart';
import '../tmdb.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';
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
    contentRefresh.addListener(_onRefresh);
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() => _future = _loadHome());
  }

  Future<void> _pullRefresh() async {
    refreshContent(); // clears caches + bumps the notifier (reloads _future)
    await _future;
  }

  Future<_HomeData> _loadHome() async {
    final c = widget.client;
    // Shared, retried category cache (reused by Search / Live too).
    final results = await Future.wait([
      CatalogCache.instance.vod(c),
      CatalogCache.instance.series(c),
      CatalogCache.instance.live(c),
    ]);
    return _HomeData(results[0], results[1], results[2]);
  }

  HItem _movie(VodStream m) => HItem(m.name, m.icon, m.rating, _year(m.name),
      () => _push(MovieDetailScreen(client: widget.client, movie: m)));
  HItem _series(Series s) => HItem(s.name, s.cover, s.rating, _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
      () => _push(SeriesDetailScreen(client: widget.client, seriesId: s.seriesId, title: s.name)));
  /// Build a live shelf whose items share one channel playlist (next/prev zap).
  List<HItem> _liveShelf(List<LiveStream> chans) {
    final pl = chans
        .map((s) => PlayerItem(
              widget.client.streamUrl('live', s.streamId, ext: 'ts'),
              s.name,
              isLive: true,
              poster: s.icon,
              favRef: MediaRef(
                kind: 'live',
                id: s.streamId,
                name: s.name,
                image: s.icon,
                url: widget.client.streamUrl('live', s.streamId, ext: 'ts'),
              ),
              epg: () => widget.client.shortEpg(s.streamId),
            ))
        .toList();
    return chans
        .asMap()
        .entries
        .map((e) => HItem(e.value.name, e.value.icon, 0, 'Live', () => PlaybackController.instance.open(pl, e.key)))
        .toList();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  /// Resume a continue-watching entry straight into the player.
  void _resume(Progress pr) {
    PlaybackController.instance.open([
      PlayerItem(pr.url, pr.title, progressKey: pr.key, poster: pr.poster, ext: pr.ext),
    ], 0);
  }

  /// Re-open a recently-watched item by reconstructing its destination.
  void _openRecent(MediaRef r) {
    switch (r.kind) {
      case 'movie':
        _push(MovieDetailScreen(
            client: widget.client,
            movie: VodStream(r.id, r.name, r.image, '', 'mp4', 0, '')));
      case 'series':
        _push(SeriesDetailScreen(client: widget.client, seriesId: r.id, title: r.name));
      case 'live':
        PlaybackController.instance.open([
          PlayerItem(r.url, r.name, isLive: true, poster: r.image, favRef: r, epg: () => widget.client.shortEpg(r.id)),
        ], 0);
    }
  }

  /// Continue-watching + recently-watched rows, rebuilt when the library changes.
  Widget _libraryRows() {
    final cont = Library.instance.continueWatching();
    final recent = Library.instance.recent;
    if (cont.isEmpty && recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cont.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: SectionHeader(title: 'Continue watching'),
          ),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cont.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _ContinueCard(progress: cont[i], onTap: () => _resume(cont[i])),
            ),
          ),
        ],
        if (recent.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: SectionHeader(title: 'Jump back in'),
          ),
          SizedBox(
            height: posterShelfHeight(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => SizedBox(
                width: kPosterW,
                child: recent[i].isLive
                    ? ChannelCard(name: recent[i].name, logo: recent[i].image, index: i, onTap: () => _openRecent(recent[i]))
                    : PosterCard(
                        name: recent[i].name,
                        image: recent[i].image,
                        index: i,
                        onTap: () => _openRecent(recent[i]),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }

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
        // Rebuild when the user customises which shelves appear on Home.
        return AnimatedBuilder(
          animation: HomeConfig.instance,
          builder: (context, _) {
            final custom = HomeConfig.instance.isCustom;

            // hero source: first chosen movie shelf, else first movie category
            String? heroCat;
            if (custom) {
              final mv = HomeConfig.instance.shelves.where((s) => s.type == 'movie');
              if (mv.isNotEmpty) heroCat = mv.first.id;
            } else if (d.vodCats.isNotEmpty) {
              heroCat = d.vodCats.first.id;
            }

            final shelves = <Widget>[];
            if (custom) {
              for (final s in HomeConfig.instance.shelves) {
                shelves.add(_shelfFor(c, s));
              }
            } else {
              final movieCats = d.vodCats.take(4).toList();
              final seriesCats = d.seriesCats.take(3).toList();
              for (var i = 0; i < movieCats.length; i++) {
                shelves.add(_shelfFor(c, ShelfRef('movie', movieCats[i].id, movieCats[i].name)));
                if (i < seriesCats.length) {
                  shelves.add(_shelfFor(c, ShelfRef('series', seriesCats[i].id, seriesCats[i].name)));
                }
              }
              if (d.liveCats.isNotEmpty) {
                shelves.add(_shelfFor(c, ShelfRef('live', d.liveCats.first.id, d.liveCats.first.name)));
              }
            }

            final below = <Widget>[
              AnimatedBuilder(animation: Library.instance, builder: (_, __) => _libraryRows()),
              AnimatedBuilder(animation: Library.instance, builder: (_, __) => _recommendationRows(c, d.vodCats)),
              ...shelves,
            ];

            if (isWide(context)) {
              return RefreshIndicator(
                onRefresh: _pullRefresh,
                color: accent,
                child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _SpotlightHero(
                      client: c,
                      future: heroCat == null
                          ? Future.value(const <VodStream>[])
                          : c
                              .vodStreams(heroCat)
                              .then((l) => l.where((m) => m.icon.isNotEmpty).take(8).toList())
                              .catchError((_) => <VodStream>[]),
                      onOpen: (m) => _push(MovieDetailScreen(client: c, movie: m)),
                    ),
                  ),
                  SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 12), child: Column(children: below))),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _pullRefresh,
              color: accent,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  _searchBar(),
                  const SizedBox(height: 14),
                  if (heroCat != null)
                    _HeroCarousel(
                      future: c
                          .vodStreams(heroCat)
                          .then((l) => l.where((m) => m.icon.isNotEmpty).take(6).map(_movie).toList())
                          .catchError((_) => <HItem>[]),
                    ),
                  ...below,
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Top movie categories inferred from favourites + recents (present in catalog).
  List<Category> _tasteCats(List<Category> all) {
    final freq = <String, int>{};
    for (final m in [...Library.instance.favourites, ...Library.instance.recent]) {
      if (m.kind == 'movie' && m.cat.isNotEmpty) freq[m.cat] = (freq[m.cat] ?? 0) + 1;
    }
    final sorted = freq.keys.toList()..sort((a, b) => freq[b]!.compareTo(freq[a]!));
    final out = <Category>[];
    for (final id in sorted) {
      final match = all.where((c) => c.id == id);
      if (match.isNotEmpty) {
        out.add(match.first);
        if (out.length >= 2) break;
      }
    }
    return out;
  }

  Widget _recommendationRows(XtreamClient c, List<Category> vodCats) {
    final cats = _tasteCats(vodCats);
    if (cats.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final cat in cats)
          _Shelf(
            title: 'Because you like ${cat.name}',
            future: c
                .vodStreams(cat.id)
                .then((l) => l.where((m) => m.icon.isNotEmpty).take(16).map(_movie).toList())
                .catchError((_) => <HItem>[]),
            onMore: widget.onBrowse,
          ),
      ],
    );
  }

  Widget _shelfFor(XtreamClient c, ShelfRef s) {
    switch (s.type) {
      case 'movie':
        return _Shelf(
          title: s.name,
          future: c.vodStreams(s.id).then((l) => l.take(16).map(_movie).toList()).catchError((_) => <HItem>[]),
          onMore: widget.onBrowse,
        );
      case 'series':
        return _Shelf(
          title: s.name,
          future: c.series(s.id).then((l) => l.take(16).map(_series).toList()).catchError((_) => <HItem>[]),
          onMore: widget.onBrowse,
        );
      default:
        return _Shelf(
          title: 'Live · ${s.name}',
          future: c.liveStreams(s.id).then((l) => _liveShelf(l.take(40).toList())).catchError((_) => <HItem>[]),
          live: true,
          onMore: widget.onBrowse,
        );
    }
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
          child: Icon(Icons.tune_rounded, color: muted, size: 18),
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
                ? Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2))
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
                      color: i == _page ? accent : subtle.withValues(alpha: 0.5),
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
            ColoredBox(color: surfaceHi),
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
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 4),
                        Text('Play', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    if (item.rating > 0)
                      Glass(
                        radius: 12,
                        blur: 8,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.star_rounded, color: gold, size: 15),
                          const SizedBox(width: 3),
                          Text(item.rating.toStringAsFixed(1),
                              style: TextStyle(color: gold, fontWeight: FontWeight.w700, fontSize: 13)),
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
/// A wide continue-watching card: thumbnail + progress bar + resume overlay.
class _ContinueCard extends StatelessWidget {
  final Progress progress;
  final VoidCallback onTap;
  const _ContinueCard({required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: progress.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: progress.poster,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => ColoredBox(color: surfaceHi),
                          )
                        : ColoredBox(color: surfaceHi),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                          stops: [0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress.fraction.toDouble(),
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              progress.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

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
                    ? Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => SizedBox(
                          width: kPosterW,
                          child: live
                              ? ChannelCard(name: items[i].name, logo: items[i].image, index: i, onTap: items[i].onTap)
                              : PosterCard(
                                  name: items[i].name,
                                  image: items[i].image,
                                  rating: items[i].rating,
                                  subtitle: items[i].subtitle.isEmpty ? null : items[i].subtitle,
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

/// Immersive desktop hero: full-bleed backdrop, big title, actions, and a
/// poster rail along the bottom that swaps the spotlight (auto-advances).
class _SpotlightHero extends StatefulWidget {
  final XtreamClient client;
  final Future<List<VodStream>> future;
  final void Function(VodStream) onOpen;
  const _SpotlightHero({required this.client, required this.future, required this.onOpen});
  @override
  State<_SpotlightHero> createState() => _SpotlightHeroState();
}

class _SpotlightHeroState extends State<_SpotlightHero> {
  List<VodStream> _items = [];
  int _index = 0;
  bool _loaded = false;
  Timer? _timer;
  final Map<int, TmdbInfo?> _meta = {};

  @override
  void initState() {
    super.initState();
    widget.future.then((l) {
      if (!mounted) return;
      setState(() {
        _items = l;
        _loaded = true;
      });
      if (l.isNotEmpty) {
        _fetchMeta(l.first);
        _timer = Timer.periodic(const Duration(seconds: 8), (_) => _advance());
      }
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _advance() {
    if (_items.length < 2) return;
    _select((_index + 1) % _items.length);
  }

  void _select(int i) {
    setState(() => _index = i);
    _fetchMeta(_items[i]);
  }

  void _fetchMeta(VodStream m) {
    if (_meta.containsKey(m.streamId)) return;
    _meta[m.streamId] = null;
    Tmdb.movie(m.name).then((t) {
      if (mounted) setState(() => _meta[m.streamId] = t);
    });
  }

  MediaRef _ref(VodStream m) => MediaRef(kind: 'movie', id: m.streamId, name: m.name, image: m.icon, cat: m.categoryId);

  void _play(VodStream m) {
    final ext = m.containerExtension.isEmpty ? 'mp4' : m.containerExtension;
    final url = widget.client.streamUrl('movie', m.streamId, ext: ext);
    PlaybackController.instance.open([
      PlayerItem(url, m.name, progressKey: 'movie:${m.streamId}', poster: m.icon, ext: ext, favRef: _ref(m)),
    ], 0);
  }

  Widget _chip(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    // Loaded but nothing to feature → collapse so the shelves show at the top.
    if (_loaded && _items.isEmpty) return const SizedBox.shrink();
    // Still loading → a bounded placeholder (never an infinite full-screen spin).
    if (_items.isEmpty) {
      return SizedBox(height: 360, child: Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2)));
    }
    final m = _items[_index];
    final t = _meta[m.streamId];
    final backdrop = (t?.backdrop.isNotEmpty == true) ? t!.backdrop : m.icon;
    final rating = (t?.rating ?? 0) > 0 ? t!.rating : m.rating;
    final year = _year(m.name);
    final genre = t?.genres ?? '';
    final overview = t?.overview ?? '';

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: SizedBox.expand(
            key: ValueKey(backdrop),
            child: CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, _, _) => ColoredBox(color: surfaceHi),
            ),
          ),
        ),
        // left + bottom scrims for legibility, fading into the page bg
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [bg, bg.withValues(alpha: 0.45), Colors.transparent],
              stops: const [0.0, 0.35, 0.7],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [bg, bg.withValues(alpha: 0.85), bg.withValues(alpha: 0)],
              stops: const [0.0, 0.22, 0.6],
            ),
          ),
        ),
        // content
        Positioned(
          left: 64,
          bottom: 188,
          child: SizedBox(
            width: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: kHero(color: Colors.white))
                    .animate(key: ValueKey('t${m.streamId}'))
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.15, end: 0),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  if (rating > 0)
                    _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_rounded, color: gold, size: 15),
                      const SizedBox(width: 4),
                      Text(rating.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: 13)),
                    ])),
                  if (year.isNotEmpty) _chip(Text(year, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                  if (genre.isNotEmpty) _chip(Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ]),
                if (overview.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(overview, maxLines: 2, overflow: TextOverflow.ellipsis, style: kBody(color: Colors.white70)),
                ],
                const SizedBox(height: 26),
                Row(children: [
                  PillButton(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => _play(m)),
                  const SizedBox(width: 12),
                  PillButton(icon: Icons.info_outline_rounded, label: 'Details', filled: false, onTap: () => widget.onOpen(m)),
                  const SizedBox(width: 12),
                  AnimatedBuilder(
                    animation: Library.instance,
                    builder: (_, __) {
                      final fav = Library.instance.isFav(_ref(m).key);
                      return GestureDetector(
                        onTap: () => Library.instance.toggleFav(_ref(m)),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Colors.white, size: 22),
                        ),
                      );
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
        // featured poster rail
        Positioned(
          left: 64,
          right: 24,
          bottom: 40,
          height: 122,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final sel = i == _index;
              return GestureDetector(
                onTap: () => _select(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 82,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? accent : Colors.white.withValues(alpha: 0.14), width: sel ? 2.5 : 1),
                    boxShadow: sel ? glow(Colors.black, blur: 16, y: 6) : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _items[i].icon.isNotEmpty
                      ? CachedNetworkImage(imageUrl: _items[i].icon, fit: BoxFit.cover, errorWidget: (_, _, _) => ColoredBox(color: surfaceHi))
                      : ColoredBox(color: surfaceHi),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}
