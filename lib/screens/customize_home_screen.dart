import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../catalog_cache.dart';
import '../home_config.dart';
import '../models.dart';
import '../responsive.dart';
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
  String _type = 'movie';

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
    final wide = isWide(context);
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Aurora(),
          SafeArea(
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: HomeConfig.instance,
                  builder: (_, child) => EditorialPageHeader(
                    eyebrow: 'Home studio',
                    title: 'Build your own front row',
                    subtitle: HomeConfig.instance.isCustom
                        ? '${HomeConfig.instance.shelves.length} shelves will appear in this order on Home.'
                        : 'Choose the collections that deserve a place on Home.',
                    icon: Icons.dashboard_customize_rounded,
                    onBack: () => Navigator.of(context).pop(),
                    trailing: HomeConfig.instance.isCustom
                        ? RemoteTap(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              HomeConfig.instance.clear();
                            },
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
                              child: const Text(
                                'Use default',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                Expanded(
                  child: !_ready
                      ? BrandedLoading()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: wide
                              ? Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: 340,
                                      child: _selectedPanel(),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(child: _browser()),
                                  ],
                                )
                              : _browser(showSelectedStrip: true),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _browser({bool showSelectedStrip = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showSelectedStrip) ...[_selectedStrip(), const SizedBox(height: 12)],
      SearchField(
        hint: 'Find a collection…',
        onChanged: (value) => setState(() => _q = value),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            LumenFilterPill(
              label: 'Films',
              icon: Icons.movie_outlined,
              selected: _type == 'movie',
              onTap: () => setState(() => _type = 'movie'),
            ),
            const SizedBox(width: 8),
            LumenFilterPill(
              label: 'Series',
              icon: Icons.video_library_outlined,
              selected: _type == 'series',
              onTap: () => setState(() => _type = 'series'),
            ),
            const SizedBox(width: 8),
            LumenFilterPill(
              label: 'Live TV',
              icon: Icons.cell_tower_rounded,
              selected: _type == 'live',
              onTap: () => setState(() => _type = 'live'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(child: _categoryGrid()),
    ],
  );

  Widget _categoryGrid() {
    final source = switch (_type) {
      'series' => _series,
      'live' => _live,
      _ => _movies,
    };
    final cats = _filter(source);
    if (cats.isEmpty) {
      return LumenEmptyState(
        icon: Icons.search_off_rounded,
        eyebrow: 'No collection found',
        title: 'Try a broader search',
        message:
            'No ${_type == 'live' ? 'live' : _type} collection matches “$_q”.',
      );
    }
    return AnimatedBuilder(
      animation: HomeConfig.instance,
      builder: (context, child) => GridView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 430,
          mainAxisExtent: 62,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
        ),
        itemCount: cats.length,
        itemBuilder: (_, index) {
          final cat = cats[index];
          final on = HomeConfig.instance.isEnabled(_type, cat.id);
          return RemoteTap(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              HomeConfig.instance.toggle(ShelfRef(_type, cat.id, cat.name));
            },
            focusRadius: 15,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on
                    ? accent.withValues(alpha: 0.14)
                    : surfaceHi.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: on ? accent.withValues(alpha: 0.48) : line,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: on ? accent : surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      on ? Icons.check_rounded : Icons.add_rounded,
                      color: on ? onAccent : muted,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      cat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: on ? textHi : muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectedPanel() => AnimatedBuilder(
    animation: HomeConfig.instance,
    builder: (_, child) {
      final shelves = HomeConfig.instance.shelves;
      return Glass(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR HOME', style: kSection(color: accent)),
            const SizedBox(height: 7),
            Text(
              shelves.isEmpty
                  ? 'Lumen mix'
                  : '${shelves.length} custom shelves',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              shelves.isEmpty
                  ? 'Lumen will blend recommendations, recent additions and live picks.'
                  : 'Use the arrows to tune the order. The first shelf appears highest.',
              style: TextStyle(color: subtle, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: line),
            const SizedBox(height: 8),
            Expanded(
              child: shelves.isEmpty
                  ? Center(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: accent.withValues(alpha: 0.5),
                        size: 46,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: shelves.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 7),
                      itemBuilder: (_, index) =>
                          _selectedRow(shelves[index], index, shelves.length),
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _selectedStrip() => AnimatedBuilder(
    animation: HomeConfig.instance,
    builder: (_, child) {
      final count = HomeConfig.instance.shelves.length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: surfaceHi.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(
              count == 0
                  ? Icons.auto_awesome_rounded
                  : Icons.view_carousel_rounded,
              color: accent,
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                count == 0
                    ? 'Using Lumen’s default mix'
                    : '$count shelves selected · order can be tuned on a larger screen',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _selectedRow(ShelfRef shelf, int index, int total) => Container(
    padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
    decoration: BoxDecoration(
      color: surfaceHi.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: line),
    ),
    child: Row(
      children: [
        Text(
          '${index + 1}'.padLeft(2, '0'),
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shelf.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              Text(
                shelf.type == 'movie'
                    ? 'Films'
                    : shelf.type == 'series'
                    ? 'Series'
                    : 'Live TV',
                style: TextStyle(color: subtle, fontSize: 10.5),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: index == 0
              ? null
              : () => HomeConfig.instance.reorder(index, index - 1),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          visualDensity: VisualDensity.compact,
          tooltip: 'Move up',
        ),
        IconButton(
          onPressed: index == total - 1
              ? null
              : () => HomeConfig.instance.reorder(index, index + 2),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          visualDensity: VisualDensity.compact,
          tooltip: 'Move down',
        ),
        IconButton(
          onPressed: () => HomeConfig.instance.toggle(shelf),
          icon: Icon(Icons.close_rounded, color: muted, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove shelf',
        ),
      ],
    ),
  );
}
