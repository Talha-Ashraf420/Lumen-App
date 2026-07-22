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
import 'search_screen.dart';
import 'series_detail_screen.dart';

String _year(String s) => RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '';

/// Strip provider filename cruft from a title — year, quality tags, dots — so
/// the hero shows a clean name (e.g. "Soul (2020).(4K)" → "Soul").
String _clean(String s) {
  var t = s;
  t = t.replaceAll(RegExp(r'\((?:19|20)\d{2}\)'), ''); // (2020)
  t = t.replaceAll(
    RegExp(
      r'\b(?:4K|UHD|FHD|HD|SD|HQ|1080p|720p|2160p|HEVC|x26[45]|DV|HDR)\b',
      caseSensitive: false,
    ),
    '',
  );
  t = t.replaceAll(RegExp(r'[._]+'), ' '); // dots/underscores → space
  t = t.replaceAll(
    RegExp(r'\(\s*\)|\[\s*\]'),
    '',
  ); // empty brackets left behind
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  t = t.replaceAll(RegExp(r'[-|·•:]\s*$'), '').trim(); // trailing separators
  return t.isEmpty ? s : t;
}

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

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<_HomeData> _future;
  List<Category> _seriesCats = const [];
  List<Category> _liveCats = const [];
  int _loadGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _beginLoad();
    contentRefresh.addListener(_onRefresh);
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (!mounted) return;
    setState(() {
      _seriesCats = const [];
      _liveCats = const [];
      _beginLoad();
    });
  }

  Future<void> _pullRefresh() async {
    refreshContent(); // clears caches + bumps the notifier (reloads _future)
    await _future;
  }

  Future<_HomeData> _loadHome() async {
    // Home's first paint only needs movie categories. Series and Live follow
    // progressively, so a slow provider cannot hold the entire landing page.
    final vod = await CatalogCache.instance.vod(widget.client);
    return _HomeData(vod);
  }

  void _beginLoad() {
    final generation = ++_loadGeneration;
    _future = _loadHome();
    unawaited(_loadSecondaryCatalogs(generation, _future));
  }

  Future<void> _loadSecondaryCatalogs(
    int generation,
    Future<_HomeData> firstPaint,
  ) async {
    try {
      await firstPaint;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final series = await CatalogCache.instance.series(widget.client);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _seriesCats = series);

      final live = await CatalogCache.instance.live(widget.client);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _liveCats = live);
    } catch (_) {
      // The primary movie experience remains usable if a secondary endpoint
      // fails. The shared cache will retry on the next refresh.
    }
  }

  HItem _movie(VodStream m) => HItem(
    m.name,
    m.icon,
    m.rating,
    _year(m.name),
    () => _push(MovieDetailScreen(client: widget.client, movie: m)),
  );
  HItem _series(Series s) => HItem(
    s.name,
    s.cover,
    s.rating,
    _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
    () => _push(
      SeriesDetailScreen(
        client: widget.client,
        seriesId: s.seriesId,
        title: s.name,
        preview: s,
      ),
    ),
  );

  /// Build a live shelf whose items share one channel playlist (next/prev zap).
  List<HItem> _liveShelf(List<LiveStream> chans) {
    final pl = chans
        .map(
          (s) => PlayerItem(
            widget.client.streamUrl('live', s.streamId, ext: 'ts'),
            s.name,
            isLive: true,
            poster: s.icon,
            httpHeaders: widget.client.streamHeaders(s.streamId),
            favRef: MediaRef(
              kind: 'live',
              id: s.streamId,
              name: s.name,
              image: s.icon,
              url: widget.client.streamUrl('live', s.streamId, ext: 'ts'),
            ),
            epg: () => widget.client.shortEpg(s.streamId),
          ),
        )
        .toList();
    return chans
        .asMap()
        .entries
        .map(
          (e) => HItem(
            e.value.name,
            e.value.icon,
            0,
            'Live',
            () => PlaybackController.instance.open(pl, e.key),
          ),
        )
        .toList();
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  /// Resume a continue-watching entry straight into the player.
  void _resume(Progress pr) {
    PlaybackController.instance.open([
      PlayerItem(
        pr.url,
        pr.title,
        progressKey: pr.key,
        poster: pr.poster,
        ext: pr.ext,
      ),
    ], 0);
  }

  /// Re-open a recently-watched item by reconstructing its destination.
  void _openRecent(MediaRef r) {
    switch (r.kind) {
      case 'movie':
        _push(
          MovieDetailScreen(
            client: widget.client,
            movie: VodStream(r.id, r.name, r.image, '', 'mp4', 0, ''),
          ),
        );
      case 'series':
        _push(
          SeriesDetailScreen(
            client: widget.client,
            seriesId: r.id,
            title: r.name,
          ),
        );
      case 'live':
        PlaybackController.instance.open([
          PlayerItem(
            r.url,
            r.name,
            isLive: true,
            poster: r.image,
            httpHeaders: widget.client.streamHeaders(r.id),
            favRef: r,
            epg: () => widget.client.shortEpg(r.id),
          ),
        ], 0);
    }
  }

  /// Continue-watching + recently-watched rows, rebuilt when the library changes.
  /// [continueRow] is turned off on desktop where the bento tile covers it.
  Widget _libraryRows({bool continueRow = true}) {
    final cont = continueRow
        ? Library.instance.continueWatching()
        : const <Progress>[];
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
              itemBuilder: (_, i) => _ContinueCard(
                progress: cont[i],
                onTap: () => _resume(cont[i]),
              ),
            ),
          ),
        ],
        if (recent.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: SectionHeader(title: 'Jump back in'),
          ),
          SizedBox(
            height: kPosterW * 1.5 + 4,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              // Uniform 2:3 cards for BOTH movies and channels (logo contained on
              // a dark tile), with the title overlaid on a scrim so it's readable.
              itemBuilder: (_, i) => _RecentCard(
                item: recent[i],
                index: i,
                onTap: () => _openRecent(recent[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openMovie(VodStream m) =>
      _push(MovieDetailScreen(client: widget.client, movie: m));

  // ── Bento quick-access row (desktop) ──────────────────────────────────────
  // Big "Continue / Start watching" tile + a Live-now tile + a Surprise-me tile.
  Widget _bentoRow(
    XtreamClient c,
    List<Category> liveCats,
    Future<List<VodStream>> pool,
  ) {
    final pad = isWide(context) ? 20.0 : 16.0;
    if (isWide(context)) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 26, pad, 0),
        child: SizedBox(
          height: 194,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: AnimatedBuilder(
                  animation: Library.instance,
                  builder: (_, __) => _continueTile(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: _liveTile(c, liveCats)),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: _surpriseTile(pool)),
            ],
          ),
        ),
      );
    }
    // Phone: a big Continue tile, then Live + Surprise side by side.
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: AnimatedBuilder(
              animation: Library.instance,
              builder: (_, __) => _continueTile(),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _liveTile(c, liveCats)),
                const SizedBox(width: 14),
                Expanded(child: _surpriseTile(pool)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bentoTile({
    required String? image,
    required IconData icon,
    required String eyebrow,
    required String title,
    String? subtitle,
    double? progress,
    Color? tint,
    IconData? fallbackIcon,
    required VoidCallback onTap,
  }) {
    return HoverScale(
      child: RemoteTap(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: surfaceHi),
              if (image != null && image.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      _bentoFallback(fallbackIcon ?? icon, tint),
                )
              else
                _bentoFallback(fallbackIcon ?? icon, tint),
              // legibility scrim
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Colors.transparent,
                      (tint ?? Colors.black).withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.86),
                    ],
                    stops: const [0.2, 0.55, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 14, color: tint ?? accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            eyebrow.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tint ?? accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    if (progress != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // play affordance
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(
                    icon == Icons.shuffle_rounded
                        ? Icons.shuffle_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bentoFallback(IconData icon, [Color? tint]) {
    final base = tint ?? accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(base.withValues(alpha: 0.55), surfaceHi),
            Color.alphaBlend(base.withValues(alpha: 0.18), surface),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.85),
          size: 42,
        ),
      ),
    );
  }

  Widget _continueTile() {
    final cont = Library.instance.continueWatching();
    if (cont.isEmpty) {
      return _bentoTile(
        image: null,
        icon: Icons.explore_rounded,
        fallbackIcon: Icons.explore_rounded,
        eyebrow: 'Start here',
        title: 'Explore the catalog',
        subtitle: 'Movies · Series · Live TV',
        onTap: widget.onBrowse,
      );
    }
    final pr = cont.first;
    return _bentoTile(
      image: pr.poster,
      icon: Icons.play_arrow_rounded,
      eyebrow: 'Continue watching',
      title: pr.title,
      subtitle: 'Pick up where you left off',
      progress: pr.fraction.toDouble().clamp(0.0, 1.0),
      onTap: () => _resume(pr),
    );
  }

  Widget _liveTile(XtreamClient c, List<Category> liveCats) {
    if (liveCats.isEmpty) {
      return _bentoTile(
        image: null,
        icon: Icons.sensors_rounded,
        fallbackIcon: Icons.live_tv_rounded,
        eyebrow: 'Live TV',
        title: 'Channels, when you want them',
        subtitle: 'Live catalog is loading quietly',
        tint: const Color(0xFFFF5A5F),
        onTap: widget.onBrowse,
      );
    }
    return FutureBuilder<List<LiveStream>>(
      future: CatalogCache.instance
          .liveStreams(c, liveCats.first.id)
          .then((l) => l.take(1).toList())
          .catchError((_) => <LiveStream>[]),
      builder: (_, snap) {
        final chan = (snap.data ?? const <LiveStream>[]).isNotEmpty
            ? snap.data!.first
            : null;
        return _bentoTile(
          // Channel logos are transparent PNGs that look bad stretched — use the
          // branded red gradient instead and just show the channel name.
          image: null,
          icon: Icons.sensors_rounded,
          fallbackIcon: Icons.live_tv_rounded,
          eyebrow: '● Live now',
          title: chan?.name ?? 'Live TV',
          subtitle: 'Jump into a channel',
          tint: const Color(0xFFFF5A5F),
          onTap: () {
            if (chan == null) return widget.onBrowse();
            final items = _liveShelf([chan]);
            items.first.onTap();
          },
        );
      },
    );
  }

  Widget _surpriseTile(Future<List<VodStream>> pool) {
    return FutureBuilder<List<VodStream>>(
      future: pool,
      builder: (_, snap) {
        final list = snap.data ?? const <VodStream>[];
        VodStream? pick;
        if (list.isNotEmpty) {
          pick = list[DateTime.now().millisecondsSinceEpoch % list.length];
        }
        return _bentoTile(
          image: pick?.icon,
          icon: Icons.shuffle_rounded,
          fallbackIcon: Icons.casino_rounded,
          eyebrow: 'Surprise me',
          title: pick?.name ?? 'Feeling lucky?',
          subtitle: 'A random pick for you',
          tint: gold,
          onTap: () => pick != null ? _openMovie(pick) : widget.onBrowse(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return BrandedLoading();
        }
        if (snap.hasError || snap.data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${snap.error ?? "Couldn't load."}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF8FA3)),
              ),
            ),
          );
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
              final mv = HomeConfig.instance.shelves.where(
                (s) => s.type == 'movie',
              );
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
              final seriesCats = _seriesCats.take(3).toList();
              for (var i = 0; i < movieCats.length; i++) {
                shelves.add(
                  _shelfFor(
                    c,
                    ShelfRef('movie', movieCats[i].id, movieCats[i].name),
                  ),
                );
                if (i < seriesCats.length) {
                  shelves.add(
                    _shelfFor(
                      c,
                      ShelfRef('series', seriesCats[i].id, seriesCats[i].name),
                    ),
                  );
                }
              }
              if (_liveCats.isNotEmpty) {
                shelves.add(
                  _shelfFor(
                    c,
                    ShelfRef('live', _liveCats.first.id, _liveCats.first.name),
                  ),
                );
              }
            }

            // Two focused category calls replace the previous whole-catalog
            // download. They are shared with shelves/Search by CatalogCache.
            final primarySource = heroCat == null
                ? Future.value(const <VodStream>[])
                : CatalogCache.instance
                      .vodStreams(c, heroCat)
                      .catchError((_) => <VodStream>[]);
            final trendCat = d.vodCats.length > 1 ? d.vodCats[1].id : heroCat;
            final trendSource = trendCat == null
                ? Future.value(const <VodStream>[])
                : CatalogCache.instance
                      .vodStreams(c, trendCat)
                      .catchError((_) => <VodStream>[]);
            final heroFuture = primarySource.then((items) {
              final ranked = items.where((m) => m.icon.isNotEmpty).toList()
                ..sort(
                  (a, b) => (int.tryParse(b.added) ?? 0).compareTo(
                    int.tryParse(a.added) ?? 0,
                  ),
                );
              return ranked.take(8).toList();
            });
            final trendFuture = trendSource.then((items) {
              final ranked = items.where((m) => m.icon.isNotEmpty).toList()
                ..sort((a, b) => b.rating.compareTo(a.rating));
              return ranked.take(10).toList();
            });

            // Continue watching is the big bento tile, so the shelf below only
            // shows "Jump back in" (recent) to avoid duplication.
            final content = <Widget>[
              AnimatedBuilder(
                animation: Library.instance,
                builder: (_, __) => _libraryRows(continueRow: false),
              ),
              _bentoRow(c, _liveCats, trendFuture),
              if (heroCat != null)
                _Shelf(
                  key: ValueKey('$_loadGeneration:fresh:$heroCat'),
                  title: 'Fresh picks',
                  load: () => primarySource.then((items) {
                    final ranked =
                        items.where((m) => m.icon.isNotEmpty).toList()..sort(
                          (a, b) => (int.tryParse(b.added) ?? 0).compareTo(
                            int.tryParse(a.added) ?? 0,
                          ),
                        );
                    return ranked.skip(8).take(20).map(_movie).toList();
                  }),
                  onMore: d.vodCats.isNotEmpty
                      ? () => _openCategory(
                          c,
                          'movie',
                          heroCat!,
                          d.vodCats
                              .firstWhere(
                                (cat) => cat.id == heroCat,
                                orElse: () => d.vodCats.first,
                              )
                              .name,
                        )
                      : null,
                ),
              _TopTenShelf(
                future: trendFuture,
                onTap: (m) => _push(MovieDetailScreen(client: c, movie: m)),
              ),
              AnimatedBuilder(
                animation: Library.instance,
                builder: (_, __) => _recommendationRows(c, d.vodCats),
              ),
              ...shelves,
            ];

            final hero = _SpotlightHero(
              key: ValueKey('hero:$_loadGeneration'),
              client: c,
              future: heroFuture,
              onOpen: (m) => _push(MovieDetailScreen(client: c, movie: m)),
            );

            if (isWide(context)) {
              return RefreshIndicator(
                onRefresh: _pullRefresh,
                color: accent,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: hero),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(children: content),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              );
            }

            // Phone: same content, hero laid out compactly (poster on top).
            return RefreshIndicator(
              onRefresh: _pullRefresh,
              color: accent,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  _searchBar(),
                  const SizedBox(height: 10),
                  hero,
                  ...content,
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
    for (final m in [
      ...Library.instance.favourites,
      ...Library.instance.recent,
    ]) {
      if (m.kind == 'movie' && m.cat.isNotEmpty)
        freq[m.cat] = (freq[m.cat] ?? 0) + 1;
    }
    final sorted = freq.keys.toList()
      ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
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
            key: ValueKey('$_loadGeneration:taste:${cat.id}'),
            title: 'Because you like ${cat.name}',
            load: () => CatalogCache.instance
                .vodStreams(c, cat.id)
                .then(
                  (l) => l
                      .where((m) => m.icon.isNotEmpty)
                      .take(16)
                      .map(_movie)
                      .toList(),
                )
                .catchError((_) => <HItem>[]),
            onMore: () => _openCategory(c, 'movie', cat.id, cat.name),
          ),
      ],
    );
  }

  /// "See all" → open that shelf's category as a full browse grid.
  void _openCategory(XtreamClient c, String section, String id, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          client: c,
          initialSection: section,
          initialCategory: id,
          initialCategoryName: name,
        ),
      ),
    );
  }

  Widget _shelfFor(XtreamClient c, ShelfRef s) {
    switch (s.type) {
      case 'movie':
        return _Shelf(
          key: ValueKey('$_loadGeneration:movie:${s.id}'),
          title: s.name,
          load: () => CatalogCache.instance
              .vodStreams(c, s.id)
              .then((l) => l.take(16).map(_movie).toList())
              .catchError((_) => <HItem>[]),
          onMore: () => _openCategory(c, 'movie', s.id, s.name),
        );
      case 'series':
        return _Shelf(
          key: ValueKey('$_loadGeneration:series:${s.id}'),
          title: s.name,
          load: () => CatalogCache.instance
              .seriesItems(c, s.id)
              .then((l) => l.take(16).map(_series).toList())
              .catchError((_) => <HItem>[]),
          onMore: () => _openCategory(c, 'series', s.id, s.name),
        );
      default:
        return _Shelf(
          key: ValueKey('$_loadGeneration:live:${s.id}'),
          title: 'Live · ${s.name}',
          load: () => CatalogCache.instance
              .liveStreams(c, s.id)
              .then((l) => _liveShelf(l.take(40).toList()))
              .catchError((_) => <HItem>[]),
          live: true,
          onMore: () => _openCategory(c, 'live', s.id, s.name),
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
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.tune_rounded, color: muted, size: 18),
        ),
      ),
    );
  }
}

