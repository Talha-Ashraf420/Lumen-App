import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../catalog_cache.dart';
import '../device_profile.dart';
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

/// Picks the provider's best English-film bucket for the Home spotlight.
/// Xtream category names are provider-defined, so prefer an explicit
/// "English movies" label, then a recent non-CAM English/FHD bucket, and use
/// Hollywood only as a final synonym.
Category? preferredEnglishMovieCategory(Iterable<Category> categories) {
  Category? best;
  var bestScore = 0;
  for (final category in categories) {
    final name = category.name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      ' ',
    );
    final padded = ' $name ';
    final isEnglish = padded.contains(' english ');
    final isHollywood = padded.contains(' hollywood ');
    if (!isEnglish && !isHollywood) continue;
    if (padded.contains(' cam ') ||
        padded.contains(' trailer ') ||
        padded.contains(' series ') ||
        padded.contains(' tv show ')) {
      continue;
    }

    var score = isEnglish ? 700 : 400;
    if (name.trim() == 'english movies') {
      score += 1000;
    } else if (name.contains('english movies')) {
      score += 800;
    }
    if (padded.contains(' fhd ')) score += 30;
    if (padded.contains(' 4k ') || padded.contains(' uhd ')) score += 20;
    final years = RegExp(r'\b(20\d{2})\b').allMatches(name);
    for (final match in years) {
      score += (int.tryParse(match.group(1) ?? '') ?? 2000) - 2000;
    }
    if (score > bestScore) {
      best = category;
      bestScore = score;
    }
  }
  return best;
}

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

