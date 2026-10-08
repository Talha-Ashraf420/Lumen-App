import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../library.dart';
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
  final VoidCallback? onClose;
  final String? primaryUrl;
  final String? secondaryUrl;
  const SplitPicker({
    super.key,
    required this.client,
    required this.onPick,
    this.onClose,
    this.primaryUrl,
    this.secondaryUrl,
  });
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
  final _search = TextEditingController();
  String _query = '';
  String? _error;
  int _generation = 0;
  final _contentFocus = FocusNode(debugLabel: 'Split browser first result');

  void _focusResults() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _contentFocus.context != null) {
        _contentFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    _query = '';
  }

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final generation = ++_generation;
    final section = _section;
    setState(() {
      _clearSearch();
      _error = null;
      _cats = [];
      _info = null;
      _loading = true;
      _catId = null;
      _series = null;
      _items = [];
    });
    try {
      final c = widget.client;
      final cats = switch (section) {
        'movie' => await CatalogCache.instance.vod(c, priority: true),
        'series' => await CatalogCache.instance.series(c, priority: true),
        _ => await CatalogCache.instance.live(c, priority: true),
      };
      if (mounted && generation == _generation) setState(() => _cats = cats);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load categories.');
      }
    }
    if (mounted && generation == _generation) setState(() => _loading = false);
  }

  Future<void> _openCat(Category cat) async {
    final generation = ++_generation;
    final section = _section;
    setState(() {
      _clearSearch();
      _error = null;
      _info = null;
      _catId = cat.id;
      _catName = cat.name;
      _loading = true;
      _items = [];
    });
    try {
      final c = widget.client;
      final items = switch (section) {
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
      if (mounted && generation == _generation) setState(() => _items = items);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load this collection.');
      }
    }
    if (mounted && generation == _generation) {
      setState(() => _loading = false);
      _focusResults();
    }
  }

  Future<void> _openSeries(Series s) async {
    final generation = ++_generation;
    setState(() {
      _clearSearch();
      _error = null;
      _series = s;
      _loading = true;
      _info = null;
    });
    try {
      final info = await CatalogCache.instance.seriesInfo(
        widget.client,
        s.seriesId,
      );
      if (mounted && generation == _generation) setState(() => _info = info);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load episodes.');
      }
    }
    if (mounted && generation == _generation) {
      setState(() => _loading = false);
      _focusResults();
    }
  }

  void _back() {
    _generation++;
    _loading = false;
    _error = null;
    _clearSearch();
    if (_series != null) {
      setState(() => _series = null);
    } else if (_catId != null) {
      setState(() {
        _catId = null;
        _items = [];
      });
    }
    _focusResults();
  }

  void _pickLive(LiveStream s) => widget.onPick(
    PlayerItem(
      widget.client.streamUrl('live', s.streamId, ext: 'ts'),
      s.name,
      isLive: true,
      poster: s.effectiveIcon,
      httpHeaders: widget.client.streamHeaders(s.streamId),
      favRef: MediaRef(
        kind: 'live',
        id: s.streamId,
        name: s.name,
        image: s.effectiveIcon,
        url: widget.client.streamUrl('live', s.streamId, ext: 'ts'),
        cat: s.categoryId,
      ),
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
        favRef: MediaRef(
          kind: 'movie',
          id: m.streamId,
          name: m.name,
          image: m.icon,
          cat: m.categoryId,
        ),
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
        favRef: _series == null
            ? null
            : MediaRef(
                kind: 'series',
                id: _series!.seriesId,
                name: _series!.name,
                image: _series!.cover,
                cat: _series!.categoryId,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canBack = _catId != null || _series != null;
    return FocusTraversalGroup(
      policy: RemoteFocusTraversalPolicy(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Icon(Icons.view_week_outlined, color: accent, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Split view',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'Close split browser',
                    onPressed: widget.onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose a second stream · starts muted',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ),
          if (canBack)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    autofocus: true,
                    tooltip:
                        'Back to ${_series != null ? 'collection' : 'categories'}',
                    onPressed: _back,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _series?.name ?? _catName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: s.$1 == 'series' ? 0 : 8,
                        ),
                        child: RemoteTap(
                          autofocus: s.$1 == 'live',
                          onTap: () {
                            if (_section == s.$1) return;
                            setState(() => _section = s.$1);
                            _loadCats();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: _section == s.$1
                                  ? accent
                                  : Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                lumenCorner(12),
                              ),
                            ),
                            child: Text(
                              s.$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: _section == s.$1
                                    ? onAccent
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: RemoteTextInput(
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: accent,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: _catId == null
                      ? 'Find a category'
                      : 'Search this collection',
                  hintStyle: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () => setState(_clearSearch),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .055),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(lumenCorner(14)),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(lumenCorner(14)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(lumenCorner(14)),
                    borderSide: !lumenShowsNavigationFocus
                        ? BorderSide.none
                        : BorderSide(
                            color: accent,
                            width: activeFocusStyle.ringWidth,
                          ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: Colors.white54,
                size: 30,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  if (_series != null) {
                    _openSeries(_series!);
                  } else if (_catId != null) {
                    _openCat(Category(_catId!, _catName));
                  } else {
                    _loadCats();
                  }
                },
                child: Text('Try again', style: TextStyle(color: accent)),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
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
      final eps = [for (final s in seasons) ...(_info!.episodes[s] ?? [])]
          .where(
            (e) => '${e.title} ${e.episodeNum}'.toLowerCase().contains(_query),
          )
          .toList();
      if (eps.isEmpty) return _empty('No episodes.');
      return ListView.builder(
        key: ValueKey('episodes-${_series!.seriesId}-$_query'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        itemCount: eps.length,
        itemBuilder: (_, i) {
          final e = eps[i];
          return _pickerRow(
            focusNode: i == 0 ? _contentFocus : null,
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
      final cats = _cats
          .where((c) => c.name.toLowerCase().contains(_query))
          .toList();
      if (cats.isEmpty) return _empty('No matching categories.');
      return ListView.builder(
        key: ValueKey('categories-$_section-$_query'),
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
        itemCount: cats.length,
        itemBuilder: (_, i) => _pickerRow(
          focusNode: i == 0 ? _contentFocus : null,
          image: '',
          fallback: Icons.folder_outlined,
          title: Text(
            cats[i].name,
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
          onTap: () => _openCat(cats[i]),
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
    final items = _items
        .where((item) => (item.name as String).toLowerCase().contains(_query))
        .toList();
    if (items.isEmpty) return _empty('No matches. Try another name.');
    return ListView.builder(
      key: ValueKey('items-$_section-$_catId-$_query'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        if (it is LiveStream) {
          final url = widget.client.streamUrl('live', it.streamId, ext: 'ts');
          final playing = url == widget.primaryUrl
              ? 'On main screen'
              : url == widget.secondaryUrl
              ? 'On second screen'
              : null;
          return _pickerRow(
            focusNode: i == 0 ? _contentFocus : null,
            selected: playing != null,
            image: it.effectiveIcon,
            fallback: Icons.live_tv_rounded,
            title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              playing ??
                  (it.sourceLabel.isEmpty ? 'Live channel' : it.sourceLabel),
              style: TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            onTap: playing == null ? () => _pickLive(it) : null,
            trailing: playing != null
                ? Icon(Icons.check_circle_rounded, color: accent, size: 20)
                : null,
          );
        } else if (it is VodStream) {
          return _pickerRow(
            focusNode: i == 0 ? _contentFocus : null,
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
            focusNode: i == 0 ? _contentFocus : null,
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
    required VoidCallback? onTap,
    bool selected = false,
    FocusNode? focusNode,
    Widget? subtitle,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: RemoteTap(
      focusNode: focusNode,
      onTap: onTap,
      focusRadius: 15,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(lumenCorner(15)),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: .45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            _thumb(image, fallback),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ] else
              Icon(Icons.add_circle_outline_rounded, color: accent, size: 22),
          ],
        ),
      ),
    ),
  );

  Widget _thumb(String url, IconData fallback) => ClipRRect(
    borderRadius: BorderRadius.circular(lumenCorner(8)),
    child: Container(
      width: 52,
      height: 52,
      color: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(4),
      child: url.isNotEmpty
          ? MediaImage(
              source: url,
              fit: BoxFit.contain,
              error: Icon(fallback, color: Colors.white54, size: 20),
            )
          : Icon(fallback, color: Colors.white54, size: 20),
    ),
  );

  Widget _empty(String m) => Center(
    child: Text(m, style: TextStyle(color: Colors.white54)),
  );
}