class _HomeData {
  final List<Category> vodCats;
  _HomeData(this.vodCats);
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
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: snap.connectionState != ConnectionState.done
                ? Center(
                    child: CircularProgressIndicator(
                      color: accent,
                      strokeWidth: 2,
                    ),
                  )
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
                      color: i == _page
                          ? accent
                          : subtle.withValues(alpha: 0.5),
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
    return RemoteTap(
      onTap: item.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: surfaceHi),
            if (item.image.isNotEmpty)
              CachedNetworkImage(imageUrl: item.image, fit: BoxFit.cover),
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
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Play',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (item.rating > 0)
                        Glass(
                          radius: 12,
                          blur: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: gold, size: 15),
                              const SizedBox(width: 3),
                              Text(
                                item.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: gold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
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
    return RemoteTap(
      onTap: onTap,
      child: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AspectRatio is the PARENT and the Stack fills it, so the play
            // button, gradient and progress bar all align to the 16:9 thumbnail.
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    progress.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: progress.poster,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: surfaceHi),
                          )
                        : ColoredBox(color: surfaceHi),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                          stops: [0.55, 1],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
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

class _Shelf extends StatefulWidget {
  final String title;
  final Future<List<HItem>> Function() load;
  final bool live;
  final VoidCallback? onMore;
  const _Shelf({
    super.key,
    required this.title,
    required this.load,
    this.live = false,
    this.onMore,
  });

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  Future<List<HItem>>? _future;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_checkVisibility);
      _position = next;
      _position?.addListener(_checkVisibility);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void dispose() {
    _position?.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted || _future != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final viewport = MediaQuery.sizeOf(context).height;
    // Start just before the shelf enters view. This keeps scrolling fluid while
    // avoiding network work for shelves the viewer may never reach.
    if (_position == null ||
        (top < viewport * 1.65 && bottom > -viewport * .4)) {
      final future = widget.load();
      setState(() {
        _future = future;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    final h = posterShelfHeight(live: widget.live);
    if (future == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: widget.title, onSeeAll: widget.onMore),
            SizedBox(
              height: h,
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, __) => Container(
                  width: kPosterW,
                  decoration: BoxDecoration(
                    color: surfaceHi.withValues(alpha: .46),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: line),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return FutureBuilder<List<HItem>>(
      future: future,
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (snap.connectionState == ConnectionState.done && items.isEmpty)
          return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: widget.title, onSeeAll: widget.onMore),
              SizedBox(
                height: h,
                child: items.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2,
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => SizedBox(
                          width: kPosterW,
                          child: widget.live
                              ? ChannelCard(
                                  name: items[i].name,
                                  logo: items[i].image,
                                  index: i,
                                  onTap: items[i].onTap,
                                )
                              : PosterCard(
                                  name: items[i].name,
                                  image: items[i].image,
                                  rating: items[i].rating,
                                  subtitle: items[i].subtitle.isEmpty
                                      ? null
                                      : items[i].subtitle,
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
  const _SpotlightHero({
    super.key,
    required this.client,
    required this.future,
    required this.onOpen,
  });
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
    widget.future
        .then((l) {
          if (!mounted) return;
          setState(() {
            _items = l;
            _loaded = true;
          });
          if (l.isNotEmpty) {
            // Enrich only what is visible. The next item loads when selected rather
            // than issuing two TMDB requests for every hero card at startup.
            _fetchMeta(l.first);
            _timer = Timer.periodic(
              const Duration(seconds: 8),
              (_) => _advance(),
            );
          }
        })
        .catchError((_) {
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

  MediaRef _ref(VodStream m) => MediaRef(
    kind: 'movie',
    id: m.streamId,
    name: m.name,
    image: m.icon,
    cat: m.categoryId,
  );

  void _play(VodStream m) {
    final ext = m.containerExtension.isEmpty ? 'mp4' : m.containerExtension;
    final url = widget.client.streamUrl('movie', m.streamId, ext: ext);
    PlaybackController.instance.open([
      PlayerItem(
        url,
        m.name,
        progressKey: 'movie:${m.streamId}',
        poster: m.icon,
        ext: ext,
        favRef: _ref(m),
      ),
    ], 0);
  }

  Widget _chip(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: surfaceHi,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: line),
    ),
    child: child,
  );

  // Phone hero: poster on top, centred title / meta / actions, rail below.
  Widget _narrowHero(
    VodStream m,
    String poster,
    double rating,
    String year,
    String genre,
    String overview,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                scale: Tween(begin: 0.97, end: 1.0).animate(a),
                child: c,
              ),
            ),
            child: Container(
              key: ValueKey('ncard$poster'),
              width: 152,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 34,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: surfaceHi),
                      if (poster.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'FEATURED',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _clean(m.name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: kTitle(),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rating > 0)
                _chip(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, color: gold, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              if (year.isNotEmpty)
                _chip(
                  Text(
                    year,
                    style: TextStyle(
                      color: textHi,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if (genre.isNotEmpty)
                _chip(
                  Text(genre, style: TextStyle(color: muted, fontSize: 12.5)),
                ),
            ],
          ),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              overview,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: kBody(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PillButton(
                icon: Icons.play_arrow_rounded,
                label: 'Play',
                onTap: () => _play(m),
              ),
              const SizedBox(width: 10),
              HoverScale(
                child: RemoteTap(
                  onTap: () => widget.onOpen(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: surfaceHi,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: line),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: textHi,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedBuilder(
                animation: Library.instance,
                builder: (_, __) {
                  final fav = Library.instance.isFav(_ref(m).key);
                  return RemoteTap(
                    onTap: () => Library.instance.toggleFav(_ref(m)),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: surfaceHi,
                        border: Border.all(color: line),
                      ),
                      child: Icon(
                        fav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: fav ? accent : textHi,
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final it = _items[i];
                final p = _meta[it.streamId]?.poster;
                final img = (p != null && p.isNotEmpty) ? p : it.icon;
                return _RailThumb(
                  image: img,
                  number: i + 1,
                  selected: i == _index,
                  onTap: () => _select(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Loaded but nothing to feature → collapse so the shelves show at the top.
    if (_loaded && _items.isEmpty) return const SizedBox.shrink();
    // Still loading → a bounded placeholder (never an infinite full-screen spin).
    if (_items.isEmpty) {
      return SizedBox(
        height: 360,
        child: Center(
          child: CircularProgressIndicator(color: accent, strokeWidth: 2),
        ),
      );
    }
    final m = _items[_index];
    final t = _meta[m.streamId];
    // Poster-driven: use the reliable portrait poster for BOTH the sharp hero
    // card and the blurred background — so a wrong/ugly TMDB backdrop can never
    // wreck the hero. The blur turns any image into a tasteful colour wash.
    final poster = (t?.poster.isNotEmpty == true) ? t!.poster : m.icon;
    final rating = (t?.rating ?? 0) > 0 ? t!.rating : m.rating;
    final year = _year(m.name);
    final genre = t?.genres ?? '';
    final overview = t?.overview ?? '';

    if (!isWide(context))
      return _narrowHero(m, poster, rating, year, genre, overview);

    final h = (MediaQuery.sizeOf(context).height * 0.63).clamp(500.0, 610.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: SizedBox(
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: surface),
              if (poster.isNotEmpty)
                Positioned(
                  left: MediaQuery.sizeOf(context).width * 0.42,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 550),
                    child: CachedNetworkImage(
                      key: ValueKey('focus$poster'),
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      errorWidget: (_, _, _) => ColoredBox(color: surfaceHi),
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0, 0.48, 0.82, 1],
                    colors: [
                      surface,
                      surface,
                      surface.withValues(alpha: 0.60),
                      surface.withValues(alpha: 0.08),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 46,
                top: 42,
                width: 610,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 28, height: 2, color: accent),
                        const SizedBox(width: 10),
                        Text('NOW IN FOCUS', style: kSection(color: accent)),
                        const SizedBox(width: 12),
                        Text(
                          '${(_index + 1).toString().padLeft(2, '0')} / ${_items.length.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: subtle,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                          _clean(m.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kHero(),
                        )
                        .animate(key: ValueKey('t${m.streamId}'))
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.08, end: 0),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (rating > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: gold, size: 15),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: textHi,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        if (year.isNotEmpty)
                          Text(
                            year,
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        if (genre.isNotEmpty)
                          Text(
                            genre,
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                      ],
                    ),
                    if (overview.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Text(
                          overview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: kBody(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 23),
                    Row(
                      children: [
                        PillButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Watch now',
                          onTap: () => _play(m),
                        ),
                        const SizedBox(width: 10),
                        PillButton(
                          icon: Icons.arrow_outward_rounded,
                          label: 'Details',
                          filled: false,
                          onTap: () => widget.onOpen(m),
                        ),
                        const SizedBox(width: 10),
                        AnimatedBuilder(
                          animation: Library.instance,
                          builder: (_, __) {
                            final fav = Library.instance.isFav(_ref(m).key);
                            return FocusableTap(
                              onTap: () => Library.instance.toggleFav(_ref(m)),
                              builder: (_, active) => AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 47,
                                height: 47,
                                decoration: BoxDecoration(
                                  color: active ? surfaceHi : surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: active ? accent : line,
                                  ),
                                ),
                                child: Icon(
                                  fav
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: fav ? accent : textHi,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 46,
                right: 30,
                bottom: 24,
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final p = _meta[it.streamId]?.poster;
                    final img = (p != null && p.isNotEmpty) ? p : it.icon;
                    return _RailThumb(
                      image: img,
                      number: i + 1,
                      selected: i == _index,
                      onTap: () => _select(i),
                    );
                  },
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single poster in the hero's "Featured" rail — sharp TMDB poster, dimmed
/// when inactive, accent-ringed + glowing + scaled-up when active or hovered.
class _RailThumb extends StatelessWidget {
  final String image;
  final int number;
  final bool selected;
  final VoidCallback onTap;
  const _RailThumb({
    required this.image,
    required this.number,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) {
        return AnimatedScale(
          scale: active ? 1.025 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: AnimatedOpacity(
            opacity: selected ? 1 : (active ? 0.92 : 0.58),
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width: 112,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? accent : line,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: -2,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            filterQuality: FilterQuality.high,
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: surfaceHi),
                          )
                        : ColoredBox(color: surfaceHi),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.72),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Text(
                        number.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Uniform "Jump back in" card — one 2:3 tile for movies AND channels. Channel
/// logos are contained on a dark tile (not stretched); every card carries a
/// bottom scrim so the title stays readable in either theme.
class _RecentCard extends StatelessWidget {
  final MediaRef item;
  final int index;
  final VoidCallback onTap;
  const _RecentCard({
    required this.item,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final live = item.isLive;
    return SizedBox(
      width: kPosterW,
      child:
          FocusableTap(
                onTap: onTap,
                builder: (context, active) => AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [surfaceHi, surface],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        if (item.image.isNotEmpty)
                          live
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    20,
                                    18,
                                    46,
                                  ),
                                  child: CachedNetworkImage(
                                    imageUrl: item.image,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: item.image,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
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
                        if (live)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B41),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: Colors.white,
                                    size: 6,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          left: 11,
                          right: 11,
                          bottom: 10,
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: active ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.32),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                  boxShadow: glow(accent),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 320.ms, delay: (index.clamp(0, 12) * 30).ms)
              .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
    );
  }
}

/// "Top 10" shelf — big hollow rank numerals with the poster overlapping.
class _TopTenShelf extends StatelessWidget {
  final Future<List<VodStream>> future;
  final void Function(VodStream) onTap;
  const _TopTenShelf({required this.future, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VodStream>>(
      future: future,
      builder: (context, snap) {
        final items = snap.data ?? const <VodStream>[];
        if (snap.connectionState == ConnectionState.done && items.isEmpty)
          return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Top 10 this week'),
              SizedBox(
                height: 196,
                child: items.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2,
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => _TopTenCard(
                          rank: i + 1,
                          movie: items[i],
                          onTap: () => onTap(items[i]),
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

class _TopTenCard extends StatelessWidget {
  final int rank;
  final VodStream movie;
  final VoidCallback onTap;
  const _TopTenCard({
    required this.rank,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const posterW = 118.0;
    final wide = rank == 10;
    final numberStyle = TextStyle(
      fontSize: 150,
      height: 0.86,
      fontWeight: FontWeight.w900,
      letterSpacing: wide ? -14 : -4,
    );
    return HoverScale(
      child: RemoteTap(
        onTap: onTap,
        child: SizedBox(
          width: wide ? 178 : 158,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // hollow rank numeral, bottom-left, behind the poster
              Positioned(
                left: -6,
                bottom: 2,
                child: Stack(
                  children: [
                    Text(
                      '$rank',
                      style: numberStyle.copyWith(
                        color: textHi.withValues(alpha: 0.06),
                      ),
                    ),
                    Text(
                      '$rank',
                      style: numberStyle.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 3
                          ..color = accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              // poster pinned right
              Positioned(
                right: 0,
                top: 8,
                width: posterW,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: surfaceHi),
                        if (movie.icon.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: movie.icon,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: surfaceHi),
                          ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
