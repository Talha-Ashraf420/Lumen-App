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

class MyListScreen extends StatelessWidget {
  final XtreamClient client;
  const MyListScreen({super.key, required this.client});

  void _open(BuildContext context, MediaRef r) {
    if (r.kind == 'live') {
      PlaybackController.instance.open([
        PlayerItem(r.url, r.name, isLive: true, poster: r.image, favRef: r, epg: () => client.shortEpg(r.id))
      ], 0);
      return;
    }
    final w = r.kind == 'series'
        ? SeriesDetailScreen(client: client, seriesId: r.id, title: r.name)
        : MovieDetailScreen(client: client, movie: VodStream(r.id, r.name, r.image, '', 'mp4', 0, ''));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Text('My List', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Library.instance,
            builder: (context, _) {
              final favs = Library.instance.favourites;
              if (favs.isEmpty) return _empty();
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns(MediaQuery.sizeOf(context).width, tile: 136),
                  childAspectRatio: 0.66,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                ),
                itemCount: favs.length,
                itemBuilder: (_, i) => favs[i].isLive
                    ? ChannelCard(name: favs[i].name, logo: favs[i].image, index: i, onTap: () => _open(context, favs[i]))
                    : PosterCard(
                        name: favs[i].name,
                        image: favs[i].image,
                        index: i,
                        onTap: () => _open(context, favs[i]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: Icon(Icons.favorite_rounded, color: accent, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('Nothing saved yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Text('Tap the heart on any movie or series to keep it here.',
                  textAlign: TextAlign.center, style: TextStyle(color: subtle, height: 1.4)),
            ),
          ],
        ),
      );
}
