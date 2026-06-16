import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../xtream.dart';
import 'player_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final XtreamClient client;
  final int seriesId;
  final String title;
  const SeriesDetailScreen({super.key, required this.client, required this.seriesId, required this.title});
  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Future<SeriesInfo> _future;
  int? _season;

  @override
  void initState() {
    super.initState();
    _future = widget.client.seriesInfo(widget.seriesId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<SeriesInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: accent));
          }
          if (snap.hasError || snap.data == null) {
            return Center(child: Text('${snap.error ?? "Couldn't load series."}', style: const TextStyle(color: Color(0xFFFFB4B4))));
          }
          final info = snap.data!;
          final seasons = info.episodes.keys.toList()..sort();
          if (seasons.isEmpty) {
            return const Center(child: Text('No episodes listed.', style: TextStyle(color: subtle)));
          }
          final active = _season ?? seasons.first;
          final eps = info.episodes[active] ?? [];
          return Column(
            children: [
              if (info.plot.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(info.plot,
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
                ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: seasons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = seasons[i];
                    final sel = s == active;
                    return ChoiceChip(
                      label: Text('Season $s'),
                      selected: sel,
                      onSelected: (_) => setState(() => _season = s),
                      selectedColor: accent,
                      labelStyle: TextStyle(color: sel ? bg : muted, fontWeight: FontWeight.w600),
                      backgroundColor: surfaceHi,
                      shape: const StadiumBorder(side: BorderSide(color: Colors.white12)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: eps.length,
                  itemBuilder: (_, i) => _EpisodeRow(
                    ep: eps[i],
                    onTap: () {
                      final url = widget.client.streamUrl('series', eps[i].id, ext: eps[i].containerExtension);
                      final t = '${widget.title} · ${eps[i].title.isEmpty ? "Episode ${eps[i].episodeNum}" : eps[i].title}';
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(url: url, title: t)));
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final Episode ep;
  final VoidCallback onTap;
  const _EpisodeRow({required this.ep, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 40,
            child: ep.image.isNotEmpty
                ? CachedNetworkImage(imageUrl: ep.image, fit: BoxFit.cover, errorWidget: (_, __, ___) => const ColoredBox(color: surfaceHi))
                : const ColoredBox(color: surfaceHi, child: Icon(Icons.movie_rounded, size: 16, color: subtle)),
          ),
        ),
        title: Text(ep.title.isEmpty ? 'Episode ${ep.episodeNum}' : ep.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Episode ${ep.episodeNum}', style: const TextStyle(color: subtle)),
        trailing: const Icon(Icons.play_circle_fill_rounded, color: accent),
      ),
    );
  }
}
