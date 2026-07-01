import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../models.dart';
import '../playback.dart';
import '../theme.dart';
import '../xtream.dart';

/// In-player catalog browser used by split-screen to pick a second stream —
/// any Live channel, Movie or Series episode. Self-contained (own scroll +
/// drill-down) so it works inside the player's bottom panel, which has no
/// Navigator.
class SplitPicker extends StatefulWidget {
  final XtreamClient client;
  final void Function(PlayerItem) onPick;
  const SplitPicker({super.key, required this.client, required this.onPick});
  @override
  State<SplitPicker> createState() => _SplitPickerState();
}

class _SplitPickerState extends State<SplitPicker> {
  String _section = 'live'; // live | movie | series
  List<Category> _cats = [];
  String? _catId; // null → show categories
  String _catName = '';
  bool _loading = false;
  List<dynamic> _items = []; // LiveStream / VodStream / Series
  Series? _series; // drilled into a series
  SeriesInfo? _info;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    setState(() {
      _loading = true;
      _catId = null;
      _series = null;
      _items = [];
    });
    try {
      final c = widget.client;
      final cats = switch (_section) {
        'movie' => await CatalogCache.instance.vod(c),
        'series' => await CatalogCache.instance.series(c),
        _ => await CatalogCache.instance.live(c),
      };
      if (mounted) setState(() => _cats = cats);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openCat(Category cat) async {
    setState(() {
      _catId = cat.id;
      _catName = cat.name;
      _loading = true;
      _items = [];
    });
    try {
      final c = widget.client;
      final items = switch (_section) {
        'movie' => await c.vodStreams(cat.id),
        'series' => await c.series(cat.id),
        _ => await c.liveStreams(cat.id),
      };
      if (mounted) setState(() => _items = items);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openSeries(Series s) async {
    setState(() {
      _series = s;
      _loading = true;
      _info = null;
    });
    try {
      final info = await widget.client.seriesInfo(s.seriesId);
      if (mounted) setState(() => _info = info);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _back() {
    if (_series != null) {
      setState(() => _series = null);
    } else if (_catId != null) {
      setState(() {
        _catId = null;
        _items = [];
      });
    }
  }

  void _pickLive(LiveStream s) => widget.onPick(PlayerItem(
        widget.client.streamUrl('live', s.streamId, ext: 'ts'),
        s.name,
        isLive: true,
        poster: s.icon,
      ));

  void _pickMovie(VodStream m) => widget.onPick(PlayerItem(
        widget.client.streamUrl('movie', m.streamId, ext: m.containerExtension),
        m.name,
        poster: m.icon,
      ));

  void _pickEpisode(Episode e) {
    final name = e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title;
    widget.onPick(PlayerItem(
      widget.client.streamUrl('series', e.id, ext: e.containerExtension),
      '${_series?.name ?? 'Series'} · $name',
      poster: e.image.isNotEmpty ? e.image : (_info?.cover ?? ''),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canBack = _catId != null || _series != null;
    return Column(
      children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
          child: Row(
            children: [
              if (canBack)
                IconButton(onPressed: _back, icon: Icon(Icons.arrow_back_rounded, color: Colors.white))
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _series?.name ?? (_catId != null ? _catName : 'Watch alongside'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        // section chips (only at the top level)
        if (!canBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final s in const [('live', 'Live'), ('movie', 'Movies'), ('series', 'Series')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _section = s.$1);
                        _loadCats();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _section == s.$1 ? accent : Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(s.$2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _section == s.$1 ? Colors.white : Colors.white70)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty && _info == null && _cats.isEmpty) {
      return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2));
    }
    // series → episodes
    if (_series != null) {
      if (_info == null) return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2));
      final seasons = _info!.episodes.keys.toList()..sort();
      final eps = [for (final s in seasons) ...(_info!.episodes[s] ?? [])];
      if (eps.isEmpty) return _empty('No episodes.');
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: eps.length,
        itemBuilder: (_, i) {
          final e = eps[i];
          return ListTile(
            leading: _thumb(e.image.isNotEmpty ? e.image : _info!.cover, Icons.play_circle_outline_rounded),
            title: Text(e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Episode ${e.episodeNum}', style: TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () => _pickEpisode(e),
          );
        },
      );
    }
    // category list
    if (_catId == null) {
      if (_cats.isEmpty) return _empty('No categories.');
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: _cats.length,
        itemBuilder: (_, i) => ListTile(
          leading: Icon(Icons.folder_rounded, color: accent),
          title: Text(_cats[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.chevron_right_rounded, color: Colors.white54),
          onTap: () => _openCat(_cats[i]),
        ),
      );
    }
    // items in a category
    if (_loading && _items.isEmpty) return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2));
    if (_items.isEmpty) return _empty('Nothing here.');
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final it = _items[i];
        if (it is LiveStream) {
          return ListTile(
            leading: _thumb(it.icon, Icons.live_tv_rounded),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _pickLive(it),
          );
        } else if (it is VodStream) {
          return ListTile(
            leading: _thumb(it.icon, Icons.movie_rounded),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _pickMovie(it),
          );
        } else if (it is Series) {
          return ListTile(
            leading: _thumb(it.cover, Icons.video_library_rounded),
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.chevron_right_rounded, color: Colors.white54),
            onTap: () => _openSeries(it),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _thumb(String url, IconData fallback) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          color: Colors.white.withValues(alpha: 0.08),
          padding: const EdgeInsets.all(4),
          child: url.isNotEmpty
              ? CachedNetworkImage(imageUrl: url, fit: BoxFit.contain, errorWidget: (_, _, _) => Icon(fallback, color: Colors.white54, size: 20))
              : Icon(fallback, color: Colors.white54, size: 20),
        ),
      );

  Widget _empty(String m) => Center(child: Text(m, style: TextStyle(color: Colors.white54)));
}
