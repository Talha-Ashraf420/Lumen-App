import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models.dart';
import '../refresh.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'epg_guide_screen.dart';
import 'globe_screen.dart';
import 'home_screen.dart';
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

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  // Total destinations (mobile shows 0–4; desktop sidebar adds Movies/Series/
  // Live/TV-Guide = 5/6/7/8 — see _pageFor and _Sidebar).
  static const _pageCount = 9;

  // Mobile bottom-nav tabs (indices 0–4).
  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.auto_awesome_rounded, label: 'Discover'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  Widget _pageFor(int i) => switch (i) {
        0 => HomeScreen(client: widget.client, onBrowse: () => _select(2)),
        1 => GlobeScreen(client: widget.client),
        2 => SearchScreen(client: widget.client),
        3 => MyListScreen(client: widget.client),
        4 => ProfileScreen(client: widget.client, onLogout: widget.onLogout, onSwitch: widget.onSwitch),
        5 => SearchScreen(client: widget.client, initialSection: 'movie'),
        6 => SearchScreen(client: widget.client, initialSection: 'series'),
        7 => SearchScreen(client: widget.client, initialSection: 'live'),
        _ => EpgGuideScreen(client: widget.client),
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

/// Desktop floating glass navigation rail with grouped items + hairline dividers.
class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

  // Page indices match _HomeShellState._pageFor.
  static const _browse = [
    (icon: Icons.home_rounded, label: 'Home', page: 0),
    (icon: Icons.auto_awesome_rounded, label: 'Discover', page: 1),
    (icon: Icons.movie_rounded, label: 'Movies', page: 5),
    (icon: Icons.video_library_rounded, label: 'Series', page: 6),
    (icon: Icons.live_tv_rounded, label: 'Live TV', page: 7),
    (icon: Icons.grid_view_rounded, label: 'TV Guide', page: 8),
    (icon: Icons.search_rounded, label: 'Search', page: 2),
  ];

  @override
  Widget build(BuildContext context) {
    Widget rail(IconData icon, String label, int page) =>
        _RailItem(icon: icon, label: label, selected: page == index, onTap: () => onSelect(page));

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 236,
          decoration: BoxDecoration(
            color: surface.withValues(alpha: isDark ? 0.42 : 0.72),
            border: Border(right: BorderSide(color: line)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 14, 20),
                  child: Row(
                    children: [
                      const Wordmark(size: 24),
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
                // Scrollable nav so it never overflows on short windows.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Browse'),
                        for (final it in _browse) rail(it.icon, it.label, it.page),
                        _divider(),
                        _label('Library'),
                        rail(Icons.favorite_rounded, 'My List', 3),
                      ],
                    ),
                  ),
                ),
                _divider(),
                rail(Icons.person_rounded, 'Profile', 4),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) =>
      Padding(padding: const EdgeInsets.fromLTRB(26, 10, 20, 8), child: Text(s.toUpperCase(), style: kSection()));

  Widget _divider() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Divider(height: 1, color: line),
      );
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active && !sel ? surfaceHi.withValues(alpha: 0.7) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? accent.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: Row(
          children: [
            // active indicator bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 3,
              height: sel ? 20 : 0,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 11),
            Icon(icon, size: 21, color: sel ? accent : muted),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600, fontSize: 14.5, color: sel ? textHi : muted)),
          ],
        ),
      ),
    );
  }
}
