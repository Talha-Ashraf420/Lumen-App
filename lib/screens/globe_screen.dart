import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../discovery.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'movie_detail_screen.dart';

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
    _load();
  }

  Future<void> _load() async {
    try {
      final pool = await Discovery.pool(widget.client);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _base = _fibSphere(pool.length);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
          const Aurora(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(child: _loading ? const BrandedLoading() : _globe()),
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
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 4),
            const Text('Discover', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${_pool.length}', style: TextStyle(color: subtle, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Icon(Icons.auto_awesome_rounded, color: accent, size: 20),
          ],
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
          if (t < 0.12) continue; // cull the deep back (occluded anyway)
          projected.add(_Proj(i, cx + r.x * radius, cy + r.y * radius, r.z, 0.6 + 0.5 * t, 0.28 + 0.72 * t, t > 0.55));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m != null)
            Text(m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _surprise,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: surfaceHi.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.casino_rounded, color: accent, size: 20),
                      const SizedBox(width: 8),
                      const Text('Surprise me', style: TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: m == null ? null : () => _open(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16), boxShadow: glow(accent)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 6),
                      Text('Open', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ]),
                  ),
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
