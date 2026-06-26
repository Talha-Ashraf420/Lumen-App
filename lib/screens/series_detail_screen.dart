import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../downloads.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../responsive.dart';
import '../theme.dart';
import '../tmdb.dart';
import '../xtream.dart';

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
  TmdbInfo? _tmdb;

  @override
  void initState() {
    super.initState();
    _future = widget.client.seriesInfo(widget.seriesId);
    Tmdb.tv(widget.title).then((t) {
      if (mounted && t != null) setState(() => _tmdb = t);
    });
  }

  Future<void> _trailer() async {
    final url = _tmdb?.trailerUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  MediaRef _ref(String cover) => MediaRef(kind: 'series', id: widget.seriesId, name: widget.title, image: cover);

  void _playEpisodes(List<Episode> eps, int index, SeriesInfo info) {
    final ref = _ref(info.cover);
    final items = eps.map((e) {
      final t = e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title;
      return PlayerItem(
        widget.client.streamUrl('series', e.id, ext: e.containerExtension),
        '${widget.title} · $t',
        progressKey: 'ep:${e.id}',
        poster: e.image.isNotEmpty ? e.image : info.cover,
        ext: e.containerExtension,
        favRef: ref,
      );
    }).toList();
    PlaybackController.instance.open(items, index);
  }

  void _downloadEpisode(Episode e, SeriesInfo info) {
    final t = e.title.isEmpty ? 'Episode ${e.episodeNum}' : e.title;
    Downloads.instance.start(
      id: 'ep:${e.id}',
      title: '${widget.title} · $t',
      poster: e.image.isNotEmpty ? e.image : info.cover,
      kind: 'episode',
      remoteUrl: widget.client.streamUrl('series', e.id, ext: e.containerExtension),
      ext: e.containerExtension,
      progressKey: 'ep:${e.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: FutureBuilder<SeriesInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2.5));
          }
          if (snap.hasError || snap.data == null) {
            return _errorBack('Couldn’t load this series.');
          }
          final info = snap.data!;
          final seasons = info.episodes.keys.toList()..sort();
          if (seasons.isEmpty) return _errorBack('No episodes listed for this series.');
          final active = _season ?? seasons.first;
          final eps = info.episodes[active] ?? [];
          final art = (_tmdb?.backdrop.isNotEmpty == true)
              ? _tmdb!.backdrop
              : (info.backdrop.isNotEmpty ? info.backdrop : info.cover);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide(context) ? 1000 : double.infinity),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _hero(info, art, eps)),
                  SliverToBoxAdapter(child: _meta(info, seasons)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    sliver: SliverList.separated(
                      itemCount: eps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _EpisodeTile(
                        ep: eps[i],
                        fallback: info.cover,
                        index: i,
                        onTap: () => _playEpisodes(eps, i, info),
                        onDownload: () => _downloadEpisode(eps[i], info),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hero(SeriesInfo info, String art, List<Episode> eps) {
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: surfaceHi),
          // blurred art fill — premium backdrop that handles portrait covers cleanly
          if (art.isNotEmpty)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Transform.scale(scale: 1.15, child: CachedNetworkImage(imageUrl: art, fit: BoxFit.cover)),
              ),
            ),
          // sharp poster, centered, sitting over the blur
          if (art.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 28),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 190,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: CachedNetworkImage(imageUrl: art, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox.shrink()),
                    ),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [bg, Color(0x00000000)],
                stops: [0.0, 0.85],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x66000000), Colors.transparent]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                  ),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: Library.instance,
                    builder: (_, __) {
                      final ref = _ref(info.cover);
                      final fav = Library.instance.isFav(ref.key);
                      return IconButton(
                        onPressed: () => Library.instance.toggleFav(ref),
                        icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? accent2 : Colors.white),
                        style: IconButton.styleFrom(backgroundColor: Colors.black38),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.05))
                    .animate()
                    .fadeIn()
                    .slideY(begin: 0.2, end: 0),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (eps.isNotEmpty)
                      GestureDetector(
                        onTap: () => _playEpisodes(eps, 0, info),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14), boxShadow: glow(accent, a: 0.5)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Play', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                          ]),
                        ),
                      ),
                    if (_tmdb?.trailerUrl != null) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _trailer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.smart_display_rounded, size: 22, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Trailer', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                          ]),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(SeriesInfo info, List<int> seasons) {
    final active = _season ?? seasons.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (_) {
            final rating = (_tmdb?.rating ?? 0) > 0 ? _tmdb!.rating : info.rating;
            final genre = _tmdb?.genres.isNotEmpty == true ? _tmdb!.genres : info.genre;
            final year = _tmdb?.releaseDate.isNotEmpty == true
                ? (_tmdb!.releaseDate.length >= 4 ? _tmdb!.releaseDate.substring(0, 4) : _tmdb!.releaseDate)
                : info.releaseDate;
            return Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (rating > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, color: gold, size: 17),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
                  ]),
                if (year.isNotEmpty) Text(year, style: TextStyle(color: muted)),
                if (genre.isNotEmpty) Text(genre, style: TextStyle(color: subtle)),
                Text('${seasons.length} season${seasons.length == 1 ? '' : 's'}', style: TextStyle(color: subtle)),
              ],
            );
          }),
          Builder(builder: (_) {
            final plot = _tmdb?.overview.isNotEmpty == true ? _tmdb!.overview : info.plot;
            if (plot.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(plot, style: TextStyle(color: muted, height: 1.5)),
            );
          }),
          const SizedBox(height: 18),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = seasons[i];
                final sel = s == active;
                return GestureDetector(
                  onTap: () => setState(() => _season = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: sel ? accent : surfaceHi.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: sel ? Colors.transparent : line),
                    ),
                    child: Text('Season $s', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: sel ? Colors.white : muted)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _errorBack(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Go back', style: TextStyle(color: accent))),
          ],
        ),
      );
}