class HomeScreen extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onBrowse;
  final FocusNode? entryFocusNode;

  /// Test seam for exercising refresh transitions without opening the
  /// persistent catalog database. Production callers always use the shared
  /// cached provider loader below.
  final Future<List<Category>> Function()? categoryLoader;

  const HomeScreen({
    super.key,
    required this.client,
    required this.onBrowse,
    this.entryFocusNode,
    this.categoryLoader,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<_HomeData> _future;
  _HomeData? _visibleData;
  int _loadGeneration = 0;
  Timer? _catalogRevisionDebounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _beginLoad();
    contentRefresh.addListener(_onRefresh);
    CatalogCache.instance.revision.addListener(_onCatalogRevision);
  }

  @override
  void dispose() {
    _catalogRevisionDebounce?.cancel();
    contentRefresh.removeListener(_onRefresh);
    CatalogCache.instance.revision.removeListener(_onCatalogRevision);
    super.dispose();
  }

  void _onCatalogRevision() {
    _catalogRevisionDebounce?.cancel();
    // One provider refresh may update categories and several item buckets in
    // quick succession. Coalesce those notifications into one quiet upgrade
    // instead of remounting Home repeatedly and flashing its artwork.
    _catalogRevisionDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(_beginLoad);
    });
  }

  void _onRefresh() {
    if (!mounted) return;
    // Keep the currently rendered catalogs in place while fresh data arrives.
    // Pull-to-refresh should feel like an in-place update, not a cold launch.
    setState(_beginLoad);
  }

  Future<void> _pullRefresh() async {
    refreshContent(); // clears caches + bumps the notifier (reloads _future)
    await _future;
  }

  Future<_HomeData> _loadHome() async {
    final categoryLoader = widget.categoryLoader;
    if (categoryLoader != null) return _HomeData(await categoryLoader());
    // Plain M3U profiles are live-only. Do not spend multiple retry windows on
    // movie/series endpoints they can never have before showing their channels.
    if (widget.client.creds.isM3u) return _HomeData(const []);
    // The streamlined Home only needs movie categories for its spotlight.
    // Live, series and full catalog shelves belong on their dedicated tabs.
    final vod = await CatalogCache.instance.vod(widget.client);
    return _HomeData(vod);
  }

  void _beginLoad() {
    final generation = ++_loadGeneration;
    _future = _loadHome().then((data) {
      if (mounted && generation == _loadGeneration) _visibleData = data;
      return data;
    });
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

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
          ),
        ], 0);
    }
  }

  /// A single recently-watched shelf, rebuilt when the library changes.
  Widget _lastPlayedRow() {
    final recent = Library.instance.recent;
    if (recent.isEmpty) return const SizedBox.shrink();
    final posterWidth = DeviceProfile.isTelevision ? 150.0 : kPosterW;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: SectionHeader(title: 'Last played'),
        ),
        SizedBox(
          height: posterWidth * 1.5 + 4,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: DeviceProfile.isTelevision ? 28 : 16,
            ),
            itemCount: recent.length,
            separatorBuilder: (_, _) =>
                SizedBox(width: DeviceProfile.isTelevision ? 16 : 14),
            // Uniform 2:3 cards for movies, series and channels.
            itemBuilder: (_, i) => _RecentCard(
              item: recent[i],
              index: i,
              width: posterWidth,
              onTap: () => _openRecent(recent[i]),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(
      context,
    ); // Rebuild palette-backed cached Home content on mode changes.
    return FutureBuilder<_HomeData>(
      future: _future,
      initialData: _visibleData,
      builder: (context, snap) {
        if (!snap.hasData) {
          return BrandedLoading();
        }
        if (snap.hasError && _visibleData == null) {
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
        final heroCat =
            preferredEnglishMovieCategory(d.vodCats)?.id ??
            (d.vodCats.isEmpty ? null : d.vodCats.first.id);
        final primarySource = heroCat == null
            ? Future.value(const <VodStream>[])
            : CatalogCache.instance
                  .vodStreams(c, heroCat)
                  .catchError((_) => <VodStream>[]);
        final heroFuture = primarySource.then((items) {
          final ranked = moviesRecentlyAdded(
            items.where((m) => m.icon.isNotEmpty),
          );
          return ranked.take(8).toList();
        });
        final hero = _SpotlightHero(
          key: ValueKey('hero:$heroCat'),
          client: c,
          future: heroFuture,
          revision: _loadGeneration,
          onOpen: (m) => _push(MovieDetailScreen(client: c, movie: m)),
          entryFocusNode: widget.entryFocusNode,
        );
        final lastPlayed = AnimatedBuilder(
          animation: Library.instance,
          builder: (_, __) => _lastPlayedRow(),
        );

        if (isWide(context)) {
          return RefreshIndicator(
            onRefresh: _pullRefresh,
            color: accentInk,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: hero),
                SliverToBoxAdapter(child: lastPlayed),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _pullRefresh,
          color: accentInk,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _searchBar(),
              const SizedBox(height: 10),
              hero,
              lastPlayed,
            ],
          ),
        );
      },
    );
  }

  Widget _searchBar() {
    return Padding(
      // The shell owns the persistent account control in the top-right corner.
      // Reserve its footprint so the search affordance never sits underneath.
      padding: const EdgeInsets.fromLTRB(16, 4, 76, 0),
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

/// Immersive desktop hero: full-bleed backdrop, big title, actions, and a
/// poster rail along the bottom that swaps the spotlight (auto-advances).
class _SpotlightHero extends StatefulWidget {
  final XtreamClient client;
  final Future<List<VodStream>> future;
  final int revision;
  final void Function(VodStream) onOpen;
  final FocusNode? entryFocusNode;
  const _SpotlightHero({
    super.key,
    required this.client,
    required this.future,
    required this.revision,
    required this.onOpen,
    this.entryFocusNode,
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
  final List<FocusNode> _railFocusNodes = List.generate(
    8,
    (index) => FocusNode(debugLabel: 'Home spotlight tile $index'),
  );
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.future);
  }

  @override
  void didUpdateWidget(covariant _SpotlightHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load(widget.future);
  }

  void _load(Future<List<VodStream>> future) {
    final request = ++_request;
    future
        .then((l) {
          if (!mounted || request != _request) return;
          // A transient empty provider response must not blank a hero that is
          // already on screen. The next refresh can replace it once reliable
          // content arrives.
          if (l.isEmpty && _items.isNotEmpty) return;
          setState(() {
            _items = l;
            if (_index >= l.length) _index = 0;
            _loaded = true;
          });
          if (l.isNotEmpty) {
            // Enrich only what is visible. The next item loads when selected rather
            // than issuing two TMDB requests for every hero card at startup.
            _fetchMeta(l.first);
            _timer ??= Timer.periodic(
              const Duration(seconds: 8),
              (_) => _advance(),
            );
          }
        })
        .catchError((_) {
          if (mounted && request == _request && _items.isEmpty) {
            setState(() => _loaded = true);
          }
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final node in _railFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleRailKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    final target = index + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
    // Left from the first tile deliberately bubbles to HomeShell, which moves
    // focus to the navigation rail. Keep focus put at the rightmost edge.
    if (target < 0) return KeyEventResult.ignored;
    if (target >= _items.length) return KeyEventResult.handled;

    final targetNode = _railFocusNodes[target];
    final targetContext = targetNode.context;
    if (targetContext == null || !targetContext.mounted) {
      // Let the app's traversal policy reveal a lazily built tile first.
      return KeyEventResult.ignored;
    }
    targetNode.requestFocus();
    return KeyEventResult.handled;
  }

  void _advance() {
    // IndexedStack preserves Home while another tab is open. TickerMode is
    // disabled there, so do not rotate artwork or fetch metadata off-screen.
    if (!TickerMode.of(context) || _items.length < 2) return;
    _select((_index + 1) % _items.length);
  }

  void _select(int i) {
    setState(() => _index = i);
    _fetchMeta(_items[i]);
  }

  void _fetchMeta(VodStream m) {
    if (_meta.containsKey(m.streamId)) return;
    _meta[m.streamId] = null;
    if (widget.client.creds.isDemo) return;
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
                        MediaImage(
                          source: poster,
                          fit: BoxFit.cover,
                          memCacheWidth:
                              (180 * MediaQuery.devicePixelRatioOf(context))
                                  .round()
                                  .clamp(320, 560),
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
                focusNode: widget.entryFocusNode,
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
                  focusNode: _railFocusNodes[i],
                  onKeyEvent: (event) => _handleRailKey(i, event),
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
          child: CircularProgressIndicator(color: accentInk, strokeWidth: 2),
        ),
      );
    }
    final m = _items[_index];
    final t = _meta[m.streamId];
    // Prefer a cinematic 16:9 backdrop when metadata is available. Provider
    // posters remain a reliable fallback while metadata is still loading.
    final poster = (t?.poster.isNotEmpty == true) ? t!.poster : m.icon;
    final heroArt = (t?.backdrop.isNotEmpty == true) ? t!.backdrop : poster;
    final rating = (t?.rating ?? 0) > 0 ? t!.rating : m.rating;
    final year = _year(m.name);
    final genre = t?.genres ?? '';
    final overview = t?.overview ?? '';

    if (!isWide(context))
      return _narrowHero(m, poster, rating, year, genre, overview);

    final h = DeviceProfile.isTelevision
        ? (MediaQuery.sizeOf(context).height * 0.64).clamp(455.0, 520.0)
        : (MediaQuery.sizeOf(context).height * 0.63).clamp(500.0, 610.0);
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
              if (heroArt.isNotEmpty)
                Positioned(
                  left: MediaQuery.sizeOf(context).width * 0.36,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 550),
                    child: MediaImage(
                      key: ValueKey('focus$heroArt'),
                      source: heroArt,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      memCacheWidth:
                          (760 * MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(900, 1800),
                      error: ColoredBox(color: surfaceHi),
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
                left: 42,
                top: 34,
                width: 570,
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
                    const SizedBox(height: 16),
                    Text(
                          _clean(m.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kHero(),
                        )
                        .animate(key: ValueKey('t${m.streamId}'))
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.08, end: 0),
                    const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Text(
                          overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kBody(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        PillButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Watch now',
                          onTap: () => _play(m),
                          focusNode: widget.entryFocusNode,
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
                left: 42,
                right: 28,
                bottom: 20,
                height: DeviceProfile.isTelevision ? 108 : 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _items.length,
                  separatorBuilder: (_, _) =>
                      SizedBox(width: DeviceProfile.isTelevision ? 12 : 10),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final p = _meta[it.streamId]?.poster;
                    final img = (p != null && p.isNotEmpty) ? p : it.icon;
                    return _RailThumb(
                      image: img,
                      label: _clean(it.name),
                      number: i + 1,
                      selected: i == _index,
                      width: DeviceProfile.isTelevision ? 158 : 122,
                      focusNode: _railFocusNodes[i],
                      onKeyEvent: (event) => _handleRailKey(i, event),
                      onFocus: () => _select(i),
                      onTap: () => widget.onOpen(it),
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
  final String label;
  final int number;
  final bool selected;
  final double width;
  final FocusNode? focusNode;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onFocus;
  final VoidCallback onTap;
  const _RailThumb({
    required this.image,
    this.label = '',
    required this.number,
    required this.selected,
    this.width = 112,
    this.focusNode,
    this.onKeyEvent,
    this.onFocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent == null ? null : (_, event) => onKeyEvent!(event),
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
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
              width: width,
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
                        ? MediaImage(
                            source: image,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth:
                                (220 * MediaQuery.devicePixelRatioOf(context))
                                    .round()
                                    .clamp(320, 640),
                            error: ColoredBox(color: surfaceHi),
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
                      top: 7,
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
                    if (label.isNotEmpty)
                      Positioned(
                        left: 9,
                        right: 9,
                        bottom: 7,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
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
  final double width;
  final VoidCallback onTap;
  const _RecentCard({
    required this.item,
    required this.index,
    this.width = kPosterW,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final live = item.isLive;
    return SizedBox(
      width: width,
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
                                  child: MediaImage(
                                    source: item.image,
                                    fit: BoxFit.contain,
                                    memCacheWidth:
                                        (190 *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .round()
                                            .clamp(256, 540),
                                  ),
                                )
                              : MediaImage(
                                  source: item.image,
                                  fit: BoxFit.cover,
                                  memCacheWidth:
                                      (220 *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round()
                                          .clamp(320, 640),
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
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: onAccent,
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
