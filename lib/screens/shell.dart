import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../downloads.dart';
import '../models.dart';
import '../refresh.dart';
import '../updater.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'downloads_screen.dart';
import 'epg_guide_screen.dart';
import 'globe_screen.dart';
import 'home_screen.dart';
import 'update_dialog.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  final void Function(XtreamCredentials) onSwitch;
  const HomeShell({super.key, required this.client, required this.onLogout, required this.onSwitch});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  // Auto-refresh the catalog when the app returns to the foreground (throttled),
  // so recently-added movies surface without a manual Refresh.
  DateTime _lastRefresh = DateTime.now();
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  // Total destinations (mobile shows 0–4; desktop sidebar adds Movies/Series/
  // Live/TV-Guide/Downloads = 5/6/7/8/9 — see _pageFor and _Sidebar).
  static const _pageCount = 10;

  // Mobile bottom-nav tabs (indices 0–4).
  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.auto_awesome_rounded, label: 'Discover'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Quietly check for a newer build once per launch (skip dev builds).
    if (kBuildNumber > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final info = await Updater.instance.check();
        if (info != null && mounted) showUpdateFlow(context, info);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    // Throttle: only re-fetch if it's been a few minutes since the last refresh.
    if (now.difference(_lastRefresh) > const Duration(minutes: 3)) {
      _lastRefresh = now;
      refreshContent();
    }
  }

  Widget _pageFor(int i) => switch (i) {
        0 => HomeScreen(client: widget.client, onBrowse: () => _select(2)),
        1 => GlobeScreen(client: widget.client),
        2 => SearchScreen(client: widget.client),
        3 => MyListScreen(client: widget.client),
        4 => ProfileScreen(client: widget.client, onLogout: widget.onLogout, onSwitch: widget.onSwitch),
        5 => SearchScreen(client: widget.client, initialSection: 'movie'),
        6 => SearchScreen(client: widget.client, initialSection: 'series'),
        7 => SearchScreen(client: widget.client, initialSection: 'live'),
        8 => EpgGuideScreen(client: widget.client),
        _ => DownloadsScreen(client: widget.client),
      };

  void _select(int i) {
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    final pages = [
      for (var i = 0; i < _pageCount; i++)
        _visited.contains(i) ? _pageFor(i) : const SizedBox.shrink(),
    ];
    final wide = isWide(context);
    return Scaffold(
      body: Stack(
        children: [
          Aurora(),
          if (wide) _wideLayout(pages) else _mobileLayout(pages),
        ],
      ),
    );
  }

  // ---- desktop: floating glass sidebar + full-bleed content ----
  Widget _wideLayout(List<Widget> pages) {
    return Row(
      children: [
        _Sidebar(index: _index, onSelect: _select),
        Expanded(child: IndexedStack(index: _index, children: pages)),
      ],
    );
  }

  // ---- mobile: floating bottom nav ----
  Widget _mobileLayout(List<Widget> pages) {
    return Stack(
      children: [
        SafeArea(bottom: false, child: IndexedStack(index: _index, children: pages)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Glass(
              radius: 30,
              blur: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (var i = 0; i < _nav.length; i++) _item(i)],
              ),
            ),
          ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.6, end: 0, curve: Curves.easeOutBack),
        ),
      ],
    );
  }

  Widget _item(int i) {
    final sel = i == _index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(horizontal: sel ? 14 : 11, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? accent : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(_nav[i].icon, size: 21, color: sel ? Colors.white : muted),
            if (sel) ...[
              const SizedBox(width: 7),
              Text(_nav[i].label, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Collapsing icon rail ─────────────────────────────────────────────────────
// A thin icon-only rail that expands on hover to reveal labels, with a glowing
// accent pill that physically slides to the active destination. All rows share
// one coordinate space (a Stack) so the pill can animate between them.

const double _railCollapsed = 76;
const double _railExpanded = 250;
const double _railItemH = 52; // height of one nav row
const double _railGroupGap = 14; // gap a divider/group break occupies

/// One entry in the rail: either a nav destination or a group separator.
class _Nav {
  final IconData icon;
  final String label;
  final int page;
  final bool trailingIsDownloads;
  const _Nav(this.icon, this.label, this.page, {this.trailingIsDownloads = false});
}

// Flat, ordered list of destinations. `null` marks a group separator (gap).
// Page indices match _HomeShellState._pageFor.
const List<_Nav?> _railRows = [
  _Nav(Icons.home_rounded, 'Home', 0),
  _Nav(Icons.auto_awesome_rounded, 'Discover', 1),
  _Nav(Icons.movie_rounded, 'Movies', 5),
  _Nav(Icons.video_library_rounded, 'Series', 6),
  _Nav(Icons.live_tv_rounded, 'Live TV', 7),
  _Nav(Icons.grid_view_rounded, 'TV Guide', 8),
  _Nav(Icons.search_rounded, 'Search', 2),
  null, // ── Library
  _Nav(Icons.favorite_rounded, 'My List', 3),
  _Nav(Icons.download_rounded, 'Downloads', 9, trailingIsDownloads: true),
  null, // ── Account
  _Nav(Icons.person_rounded, 'Profile', 4),
];

class _Sidebar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});
  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  bool _open = false;

  /// Vertical offset of the row that owns [page], and whether it exists.
  double? _pillTop(int page) {
    double y = 0;
    for (final r in _railRows) {
      if (r == null) {
        y += _railGroupGap;
        continue;
      }
      if (r.page == page) return y;
      y += _railItemH;
    }
    return null;
  }

  double get _contentHeight {
    double y = 0;
    for (final r in _railRows) {
      y += r == null ? _railGroupGap : _railItemH;
    }
    return y;
  }

  @override
  Widget build(BuildContext context) {
    final w = _open ? _railExpanded : _railCollapsed;
    final pillTop = _pillTop(widget.index);

    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: w,
            decoration: BoxDecoration(
              color: surface.withValues(alpha: isDark ? 0.44 : 0.74),
              border: Border(right: BorderSide(color: line)),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SizedBox(
                        height: _contentHeight,
                        child: Stack(
                          children: [
                            // the sliding glow pill (behind the rows)
                            if (pillTop != null)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 340),
                                curve: Curves.easeOutCubic,
                                top: pillTop + 4,
                                left: 10,
                                right: 10,
                                height: _railItemH - 8,
                                child: _pill(),
                              ),
                            // the rows
                            Column(children: [for (final r in _railRows) _row(r)]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [accent, accentDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: -2, offset: const Offset(0, 4))],
        ),
      );

  Widget _header(BuildContext context) => SizedBox(
        height: 74,
        child: Row(
          children: [
            // brand mark stays fixed in the collapsed column; wordmark fades in
            SizedBox(width: _railCollapsed, child: Center(child: LumenMark(size: 22))),
            Expanded(
              child: ClipRect(
                child: Row(
                  children: [
                    Text('Lumen',
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: textHi, letterSpacing: -0.5)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () {
                        refreshContent();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(const SnackBar(content: Text('Refreshing content…'), duration: Duration(seconds: 2)));
                      },
                      icon: Icon(Icons.refresh_rounded, color: muted, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _row(_Nav? r) {
    if (r == null) {
      // group separator — a hairline that only shows when expanded
      return SizedBox(
        height: _railGroupGap,
        child: Center(
          child: AnimatedOpacity(
            opacity: _open ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Divider(height: 1, color: line)),
          ),
        ),
      );
    }
    final sel = r.page == widget.index;
    return _RailItem(
      nav: r,
      selected: sel,
      open: _open,
      onTap: () => widget.onSelect(r.page),
    );
  }
}

class _RailItem extends StatelessWidget {
  final _Nav nav;
  final bool selected;
  final bool open;
  final VoidCallback onTap;
  const _RailItem({required this.nav, required this.selected, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget? trailing;
    if (nav.trailingIsDownloads) {
      trailing = AnimatedBuilder(
        animation: Downloads.instance,
        builder: (_, __) {
          final active = Downloads.instance.items
              .where((d) => d.status == DlStatus.downloading || d.status == DlStatus.queued)
              .toList();
          if (active.isEmpty) return const SizedBox.shrink();
          final withSize = active.where((d) => d.total > 0).toList();
          final avg = withSize.isEmpty ? null : withSize.fold<double>(0, (s, d) => s + d.progress) / withSize.length;
          final onPill = selected;
          final c = onPill ? Colors.white : accent;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(value: avg, strokeWidth: 2, color: c)),
            const SizedBox(width: 6),
            Text('${active.length}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
          ]);
        },
      );
    }

    final fg = selected ? Colors.white : muted;
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) => SizedBox(
        height: _railItemH,
        child: Stack(
          children: [
            // hover wash (only when not the selected/pill row)
            if (active && !selected)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: DecoratedBox(decoration: BoxDecoration(color: surfaceHi.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16))),
                ),
              ),
            Row(
              children: [
                // fixed icon column — keeps icons pinned as the rail widens
                SizedBox(width: _railCollapsed, child: Center(child: Icon(nav.icon, size: 22, color: selected ? Colors.white : (active ? textHi : muted)))),
                Expanded(
                  child: ClipRect(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(nav.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 14.5, color: fg)),
                        ),
                        if (trailing != null) trailing,
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