class _EpisodeTile extends StatelessWidget {
  final Episode ep;
  final String fallback; // series cover used when episode image is missing
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  const _EpisodeTile({required this.ep, required this.fallback, required this.index, required this.onTap, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final img = ep.image.isNotEmpty ? ep.image : fallback;
    final title = ep.title.isEmpty ? 'Episode ${ep.episodeNum}' : ep.title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: 118,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ThumbFallback(number: ep.episodeNum),
                    if (img.isNotEmpty)
                      CachedNetworkImage(imageUrl: img, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox.shrink()),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Color(0x99000000), Colors.transparent]),
                      ),
                    ),
                    const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
                  const SizedBox(height: 5),
                  Text('Episode ${ep.episodeNum}', style: TextStyle(color: subtle, fontSize: 12)),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: Downloads.instance,
              builder: (_, __) {
                final d = Downloads.instance.find('ep:${ep.id}');
                if (d?.status == DlStatus.completed) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.download_done_rounded, color: accent, size: 22),
                  );
                }
                if (d?.status == DlStatus.queued) {
                  return IconButton(
                    onPressed: () => Downloads.instance.cancel('ep:${ep.id}'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.schedule_rounded, color: muted, size: 20),
                    tooltip: 'Queued — tap to cancel',
                  );
                }
                if (d?.status == DlStatus.downloading) {
                  return GestureDetector(
                    onTap: () => Downloads.instance.cancel('ep:${ep.id}'),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(value: d!.total > 0 ? d.progress : null, strokeWidth: 2.2, color: accent),
                      ),
                    ),
                  );
                }
                return IconButton(
                  onPressed: onDownload,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.download_rounded, color: muted, size: 20),
                  tooltip: 'Download',
                );
              },
            ),
            GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent, blur: 12, y: 3, a: 0.4)),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 280.ms, delay: (index.clamp(0, 12) * 25).ms).slideY(begin: 0.08, end: 0);
  }
}

class _ThumbFallback extends StatelessWidget {
  final int number;
  const _ThumbFallback({required this.number});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [surfaceHi, surface])),
        child: Center(child: Text('E$number', style: TextStyle(color: subtle, fontWeight: FontWeight.w800, fontSize: 16))),
      );
}
