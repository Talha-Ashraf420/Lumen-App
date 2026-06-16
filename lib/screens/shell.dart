import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'mylist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  final XtreamClient client;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.client, required this.onLogout});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  // Tabs initialise only once first opened — avoids a startup request burst
  // (e.g. the Live guide loading EPG) that can trip the provider.
  final Set<int> _visited = {0};

  static const _nav = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.live_tv_rounded, label: 'Live'),
    (icon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.favorite_rounded, label: 'My List'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  Widget _pageFor(int i) => switch (i) {
        0 => HomeScreen(client: widget.client, onBrowse: () => setState(() => _index = 2)),
        1 => GuideScreen(client: widget.client),
        2 => SearchScreen(client: widget.client),
        3 => MyListScreen(client: widget.client),
        _ => ProfileScreen(client: widget.client, onLogout: widget.onLogout),
      };

  @override
  Widget build(BuildContext context) {
    _visited.add(_index);
    // Build a real page only for visited tabs (so unopened tabs don't fetch);
    // pages are rebuilt each frame so they re-read the active theme palette.
    final pages = [
      for (var i = 0; i < _nav.length; i++)
        _visited.contains(i) ? _pageFor(i) : const SizedBox.shrink(),
    ];
    return Scaffold(
      body: Stack(
        children: [
          const Aurora(),
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
      ),
    );
  }

  Widget _item(int i) {
    final sel = i == _index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _index = i),
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
