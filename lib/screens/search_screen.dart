import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../library.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../models.dart';
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
  _Res(this.name, this.image, this.rating, this.subtitle, this.live, this.onTap);
}

class SearchScreen extends StatefulWidget {
  final XtreamClient client;
  /// When set ('movie' | 'series' | 'live'), the screen opens straight into
  /// that catalog (used by the desktop sidebar's Movies/Series/Live entries).
  final String? initialSection;
  /// Optional category to preselect (used by Home's "See all").
  final String? initialCategory;
  final String? initialCategoryName;
  const SearchScreen({super.key, required this.client, this.initialSection, this.initialCategory, this.initialCategoryName});
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  String _q = '';
  late String _section = widget.initialSection ?? 'all'; // all | movie | series | live
  late String _cat = widget.initialCategory ?? 'all';
  String _sort = 'default';

  // Streams cached per category id ('all' = whole catalog). Many providers
  // return nothing for the no-category "list all" call, so we fetch per
  // category (like Home does) and aggregate for the 'all' view.
  final Map<String, List<VodStream>> _movieByCat = {};
  final Map<String, List<Series>> _seriesByCat = {};
  final Map<String, List<LiveStream>> _liveByCat = {};
  final Set<String> _inFlight = {};

  List<Category> _movieCats = [], _seriesCats = [], _liveCats = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCats();
    contentRefresh.addListener(_onRefresh);
  }

  void _loadCats() {
    final c = widget.client;
    CatalogCache.instance.vod(c).then((v) => mounted ? setState(() => _movieCats = v) : null);
    CatalogCache.instance.series(c).then((v) => mounted ? setState(() => _seriesCats = v) : null);
    CatalogCache.instance.live(c).then((v) => mounted ? setState(() => _liveCats = v) : null);
  }

  void _onRefresh() {
    if (!mounted) return;
    setState(() {
      _movieByCat.clear();
      _seriesByCat.clear();
      _liveByCat.clear();
    });
    _loadCats();
  }

  @override
  void dispose() {
    contentRefresh.removeListener(_onRefresh);
    _ctrl.dispose();
    super.dispose();
  }

  bool _has(String section, String cat) => switch (section) {
        'movie' => _movieByCat.containsKey(cat),
        'series' => _seriesByCat.containsKey(cat),
        _ => _liveByCat.containsKey(cat),
      };

  /// Ensure the streams for (section, cat) are loaded. Safe to call from build.
  void _ensure(String section, String cat) {
    final key = '$section:$cat';
    if (_has(section, cat) || _inFlight.contains(key)) return;
    _inFlight.add(key);
    Future<void> store(Future<void> Function() run) =>
        run().catchError((_) => _store(section, cat, const [])).whenComplete(() => _inFlight.remove(key));
    switch (section) {
      case 'movie':
        store(() => _loadMovies(cat).then((v) => _store(section, cat, v)));
      case 'series':
        store(() => _loadSeries(cat).then((v) => _store(section, cat, v)));
      default:
        store(() => _loadLive(cat).then((v) => _store(section, cat, v)));
    }
  }

  void _store(String section, String cat, List<dynamic> v) {
    if (!mounted) return;
    setState(() {
      switch (section) {
        case 'movie':
          _movieByCat[cat] = v.cast<VodStream>();
        case 'series':
          _seriesByCat[cat] = v.cast<Series>();
        default:
          _liveByCat[cat] = v.cast<LiveStream>();
      }
    });
  }

  Future<List<VodStream>> _loadMovies(String cat) async {
    if (cat != 'all') return widget.client.vodStreams(cat);
    final all = await widget.client.vodStreams(null).catchError((_) => <VodStream>[]);
    if (all.isNotEmpty || _movieCats.isEmpty) return all;
    return _aggregate(_movieCats, (id) => widget.client.vodStreams(id));
  }

  Future<List<Series>> _loadSeries(String cat) async {
    if (cat != 'all') return widget.client.series(cat);
    final all = await widget.client.series(null).catchError((_) => <Series>[]);
    if (all.isNotEmpty || _seriesCats.isEmpty) return all;
    return _aggregate(_seriesCats, (id) => widget.client.series(id));
  }

  Future<List<LiveStream>> _loadLive(String cat) async {
    if (cat != 'all') return widget.client.liveStreams(cat);
    final all = await widget.client.liveStreams(null).catchError((_) => <LiveStream>[]);
    if (all.isNotEmpty || _liveCats.isEmpty) return all;
    return _aggregate(_liveCats, (id) => widget.client.liveStreams(id));
  }

  /// Concatenate streams across all categories in gentle batches (fallback when
  /// the provider doesn't support the "list all" call).
  Future<List<T>> _aggregate<T>(List<Category> cats, Future<List<T>> Function(String) fetch) async {
    final out = <T>[];
    const batch = 4;
    for (var i = 0; i < cats.length; i += batch) {
      final slice = cats.skip(i).take(batch);
      final res = await Future.wait(slice.map((c) => fetch(c.id).catchError((_) => <T>[])));
      for (final r in res) {
        out.addAll(r);
      }
    }
    return out;
  }

  // builders → result items
  _Res _movie(VodStream m) => _Res(m.name, m.icon, m.rating, _year(m.name), false,
      () => _push(MovieDetailScreen(client: widget.client, movie: m)));
  _Res _ser(Series s) => _Res(s.name, s.cover, s.rating, _year(s.releaseDate.isEmpty ? s.name : s.releaseDate), false,
      () => _push(SeriesDetailScreen(client: widget.client, seriesId: s.seriesId, title: s.name)));
  _Res _liv(LiveStream s) => _Res(s.name, s.icon, 0, '', true,
      () => PlaybackController.instance.open([_liveItem(s)], 0));

  PlayerItem _liveItem(LiveStream s) {
    final url = widget.client.streamUrl('live', s.streamId, ext: 'ts');
    return PlayerItem(url, s.name,
        isLive: true,
        poster: s.icon,
        favRef: MediaRef(kind: 'live', id: s.streamId, name: s.name, image: s.icon, url: url),
        epg: () => widget.client.shortEpg(s.streamId));
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  List<Category> get _curCats => switch (_section) {
        'movie' => _movieCats,
        'series' => _seriesCats,
        'live' => _liveCats,
        _ => const [],
      };

  String get _catLabel {
    if (_cat == 'all') return 'All categories';
    return _curCats.firstWhere((c) => c.id == _cat, orElse: () => Category('all', 'All categories')).name;
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
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _catButton()),
                const SizedBox(height: 8),
                Expanded(child: _body()),
              ],
            ],
          )
        : Column(
            children: [
              const SizedBox(height: 6),
              _searchField(),
              const SizedBox(height: 14),
              _sectionChips(),
              if (_section != 'all') ...[const SizedBox(height: 12), _categoryRow()],
              const SizedBox(height: 6),
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
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back_rounded, color: textHi),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(widget.initialCategoryName ?? _sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                ),
                const SizedBox(width: 12),
                Icon(
                  _section == 'movie'
                      ? Icons.movie_rounded
                      : _section == 'series'
                          ? Icons.video_library_rounded
                          : Icons.live_tv_rounded,
                  color: accent,
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
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SearchField(
        hint: 'Search movies, series, channels…',
        controller: _ctrl,
        onChanged: (v) => setState(() => _q = v),
        trailing: _q.isNotEmpty
            ? GestureDetector(
                onTap: () => setState(() {
                  _q = '';
                  _ctrl.clear();
                }),
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close_rounded, color: subtle, size: 20)),
              )
            : null,
      ),
    );
  }

  Widget _sectionChips() {
    const items = [(id: 'all', label: 'All'), (id: 'movie', label: 'Movies'), (id: 'series', label: 'Series'), (id: 'live', label: 'Live')];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _section == items[i].id;
          return GestureDetector(
            onTap: () => setState(() {
              _section = items[i].id;
              _cat = 'all';
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
              child: Text(items[i].label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sel ? Colors.white : muted)),
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
        .where((e) => !(_section == 'live' && (e.key == 'rating' || e.key == 'recent' || e.key == 'year')))
        .toList();
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: line)),
      onSelected: (v) => setState(() => _sort = v),
      itemBuilder: (_) => [
        for (final e in entries)
          PopupMenuItem(
            value: e.key,
            child: Row(children: [
              Icon(_sort == e.key ? Icons.check_rounded : Icons.sort_rounded, color: _sort == e.key ? accent : muted, size: 18),
              const SizedBox(width: 10),
              Text(e.value, style: TextStyle(fontWeight: _sort == e.key ? FontWeight.w800 : FontWeight.w600, color: textHi)),
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_vert_rounded, size: 18, color: _sort == 'default' ? muted : accent),
          const SizedBox(width: 6),
          Text(_sort == 'default' ? 'Sort' : _sortLabels[_sort]!,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _sort == 'default' ? textHi : accent)),
        ]),
      ),
    );
  }

  // Category → anchored dropdown (used on mobile / search mode). No bottom sheet.
  Widget _catButton() {
    return PopupMenuButton<String>(
      tooltip: 'Category',
      color: surface,
      constraints: const BoxConstraints(minWidth: 260, maxHeight: 460),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: line)),
      onSelected: (v) => setState(() => _cat = v),
      itemBuilder: (_) => [
        _catItem('all', 'All categories'),
        for (final c in _curCats) _catItem(c.id, c.name),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
        child: Row(children: [
          Icon(Icons.category_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(child: Text(_catLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          Icon(Icons.expand_more_rounded, color: muted, size: 20),
        ]),
      ),
    );
  }

  PopupMenuItem<String> _catItem(String id, String name) {
    final sel = _cat == id;
    return PopupMenuItem(
      value: id,
      child: Row(children: [
        if (sel) Icon(Icons.check_rounded, color: accent, size: 18) else const SizedBox(width: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: sel ? textHi : muted))),
      ]),
    );
  }

  // Desktop browse: a persistent category list beside the grid (no sheet).
  Widget _catSidebar() {
    final cats = <(String, String)>[('all', 'All categories'), for (final c in _curCats) (c.id, c.name)];
    return Container(
      width: 240,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: line))),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 10), child: Text('CATEGORIES', style: kSection())),
          for (final (id, name) in cats) _catTile(id, name),
        ],
      ),
    );
  }

  Widget _catTile(String id, String name) {
    final sel = _cat == id;
    return FocusableTap(
      onTap: () => setState(() => _cat = id),
      builder: (context, active) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? accent.withValues(alpha: 0.16) : (active ? surfaceHi.withValues(alpha: 0.7) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 3,
            height: sel ? 16 : 0,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600, fontSize: 14, color: sel ? textHi : muted)),
          ),
        ]),
      ),
    );
  }

  Widget _categoryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: _catButton()),
        const SizedBox(width: 10),
        _sortButton(),
      ]),
    );
  }

  int _yr(String s) => int.tryParse(RegExp(r'(19|20)\d{2}').firstMatch(s)?.group(0) ?? '') ?? 0;

  List<VodStream> _sortMovies(List<VodStream> l) {
    final x = [...l];
    switch (_sort) {
      case 'az':
        x.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'za':
        x.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case 'rating':
        x.sort((a, b) => b.rating.compareTo(a.rating));
      case 'recent':
        x.sort((a, b) => (int.tryParse(b.added) ?? 0).compareTo(int.tryParse(a.added) ?? 0));
      case 'year':
        x.sort((a, b) => _yr(b.name).compareTo(_yr(a.name)));
    }
    return x;
  }

  List<Series> _sortSeries(List<Series> l) {
    final x = [...l];
    switch (_sort) {
      case 'az':
        x.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'za':
        x.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case 'rating':
        x.sort((a, b) => b.rating.compareTo(a.rating));
      case 'year':
      case 'recent':
        x.sort((a, b) => _yr(b.releaseDate).compareTo(_yr(a.releaseDate)));
    }
    return x;
  }

  List<LiveStream> _sortLive(List<LiveStream> l) {
    final x = [...l];
    if (_sort == 'az') x.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_sort == 'za') x.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    return x;
  }

  Widget _body() {
    final q = _q.trim().toLowerCase();
    bool m(String s) => q.isEmpty || s.toLowerCase().contains(q);

    if (_section == 'all') {
      if (q.isEmpty) return _prompt();
      // global search across everything (whole-catalog 'all' lists)
      _ensure('movie', 'all');
      _ensure('series', 'all');
      _ensure('live', 'all');
      final movies = _movieByCat['all'];
      final series = _seriesByCat['all'];
      final live = _liveByCat['all'];
      final loading = movies == null || series == null || live == null;
      final mr = (movies ?? []).where((x) => m(x.name)).take(18).map(_movie).toList();
      final sr = (series ?? []).where((x) => m(x.name)).take(18).map(_ser).toList();
      final lr = (live ?? []).where((x) => m(x.name)).take(18).map(_liv).toList();
      if (loading && mr.isEmpty && sr.isEmpty && lr.isEmpty) return const GridLoading();
      if (mr.isEmpty && sr.isEmpty && lr.isEmpty) return _empty('No results for “$_q”.');
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
    final catId = _cat;
    _ensure(_section, catId);
    final loaded = _has(_section, catId);
    List<_Res> items;
    if (_section == 'movie') {
      items = _sortMovies(_movieByCat[catId] ?? const []).where((x) => m(x.name)).map(_movie).toList();
    } else if (_section == 'series') {
      items = _sortSeries(_seriesByCat[catId] ?? const []).where((x) => m(x.name)).map(_ser).toList();
    } else {
      // build a shared channel playlist so the player can zap next/previous
      final chans = _sortLive(_liveByCat[catId] ?? const <LiveStream>[]).where((x) => m(x.name)).toList();
      final pl = chans.map(_liveItem).toList();
      items = chans
          .asMap()
          .entries
          .map((e) => _Res(e.value.name, e.value.icon, 0, '', true, () => PlaybackController.instance.open(pl, e.key)))
          .toList();
    }

    if (!loaded) return GridLoading(channel: live);
    if (items.isEmpty) return _empty(q.isEmpty ? 'Nothing here.' : 'No results for “$_q”.');

    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns(constraints.maxWidth, tile: live ? 150 : 136),
          childAspectRatio: live ? 0.82 : 0.66,
          crossAxisSpacing: 13,
          mainAxisSpacing: 20,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => live
            ? ChannelCard(name: items[i].name, logo: items[i].image, index: i, onTap: items[i].onTap)
            : PosterCard(
                name: items[i].name,
                image: items[i].image,
                rating: items[i].rating,
                subtitle: items[i].subtitle,
                index: i,
                onTap: items[i].onTap,
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
          child: Text('$title  ·  ${items.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                  ? ChannelCard(name: items[i].name, logo: items[i].image, index: i, onTap: items[i].onTap)
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(Icons.search_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('Search everything', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Text('Find movies, series and live channels across your whole library.',
                  textAlign: TextAlign.center, style: TextStyle(color: subtle, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _empty(String msg) => Center(child: Text(msg, style: TextStyle(color: subtle)));
}
