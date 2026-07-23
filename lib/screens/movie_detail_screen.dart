import 'package:cached_network_image/cached_network_image.dart';
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

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({
    super.key,
    required this.client,
    required this.movie,
  });

  final XtreamClient client;
  final VodStream movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  VodInfo? _info;
  TmdbInfo? _tmdb;
  bool _providerLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  void _loadDetails() {
    CatalogCache.instance
        .vodInfo(widget.client, widget.movie.streamId)
        .then((value) {
          if (mounted) {
            setState(() {
              _info = value;
              _providerLoading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _providerLoading = false);
        });
    Tmdb.movie(widget.movie.name).then((value) {
      if (mounted && value != null) setState(() => _tmdb = value);
    });
  }

  String get _title => cleanMediaTitle(widget.movie.name);

  MediaRef _ref() => MediaRef(
    kind: 'movie',
    id: widget.movie.streamId,
    name: _title,
    image: widget.movie.icon,
    cat: widget.movie.categoryId,
  );

  String get _progressKey => 'movie:${widget.movie.streamId}';
  String get _downloadId => _progressKey;

  String get _extension {
    final provider = _info?.containerExtension ?? '';
    if (provider.isNotEmpty) return provider;
    return widget.movie.containerExtension.isEmpty
        ? 'mp4'
        : widget.movie.containerExtension;
  }

  void _play() {
    final ext = _extension;
    PlaybackController.instance.open([
      PlayerItem(
        widget.client.streamUrl('movie', widget.movie.streamId, ext: ext),
        _title,
        progressKey: _progressKey,
        poster: widget.movie.icon,
        ext: ext,
        favRef: _ref(),
      ),
    ], 0);
  }

  Future<void> _trailer() async {
    final trailer = _tmdb?.trailerUrl;
    if (trailer == null) return;
    await launchUrl(Uri.parse(trailer), mode: LaunchMode.externalApplication);
  }

  void _download() {
    final ext = _extension;
    Downloads.instance.start(
      id: _downloadId,
      title: _title,
      poster: widget.movie.icon,
      kind: 'movie',
      remoteUrl: widget.client.streamUrl(
        'movie',
        widget.movie.streamId,
        ext: ext,
      ),
      ext: ext,
      progressKey: _progressKey,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Added to offline downloads'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _removeDownload(DownloadItem item) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Remove offline copy?'),
        content: const Text(
          'The film remains in your library, but its downloaded file will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep it', style: TextStyle(color: muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) Downloads.instance.delete(item);
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final info = _info;
    final tmdb = _tmdb;
    final wide = isWide(context);

    final backdrop = tmdb?.backdrop.isNotEmpty == true
        ? tmdb!.backdrop
        : info?.backdrop.isNotEmpty == true
        ? info!.backdrop
        : '';
    final poster = tmdb?.poster.isNotEmpty == true
        ? tmdb!.poster
        : info?.image.isNotEmpty == true
        ? info!.image
        : movie.icon;
    final plot = tmdb?.overview.isNotEmpty == true
        ? tmdb!.overview
        : info?.plot ?? '';
    final genre = tmdb?.genres.isNotEmpty == true
        ? tmdb!.genres
        : info?.genre ?? '';
    final cast = tmdb?.cast.isNotEmpty == true ? tmdb!.cast : info?.cast ?? '';
    final rating = (tmdb?.rating ?? 0) > 0
        ? tmdb!.rating
        : (info?.rating ?? 0) > 0
        ? info!.rating
        : movie.rating;
    final rawDate = tmdb?.releaseDate.isNotEmpty == true
        ? tmdb!.releaseDate
        : info?.releaseDate ?? '';
    final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : rawDate;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _CinematicHero(
                    movie: movie,
                    title: _title,
                    backdrop: backdrop,
                    poster: poster,
                    year: year,
                    genre: genre,
                    rating: rating,
                    duration: info?.duration ?? '',
                    plot: plot,
                    loadingDetails: _providerLoading,
                    hasTrailer: tmdb?.trailerUrl != null,
                    onPlay: _play,
                    onTrailer: _trailer,
                    downloadAction: _downloadAction(),
                    favoriteAction: _favoriteAction(),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 42 : 20,
                          wide ? 34 : 24,
                          wide ? 42 : 20,
                          wide ? 80 : 54,
                        ),
                        child: _EditorialDetails(
                          plot: plot,
                          cast: cast,
                          director: info?.director ?? '',
                          genre: genre,
                          format: _extension.toUpperCase(),
                          loading: _providerLoading,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: LumenBackButton(
                  key: const ValueKey('movie-detail-back'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _favoriteAction() => AnimatedBuilder(
    animation: Library.instance,
    builder: (_, _) {
      final favorite = Library.instance.isFav(_ref().key);
      return _DetailAction(
        icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: favorite ? 'Saved' : 'My list',
        selected: favorite,
        onTap: () => Library.instance.toggleFav(_ref()),
      );
    },
  );

  Widget _downloadAction() => AnimatedBuilder(
    animation: Downloads.instance,
    builder: (_, _) {
      final item = Downloads.instance.find(_downloadId);
      final status = item?.status;
      if (status == DlStatus.completed) {
        return _DetailAction(
          icon: Icons.offline_pin_rounded,
          label: 'Offline',
          selected: true,
          onTap: () => _removeDownload(item!),
        );
      }
      if (status == DlStatus.downloading) {
        return _DetailAction(
          icon: Icons.pause_rounded,
          label: '${((item?.progress ?? 0) * 100).round()}%',
          progress: item?.total == 0 ? null : item?.progress,
          onTap: () => Downloads.instance.pause(_downloadId),
        );
      }
      if (status == DlStatus.queued) {
        return _DetailAction(
          icon: Icons.schedule_rounded,
          label: 'Queued',
          onTap: () => Downloads.instance.cancel(_downloadId),
        );
      }
      if (status == DlStatus.paused || status == DlStatus.failed) {
        return _DetailAction(
          icon: Icons.download_rounded,
          label: 'Resume',
          onTap: () => Downloads.instance.resume(_downloadId),
        );
      }
      return _DetailAction(
        icon: Icons.download_rounded,
        label: 'Offline',
        onTap: _download,
      );
    },
  );
}

class _CinematicHero extends StatelessWidget {
  const _CinematicHero({
    required this.movie,
    required this.title,
    required this.backdrop,
    required this.poster,
    required this.year,
    required this.genre,
    required this.rating,
    required this.duration,
    required this.plot,
    required this.loadingDetails,
    required this.hasTrailer,
    required this.onPlay,
    required this.onTrailer,
    required this.downloadAction,
    required this.favoriteAction,
  });

  final VodStream movie;
  final String title;
  final String backdrop;
  final String poster;
  final String year;
  final String genre;
  final double rating;
  final String duration;
  final String plot;
  final bool loadingDetails;
  final bool hasTrailer;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final Widget downloadAction;
  final Widget favoriteAction;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final height = wide ? 650.0 : 590.0;
    final progress = Library.instance.progress['movie:${movie.streamId}'];

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DetailBackdropPlaceholder(
            icon: Icons.movie_filter_rounded,
            loading: loadingDetails && backdrop.isEmpty,
          ),
          if (backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              memCacheWidth: wide ? 1800 : 900,
              placeholder: (_, _) => const DetailBackdropPlaceholder(
                icon: Icons.movie_filter_rounded,
                loading: true,
              ),
              errorWidget: (_, _, _) => const DetailBackdropPlaceholder(
                icon: Icons.movie_filter_rounded,
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
                        bg.withValues(alpha: .80),
                        bg.withValues(alpha: .16),
                      ]
                    : [
                        Colors.black.withValues(alpha: .12),
                        bg.withValues(alpha: .48),
                        bg,
                      ],
                stops: wide ? const [0, .48, 1] : const [0, .50, .82],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, bg],
                stops: const [.70, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 42 : 20,
                      wide ? 86 : 224,
                      wide ? 42 : 20,
                      wide ? 42 : 20,
                    ),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _HeroCopy(
                                  movie: movie,
                                  title: title,
                                  year: year,
                                  genre: genre,
                                  rating: rating,
                                  duration: duration,
                                  plot: plot,
                                  loadingDetails: loadingDetails,
                                  progress: progress,
                                  hasTrailer: hasTrailer,
                                  onPlay: onPlay,
                                  onTrailer: onTrailer,
                                  downloadAction: downloadAction,
                                  favoriteAction: favoriteAction,
                                ),
                              ),
                              const SizedBox(width: 60),
                              if (poster.isNotEmpty)
                                _PosterArtifact(url: poster, width: 238),
                            ],
                          )
                        : _HeroCopy(
                            movie: movie,
                            title: title,
                            year: year,
                            genre: genre,
                            rating: rating,
                            duration: duration,
                            plot: plot,
                            loadingDetails: loadingDetails,
                            progress: progress,
                            hasTrailer: hasTrailer,
                            onPlay: onPlay,
                            onTrailer: onTrailer,
                            downloadAction: downloadAction,
                            favoriteAction: favoriteAction,
                          ),
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

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.movie,
    required this.title,
    required this.year,
    required this.genre,
    required this.rating,
    required this.duration,
    required this.plot,
    required this.loadingDetails,
    required this.progress,
    required this.hasTrailer,
    required this.onPlay,
    required this.onTrailer,
    required this.downloadAction,
    required this.favoriteAction,
  });

  final VodStream movie;
  final String title;
  final String year;
  final String genre;
  final double rating;
  final String duration;
  final String plot;
  final bool loadingDetails;
  final Progress? progress;
  final bool hasTrailer;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final Widget downloadAction;
  final Widget favoriteAction;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 30, height: 2, color: accent),
            const SizedBox(width: 10),
            Text('FEATURE PRESENTATION', style: kSection()),
            if (loadingDetails) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.7,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text(
          title,
          maxLines: wide ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 56 : 34,
            height: .96,
            letterSpacing: wide ? -2.5 : -1.2,
            fontWeight: FontWeight.w800,
          ),
        ).animate().fadeIn(duration: 320.ms).slideY(begin: .06, end: 0),
        const SizedBox(height: 16),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            if (rating > 0)
              _Fact(
                icon: Icons.star_rounded,
                label: rating.toStringAsFixed(1),
                color: gold,
              ),
            if (year.isNotEmpty) _Fact(label: year),
            if (duration.isNotEmpty) _Fact(label: duration),
            if (genre.isNotEmpty) _Fact(label: genre, maxWidth: 230),
          ],
        ),
        if (plot.isNotEmpty) ...[
          const SizedBox(height: 17),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 680 : 540),
            child: Text(
              plot,
              maxLines: wide ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted,
                fontSize: wide ? 15.5 : 14,
                height: 1.5,
              ),
            ),
          ),
        ] else if (loadingDetails) ...[
          const SizedBox(height: 19),
          DetailMetadataSkeleton(maxWidth: wide ? 680 : 540),
        ],
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _PrimaryPlay(
              label: progress == null ? 'Play film' : 'Resume film',
              progress: progress?.fraction,
              onTap: onPlay,
            ),
            if (hasTrailer)
              _DetailAction(
                icon: Icons.smart_display_rounded,
                label: 'Trailer',
                onTap: onTrailer,
              ),
            downloadAction,
            favoriteAction,
          ],
        ),
      ],
    );
  }
}

