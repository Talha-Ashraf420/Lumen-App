import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../library.dart';
import '../models.dart';
import '../theme.dart';
import '../xtream.dart';
import 'player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final XtreamClient client;
  final VodStream movie;
  const MovieDetailScreen({super.key, required this.client, required this.movie});
  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  VodInfo? _info;

  @override
  void initState() {
    super.initState();
    widget.client.vodInfo(widget.movie.streamId).then((v) {
      if (mounted) setState(() => _info = v);
    }).catchError((_) {});
  }

  void _play() {
    final ext = _info?.containerExtension.isNotEmpty == true
        ? _info!.containerExtension
        : widget.movie.containerExtension;
    final url = widget.client.streamUrl('movie', widget.movie.streamId, ext: ext);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(items: [
              PlayerItem(
                url,
                widget.movie.name,
                progressKey: 'movie:${widget.movie.streamId}',
                poster: widget.movie.icon,
                ext: ext,
                favRef: _ref(),
              )
            ])));
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
    final backdrop = (info?.backdrop.isNotEmpty == true) ? info!.backdrop : m.icon;
    final rating = info?.rating != null && info!.rating > 0 ? info.rating : m.rating;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // backdrop
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.6,
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
                  colors: [Colors.transparent, bg, bg],
                  stops: [0.25, 0.7, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        style: IconButton.styleFrom(backgroundColor: Colors.black38),
                      ),
                      const Spacer(),
                      AnimatedBuilder(
                        animation: Library.instance,
                        builder: (_, __) {
                          final fav = Library.instance.isFav(_ref().key);
                          return IconButton(
                            onPressed: () => Library.instance.toggleFav(_ref()),
                            icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? accent2 : Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.black38),
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.34),
                  Text(m.name,
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.05))
                      .animate()
                      .fadeIn()
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating > 0)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.star_rounded, color: gold, size: 18),
                          const SizedBox(width: 4),
                          Text(rating.toStringAsFixed(1),
                              style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
                        ]),
                      if (info?.releaseDate.isNotEmpty == true)
                        Text(info!.releaseDate, style: TextStyle(color: muted)),
                      if (info?.duration.isNotEmpty == true)
                        Text(info!.duration, style: TextStyle(color: muted)),
                      if (info?.genre.isNotEmpty == true)
                        Text(info!.genre, style: TextStyle(color: subtle)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _play,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: glow(accent, blur: 22, y: 8, a: 0.5),
                            ),
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Play', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (info?.plot.isNotEmpty == true) ...[
                    const SizedBox(height: 22),
                    Text(info!.plot, style: TextStyle(color: muted, height: 1.5)),
                  ],
                  if (info?.cast.isNotEmpty == true) ...[
                    const SizedBox(height: 18),
                    _meta('Cast', info!.cast),
                  ],
                  if (info?.director.isNotEmpty == true) _meta('Director', info!.director),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: RichText(
          text: TextSpan(style: TextStyle(color: muted, height: 1.4), children: [
            TextSpan(text: '$label:  ', style: TextStyle(color: subtle, fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ]),
        ),
      );
}
