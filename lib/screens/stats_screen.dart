import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../models.dart';
import '../stats.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';

/// "Your Lumen" — watch-time stats: total time, this-week activity, the
/// movie/series/live split, and top categories.
class StatsScreen extends StatefulWidget {
  final XtreamClient client;
  const StatsScreen({super.key, required this.client});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, String> _catNames = {}; // id -> name

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    final c = widget.client;
    final lists = await Future.wait([
      CatalogCache.instance.vod(c),
      CatalogCache.instance.series(c),
      CatalogCache.instance.live(c),
    ]);
    if (!mounted) return;
    final map = <String, String>{};
    for (final l in lists) {
      for (final Category cat in l) {
        map[cat.id] = cat.name;
      }
    }
    setState(() => _catNames = map);
  }

  String _dur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Aurora(),
          SafeArea(
            child: AnimatedBuilder(
              animation: WatchStats.instance,
              builder: (context, _) {
                final s = WatchStats.instance;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                        const SizedBox(width: 4),
                        const Text('Your Lumen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (s.total > 0)
                          TextButton(onPressed: s.reset, child: Text('Reset', style: TextStyle(color: accent, fontWeight: FontWeight.w700))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (s.total == 0)
                      _empty()
                    else ...[
                      _hero(s),
                      const SizedBox(height: 18),
                      _weekChart(s),
                      const SizedBox(height: 18),
                      _split(s),
                      const SizedBox(height: 18),
                      _topCats(s),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded, color: subtle, size: 44),
            const SizedBox(height: 14),
            Text('No watch history yet', style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text('Play something and your stats will show up here.', textAlign: TextAlign.center, style: TextStyle(color: subtle)),
          ],
        ),
      );

  Widget _hero(WatchStats s) => Glass(
        radius: 22,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: glow(accent)),
              child: const Icon(Icons.timer_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dur(s.total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${s.titleCount} title${s.titleCount == 1 ? '' : 's'} watched', style: TextStyle(color: subtle)),
              ],
            ),
          ],
        ),
      );

  Widget _weekChart(WatchStats s) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final mins = days.map((d) => (s.byDay['${d.year}-${two(d.month)}-${two(d.day)}'] ?? 0) / 60).toList();
    final maxMin = mins.fold<double>(1, (a, b) => b > a ? b : a);
    return Glass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(mins[i] >= 1 ? '${mins[i].round()}' : '', style: TextStyle(color: subtle, fontSize: 10)),
                        const SizedBox(height: 4),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          height: 8 + 78 * (mins[i] / maxMin),
                          decoration: BoxDecoration(
                            color: days[i].day == now.day ? accent : accent.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(labels[days[i].weekday - 1], style: TextStyle(color: subtle, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _split(WatchStats s) {
    Widget cell(String label, int secs, IconData icon) => Expanded(
          child: Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(height: 8),
              Text(_dur(secs), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: subtle, fontSize: 12)),
            ]),
          ),
        );
    return Row(children: [
      cell('Movies', s.movie, Icons.movie_rounded),
      const SizedBox(width: 12),
      cell('Series', s.series, Icons.live_tv_rounded),
      const SizedBox(width: 12),
      cell('Live', s.live, Icons.cell_tower_rounded),
    ]);
  }

  Widget _topCats(WatchStats s) {
    final entries = s.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final maxV = top.first.value.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Top categories', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        Glass(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final e in top) ...[
                Row(children: [
                  Expanded(
                    flex: 5,
                    child: Text(_catNames[e.key] ?? 'Category', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: e.value / maxV,
                          minHeight: 6,
                          backgroundColor: surfaceHi,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ),
                  ),
                  Text(_dur(e.value), style: TextStyle(color: subtle, fontSize: 12)),
                ]),
                if (e != top.last) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
