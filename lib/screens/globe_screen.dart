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

/// "Discover" — a rotatable 3D globe of movie posters. Drag to spin (with
/// inertia), tap a poster to open it, or hit Surprise to fling and land on a
/// random pick. The pool is taste-weighted by what the user has watched.
class GlobeScreen extends StatefulWidget {
  final XtreamClient client;
  const GlobeScreen({super.key, required this.client});
  @override
  State<GlobeScreen> createState() => _GlobeScreenState();
}

class _GlobeScreenState extends State<GlobeScreen> with TickerProviderStateMixin {
  List<VodStream> _pool = [];
  List<_P3> _base = []; // unit sphere positions
  bool _loading = true;

  double _yaw = 0, _pitch = -0.15;
  double _vYaw = 0.0045, _vPitch = 0; // gentle idle spin
  bool _dragging = false;
  int _front = 0;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
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

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.016 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_dragging || _pool.isEmpty) return;
    // inertia + friction
    _yaw += _vYaw;
    _pitch = (_pitch + _vPitch).clamp(-1.1, 1.1);
    _vYaw *= 0.95;
    _vPitch *= 0.95;
    // settle into a gentle idle spin once inertia fades
    if (_vYaw.abs() < 0.004 && _vPitch.abs() < 0.002) {
      _vYaw = _vYaw + (0.0045 - _vYaw) * 0.04;
      _vPitch *= 0.9;
    }
    setState(() {});
  }

  void _surprise() {
    HapticFeedback.mediumImpact();
    _vYaw = (_rng.nextBool() ? 1 : -1) * (0.12 + _rng.nextDouble() * 0.08);
    _vPitch = (_rng.nextDouble() - 0.5) * 0.05;
  }

  // Fibonacci sphere — even point distribution.
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
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            const Text('Discover', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Spacer(),
            Icon(Icons.auto_awesome_rounded, color: accent, size: 20),
          ],
        ),
      );

  Widget _globe() {
    if (_pool.isEmpty) {
      return Center(child: Text('Nothing to discover yet.', style: TextStyle(color: subtle)));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        final cx = w / 2, cy = h / 2;
        final radius = math.min(w, h) * 0.40;
        const pw = 58.0, ph = 86.0;

        // project + sort back-to-front
        final projected = <_Proj>[];
        var frontIdx = 0;
        var frontDepth = -2.0;
        for (var i = 0; i < _base.length; i++) {
          final r = _rotate(_base[i]);
          if (r.z > frontDepth) {
            frontDepth = r.z;
            frontIdx = i;
          }
          final t = (r.z + 1) / 2; // 0 back .. 1 front
          projected.add(_Proj(
            i,
            cx + r.x * radius,
            cy + r.y * radius,
            r.z,
            0.55 + 0.55 * t,
            0.30 + 0.70 * t,
          ));
        }
        if (frontIdx != _front) {
          _front = frontIdx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        projected.sort((a, b) => a.depth.compareTo(b.depth));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _dragging = true;
            _vYaw = 0;
            _vPitch = 0;
          },
          onPanUpdate: (d) {
            setState(() {
              _yaw += d.delta.dx * 0.008;
              _pitch = (_pitch - d.delta.dy * 0.008).clamp(-1.1, 1.1);
              _vYaw = d.delta.dx * 0.008;
              _vPitch = -d.delta.dy * 0.008;
            });
          },
          onPanEnd: (_) => _dragging = false,
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
                      child: _poster(_pool[p.i], p.i == _front),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _poster(VodStream m, bool focused) {
    return GestureDetector(
      onTap: () => _open(m),
      child: Container(
        width: 58,
        height: 86,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: surfaceHi,
          border: focused ? Border.all(color: accent, width: 2) : null,
          boxShadow: focused ? glow(accent) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: m.icon,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Icon(Icons.movie_outlined, color: subtle, size: 20),
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
            Text(
              m.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _surprise,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
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
  _Proj(this.i, this.x, this.y, this.depth, this.scale, this.opacity);
}
