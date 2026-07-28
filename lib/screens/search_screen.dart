import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../library.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import '../playback.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

String _year(String s) => RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '';

class _Res {
  final String name, image, subtitle;
  final double rating;
  final bool live;
  final VoidCallback onTap;
  _Res(
    this.name,
    this.image,
    this.rating,
    this.subtitle,
    this.live,
    this.onTap,
  );
}

class SearchScreen extends StatefulWidget {
  final XtreamClient client;

  /// When set ('movie' | 'series' | 'live'), the screen opens straight into
  /// that catalog (used by the desktop sidebar's Movies/Series/Live entries).
  final String? initialSection;

  /// Optional category to preselect (used by Home's "See all").
  final String? initialCategory;
  final String? initialCategoryName;
  const SearchScreen({
    super.key,
    required this.client,
    this.initialSection,
    this.initialCategory,
    this.initialCategoryName,
  });
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search library');
  String _q = '';
  late String _section =
      widget.initialSection ?? 'all'; // all | movie | series | live
  late String _cat = widget.initialCategory ?? 'all';
  String _sort = 'default';

  // Streams cached per category id ('all' = whole catalog). Many providers
  // return nothing for the no-category "list all" call, so we fetch per
  // category (like Home does) and aggregate for the 'all' view.
  final Map<String, List<VodStream>> _movieByCat = {};
  final Map<String, List<Series>> _seriesByCat = {};
  final Map<String, List<LiveStream>> _liveByCat = {};
  final Set<String> _inFlight = {};
  final Map<String, bool> _hasMore = {};
  int _resultGeneration = 0;
  static const _pageSize = 48;

  List<Category> _movieCats = [], _seriesCats = [], _liveCats = [];
  bool _movieCatsReady = false;
  bool _seriesCatsReady = false;
  bool _liveCatsReady = false;

  @override
  bool get wantKeepAlive => true;

  int get debugLoadedResultCount => switch (_section) {
    'movie' => _movieByCat[_cat]?.length ?? 0,
    'series' => _seriesByCat[_cat]?.length ?? 0,
    'live' => _liveByCat[_cat]?.length ?? 0,
    _ =>
      (_movieByCat['all']?.length ?? 0) +
          (_seriesByCat['all']?.length ?? 0) +
          (_liveByCat['all']?.length ?? 0),
  };

  @override
  void initState() {
    super.initState();
    _loadCats();
    contentRefresh.addListener(_onRefresh);
    CatalogCache.instance.revision.addListener(_onCatalogRevision);
  }

  void _loadCats() {
    final c = widget.client;
    final wanted = widget.initialSection;
    if (wanted == null || wanted == 'movie') {
      CatalogCache.instance
          .vod(c, priority: true)
          .then((categories) => _storeCategories('movie', categories));
    }
    if (wanted == null || wanted == 'series') {
      CatalogCache.instance
          .series(c, priority: true)
          .then((categories) => _storeCategories('series', categories));
    }
    if (wanted == null || wanted == 'live') {
      CatalogCache.instance
          .live(c, priority: true)
          .then((categories) => _storeCategories('live', categories));
    }
  }

  void _storeCategories(String section, List<Category> categories) {
    if (!mounted) return;
    setState(() {
      switch (section) {
        case 'movie':
          _movieCats = categories;
          _movieCatsReady = true;
        case 'series':
          _seriesCats = categories;
          _seriesCatsReady = true;
        case 'live':
          _liveCats = categories;
          _liveCatsReady = true;
      }
      // Dedicated browse pages open on a focused category instead of issuing
      // an expensive whole-catalog request. “All categories” remains selectable.
      if (_browse &&
          _section == section &&
          widget.initialCategory == null &&
          _cat == 'all' &&
          categories.isNotEmpty) {
        _cat = categories.first.id;
      }
    });
  }

