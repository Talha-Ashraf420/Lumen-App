import 'package:flutter/material.dart';
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
  const MyListScreen({super.key, required this.client});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  String _filter = 'all';

  void _open(BuildContext context, MediaRef r) {
    if (r.kind == 'live') {
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
                      label: 'All ${all.length}',
                      selected: _filter == 'all',
                      onTap: () => setState(() => _filter = 'all'),
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
                      label: 'Films $movies',
                      selected: _filter == 'movie',
                      onTap: () => setState(() => _filter = 'movie'),
                      icon: Icons.movie_outlined,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
                      label: 'Series $series',
                      selected: _filter == 'series',
                      onTap: () => setState(() => _filter = 'series'),
                      icon: Icons.video_library_outlined,
                    ),
                    const SizedBox(width: 8),
                    LumenFilterPill(
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
                      builder: (context, constraints) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridColumns(
                            constraints.maxWidth,
                            tile: 170,
                            min: constraints.maxWidth < 520 ? 2 : 3,
                          ),
                          childAspectRatio: 0.66,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (_, i) => visible[i].isLive
                            ? ChannelCard(
                                name: visible[i].name,
                                logo: visible[i].image,
                                index: i,
                                onTap: () => _open(context, visible[i]),
                              )
                            : PosterCard(
                                name: visible[i].name,
                                image: visible[i].image,
                                index: i,
                                onTap: () => _open(context, visible[i]),
                              ),
                      ),
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
