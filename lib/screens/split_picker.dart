import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../models.dart';
import '../playback.dart';
import '../theme.dart';
import '../widgets.dart';
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
        'movie' => await CatalogCache.instance.vod(c, priority: true),
        'series' => await CatalogCache.instance.series(c, priority: true),
        _ => await CatalogCache.instance.live(c, priority: true),
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
        'movie' => await CatalogCache.instance.vodStreams(
          c,
          cat.id,
          priority: true,
        ),
        'series' => await CatalogCache.instance.seriesItems(
          c,
          cat.id,
          priority: true,
        ),
        _ => await CatalogCache.instance.liveStreams(c, cat.id, priority: true),
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
      final info = await CatalogCache.instance.seriesInfo(
        widget.client,
        s.seriesId,
      );
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

  void _pickLive(LiveStream s) => widget.onPick(
    PlayerItem(
      widget.client.streamUrl('live', s.streamId, ext: 'ts'),
      s.name,
      isLive: true,
      poster: s.icon,
      httpHeaders: widget.client.streamHeaders(s.streamId),
    ),
  );

  void _pickMovie(VodStream m) {
    final ext = m.containerExtension.isEmpty ? 'mp4' : m.containerExtension;
    widget.onPick(
      PlayerItem(
        widget.client.streamUrl('movie', m.streamId, ext: ext),
        m.name,
        poster: m.icon,
        ext: ext,
      ),
    );
  }

  void _pickEpisode(Episode e) {
    final name = e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title;
    final ext = e.containerExtension.isEmpty ? 'mp4' : e.containerExtension;
    widget.onPick(
      PlayerItem(
        widget.client.streamUrl('series', e.id, ext: ext),
        '${_series?.name ?? 'Series'} · $name',
        poster: e.image.isNotEmpty ? e.image : (_info?.cover ?? ''),
        ext: ext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canBack = _catId != null || _series != null;
    return Column(
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white54,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
          child: Row(
            children: [
              if (canBack)
                IconButton(
                  autofocus: true,
                  onPressed: _back,
                  icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _series?.name ??
                      (_catId != null ? _catName : 'Watch alongside'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
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
                for (final s in const [
                  ('live', 'Live'),
                  ('movie', 'Movies'),
                  ('series', 'Series'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RemoteTap(
                      autofocus: s.$1 == 'live',
                      onTap: () {
                        setState(() => _section = s.$1);
                        _loadCats();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _section == s.$1
                              ? accent
                              : Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          s.$2,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: _section == s.$1 ? onAccent : Colors.white70,
                          ),
                        ),
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
      return Center(
        child: CircularProgressIndicator(color: accent, strokeWidth: 2),
      );
    }
    // series → episodes
    if (_series != null) {
      if (_info == null) {
        return Center(
          child: CircularProgressIndicator(color: accent, strokeWidth: 2),
        );
      }
      final seasons = _info!.episodes.keys.toList()..sort();
      final eps = [for (final s in seasons) ...(_info!.episodes[s] ?? [])];
      if (eps.isEmpty) return _empty('No episodes.');
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: eps.length,
        itemBuilder: (_, i) {
          final e = eps[i];
          return _pickerRow(
            image: e.image.isNotEmpty ? e.image : _info!.cover,
            fallback: Icons.play_circle_outline_rounded,
            title: Text(
              e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Episode ${e.episodeNum}',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () => _pickEpisode(e),
          );
        },
      );
    }
    // category list
    if (_catId == null) {
      if (_cats.isEmpty) return _empty('No categories.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
        itemCount: _cats.length,
        itemBuilder: (_, i) => _pickerRow(
          image: '',
          fallback: Icons.folder_outlined,
          title: Text(
            _cats[i].name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _section == 'live'
                ? 'Live collection'
                : _section == 'series'
                ? 'Series collection'
                : 'Film collection',
            style: TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: Colors.white54),
          onTap: () => _openCat(_cats[i]),
        ),
      );
    }
    // items in a category
    if (_loading && _items.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: accent, strokeWidth: 2),
      );
    }
    if (_items.isEmpty) return _empty('Nothing here.');
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final it = _items[i];
        if (it is LiveStream) {
          return _pickerRow(
            image: it.icon,
            fallback: Icons.live_tv_rounded,
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text(
              'Add live channel',
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            onTap: () => _pickLive(it),
          );
        } else if (it is VodStream) {
          return _pickerRow(
            image: it.icon,
            fallback: Icons.movie_rounded,
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text(
              'Play alongside',
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            onTap: () => _pickMovie(it),
          );
        } else if (it is Series) {
          return _pickerRow(
            image: it.cover,
            fallback: Icons.video_library_rounded,
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text(
              'Choose an episode',
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: Colors.white54),
            onTap: () => _openSeries(it),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _pickerRow({
    required String image,
    required IconData fallback,
    required Widget title,
    required VoidCallback onTap,
    Widget? subtitle,
    Widget? trailing,
  }) => RemoteTap(
    onTap: onTap,
    focusRadius: 15,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _thumb(image, fallback),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  child: title,
                ),
                if (subtitle != null) ...[const SizedBox(height: 3), subtitle],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ] else
            Icon(Icons.add_rounded, color: accent, size: 19),
        ],
      ),
    ),
  );

  Widget _thumb(String url, IconData fallback) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 44,
      height: 44,
      color: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(4),
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  Icon(fallback, color: Colors.white54, size: 20),
            )
          : Icon(fallback, color: Colors.white54, size: 20),
    ),
  );

  Widget _empty(String m) => Center(
    child: Text(m, style: TextStyle(color: Colors.white54)),
  );
}
