import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../library.dart';
import '../models.dart';
import '../responsive.dart';
import '../theme.dart';
import '../playback.dart';
import '../tmdb.dart';
import '../xtream.dart';

class MovieDetailScreen extends StatefulWidget {
  final XtreamClient client;
  final VodStream movie;
  const MovieDetailScreen({super.key, required this.client, required this.movie});
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  VodInfo? _info;
  TmdbInfo? _tmdb;

  @override
  void initState() {
    super.initState();
    widget.client.vodInfo(widget.movie.streamId).then((v) {
      if (mounted) setState(() => _info = v);
    }).catchError((_) {});
    Tmdb.movie(widget.movie.name).then((t) {
      if (mounted && t != null) setState(() => _tmdb = t);
    });
  }

  Future<void> _trailer() async {
    final url = _tmdb?.trailerUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _play() {
    final ext = _info?.containerExtension.isNotEmpty == true
        ? _info!.containerExtension
        : widget.movie.containerExtension;
    final url = widget.client.streamUrl('movie', widget.movie.streamId, ext: ext);
    PlaybackController.instance.open([
      PlayerItem(
        url,
        widget.movie.name,
        progressKey: 'movie:${widget.movie.streamId}',
        poster: widget.movie.icon,
        ext: ext,
        favRef: _ref(),
      )
    ], 0);
  }

  MediaRef _ref() => MediaRef(
      kind: 'movie',
      id: widget.movie.streamId,
      name: widget.movie.name,
      image: widget.movie.icon,
      cat: widget.movie.categoryId);

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    final info = _info;
    final t = _tmdb;
    // Prefer richer TMDB metadata, fall back to provider data.
    final backdrop = (t?.backdrop.isNotEmpty == true)
        ? t!.backdrop
        : (info?.backdrop.isNotEmpty == true ? info!.backdrop : m.icon);
    final posterUrl = (t?.poster.isNotEmpty == true) ? t!.poster : m.icon;
    final rating = (t?.rating ?? 0) > 0
        ? t!.rating
        : (info?.rating != null && info!.rating > 0 ? info.rating : m.rating);
    final rawDate = t?.releaseDate.isNotEmpty == true ? t!.releaseDate : (info?.releaseDate ?? '');
    final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : rawDate;
    final genre = t?.genres.isNotEmpty == true ? t!.genres : (info?.genre ?? '');
    final plot = t?.overview.isNotEmpty == true ? t!.overview : (info?.plot ?? '');
    final cast = t?.cast.isNotEmpty == true ? t!.cast : (info?.cast ?? '');
    final wide = isWide(context);
    final h = MediaQuery.sizeOf(context).height;

    // ---- shared building blocks ----
    Widget posterCard(double w) => Container(
          width: w,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: glow(Colors.black, blur: 30, y: 14, a: 0.55),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: posterUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: posterUrl, fit: BoxFit.cover, errorWidget: (_, _, _) => ColoredBox(color: surfaceHi))
                  : ColoredBox(color: surfaceHi),
            ),
          ),
        );

    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: surfaceHi.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: line),
          ),
          child: child,
        );

    Widget metaChips(WrapAlignment align) => Wrap(
          alignment: align,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (rating > 0)
              chip(Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, color: gold, size: 15),
                const SizedBox(width: 4),
                Text(rating.toStringAsFixed(1), style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: 13)),
              ])),
            if (year.isNotEmpty) chip(Text(year, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            if (info?.duration.isNotEmpty == true) chip(Text(info!.duration, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            if (genre.isNotEmpty) chip(Text(genre, style: TextStyle(color: muted, fontSize: 13))),
          ],
        );

    Widget favBtn() => AnimatedBuilder(
          animation: Library.instance,
          builder: (_, __) {
            final fav = Library.instance.isFav(_ref().key);
            return GestureDetector(
              onTap: () => Library.instance.toggleFav(_ref()),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: surfaceHi.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: line),
                ),
                child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? accent2 : textHi, size: 22),
              ),
            );
          },
        );

    Widget actions(bool expandPlay) {
      final play = GestureDetector(
        onTap: _play,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: expandPlay ? 0 : 34, vertical: 15),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16), boxShadow: glow(accent, blur: 22, y: 8, a: 0.5)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
            SizedBox(width: 6),
            Text('Play', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
          ]),
        ),
      );
      return Row(
        children: [
          expandPlay ? Expanded(child: play) : play,
          if (t?.trailerUrl != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _trailer,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.smart_display_rounded, color: accent, size: 22),
                  const SizedBox(width: 6),
                  const Text('Trailer', style: TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ],
          const SizedBox(width: 12),
          favBtn(),
        ],
      );
    }

    Widget infoBlock(CrossAxisAlignment align, TextAlign ta, double titleSize) => Column(
          crossAxisAlignment: align,
          children: [
            Text(m.name, textAlign: ta, style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w800, height: 1.05))
                .animate()
                .fadeIn()
                .slideY(begin: 0.15, end: 0),
            const SizedBox(height: 14),
            metaChips(align == CrossAxisAlignment.center ? WrapAlignment.center : WrapAlignment.start),
            const SizedBox(height: 22),
            actions(align != CrossAxisAlignment.center ? false : true),
            if (plot.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(plot, textAlign: align == CrossAxisAlignment.center ? TextAlign.center : TextAlign.start, style: TextStyle(color: muted, height: 1.6, fontSize: 15)),
            ],
            if (cast.isNotEmpty) ...[
              const SizedBox(height: 18),
              _meta('Cast', cast, ta),
            ],
            if (info?.director.isNotEmpty == true) _meta('Director', info!.director, ta),
          ],
        );

    final body = wide
        ? SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 0, 36, 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 280),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          posterCard(232),
                          const SizedBox(width: 40),
                          Expanded(child: Padding(padding: const EdgeInsets.only(top: 28), child: infoBlock(CrossAxisAlignment.start, TextAlign.start, 40))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: h * 0.20),
                posterCard(150),
                const SizedBox(height: 22),
                infoBlock(CrossAxisAlignment.center, TextAlign.center, 26),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Full-bleed backdrop with a fade into the page.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: wide ? 540 : h * 0.5,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.transparent],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: backdrop.isNotEmpty
                  ? CachedNetworkImage(imageUrl: backdrop, fit: BoxFit.cover)
                  : ColoredBox(color: surfaceHi),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, bg.withValues(alpha: 0.6), bg, bg],
                  stops: const [0.0, 0.45, 0.72, 1],
                ),
              ),
            ),
          ),
          SafeArea(child: body),
          // pinned back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value, TextAlign align) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: RichText(
          textAlign: align,
          text: TextSpan(style: TextStyle(color: muted, height: 1.4), children: [
            TextSpan(text: '$label:  ', style: TextStyle(color: subtle, fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ]),
        ),
      );
}