class _PosterArtifact extends StatelessWidget {
  const _PosterArtifact({required this.url, required this.width});

  final String url;
  final double width;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: .018,
    child: Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: line, width: 1.5),
        boxShadow: glow(Colors.black, blur: 44, y: 22, a: .65),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 520,
            placeholder: (_, _) => const DetailBackdropPlaceholder(
              icon: Icons.movie_outlined,
              loading: true,
            ),
            errorWidget: (_, _, _) =>
                const DetailBackdropPlaceholder(icon: Icons.movie_outlined),
          ),
        ),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, this.icon, this.color, this.maxWidth});

  final String label;
  final IconData? icon;
  final Color? color;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) => Container(
    constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: surface.withValues(alpha: isDark ? .78 : .90),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color ?? textHi, size: 15),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? textHi,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PrimaryPlay extends StatelessWidget {
  const _PrimaryPlay({required this.label, required this.onTap, this.progress});

  final String label;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) => RemoteTap(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(14),
        boxShadow: glow(accent, blur: 24, y: 9, a: .42),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: onAccent, size: 23),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: onAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 112,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: onAccent.withValues(alpha: .28),
                valueColor: AlwaysStoppedAnimation(onAccent),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.progress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? onAccent : textHi;
    return RemoteTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : surface.withValues(alpha: isDark ? .82 : .92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.transparent : line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress == null)
              Icon(icon, color: foreground, size: 20)
            else
              SizedBox(
                width: 20,
                height: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2,
                      color: accentInk,
                    ),
                    Icon(icon, color: foreground, size: 12),
                  ],
                ),
              ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorialDetails extends StatelessWidget {
  const _EditorialDetails({
    required this.plot,
    required this.cast,
    required this.director,
    required this.genre,
    required this.format,
    required this.loading,
  });

  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String format;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final synopsis = plot.isEmpty
        ? loading
              ? 'The story and credits are arriving in the background. You can start watching now.'
              : 'No synopsis was supplied for this film.'
        : plot;
    final facts = [
      if (cast.isNotEmpty) ('CAST', cast),
      if (director.isNotEmpty) ('DIRECTED BY', director),
      if (genre.isNotEmpty) ('GENRE', genre),
      if (format.isNotEmpty) ('SOURCE FORMAT', format),
    ];

    final synopsisCard = _DetailPanel(
      eyebrow: 'THE STORY',
      child: Text(
        synopsis,
        style: TextStyle(color: muted, fontSize: wide ? 17 : 15, height: 1.65),
      ),
    );
    final factsCard = _DetailPanel(
      eyebrow: 'THE CREDITS',
      child: facts.isEmpty
          ? Text(
              loading ? 'Loading credits…' : 'Credits were not provided.',
              style: TextStyle(color: muted),
            )
          : Column(
              children: [
                for (var i = 0; i < facts.length; i++) ...[
                  if (i > 0) Divider(color: line, height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: wide ? 112 : 92,
                        child: Text(facts[i].$1, style: kSection()),
                      ),
                      Expanded(
                        child: Text(
                          facts[i].$2,
                          style: TextStyle(color: textHi, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );

    if (!wide) {
      return Column(
        children: [synopsisCard, const SizedBox(height: 14), factsCard],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: synopsisCard),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: factsCard),
      ],
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.eyebrow, required this.child});

  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: kSection()),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}