  void _onRefresh() {
    if (!mounted) return;
    setState(() {
      _clearResults();
      _movieCatsReady = false;
      _seriesCatsReady = false;
      _liveCatsReady = false;
      _cat = widget.initialCategory ?? 'all';
    });
    _loadCats();
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_onRefresh);
    CatalogCache.instance.revision.removeListener(_onCatalogRevision);
    _ctrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onCatalogRevision() {
    if (!mounted) return;
    setState(_clearResults);
    _loadCats();
  }

  void focusSearch() {
    _searchFocus.requestFocus();
  }

  bool _has(String section, String cat) => switch (section) {
    'movie' => _movieByCat.containsKey(cat),
    'series' => _seriesByCat.containsKey(cat),
    _ => _liveByCat.containsKey(cat),
  };

  String _pageKey(String section, String cat) => '$section:$cat';

  void _clearResults() {
    _resultGeneration++;
    _movieByCat.clear();
    _seriesByCat.clear();
    _liveByCat.clear();
    _hasMore.clear();
    _inFlight.clear();
  }

  void _changeResults(VoidCallback change) {
    setState(() {
      change();
      _clearResults();
    });
  }

  /// Ensure the first page for (section, category) is loaded. Safe from build.
  void _ensure(String section, String cat) {
    if (_has(section, cat)) return;
    _loadNext(section, cat);
  }

