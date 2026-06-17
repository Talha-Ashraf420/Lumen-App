import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../library.dart';
import '../responsive.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import '../playback.dart';
import 'category_sheet.dart';
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
  const SearchScreen({super.key, required this.client});
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  String _q = '';
  String _section = 'all'; // all | movie | series | live
  String _cat = 'all';
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
    final c = widget.client;
    CatalogCache.instance.vod(c).then((v) => mounted ? setState(() => _movieCats = v) : null);
    CatalogCache.instance.series(c).then((v) => mounted ? setState(() => _seriesCats = v) : null);
    CatalogCache.instance.live(c).then((v) => mounted ? setState(() => _liveCats = v) : null);
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
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

  Future<void> _pickSort() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('Sort by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ),
            for (final e in _sortLabels.entries)
              if (!(_section == 'live' && (e.key == 'rating' || e.key == 'recent' || e.key == 'year')))
                ListTile(
                  onTap: () => Navigator.pop(context, e.key),
                  leading: Icon(_sort == e.key ? Icons.check_circle_rounded : Icons.sort_rounded, color: _sort == e.key ? accent : muted),
                  title: Text(e.value, style: TextStyle(fontWeight: _sort == e.key ? FontWeight.w700 : FontWeight.w500)),
                ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (r != null && mounted) setState(() => _sort = r);
  }

  Widget _categoryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final r = await showCategorySheet(context, categories: _curCats, selected: _cat);
                if (r != null && mounted) setState(() => _cat = r);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
                child: Row(children: [
                  Icon(Icons.category_rounded, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_catLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Icon(Icons.expand_more_rounded, color: muted, size: 20),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _pickSort,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.swap_vert_rounded, size: 18, color: _sort == 'default' ? muted : accent),
                if (_sort != 'default') ...[
                  const SizedBox(width: 6),
                  Text(_sortLabels[_sort]!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: accent)),
                ],
              ]),
            ),
          ),
        ],
      ),
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
      if (loading && mr.isEmpty && sr.isEmpty && lr.isEmpty) return const BrandedLoading();
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

    if (!loaded) return const BrandedLoading();
    if (items.isEmpty) return _empty(q.isEmpty ? 'Nothing here.' : 'No results for “$_q”.');

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns(MediaQuery.sizeOf(context).width, tile: live ? 150 : 132),
        childAspectRatio: live ? 0.82 : 0.50,
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
