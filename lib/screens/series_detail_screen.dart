import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../catalog_cache.dart';
import '../downloads.dart';
import '../library.dart';
import '../models.dart';
import '../playback.dart';
import '../responsive.dart';
import '../theme.dart';
import '../tmdb.dart';
import '../widgets.dart';
import '../xtream.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    required this.client,
    required this.seriesId,
    required this.title,
    this.preview,
  });

  final XtreamClient client;
  final int seriesId;
  final String title;

  /// Lightweight catalog data lets the page paint before the much larger
  /// episode response arrives.
  final Series? preview;

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
    _future = CatalogCache.instance.seriesInfo(widget.client, widget.seriesId);
    if (!widget.client.creds.isDemo) {
      Tmdb.tv(widget.title).then((value) {
        if (mounted && value != null) setState(() => _tmdb = value);
      });
    }
  }

  String get _title => cleanMediaTitle(widget.title);

  MediaRef _ref(String cover) =>
      MediaRef(kind: 'series', id: widget.seriesId, name: _title, image: cover);

  Future<void> _trailer() async {
    final trailer = _tmdb?.trailerUrl;
    if (trailer == null) return;
    await launchUrl(Uri.parse(trailer), mode: LaunchMode.externalApplication);
  }

  void _playEpisodes(List<Episode> episodes, int index, SeriesInfo info) {
    final reference = _ref(info.cover);
    final items = episodes.map((episode) {
      final title = episode.title.isEmpty
          ? 'Episode ${episode.episodeNum}'
          : episode.title;
      final ext = episode.containerExtension.isEmpty
          ? 'mp4'
          : episode.containerExtension;
      return PlayerItem(
        widget.client.streamUrl('series', episode.id, ext: ext),
        '$_title · $title',
        progressKey: 'ep:${episode.id}',
        poster: episode.image.isNotEmpty ? episode.image : info.cover,
        ext: ext,
        favRef: reference,
      );
    }).toList();
    PlaybackController.instance.open(items, index);
  }

  int _nextEpisodeIndex(List<Episode> episodes) {
    var bestIndex = 0;
    var latest = -1;
    for (var i = 0; i < episodes.length; i++) {
      final progress = Library.instance.progress['ep:${episodes[i].id}'];
      if (progress != null && progress.updatedAt > latest) {
        latest = progress.updatedAt;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  void _downloadEpisode(Episode episode, SeriesInfo info) {
    if (widget.client.creds.isDemo) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('The demo preview is already available offline.'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    final title = episode.title.isEmpty
        ? 'Episode ${episode.episodeNum}'
        : episode.title;
    final ext = episode.containerExtension.isEmpty
        ? 'mp4'
        : episode.containerExtension;
    Downloads.instance.start(
      id: 'ep:${episode.id}',
      title: '$_title · $title',
      poster: episode.image.isNotEmpty ? episode.image : info.cover,
      kind: 'episode',
      remoteUrl: widget.client.streamUrl('series', episode.id, ext: ext),
      ext: ext,
      progressKey: 'ep:${episode.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: FutureBuilder<SeriesInfo>(
        future: _future,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final loading = snapshot.connectionState != ConnectionState.done;
          final seasons = info?.episodes.keys.toList() ?? <int>[];
          seasons.sort();
          final activeSeason = seasons.isEmpty
              ? null
              : seasons.contains(_season)
              ? _season
              : seasons.first;
          final episodes = activeSeason == null
              ? const <Episode>[]
              : info?.episodes[activeSeason] ?? const <Episode>[];

          final preview = widget.preview;
          final cover = _tmdb?.poster.isNotEmpty == true
              ? _tmdb!.poster
              : info?.cover.isNotEmpty == true
              ? info!.cover
              : preview?.cover ?? '';
          final backdrop = _tmdb?.backdrop.isNotEmpty == true
              ? _tmdb!.backdrop
              : info?.backdrop.isNotEmpty == true
              ? info!.backdrop
              : '';
          final plot = _tmdb?.overview.isNotEmpty == true
              ? _tmdb!.overview
              : info?.plot.isNotEmpty == true
              ? info!.plot
              : preview?.plot ?? '';
          final genre = _tmdb?.genres.isNotEmpty == true
              ? _tmdb!.genres
              : info?.genre.isNotEmpty == true
              ? info!.genre
              : preview?.genre ?? '';
          final rating = (_tmdb?.rating ?? 0) > 0
              ? _tmdb!.rating
              : (info?.rating ?? 0) > 0
              ? info!.rating
              : preview?.rating ?? 0;
          final rawDate = _tmdb?.releaseDate.isNotEmpty == true
              ? _tmdb!.releaseDate
              : info?.releaseDate.isNotEmpty == true
              ? info!.releaseDate
              : preview?.releaseDate ?? '';
          final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : rawDate;

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _SeriesHero(
                      title: _title,
                      cover: cover,
                      backdrop: backdrop,
                      plot: plot,
                      genre: genre,
                      year: year,
                      rating: rating,
                      seasonCount: seasons.length,
                      episodeCount:
                          info?.episodes.values.fold<int>(
                            0,
                            (total, list) => total + list.length,
                          ) ??
                          0,
                      loading: loading,
                      hasTrailer: _tmdb?.trailerUrl != null,
                      favorite: _favoriteAction(cover),
                      onTrailer: _trailer,
                      onPlay: info != null && episodes.isNotEmpty
                          ? () => _playEpisodes(
                              episodes,
                              _nextEpisodeIndex(episodes),
                              info,
                            )
                          : null,
                    ),
                  ),
                  if (snapshot.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: LumenEmptyState(
                        icon: Icons
                            .signal_wifi_statusbar_connected_no_internet_4_rounded,
                        eyebrow: 'Provider unavailable',
                        title: 'This season archive is unavailable',
                        message:
                            'The provider did not return episode information. Go back or refresh the catalog and try again.',
                        actionLabel: 'Go back',
                        onAction: () => Navigator.of(context).pop(),
                      ),
                    )
                  else if (loading)
                    const SliverToBoxAdapter(child: _EpisodeLoading())
                  else if (seasons.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: LumenEmptyState(
                          icon: Icons.video_library_outlined,
                          eyebrow: 'Empty archive',
                          title: 'No episodes listed',
                          message:
                              'This provider returned the show details without an episode archive.',
                        ),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _SeasonNavigator(
                        seasons: seasons,
                        active: activeSeason!,
                        episodeCount: episodes.length,
                        onSelected: (season) =>
                            setState(() => _season = season),
                      ),
                    ),
                    _episodeSliver(episodes, info!),
                    const SliverToBoxAdapter(child: SizedBox(height: 64)),
                  ],
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: LumenBackButton(
                      key: const ValueKey('series-detail-back'),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _favoriteAction(String cover) => AnimatedBuilder(
    animation: Library.instance,
    builder: (_, _) {
      final reference = _ref(cover);
      final favorite = Library.instance.isFav(reference.key);
      return _SeriesAction(
        icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: favorite ? 'Saved' : 'My list',
        selected: favorite,
        onTap: () => Library.instance.toggleFav(reference),
      );
    },
  );

  Widget _episodeSliver(List<Episode> episodes, SeriesInfo info) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        isWide(context) ? 34 : 16,
        8,
        isWide(context) ? 34 : 16,
        0,
      ),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.crossAxisExtent >= 850;
          if (wide) {
            return SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 520,
                mainAxisExtent: 152,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _EpisodeChapter(
                  episode: episodes[index],
                  fallback: info.cover,
                  index: index,
                  onPlay: () => _playEpisodes(episodes, index, info),
                  onDownload: () => _downloadEpisode(episodes[index], info),
                ),
                childCount: episodes.length,
              ),
            );
          }
          return SliverList.separated(
            itemCount: episodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _EpisodeChapter(
              episode: episodes[index],
              fallback: info.cover,
              index: index,
              onPlay: () => _playEpisodes(episodes, index, info),
              onDownload: () => _downloadEpisode(episodes[index], info),
            ),
          );
        },
      ),
    );
  }
}