  void _loadNext(String section, String cat) {
    final pageKey = _pageKey(section, cat);
    if (_has(section, cat) && !(_hasMore[pageKey] ?? false)) return;
    final generation = _resultGeneration;
    final requestKey = '$generation:$pageKey';
    if (_inFlight.contains(requestKey)) return;
    _inFlight.add(requestKey);
    final offset = switch (section) {
      'movie' => _movieByCat[cat]?.length ?? 0,
      'series' => _seriesByCat[cat]?.length ?? 0,
      _ => _liveByCat[cat]?.length ?? 0,
    };

    Future<void> finish(Future<void> Function() run) => run()
        .catchError(
          (_) => _storePage(section, cat, const [], false, generation, offset),
        )
        .whenComplete(() => _inFlight.remove(requestKey));

    final categoryId = cat == 'all' ? null : cat;
    switch (section) {
      case 'movie':
        finish(
          () => CatalogCache.instance
              .vodPage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                ),
              ),
        );
      case 'series':
        finish(
          () => CatalogCache.instance
              .seriesPage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                ),
              ),
        );
      default:
        finish(
          () => CatalogCache.instance
              .livePage(
                widget.client,
                categoryId: categoryId,
                offset: offset,
                limit: _pageSize,
                query: _q.trim(),
                sort: _sort,
              )
              .then(
                (page) => _storePage(
                  section,
                  cat,
                  page.items,
                  page.hasMore,
                  generation,
                  offset,
                ),
              ),
        );
    }
  }

  void _storePage(
    String section,
    String cat,
    List<dynamic> values,
    bool hasMore,
    int generation,
    int offset,
  ) {
    if (!mounted || generation != _resultGeneration) return;
    setState(() {
      switch (section) {
        case 'movie':
          _movieByCat[cat] = [
            if (offset > 0) ...?_movieByCat[cat],
            ...values.cast<VodStream>(),
          ];
        case 'series':
          _seriesByCat[cat] = [
            if (offset > 0) ...?_seriesByCat[cat],
            ...values.cast<Series>(),
          ];
        default:
          _liveByCat[cat] = [
            if (offset > 0) ...?_liveByCat[cat],
            ...values.cast<LiveStream>(),
          ];
      }
      _hasMore[_pageKey(section, cat)] = hasMore;
    });
  }

  // builders → result items
  _Res _movie(VodStream m) => _Res(
    m.name,
    m.icon,
    m.rating,
    _year(m.name),
    false,
    () => _push(MovieDetailScreen(client: widget.client, movie: m)),
  );
  _Res _ser(Series s) => _Res(
    s.name,
    s.cover,
    s.rating,
    _year(s.releaseDate.isEmpty ? s.name : s.releaseDate),
    false,
    () => _push(
      SeriesDetailScreen(
        client: widget.client,
        seriesId: s.seriesId,
        title: s.name,
        preview: s,
      ),
    ),
  );
  _Res _liv(LiveStream s) => _Res(
    s.name,
    s.icon,
    0,
    '',
    true,
    () => PlaybackController.instance.open([_liveItem(s)], 0),
  );

  PlayerItem _liveItem(LiveStream s) {
    final url = widget.client.streamUrl('live', s.streamId, ext: 'ts');
    return PlayerItem(
      url,
      s.name,
      isLive: true,
      poster: s.icon,
      httpHeaders: widget.client.streamHeaders(s.streamId),
      favRef: MediaRef(
        kind: 'live',
        id: s.streamId,
        name: s.name,
        image: s.icon,
        url: url,
      ),
      epg: () => widget.client.shortEpg(s.streamId),
    );
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  List<Category> get _curCats => switch (_section) {
    'movie' => _movieCats,
    'series' => _seriesCats,
    'live' => _liveCats,
    _ => const [],
  };

  bool get _curCatsReady => switch (_section) {
    'movie' => _movieCatsReady,
    'series' => _seriesCatsReady,
    'live' => _liveCatsReady,
    _ => true,
  };

  String get _catLabel {
    if (_cat == 'all') return 'All categories';
    return _curCats
        .firstWhere(
          (c) => c.id == _cat,
          orElse: () => Category('all', 'All categories'),
        )
        .name;
  }

  // Dedicated browse mode (Movies / Series / Live sidebar entries): a titled
  // catalog page — no search bar or section chips, just category + sort + grid.
  bool get _browse => widget.initialSection != null;
  String get _sectionTitle => switch (_section) {
    'movie' => 'Movies',
    'series' => 'Series',
    'live' => 'Live TV',
    _ => 'Browse',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Self-contained Scaffold so it renders correctly whether it's a shell tab
    // or pushed as a route (e.g. Home's "See all") — otherwise text loses its
    // theme (red/yellow unstyled rendering) with no Material ancestor.
    final canBack = Navigator.of(context).canPop();
    final wide = isWide(context);
    final body = _browse
        ? Column(
            children: [
              const SizedBox(height: 10),
              _browseHeader(canBack),
              const SizedBox(height: 12),
              if (wide)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _catSidebar(),
                      Expanded(child: _body()),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _catButton(),
                ),
                const SizedBox(height: 8),
                Expanded(child: _body()),
              ],
            ],
          )
        : Column(
            children: [
              const SizedBox(height: 8),
              _searchControls(),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ],
          );
    return Scaffold(
      backgroundColor: canBack ? bg : Colors.transparent,
      body: SafeArea(top: canBack, bottom: false, child: body),
    );
  }

  Widget _browseHeader(bool canBack) {
    return Padding(
      padding: EdgeInsets.fromLTRB(canBack ? 4 : 18, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (canBack)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back_rounded, color: textHi),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.initialCategoryName ?? _sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _section == 'movie'
                      ? Icons.movie_rounded
                      : _section == 'series'
                      ? Icons.video_library_rounded
                      : Icons.live_tv_rounded,
                  color: accentInk,
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _sortButton(),
        ],
      ),
    );
  }

  // ---- pieces ----
  Widget _searchField() => SearchField(
    hint: 'Search movies, series, channels…',
    controller: _ctrl,
    focusNode: _searchFocus,
    onChanged: (v) => _changeResults(() => _q = v),
    trailing: _q.isNotEmpty
        ? RemoteTap(
            semanticLabel: 'Clear search',
            focusRadius: 18,
            onTap: () => _changeResults(() {
              _q = '';
              _ctrl.clear();
              _searchFocus.requestFocus();
            }),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, color: subtle, size: 20),
            ),
          )
        : null,
  );

  Widget _searchControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filters = _section != 'all';
        final roomy = constraints.maxWidth >= 1180;
        final medium = constraints.maxWidth >= 720;

        if (roomy) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 14),
                SizedBox(width: 332, child: _sectionChips()),
                if (filters) ...[
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: _catButton()),
                  const SizedBox(width: 8),
                  _sortButton(),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _searchField(),
              const SizedBox(height: 10),
              if (medium)
                Row(
                  children: [
                    Expanded(child: _sectionChips()),
                    if (filters) ...[
                      const SizedBox(width: 10),
                      SizedBox(width: 220, child: _catButton()),
                      const SizedBox(width: 8),
                      _sortButton(),
                    ],
                  ],
                )
              else ...[
                _sectionChips(),
                if (filters) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _catButton()),
                      const SizedBox(width: 8),
                      _sortButton(),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionChips() {
    const items = [
      (id: 'all', label: 'All'),
      (id: 'movie', label: 'Movies'),
      (id: 'series', label: 'Series'),
      (id: 'live', label: 'Live'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _section == items[i].id;
          return RemoteTap(
            onTap: () => _changeResults(() {
              _section = items[i].id;
              _cat = 'all';
              _sort = 'default';
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: sel ? accent : surfaceHi.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: sel ? Colors.transparent : line),
              ),
              child: Text(
                items[i].label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: sel ? onAccent : muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _sortLabels = {
    'default': 'Default',
    'az': 'A–Z',
    'za': 'Z–A',
    'rating': 'Top rated',
    'recent': 'Recently added',
    'year': 'Newest',
  };

  // Sort → an anchored dropdown menu (not a bottom sheet).
  Widget _sortButton() {
    final entries = _sortLabels.entries
        .where(
          (e) =>
              !(_section == 'live' &&
                  (e.key == 'rating' || e.key == 'recent' || e.key == 'year')),
        )
        .toList();
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line),
      ),
      onSelected: (v) => _changeResults(() => _sort = v),
      itemBuilder: (_) => [
        for (final e in entries)
          PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                Icon(
                  _sort == e.key ? Icons.check_rounded : Icons.sort_rounded,
                  color: _sort == e.key ? accentInk : muted,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  e.value,
                  style: TextStyle(
                    fontWeight: _sort == e.key
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: textHi,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: surfaceHi.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: _sort == 'default' ? muted : accentInk,
            ),
            const SizedBox(width: 6),
            Text(
              _sort == 'default' ? 'Sort' : _sortLabels[_sort]!,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: _sort == 'default' ? textHi : accentInk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Category → anchored dropdown (used on mobile / search mode). No bottom sheet.
  Widget _catButton() {
    return PopupMenuButton<String>(
      tooltip: 'Category',
      color: surface,
      constraints: const BoxConstraints(minWidth: 260, maxHeight: 460),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: line),
      ),
      onSelected: (v) => _changeResults(() => _cat = v),
      itemBuilder: (_) => [
        _catItem('all', 'All categories'),
        for (final c in _curCats) _catItem(c.id, c.name),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceHi.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(Icons.category_rounded, size: 18, color: accentInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _catLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _catItem(String id, String name) {
    final sel = _cat == id;
    return PopupMenuItem(
      value: id,
      child: Row(
        children: [
          if (sel)
            Icon(Icons.check_rounded, color: accentInk, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                color: sel ? textHi : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Desktop browse: a persistent category list beside the grid (no sheet).
  Widget _catSidebar() {
    final cats = <(String, String)>[
      ('all', 'All categories'),
      for (final c in _curCats) (c.id, c.name),
    ];
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: line)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text('CATEGORIES', style: kSection()),
          ),
          for (final (id, name) in cats) _catTile(id, name),
        ],
      ),
    );
  }

  Widget _catTile(String id, String name) {
    final sel = _cat == id;
    return FocusableTap(
      onTap: () => _changeResults(() => _cat = id),
      builder: (context, active) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: sel
              ? accent.withValues(alpha: 0.16)
              : (active
                    ? surfaceHi.withValues(alpha: 0.7)
                    : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 3,
              height: sel ? 16 : 0,
              decoration: BoxDecoration(
                color: accentInk,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                  color: sel ? textHi : muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final q = _q.trim();

    if (_section == 'all') {
      if (q.isEmpty) return _prompt();
      // Each media type queries only its first matching page. Providers that
      // lack a whole-catalog endpoint are imported into SQLite once, then all
      // subsequent searches stay local and paged.
      _ensure('movie', 'all');
      _ensure('series', 'all');
      _ensure('live', 'all');
      final movies = _movieByCat['all'];
      final series = _seriesByCat['all'];
      final live = _liveByCat['all'];
      final loading = movies == null || series == null || live == null;
      final mr = (movies ?? []).take(18).map(_movie).toList();
      final sr = (series ?? []).take(18).map(_ser).toList();
      final lr = (live ?? []).take(18).map(_liv).toList();
      if (loading && mr.isEmpty && sr.isEmpty && lr.isEmpty) {
        return const GridLoading();
      }
      if (mr.isEmpty && sr.isEmpty && lr.isEmpty) {
        return _empty('No results for “$_q”.');
      }
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 120),
        children: [
          if (mr.isNotEmpty) _group('Movies', mr),
          if (sr.isNotEmpty) _group('Series', sr),
          if (lr.isNotEmpty) _group('Channels', lr),
        ],
      );
    }

    // specific section — fetch the selected category directly
    final live = _section == 'live';
    if (_browse && !_curCatsReady) return GridLoading(channel: live);
    final catId = _cat;
    _ensure(_section, catId);
    final loaded = _has(_section, catId);
    final pageKey = _pageKey(_section, catId);
    List<_Res> items;
    if (_section == 'movie') {
      items = (_movieByCat[catId] ?? const []).map(_movie).toList();
    } else if (_section == 'series') {
      items = (_seriesByCat[catId] ?? const []).map(_ser).toList();
    } else {
      // build a shared channel playlist so the player can zap next/previous
      final chans = _liveByCat[catId] ?? const <LiveStream>[];
      final pl = chans.map(_liveItem).toList();
      items = chans
          .asMap()
          .entries
          .map(
            (e) => _Res(
              e.value.name,
              e.value.icon,
              0,
              '',
              true,
              () => PlaybackController.instance.open(pl, e.key),
            ),
          )
          .toList();
    }

    if (!loaded) return GridLoading(channel: live);
    if (items.isEmpty) {
      return _empty(q.isEmpty ? 'Nothing here.' : 'No results for “$_q”.');
    }

    final more = _hasMore[pageKey] ?? false;
    return LayoutBuilder(
      builder: (context, constraints) =>
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (more && notification.metrics.extentAfter < 900) {
                _loadNext(_section, catId);
              }
              return false;
            },
            child: GridView.builder(
              key: PageStorageKey(
                'catalog:${Store.profileScope(widget.client.creds)}:'
                '$_section:$catId:$_sort:$q',
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridColumns(
                  constraints.maxWidth,
                  tile: live ? 150 : 136,
                ),
                // A channel tile is square artwork plus its label. At three
                // columns on a phone, .82 left less room than the label's
                // actual line box and produced a repeating 1.5px overflow.
                childAspectRatio: live ? 0.76 : 0.66,
                crossAxisSpacing: 13,
                mainAxisSpacing: 20,
              ),
              itemCount: items.length + (more ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == items.length) {
                  return Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: accentInk,
                      ),
                    ),
                  );
                }
                return live
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
                        subtitle: items[i].subtitle,
                        index: i,
                        onTap: items[i].onTap,
                      );
              },
            ),
          ),
    );
  }

  Widget _group(String title, List<_Res> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 12),
          child: Text(
            '$title  ·  ${items.length}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: posterShelfHeight(live: items.first.live),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => SizedBox(
              width: kPosterW,
              child: items[i].live
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
                      subtitle: items[i].subtitle,
                      index: i,
                      onTap: items[i].onTap,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _prompt() => Center(
    child: Text(
      'Type a movie, series, or channel name',
      textAlign: TextAlign.center,
      style: TextStyle(color: subtle, fontSize: 14),
    ),
  );

  Widget _empty(String msg) => Center(
    child: Text(msg, style: TextStyle(color: subtle)),
  );
}
