import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'category_sheet.dart';
import 'movie_detail_screen.dart';
import 'player_screen.dart';
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

  // cached full catalogs (loaded once, filtered locally)
  List<VodStream>? _movies;
  List<Series>? _series;
  List<LiveStream>? _live;
  bool _lm = false, _ls = false, _ll = false;

  List<Category> _movieCats = [], _seriesCats = [], _liveCats = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    c.vodCategories().then((v) => mounted ? setState(() => _movieCats = v) : null).catchError((_) {});
    c.seriesCategories().then((v) => mounted ? setState(() => _seriesCats = v) : null).catchError((_) {});
    c.liveCategories().then((v) => mounted ? setState(() => _liveCats = v) : null).catchError((_) {});
    _ensureFor(_section);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _ensureFor(String section) {
    final c = widget.client;
    void ensureMovies() {
      if (_movies != null || _lm) return;
      _lm = true;
      c.vodStreams(null).then((v) {
        if (mounted) setState(() => _movies = v);
      }).catchError((_) {
        if (mounted) setState(() => _movies = []);
      });
    }

    void ensureSeries() {
      if (_series != null || _ls) return;
      _ls = true;
      c.series(null).then((v) {
        if (mounted) setState(() => _series = v);
      }).catchError((_) {
        if (mounted) setState(() => _series = []);
      });
    }

    void ensureLive() {
      if (_live != null || _ll) return;
      _ll = true;
      c.liveStreams(null).then((v) {
        if (mounted) setState(() => _live = v);
      }).catchError((_) {
        if (mounted) setState(() => _live = []);
      });
    }

    if (section == 'movie') ensureMovies();
    else if (section == 'series') ensureSeries();
    else if (section == 'live') ensureLive();
    else {
      ensureMovies();
      ensureSeries();
      ensureLive();
    }
  }

  // builders → result items
  _Res _movie(VodStream m) => _Res(m.name, m.icon, m.rating, _year(m.name), false,
      () => _push(MovieDetailScreen(client: widget.client, movie: m)));
  _Res _ser(Series s) => _Res(s.name, s.cover, s.rating, _year(s.releaseDate.isEmpty ? s.name : s.releaseDate), false,
      () => _push(SeriesDetailScreen(client: widget.client, seriesId: s.seriesId, title: s.name)));
  _Res _liv(LiveStream s) => _Res(s.name, s.icon, 0, '', true,
      () => _push(PlayerScreen(url: widget.client.streamUrl('live', s.streamId, ext: 'ts'), title: s.name)));

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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Glass(
        radius: 20,
        blur: 16,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                  border: InputBorder.none,
                  hintText: 'Search movies, series, channels…',
                  hintStyle: TextStyle(color: subtle, fontSize: 15),
                ),
              ),
            ),
            if (_q.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() {
                  _q = '';
                  _ctrl.clear();
                }),
                child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close_rounded, color: subtle, size: 20)),
              ),
          ],
        ),
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
              _ensureFor(_section);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: sel ? accentGradient : null,
                color: sel ? null : surfaceHi.withValues(alpha: 0.5),
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

  Widget _categoryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () async {
          final r = await showCategorySheet(context, categories: _curCats, selected: _cat);
          if (r != null && mounted) setState(() => _cat = r);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(13), border: Border.all(color: line)),
          child: Row(children: [
            const Icon(Icons.category_rounded, size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(child: Text(_catLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            const Icon(Icons.expand_more_rounded, color: muted, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    final q = _q.trim().toLowerCase();
    bool m(String s) => q.isEmpty || s.toLowerCase().contains(q);

    if (_section == 'all') {
      if (q.isEmpty) return _prompt();
      // global search across everything
      final loading = _movies == null || _series == null || _live == null;
      final mr = (_movies ?? []).where((x) => m(x.name)).take(18).map(_movie).toList();
      final sr = (_series ?? []).where((x) => m(x.name)).take(18).map(_ser).toList();
      final lr = (_live ?? []).where((x) => m(x.name)).take(18).map(_liv).toList();
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

    // specific section
    final live = _section == 'live';
    final List<_Res> all = switch (_section) {
      'movie' => (_movies)?.map(_movie).toList() ?? const [],
      'series' => (_series)?.map(_ser).toList() ?? const [],
      _ => (_live)?.map(_liv).toList() ?? const [],
    };
    final loaded = switch (_section) {
      'movie' => _movies != null,
      'series' => _series != null,
      _ => _live != null,
    };
    final catId = _cat;
    // category filter needs raw items; rebuild filtered raw lists
    List<_Res> items;
    if (_section == 'movie') {
      items = (_movies ?? []).where((x) => (catId == 'all' || x.categoryId == catId) && m(x.name)).map(_movie).toList();
    } else if (_section == 'series') {
      items = (_series ?? []).where((x) => (catId == 'all' || x.categoryId == catId) && m(x.name)).map(_ser).toList();
    } else {
      items = (_live ?? []).where((x) => (catId == 'all' || x.categoryId == catId) && m(x.name)).map(_liv).toList();
    }

    if (!loaded && all.isEmpty) return const BrandedLoading();
    if (items.isEmpty) return _empty(q.isEmpty ? 'Nothing here.' : 'No results for “$_q”.');

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: live ? 0.80 : 0.52,
        crossAxisSpacing: 13,
        mainAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => PosterCard(
        name: items[i].name,
        image: items[i].image,
        rating: items[i].rating,
        subtitle: live ? null : items[i].subtitle,
        badge: live ? 'LIVE' : null,
        live: live,
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
          height: items.first.live ? 148 : 224,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: items[i].live ? 118 : 122,
              child: PosterCard(
                name: items[i].name,
                image: items[i].image,
                rating: items[i].rating,
                subtitle: items[i].live ? null : items[i].subtitle,
                badge: items[i].live ? 'LIVE' : null,
                live: items[i].live,
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
              child: const Icon(Icons.search_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('Search everything', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 50),
              child: Text('Find movies, series and live channels across your whole library.',
                  textAlign: TextAlign.center, style: TextStyle(color: subtle, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _empty(String msg) => Center(child: Text(msg, style: const TextStyle(color: subtle)));
}
