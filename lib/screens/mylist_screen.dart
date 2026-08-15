import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../library.dart';
import '../models.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../playback.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

class MyListScreen extends StatefulWidget {
  final XtreamClient client;
  final FocusNode? shellRailFocusNode;
  final FocusNode? shellTopFocusNode;
  final FocusNode? entryFocusNode;
  const MyListScreen({
    super.key,
    required this.client,
    this.shellRailFocusNode,
    this.shellTopFocusNode,
    this.entryFocusNode,
  });

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  String _filter = 'all';
  final _gridScroll = ScrollController();
  late final List<FocusNode> _filterFocus;
  final List<FocusNode> _gridFocus = <FocusNode>[];
  int _gridColumns = 1;
  double _gridRowExtent = 220;

  @override
  void initState() {
    super.initState();
    _filterFocus = <FocusNode>[
      widget.entryFocusNode ?? FocusNode(debugLabel: 'My List filter 0'),
      for (var index = 1; index < 4; index++)
        FocusNode(debugLabel: 'My List filter $index'),
    ];
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    for (var index = 0; index < _filterFocus.length; index++) {
      if (index != 0 || widget.entryFocusNode == null) {
        _filterFocus[index].dispose();
      }
    }
    for (final node in _gridFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _ensureGridFocus(int count) {
    while (_gridFocus.length < count) {
      _gridFocus.add(
        FocusNode(debugLabel: 'My List tile ${_gridFocus.length}'),
      );
    }
  }

  void _requestGridFocus(int requested, int itemCount) {
    if (itemCount == 0) return;
    final target = requested.clamp(0, itemCount - 1).toInt();

    void attempt(int frames) {
      if (!mounted || target >= _gridFocus.length) return;
      final node = _gridFocus[target];
      if (node.context != null && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
      if (_gridScroll.hasClients && _gridScroll.position.hasContentDimensions) {
        final row = target ~/ _gridColumns;
        final desired = (row * _gridRowExtent - _gridRowExtent * .45).clamp(
          _gridScroll.position.minScrollExtent,
          _gridScroll.position.maxScrollExtent,
        );
        _gridScroll.jumpTo(desired);
      }
      if (frames > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => attempt(frames - 1),
        );
      }
    }

    attempt(8);
  }

  KeyEventResult _filterKey(int index, int itemCount, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _filterFocus[index - 1].requestFocus();
      } else {
        widget.shellRailFocusNode?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _filterFocus[(index + 1).clamp(0, _filterFocus.length - 1)]
          .requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _requestGridFocus(index, itemCount);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final top = widget.shellTopFocusNode;
      if (top != null && top.canRequestFocus) top.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _gridKey(int index, int itemCount, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final column = index % _gridColumns;
    int? target;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (column == 0) {
        widget.shellRailFocusNode?.requestFocus();
        return KeyEventResult.handled;
      }
      target = index - 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (column == _gridColumns - 1 || index + 1 >= itemCount) {
        return KeyEventResult.handled;
      }
      target = index + 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index < _gridColumns) {
        _filterFocus[column.clamp(0, _filterFocus.length - 1)].requestFocus();
        return KeyEventResult.handled;
      }
      target = index - _gridColumns;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index + _gridColumns >= itemCount) return KeyEventResult.handled;
      target = index + _gridColumns;
    } else {
      return KeyEventResult.ignored;
    }
    _requestGridFocus(target, itemCount);
    return KeyEventResult.handled;
  }

  void _open(BuildContext context, MediaRef r, List<MediaRef> contextItems) {
    if (r.kind == 'live') {
      final channels = contextItems
          .where((item) => item.kind == 'live')
          .toList();
      final index = channels.indexWhere((item) => item.key == r.key);
      PlaybackController.instance.open([
        for (final channel in channels)
          PlayerItem(
            channel.url,
            channel.name,
            isLive: true,
            poster: channel.image,
            httpHeaders: widget.client.streamHeaders(channel.id),
            favRef: channel,
          ),
      ], index < 0 ? 0 : index);
      return;
    }
    final w = r.kind == 'series'
        ? SeriesDetailScreen(
            client: widget.client,
            seriesId: r.id,
            title: r.name,
          )
        : MovieDetailScreen(
            client: widget.client,
            movie: VodStream(r.id, r.name, r.image, '', 'mp4', 0, ''),
          );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  }

