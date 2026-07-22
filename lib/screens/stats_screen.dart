import 'package:flutter/material.dart';
import '../catalog_cache.dart';
import '../models.dart';
import '../responsive.dart';
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
                final wide = isWide(context);
                return Column(
                  children: [
                    EditorialPageHeader(
                      eyebrow: 'Your viewing story',
                      title: 'Time well watched',
                      subtitle: s.total == 0
                          ? 'Your activity becomes a private story, kept only on this device.'
                          : '${s.titleCount} ${s.titleCount == 1 ? 'title' : 'titles'} across films, series and live TV',
                      icon: Icons.insights_rounded,
                      onBack: () => Navigator.of(context).pop(),
                      trailing: s.total > 0
                          ? RemoteTap(
                              onTap: s.reset,
                              focusRadius: 13,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: surfaceHi.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: line),
                                ),
                                child: Text(
                                  'Reset stats',
                                  style: TextStyle(
                                    color: muted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    Expanded(
                      child: s.total == 0
                          ? const LumenEmptyState(
                              icon: Icons.auto_graph_rounded,
                              eyebrow: 'A blank reel',
                              title: 'Your story starts with Play',
                              message:
                                  'Watch something in Lumen and this space will quietly map your week, formats and favourite collections.',
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1120,
                                  ),
                                  child: wide
                                      ? Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: Column(
                                                children: [
                                                  _hero(s),
                                                  const SizedBox(height: 16),
                                                  _split(s),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              flex: 6,
                                              child: Column(
                                                children: [
                                                  _weekChart(s),
                                                  const SizedBox(height: 16),
                                                  _topCats(s),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            _hero(s),
                                            const SizedBox(height: 16),
                                            _weekChart(s),
                                            const SizedBox(height: 16),
                                            _split(s),
                                            const SizedBox(height: 16),
                                            _topCats(s),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(WatchStats s) => Glass(
    radius: 26,
    padding: const EdgeInsets.all(24),
    tint: accent.withValues(alpha: isDark ? 0.16 : 0.10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ALL-TIME PLAYBACK', style: kSection(color: accent)),
            const Spacer(),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.play_arrow_rounded, color: onAccent),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          _dur(s.total),
          style: kDisplay(color: textHi).copyWith(fontSize: 48),
        ),
        const SizedBox(height: 6),
        Text(
          '${s.titleCount} distinct ${s.titleCount == 1 ? 'title' : 'titles'} watched',
          style: TextStyle(color: muted, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        Container(height: 1, color: accent.withValues(alpha: 0.24)),
        const SizedBox(height: 16),
        Text(
          'Your activity stays on this device.',
          style: TextStyle(color: subtle, fontSize: 11.5),
        ),
      ],
    ),
  );

  Widget _weekChart(WatchStats s) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final mins = days
        .map(
          (d) => (s.byDay['${d.year}-${two(d.month)}-${two(d.day)}'] ?? 0) / 60,
        )
        .toList();
    final maxMin = mins.fold<double>(1, (a, b) => b > a ? b : a);
    return Glass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This week',
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
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
                        Text(
                          mins[i] >= 1 ? '${mins[i].round()}' : '',
                          style: TextStyle(color: subtle, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          height: 8 + 78 * (mins[i] / maxMin),
                          decoration: BoxDecoration(
                            color: days[i].day == now.day
                                ? accent
                                : accent.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[days[i].weekday - 1],
                          style: TextStyle(
                            color: subtle,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    final total = (s.movie + s.series + s.live).clamp(1, 1 << 62);
    final values = [
      ('Films', s.movie, Icons.movie_outlined, accent),
      (
        'Series',
        s.series,
        Icons.video_library_outlined,
        const Color(0xFF22CBA8),
      ),
      ('Live TV', s.live, Icons.cell_tower_rounded, const Color(0xFFF59E0B)),
    ];
    return Glass(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What you watched',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Your playback mix',
            style: TextStyle(color: subtle, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 9,
              child: Row(
                children: [
                  for (final value in values)
                    if (value.$2 > 0)
                      Expanded(
                        flex: value.$2,
                        child: ColoredBox(color: value.$4),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(value.$3, color: value.$4, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      value.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${(value.$2 / total * 100).round()}%',
                    style: TextStyle(color: subtle, fontSize: 12),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 62,
                    child: Text(
                      _dur(value.$2),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
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

  Widget _topCats(WatchStats s) {
    final entries = s.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final maxV = top.first.value.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Glass(
          radius: 24,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Most-watched collections',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Where your time naturally gathers',
                style: TextStyle(color: subtle, fontSize: 12),
              ),
              const SizedBox(height: 16),
              for (final e in top) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        _catNames[e.key] ?? 'Category',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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
                    Text(
                      _dur(e.value),
                      style: TextStyle(color: subtle, fontSize: 12),
                    ),
                  ],
                ),
                if (e != top.last) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