class _SeriesHero extends StatelessWidget {
  const _SeriesHero({
    required this.title,
    required this.cover,
    required this.backdrop,
    required this.plot,
    required this.genre,
    required this.year,
    required this.rating,
    required this.seasonCount,
    required this.episodeCount,
    required this.loading,
    required this.hasTrailer,
    required this.favorite,
    required this.onTrailer,
    required this.onPlay,
  });

  final String title;
  final String cover;
  final String backdrop;
  final String plot;
  final String genre;
  final String year;
  final double rating;
  final int seasonCount;
  final int episodeCount;
  final bool loading;
  final bool hasTrailer;
  final Widget favorite;
  final VoidCallback onTrailer;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return SizedBox(
      height: wide ? 540 : 570,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DetailBackdropPlaceholder(
            icon: Icons.video_library_rounded,
            loading: loading && backdrop.isEmpty,
          ),
          if (backdrop.isNotEmpty)
            MediaImage(
              source: backdrop,
              fit: BoxFit.cover,
              memCacheWidth: wide ? 1800 : 900,
              placeholder: const DetailBackdropPlaceholder(
                icon: Icons.video_library_rounded,
                loading: true,
              ),
              error: const DetailBackdropPlaceholder(
                icon: Icons.video_library_rounded,
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: wide ? Alignment.centerLeft : Alignment.topCenter,
                end: wide ? Alignment.centerRight : Alignment.bottomCenter,
                colors: wide
                    ? [
                        bg.withValues(alpha: .98),
                        bg.withValues(alpha: .76),
                        bg.withValues(alpha: .20),
                      ]
                    : [
                        Colors.black.withValues(alpha: .12),
                        bg.withValues(alpha: .56),
                        bg,
                      ],
                stops: wide ? const [0, .52, 1] : const [0, .48, .80],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, bg],
                stops: const [.72, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 42 : 20,
                    wide ? 86 : 238,
                    wide ? 42 : 20,
                    wide ? 42 : 18,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(width: 30, height: 2, color: accent2),
                                const SizedBox(width: 10),
                                Text('SEASON ARCHIVE', style: kSection()),
                                if (loading) ...[
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.7,
                                      color: accent2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: wide ? 52 : 33,
                                height: .98,
                                letterSpacing: wide ? -2.2 : -1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ).animate().fadeIn(duration: 320.ms),
                            const SizedBox(height: 15),
                            Wrap(
                              spacing: 12,
                              runSpacing: 7,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (rating > 0)
                                  _SeriesFact(
                                    icon: Icons.star_rounded,
                                    label: rating.toStringAsFixed(1),
                                    color: gold,
                                  ),
                                if (year.isNotEmpty) _SeriesFact(label: year),
                                if (seasonCount > 0)
                                  _SeriesFact(
                                    label:
                                        '$seasonCount season${seasonCount == 1 ? '' : 's'}',
                                  ),
                                if (episodeCount > 0)
                                  _SeriesFact(label: '$episodeCount episodes'),
                                if (genre.isNotEmpty) _SeriesFact(label: genre),
                              ],
                            ),
                            if (plot.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 680,
                                ),
                                child: Text(
                                  plot,
                                  maxLines: wide ? 3 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: muted,
                                    height: 1.5,
                                    fontSize: wide ? 15.5 : 14,
                                  ),
                                ),
                              ),
                            ] else if (loading) ...[
                              const SizedBox(height: 18),
                              const DetailMetadataSkeleton(maxWidth: 680),
                            ],
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _SeriesAction(
                                  icon: Icons.play_arrow_rounded,
                                  label: loading
                                      ? 'Loading episodes'
                                      : 'Play next',
                                  primary: true,
                                  onTap: onPlay,
                                ),
                                if (hasTrailer)
                                  _SeriesAction(
                                    icon: Icons.smart_display_rounded,
                                    label: 'Trailer',
                                    onTap: onTrailer,
                                  ),
                                favorite,
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (wide && cover.isNotEmpty) ...[
                        const SizedBox(width: 62),
                        Transform.rotate(
                          angle: -.016,
                          child: Container(
                            width: 220,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: line),
                              boxShadow: glow(
                                Colors.black,
                                blur: 44,
                                y: 22,
                                a: .62,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: MediaImage(
                                  source: cover,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 500,
                                  placeholder: const DetailBackdropPlaceholder(
                                    icon: Icons.tv_rounded,
                                    loading: true,
                                  ),
                                  error: const DetailBackdropPlaceholder(
                                    icon: Icons.tv_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesFact extends StatelessWidget {
  const _SeriesFact({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, color: color ?? muted, size: 16),
        const SizedBox(width: 4),
      ],
      Text(
        label,
        style: TextStyle(
          color: color ?? muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _SeriesAction extends StatelessWidget {
  const _SeriesAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final filled = primary || selected;
    final foreground = filled ? onAccent : textHi;
    return Opacity(
      opacity: onTap == null ? .55 : 1,
      child: RemoteTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          decoration: BoxDecoration(
            color: filled
                ? accent
                : surface.withValues(alpha: isDark ? .82 : .92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: filled ? Colors.transparent : line),
            boxShadow: primary ? glow(accent, blur: 22, y: 8, a: .38) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 21),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonNavigator extends StatelessWidget {
  const _SeasonNavigator({
    required this.seasons,
    required this.active,
    required this.episodeCount,
    required this.onSelected,
  });

  final List<int> seasons;
  final int active;
  final int episodeCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide(context) ? 34 : 16,
          22,
          isWide(context) ? 34 : 16,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CHOOSE A CHAPTER', style: kSection()),
                      const SizedBox(height: 5),
                      Text(
                        'Season $active · $episodeCount episode${episodeCount == 1 ? '' : 's'}',
                        style: TextStyle(color: muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Text(
                  active.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: accent.withValues(alpha: .22),
                    fontSize: 52,
                    height: .8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final season = seasons[index];
                  return LumenFilterPill(
                    label: 'Season $season',
                    selected: season == active,
                    onTap: () => onSelected(season),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EpisodeChapter extends StatelessWidget {
  const _EpisodeChapter({
    required this.episode,
    required this.fallback,
    required this.index,
    required this.onPlay,
    required this.onDownload,
  });

  final Episode episode;
  final String fallback;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final image = episode.image.isNotEmpty ? episode.image : fallback;
    final title = episode.title.isEmpty
        ? 'Episode ${episode.episodeNum}'
        : episode.title;
    final progress = Library.instance.progress['ep:${episode.id}'];

    return RemoteTap(
          onTap: onPlay,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: line),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  height: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _EpisodeFallback(number: episode.episodeNum),
                      if (image.isNotEmpty)
                        MediaImage(
                          source: image,
                          fit: BoxFit.cover,
                          memCacheWidth: 420,
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [surface, Colors.transparent],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .48),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (progress != null)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress.fraction,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EPISODE ${episode.episodeNum.toString().padLeft(2, '0')}',
                          style: kSection(),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            '${(progress.fraction * 100).round()}% watched',
                            style: TextStyle(color: accentInk, fontSize: 11.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _EpisodeDownload(
                  id: 'ep:${episode.id}',
                  onDownload: onDownload,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 260.ms, delay: (index.clamp(0, 10) * 20).ms)
        .slideY(begin: .05, end: 0);
  }
}

class _EpisodeDownload extends StatelessWidget {
  const _EpisodeDownload({required this.id, required this.onDownload});

  final String id;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Downloads.instance,
    builder: (_, _) {
      final item = Downloads.instance.find(id);
      final status = item?.status;
      IconData icon = Icons.download_rounded;
      Color color = muted;
      VoidCallback action = onDownload;
      String label = 'Download episode';

      if (status == DlStatus.completed) {
        icon = Icons.offline_pin_rounded;
        color = accent;
        action = () {};
        label = 'Available offline';
      } else if (status == DlStatus.queued) {
        icon = Icons.schedule_rounded;
        action = () => Downloads.instance.cancel(id);
        label = 'Queued; activate to cancel';
      } else if (status == DlStatus.downloading) {
        icon = Icons.pause_rounded;
        color = accent;
        action = () => Downloads.instance.pause(id);
        label = 'Downloading; activate to pause';
      } else if (status == DlStatus.paused || status == DlStatus.failed) {
        icon = Icons.play_arrow_rounded;
        color = accent;
        action = () => Downloads.instance.resume(id);
        label = 'Resume download';
      }

      return RemoteTap(
        semanticLabel: label,
        onTap: action,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: .26)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );
    },
  );
}

class _EpisodeFallback extends StatelessWidget {
  const _EpisodeFallback({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [surfaceHi, surface],
      ),
    ),
    child: Center(
      child: Text(
        number.toString().padLeft(2, '0'),
        style: TextStyle(
          color: accent.withValues(alpha: .38),
          fontSize: 46,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _EpisodeLoading extends StatelessWidget {
  const _EpisodeLoading();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide(context) ? 34 : 16,
          26,
          isWide(context) ? 34 : 16,
          50,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OPENING THE SEASON ARCHIVE', style: kSection()),
            const SizedBox(height: 15),
            for (var i = 0; i < 3; i++) ...[
              Container(
                height: 116,
                decoration: BoxDecoration(
                  color: surfaceHi.withValues(alpha: .46),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: line),
                ),
              ),
              if (i < 2) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}