  List<MediaRef> _visible(List<MediaRef> items) => _filter == 'all'
      ? items
      : items.where((item) => item.kind == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final wideShell = isWide(context);
    return AnimatedBuilder(
      animation: Library.instance,
      builder: (context, _) {
        final all = Library.instance.favourites;
        final visible = _visible(all);
        _ensureGridFocus(visible.length);
        final movies = all.where((item) => item.kind == 'movie').length;
        final series = all.where((item) => item.kind == 'series').length;
        final live = all.where((item) => item.kind == 'live').length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EditorialPageHeader(
              eyebrow: 'Your library',
              title: wideShell ? 'Saved for later' : 'My list',
              subtitle: all.isEmpty
                  ? 'Keep the films, series and channels you care about close.'
                  : '${all.length} saved ${all.length == 1 ? 'item' : 'items'} across your library',
              icon: Icons.bookmark_rounded,
              trailing: MediaQuery.sizeOf(context).width >= 560
                  ? _countBadge(all.length)
                  : null,
            ),
            if (all.isNotEmpty)
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  children: [
                    LumenFilterPill(
                      focusNode: _filterFocus[0],
                      onKeyEvent: (_, event) =>
                          _filterKey(0, visible.length, event),
                      label: 'All ${all.length}',
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
                      focusNode: _filterFocus[1],
                      onKeyEvent: (_, event) =>
                          _filterKey(1, visible.length, event),
                      label: 'Films $movies',
                      selected: _filter == 'movie',
                      onTap: () => setState(() => _filter = 'movie'),
                      icon: Icons.movie_outlined,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
                      focusNode: _filterFocus[2],
                      onKeyEvent: (_, event) =>
                          _filterKey(2, visible.length, event),
                      label: 'Series $series',
                      selected: _filter == 'series',
                      onTap: () => setState(() => _filter = 'series'),
                      icon: Icons.video_library_outlined,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
                      focusNode: _filterFocus[3],
                      onKeyEvent: (_, event) =>
                          _filterKey(3, visible.length, event),
                      label: 'Live $live',
                      selected: _filter == 'live',
                      onTap: () => setState(() => _filter = 'live'),
                      icon: Icons.cell_tower_rounded,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: all.isEmpty
                  ? const LumenEmptyState(
                      icon: Icons.favorite_border_rounded,
                      eyebrow: 'Your collection',
                      title: 'Save the good stuff',
                      message:
                          'Use the heart on a film, series or live channel. Everything you save will meet you here.',
                    )
                  : visible.isEmpty
                  ? LumenEmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      eyebrow: 'Nothing in this view',
                      title: 'Try another collection',
                      message:
                          'You have saved items, just not in this category yet.',
                      actionLabel: 'Show everything',
                      onAction: () => setState(() => _filter = 'all'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = gridColumns(
                          constraints.maxWidth,
                          tile: 170,
                          min: constraints.maxWidth < 520 ? 2 : 3,
                        );
                        _gridColumns = columns;
                        final tileWidth =
                            (constraints.maxWidth - 40 - (columns - 1) * 14) /
                            columns;
                        _gridRowExtent = tileWidth / .66 + 20;
                        return GridView.builder(
                          controller: _gridScroll,
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                childAspectRatio: 0.66,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 20,
                              ),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => visible[i].isLive
                              ? ChannelCard(
                                  focusNode: _gridFocus[i],
                                  onKeyEvent: (_, event) =>
                                      _gridKey(i, visible.length, event),
                                  name: visible[i].name,
                                  logo: visible[i].image,
                                  index: i,
                                  onTap: () =>
                                      _open(context, visible[i], visible),
                                )
                              : PosterCard(
                                  focusNode: _gridFocus[i],
                                  onKeyEvent: (_, event) =>
                                      _gridKey(i, visible.length, event),
                                  name: visible[i].name,
                                  image: visible[i].image,
                                  index: i,
                                  onTap: () =>
                                      _open(context, visible[i], visible),
                                ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _countBadge(int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    decoration: BoxDecoration(
      color: surfaceHi.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.favorite_rounded, color: accentInk, size: 16),
        const SizedBox(width: 7),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
