import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../catalog_cache.dart';
import '../home_config.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

/// Pick which categories/playlists (movies, series, live) appear on Home.
/// When nothing is selected, Home shows its default mix.
class CustomizeHomeScreen extends StatefulWidget {
  final XtreamClient client;
  const CustomizeHomeScreen({super.key, required this.client});
  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  List<Category> _movies = [], _series = [], _live = [];
  bool _ready = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.client;
    final r = await Future.wait([
      CatalogCache.instance.vod(c),
      CatalogCache.instance.series(c),
      CatalogCache.instance.live(c),
    ]);
    if (!mounted) return;
    setState(() {
      _movies = r[0];
      _series = r[1];
      _live = r[2];
      _ready = true;
    });
  }

  List<Category> _filter(List<Category> cats) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return cats;
    return cats.where((c) => c.name.toLowerCase().contains(q)).toList();
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                      const SizedBox(width: 4),
                      const Text('Customize Home', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      AnimatedBuilder(
                        animation: HomeConfig.instance,
                        builder: (_, __) => HomeConfig.instance.isCustom
                            ? TextButton(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  HomeConfig.instance.clear();
                                },
                                child: Text('Reset', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SearchField(hint: 'Search categories…', onChanged: (v) => setState(() => _q = v)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: subtle),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Pick the categories to feature on Home. Empty = default mix.',
                            style: TextStyle(color: subtle, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !_ready
                      ? BrandedLoading()
                      : AnimatedBuilder(
                          animation: HomeConfig.instance,
                          builder: (context, _) => ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            children: [
                              _section('Movies', 'movie', _filter(_movies)),
                              _section('Series', 'series', _filter(_series)),
                              _section('Live TV', 'live', _filter(_live)),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, String type, List<Category> cats) {
    if (cats.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        ...cats.map((cat) {
          final on = HomeConfig.instance.isEnabled(type, cat.id);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              HomeConfig.instance.toggle(ShelfRef(type, cat.id, cat.name));
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: on ? accent.withValues(alpha: 0.14) : surfaceHi.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? accent.withValues(alpha: 0.5) : line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(cat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: on ? textHi : muted)),
                  ),
                  Icon(on ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                      color: on ? accent : subtle, size: 22),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
