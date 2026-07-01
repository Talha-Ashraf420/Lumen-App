import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../catalog_cache.dart';
import '../discovery.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'category_sheet.dart';
import 'movie_detail_screen.dart';
import 'swipe_screen.dart';

/// "Discover" — a dense, rotatable 3D globe of movie posters. One finger spins
/// it (with inertia); two fingers pinch to zoom in. Tap a poster to open it, or
/// hit Surprise to fling to a random pick. The pool is taste-weighted.
class GlobeScreen extends StatefulWidget {
  final XtreamClient client;
  const GlobeScreen({super.key, required this.client});
  @override
  State<GlobeScreen> createState() => _GlobeScreenState();
}

class _GlobeScreenState extends State<GlobeScreen> with TickerProviderStateMixin {
  List<VodStream> _pool = [];
  List<_P3> _base = [];
  bool _loading = true;
  List<Category> _cats = [];
  String? _cat; // null = "For you" (taste-weighted mix)

  double _yaw = 0, _pitch = -0.12;
  double _vYaw = 0.04, _vPitch = 0; // initial intro spin, decays to rest
  double _zoom = 1.0, _zoomStart = 1.0;
  bool _interacting = false;
  int _front = 0;

  late final Ticker _ticker;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    CatalogCache.instance.vod(widget.client).then((c) => mounted ? setState(() => _cats = c) : null);
    _load();
  }

  Future<void> _load() async {
    try {
      final pool = await Discovery.pool(widget.client, target: 250, categoryId: _cat);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _base = _fibSphere(pool.length);
        _loading = false;
        _yaw = 0;
        _pitch = -0.12;
        _vYaw = 0.04;
        _zoom = 1.0;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _genreLabel =>
      _cat == null ? 'For you' : _cats.firstWhere((c) => c.id == _cat, orElse: () => Category(_cat!, 'Genre')).name;

  Future<void> _pickGenre() async {
    final r = await showCategorySheet(context, categories: _cats, selected: _cat ?? 'all');
    if (r == null || !mounted) return;
    setState(() {
      _cat = (r == 'all') ? null : r;
      _loading = true;
    });
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Spin via inertia only; rest (no rebuilds) once it slows — keeps a big globe smooth.
  void _tick(Duration elapsed) {
    if (_interacting || _pool.isEmpty) return;
    if (_vYaw.abs() < 0.0009 && _vPitch.abs() < 0.0009) return;
    _yaw += _vYaw;
    _pitch = (_pitch + _vPitch).clamp(-1.1, 1.1);
    _vYaw *= 0.94;
    _vPitch *= 0.94;
    setState(() {});
  }

  void _surprise() {
    HapticFeedback.mediumImpact();
    _vYaw = (_rng.nextBool() ? 1 : -1) * (0.16 + _rng.nextDouble() * 0.1);
    _vPitch = (_rng.nextDouble() - 0.5) * 0.06;
  }

  List<_P3> _fibSphere(int n) {
    if (n == 0) return [];
    final pts = <_P3>[];
    final golden = math.pi * (3 - math.sqrt(5));
    for (var i = 0; i < n; i++) {
      final y = n == 1 ? 0.0 : 1 - (i / (n - 1)) * 2;
      final r = math.sqrt(math.max(0, 1 - y * y));
      final t = golden * i;
      pts.add(_P3(math.cos(t) * r, y, math.sin(t) * r));
    }
    return pts;
  }

  _P3 _rotate(_P3 v) {
    final cy = math.cos(_yaw), sy = math.sin(_yaw);
    final x1 = v.x * cy + v.z * sy;
    final z1 = -v.x * sy + v.z * cy;
    final cx = math.cos(_pitch), sx = math.sin(_pitch);
    final y2 = v.y * cx - z1 * sx;
    final z2 = v.y * sx + z1 * cx;
    return _P3(x1, y2, z2);
  }

  void _open(VodStream m) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(client: widget.client, movie: m),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Aurora(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                _genreBar(),
                Expanded(child: _loading ? BrandedLoading() : _globe()),
                _footer(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
        child: Row(
          children: [
            // Discover is a root tab (not a pushed route), so only show a back
            // button when there's actually something to pop — otherwise popping
            // would unwind the whole app shell and leave a black screen.
            if (Navigator.of(context).canPop()) ...[
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
              const SizedBox(width: 4),
            ] else
              const SizedBox(width: 4),
            const Text('Discover', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${_pool.length}', style: TextStyle(color: subtle, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SwipeScreen(client: widget.client))),
              icon: Icon(Icons.style_rounded, color: accent),
              tooltip: 'Swipe',
            ),
          ],
        ),
      );

  Widget _genreBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: GestureDetector(
          onTap: _cats.isEmpty ? null : _pickGenre,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: surfaceHi.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
            ),
            child: Row(children: [
              Icon(Icons.theaters_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_genreLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: muted),
            ]),
          ),
        ),
      );

  Widget _globe() {
    if (_pool.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Couldn’t load titles.', style: TextStyle(color: subtle)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                setState(() => _loading = true);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        final cx = w / 2, cy = h / 2;
        final radius = math.min(w, h) * 0.42 * _zoom;
        final pw = 40.0 * _zoom, ph = 60.0 * _zoom;

        final projected = <_Proj>[];
        var frontIdx = 0;
        var frontDepth = -2.0;
        for (var i = 0; i < _base.length; i++) {
          final r = _rotate(_base[i]);
          if (r.z > frontDepth) {
            frontDepth = r.z;
            frontIdx = i;
          }
          final t = (r.z + 1) / 2; // 0 = far back, 1 = front
          if (t < 0.06) continue; // cull only the deep-back tip
          projected.add(_Proj(i, cx + r.x * radius, cy + r.y * radius, r.z, 0.6 + 0.5 * t, 0.28 + 0.72 * t, true));
        }
        if (frontIdx != _front) {
          _front = frontIdx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        projected.sort((a, b) => a.depth.compareTo(b.depth));

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              _interacting = true;
              _vYaw = 0;
              _vPitch = 0;
              _zoomStart = _zoom;
            },
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) {
                setState(() {
                  _zoom = (_zoomStart * d.scale).clamp(1.0, 3.0);
                  _vYaw = 0;
                  _vPitch = 0;
                });
              } else {
                setState(() {
                  _yaw += d.focalPointDelta.dx * 0.008;
                  _pitch = (_pitch - d.focalPointDelta.dy * 0.008).clamp(-1.1, 1.1);
                  _vYaw = d.focalPointDelta.dx * 0.008;
                  _vPitch = -d.focalPointDelta.dy * 0.008;
                });
              }
            },
            onScaleEnd: (_) => _interacting = false,
            child: Stack(
              children: [
                for (final p in projected)
                  Positioned(
                    left: p.x - pw / 2,
                    top: p.y - ph / 2,
                    child: Opacity(
                      opacity: p.opacity,
                      child: Transform.scale(
                        scale: p.scale,
                        child: _poster(_pool[p.i], pw, ph, p.i == _front, p.img),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _poster(VodStream m, double w, double h, bool focused, bool loadImage) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _open(m),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: surfaceHi,
            border: focused ? Border.all(color: accent, width: 2) : null,
          ),
          clipBehavior: Clip.antiAlias,
          // Only front-facing posters load an image (small-decoded to bound
          // memory across a ~1000-poster globe); the rest are plain tiles.
          child: loadImage
              ? CachedNetworkImage(
                  imageUrl: m.icon,
                  fit: BoxFit.cover,
                  memCacheWidth: 160,
                  errorWidget: (_, _, _) => Icon(Icons.movie_outlined, color: subtle, size: 18),
                )
              : null,
        ),
      ),
    );
  }

  Widget _footer() {
    final m = _pool.isNotEmpty ? _pool[_front.clamp(0, _pool.length - 1)] : null;
    // Bottom padding lifts the controls clear of the floating nav bar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m != null)
            Text(
              m.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.15,
                letterSpacing: -0.3,
                shadows: [Shadow(color: Colors.black, blurRadius: 12)],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Compact pill: spin to a random pick.
              GestureDetector(
                onTap: _surprise,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                      color: surfaceHi.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.casino_rounded, color: accent, size: 19),
                    const SizedBox(width: 7),
                    const Text('Surprise', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              // Compact pill: open the focused pick.
              GestureDetector(
                onTap: m == null ? null : () => _open(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(30), boxShadow: glow(accent)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 5),
                    Text('Open', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _P3 {
  final double x, y, z;
  _P3(this.x, this.y, this.z);
}

class _Proj {
  final int i;
  final double x, y, depth, scale, opacity;
  final bool img;
  _Proj(this.i, this.x, this.y, this.depth, this.scale, this.opacity, this.img);
}
